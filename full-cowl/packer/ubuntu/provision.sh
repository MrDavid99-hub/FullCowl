#!/bin/bash
# Se ejecuta (con sudo) dentro de la VM base de Ubuntu antes de apagarla.
set -e
export DEBIAN_FRONTEND=noninteractive

echo "== VMware Tools =="
# Lo normal: open-vm-tools (paquete del sistema, recomendado por VMware), que ya pone el
# instalador. Plan B para sistemas antiguos sin ese paquete: las VMware Tools del linux.iso
# de VMware, que crear-base.ps1 conecta como CD si lo encuentra.
instalar_tools_cd() {
  local dev m tgz aqui
  for dev in /dev/sr* /dev/cdrom; do
    [ -b "$dev" ] || continue
    aqui=""
    # Si el escritorio ya montó el CD (a veces sin permiso de ejecución) se usa ese montaje;
    # si no, se monta aquí. El instalador se copia a /tmp, así que da igual cómo esté montado.
    m=$(findmnt -n -o TARGET --source "$dev" 2>/dev/null | head -1)
    if [ -z "$m" ]; then
      mkdir -p /mnt/vmtools
      mount -o ro "$dev" /mnt/vmtools 2>/dev/null || continue
      m=/mnt/vmtools; aqui=1
    fi
    tgz=$(ls "$m"/VMwareTools-*.tar.gz 2>/dev/null | head -1)
    if [ -n "$tgz" ]; then
      echo "Instalando VMware Tools desde el CD ($(basename "$tgz"))..."
      rm -rf /tmp/vmware-tools-distrib
      tar -xzf "$tgz" -C /tmp
      [ -n "$aqui" ] && umount "$m"
      perl /tmp/vmware-tools-distrib/vmware-install.pl -d -f
      rm -rf /tmp/vmware-tools-distrib
      return 0
    fi
    [ -n "$aqui" ] && umount "$m"
  done
  return 1
}
if ! command -v vmtoolsd >/dev/null 2>&1; then
  echo "open-vm-tools no esta: se intenta instalar el paquete..."
  apt-get install -y open-vm-tools >/dev/null 2>&1 || true
fi
if ! command -v vmtoolsd >/dev/null 2>&1; then
  instalar_tools_cd || echo "AVISO: no hay CD de VMware Tools (linux.iso)."
fi
if command -v vmtoolsd >/dev/null 2>&1; then
  echo "VMware Tools instaladas: $(vmtoolsd -v 2>/dev/null | head -1)"
else
  echo "AVISO: VMware Tools no se ha instalado: Red, Usuarios, Archivos y el progreso de los laboratorios no funcionaran en sus copias."
fi

# Idioma: el que dejo elegido el instalador (ficha 36: es_ES.UTF-8 o en_US.UTF-8). Se lee de /etc/default/locale
# en vez de pasarlo por Packer (asi vale igual para Ubuntu, Debian y Kali). Si no se puede leer: espanol.
LOC=$(sed -n 's/^LANG=["]\{0,1\}\([A-Za-z_]*\.UTF-8\).*/\1/p' /etc/default/locale 2>/dev/null | head -1)
case "$LOC" in en_US.UTF-8) IDI=en; LANGUAGE_V="en_US:en" ;; *) LOC=es_ES.UTF-8; IDI=es; LANGUAGE_V="es_ES:es" ;; esac
echo "== Idioma: $LOC =="
# Se completan las traducciones que falten (diccionarios, ayuda, LibreOffice si lo hubiera...) y se fija el idioma.
if command -v check-language-support >/dev/null 2>&1; then
  FALTAN=$(check-language-support -l "$IDI" 2>/dev/null || true)
  if [ -n "$FALTAN" ]; then
    apt-get update -qq >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    apt-get install -y -qq $FALTAN >/dev/null 2>&1 || echo "AVISO: no se pudieron instalar todas las traducciones"
  fi
fi
update-locale LANG="$LOC" LANGUAGE="$LANGUAGE_V" >/dev/null 2>&1 || true

# (Sin apt update/upgrade: el instalador ya aplica los parches de seguridad y
#  cada clon puede actualizarse con la opción "Actualizar el sistema".)

# Escritorio de Ubuntu (variante minima). No se instala desde el instalador porque trae 'firefox' como recomendado
# (envoltorio del snap) y alli falla. Aqui el sistema ya esta arrancado y snapd funciona. Lubuntu y la ISO Desktop
# ya vienen con su escritorio y se saltan este paso.
# Solo en Ubuntu: Debian con escritorio tambien pasa por aqui con DESKTOP=true (su Xfce lo pone debian/escritorio.sh)
if [ "$DESKTOP" = "true" ] && grep -q '^ID=ubuntu' /etc/os-release && ! dpkg -s ubuntu-desktop-minimal >/dev/null 2>&1 && ! dpkg -s lubuntu-desktop >/dev/null 2>&1; then
  echo "== Escritorio: instalando ubuntu-desktop-minimal (tarda unos minutos) =="
  # 'firefox-' = no instalar firefox en este paso (se instala aparte, mas abajo, para que un fallo no rompa el escritorio)
  apt-get update -y
  apt-get install -y ubuntu-desktop-minimal firefox-
  systemctl set-default graphical.target
  systemctl enable NetworkManager >/dev/null 2>&1 || true
fi

echo "== Red: DHCP en cualquier interfaz cableada, identificada por MAC =="
if command -v netplan >/dev/null 2>&1; then
rm -f /etc/netplan/*.yaml
if [ "$DESKTOP" = "true" ]; then RENDER="  renderer: NetworkManager"; else RENDER=""; fi
cat > /etc/netplan/01-vmtareas.yaml <<EOF
network:
  version: 2
$RENDER
  ethernets:
    cableada:
      match:
        name: "en*"
      dhcp4: true
      dhcp-identifier: mac
      optional: true
EOF
chmod 600 /etc/netplan/01-vmtareas.yaml
else
  # Debian/Kali: NetworkManager gestiona la red (DHCP automático en cada tarjeta)
  printf 'auto lo\niface lo inet loopback\n' > /etc/network/interfaces
  rm -f /etc/NetworkManager/system-connections/*
fi
# Arranque sin esperas: systemd-networkd-wait-online puede tener el arranque parado ~2 min
# (con escritorio no hace nada útil porque la red la lleva NetworkManager; sin escritorio
# espera a TODAS las tarjetas, aunque alguna esté en un segmento sin nadie más).
arranque_rapido() {
  systemctl cat systemd-networkd-wait-online.service >/dev/null 2>&1 || return 0
  if systemctl is-enabled NetworkManager >/dev/null 2>&1; then
    systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true
  else
    BIN=/usr/lib/systemd/systemd-networkd-wait-online
    [ -x "$BIN" ] || BIN=/lib/systemd/systemd-networkd-wait-online
    mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
    printf '[Service]\nExecStart=\nExecStart=%s --any --timeout=15\n' "$BIN" \
      > /etc/systemd/system/systemd-networkd-wait-online.service.d/vmtareas.conf
  fi
}
arranque_rapido

# Que cloud-init no vuelva a tocar la configuración en los clones
if [ -d /etc/cloud ]; then touch /etc/cloud/cloud-init.disabled; fi

if [ "$DESKTOP" = "true" ]; then
  echo "== Escritorio: arranque rapido y sesion Xorg =="
  # Con NetworkManager, la espera de systemd-networkd solo retrasa el arranque ~2 min
  systemctl disable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
  systemctl mask systemd-networkd-wait-online.service
  # Sin el asistente de bienvenida de GNOME («Welcome to Ubuntu») al entrar en los clones.
  # En 24.04 la marca gnome-initial-setup-done no siempre basta: se bloquea el servicio que lo abre
  # para todos los usuarios (sin desinstalar nada: un autoremove posterior podría llevarse el
  # escritorio) y se deja también la marca en cada usuario.
  systemctl --global mask gnome-initial-setup-first-login.service >/dev/null 2>&1 || true
  mkdir -p /etc/skel/.config && echo yes > /etc/skel/.config/gnome-initial-setup-done
  for h in /home/*; do
    [ -d "$h" ] || continue
    mkdir -p "$h/.config" && echo yes > "$h/.config/gnome-initial-setup-done"
    chown "$(stat -c %U "$h"):$(stat -c %G "$h")" "$h/.config" "$h/.config/gnome-initial-setup-done"
  done
  # Wayland deja la pantalla en negro en algunas VMs de VMware: usar Xorg
  if [ -f /etc/gdm3/custom.conf ]; then
    sed -i 's/^#\?\s*WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
    grep -q '^WaylandEnable=false' /etc/gdm3/custom.conf || \
      sed -i 's/^\[daemon\]/[daemon]\nWaylandEnable=false/' /etc/gdm3/custom.conf
  fi
fi

# Navegador (la variante minima del escritorio no lo trae). En 24.04 'firefox' es un envoltorio que baja el snap:
# dentro del instalador falla, por eso se instala aqui, con el sistema ya arrancado. Si falla no se para la base.
if dpkg -s ubuntu-desktop-minimal >/dev/null 2>&1; then
  echo "== Navegador: Firefox =="
  snap wait system seed.loaded >/dev/null 2>&1 || true
  firefox_ok=no
  for intento in 1 2 3; do
    if DEBIAN_FRONTEND=noninteractive apt-get install -y firefox; then firefox_ok=si; break; fi
    echo "AVISO: Firefox no se ha podido instalar (intento $intento de 3)"; sleep 15
  done
  if [ "$firefox_ok" = "no" ]; then
    # Un firefox a medias dejaria a dpkg roto (y fallaria 'Actualizar el sistema' en los clones): se quita
    dpkg --remove --force-remove-reinstreq firefox >/dev/null 2>&1 || true
    apt-get -f install -y >/dev/null 2>&1 || true
    echo "AVISO: la base se crea sin Firefox. Dentro de la maquina: sudo snap install firefox"
  fi
fi

echo "== Agente de primer arranque para los clones =="
# Cada clon lleva un CD con etiqueta VMTAREAS (lo crea nueva-maquina.ps1) con:
#   temprano.sh -> antes de la red (nombre de equipo, IP fija)
#   config.sh   -> con red (actualizaciones, servicios)
mkdir -p /usr/local/lib/vmtareas
cat > /usr/local/lib/vmtareas/montar-cd <<'EOF'
#!/bin/bash
# Monta el CD VMTAREAS en /run/vmtareas-cd (espera hasta 20 s a que aparezca)
mountpoint -q /run/vmtareas-cd && exit 0
for i in $(seq 1 20); do
  dev=$(blkid -L VMTAREAS 2>/dev/null) && break
  sleep 1
done
[ -n "$dev" ] || exit 1
mkdir -p /run/vmtareas-cd
# Solo root puede leerlo (el CD puede llevar la contraseña de la cuenta: otros usuarios no deben verla)
mount -o ro,uid=0,gid=0,mode=0500,dmode=0500 "$dev" /run/vmtareas-cd
EOF

cat > /usr/local/lib/vmtareas/temprano <<'EOF'
#!/bin/bash
# Claves SSH nuevas en cada clon
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A
if /usr/local/lib/vmtareas/montar-cd && [ -f /run/vmtareas-cd/temprano.sh ]; then
  bash /run/vmtareas-cd/temprano.sh
  exit 0
fi
# Sin CD: nombre de equipo desde el .vmx (guestinfo.hostname), una sola vez
n=$(vmware-rpctool "info-get guestinfo.hostname" 2>/dev/null | tr -d '[:space:]') || exit 0
[ -z "$n" ] && exit 0
# (viene del .vmx: solo letras, numeros y guiones, que es lo que admite un nombre de equipo)
case $n in *[!A-Za-z0-9-]*) exit 0 ;; esac
[ "${#n}" -le 63 ] || exit 0
marca=/var/lib/vmtareas/hostname.done
[ -f "$marca" ] && [ "$(cat "$marca")" = "$n" ] && exit 0
hostnamectl set-hostname "$n"
if grep -q '^127\.0\.1\.1' /etc/hosts; then sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $n/" /etc/hosts
else echo "127.0.1.1 $n" >> /etc/hosts; fi
mkdir -p /var/lib/vmtareas && echo "$n" > "$marca"
EOF

cat > /usr/local/lib/vmtareas/config <<'EOF'
#!/bin/bash
/usr/local/lib/vmtareas/montar-cd || exit 0
[ -f /run/vmtareas-cd/config.sh ] || exit 0
exec bash /run/vmtareas-cd/config.sh
EOF
chmod 755 /usr/local/lib/vmtareas/*

cat > /etc/systemd/system/vmtareas-temprano.service <<'EOF'
[Unit]
Description=VMTareas: nombre de equipo, IP y claves SSH del clon
After=local-fs.target systemd-udevd.service
Before=network-pre.target ssh.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/vmtareas/temprano

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vmtareas-config.service <<'EOF'
[Unit]
Description=VMTareas: actualizaciones y servicios del clon (en segundo plano)
After=network-online.target vmtareas-temprano.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/lib/vmtareas/config

[Install]
WantedBy=multi-user.target
EOF
rm -f /etc/systemd/system/vmtareas-primer-arranque.service /usr/local/sbin/vmtareas-primer-arranque
systemctl enable vmtareas-temprano.service vmtareas-config.service

# SSH activado en la base (Kali lo trae desactivado de fabrica y sus actualizaciones pueden desactivarlo otra vez)
if systemctl cat ssh.service >/dev/null 2>&1 && ! systemctl is-enabled ssh.socket >/dev/null 2>&1; then
  systemctl enable ssh.service >/dev/null 2>&1 || true
fi

echo "== Limpieza para clonar =="
apt-get -y autoremove
apt-get clean
# La configuración de instalación contiene la contraseña: no dejarla en la VM
cloud-init clean --logs >/dev/null 2>&1 || true
rm -rf /var/lib/cloud/instances /var/lib/cloud/instance /var/log/installer
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg /etc/cloud/cloud.cfg.d/*autoinstall*
rm -rf /var/lib/vmtareas
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
echo "Listo."
