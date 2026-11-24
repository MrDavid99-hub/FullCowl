#!/bin/bash
# CD de configuración del clon (Ubuntu) - se ejecuta como root ANTES de levantar la red.
# Nombre de equipo e IP fija. Solo una vez por clon: si luego lo cambias a mano, se respeta.
CD=$(dirname "$(readlink -f "$0")")
. "$CD/config.env"
EST=/var/lib/vmtareas
mkdir -p "$EST"
# Progreso para Full Cowl (lo lee desde fuera con vmrun, por las VMware Tools):
#   1|paso|total|segundos estimados|inicio (epoch)|estado|clave     estado: curso, ok, fallos, error
# Pasos: 1 preparar (primer arranque), 2 nombre y red, [actualizar], [paquetes]
TOTAL=2; [ "$ACTUALIZAR" = "true" ] && TOTAL=$((TOTAL + 1)); [ -n "$PAQUETES" ] && TOTAL=$((TOTAL + 1))
progreso() {  # paso segundos estado clave
  command -v vmware-rpctool >/dev/null 2>&1 || return 0
  vmware-rpctool "info-set guestinfo.vmtareas.progreso 1|$1|$TOTAL|$2|$(date +%s)|$3|$4" >/dev/null 2>&1 || true
}
# Arranque sin esperas (también en clones de bases hechas antes de este arreglo): systemd-networkd-wait-online puede tener el arranque parado ~2 min
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

# SSH encendido (16/11/2026): Kali trae el servidor SSH desactivado de fabrica y una actualizacion puede volver a
# desactivarlo. Si no esta activado ni el servicio ni el socket (Ubuntu 24.04 usa el socket), se activa.
ssh_activo() {
  systemctl cat ssh.service >/dev/null 2>&1 || return 0
  systemctl is-enabled ssh.service >/dev/null 2>&1 && return 0
  systemctl is-enabled ssh.socket >/dev/null 2>&1 && return 0
  systemctl enable ssh.service >/dev/null 2>&1 && systemctl start --no-block ssh.service >/dev/null 2>&1 &&
    echo "SSH estaba desactivado: activado" >> /var/log/vmtareas.log
  return 0
}

[ "$(cat "$EST/temprano.done" 2>/dev/null)" = "$ID" ] && exit 0
progreso 2 20 curso red
ssh_activo

# Contraseña de la cuenta: las bases nuevas se instalan con una aleatoria de un solo uso y la real
# llega en este CD (archivo «clave», sin salto de línea). Nunca se escribe en ningún registro.
if [ -s "$CD/clave" ] && id "$USUARIO" >/dev/null 2>&1; then
  CLAVE=""
  IFS= read -r CLAVE < "$CD/clave" || true
  if [ -n "$CLAVE" ] && printf '%s:%s\n' "$USUARIO" "$CLAVE" | chpasswd 2>/dev/null; then
    passwd -u "$USUARIO" >/dev/null 2>&1 || true
    echo "Contrasena puesta a $USUARIO" >> /var/log/vmtareas.log
  else
    echo "ERROR: no se pudo poner la contrasena de $USUARIO" >> /var/log/vmtareas.log
  fi
  unset CLAVE
fi

# (solo letras, números y guiones: el nombre se usa abajo dentro de una orden de sed)
case $HOSTNAME_VM in *[!A-Za-z0-9-]*) HOSTNAME_VM="" ;; esac
if [ -n "$HOSTNAME_VM" ]; then
  hostnamectl set-hostname "$HOSTNAME_VM"
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $HOSTNAME_VM/" /etc/hosts
  else
    echo "127.0.1.1 $HOSTNAME_VM" >> /etc/hosts
  fi
fi

# Zona horaria (ficha 36): solo llega si en Nueva maquina se eligio una distinta a la de la base.
# Solo letras, numeros, _ / + - y que exista en /usr/share/zoneinfo; si no, se avisa y se sigue (no estropea nada).
case $ZONA in *[!A-Za-z0-9_/+-]*) ZONA="" ;; esac
if [ -n "$ZONA" ]; then
  if [ -f "/usr/share/zoneinfo/$ZONA" ] && timedatectl set-timezone "$ZONA" 2>/dev/null; then
    echo "Zona horaria: $ZONA" >> /var/log/vmtareas.log
  else
    echo "AVISO: no se pudo poner la zona horaria $ZONA (se deja la de la base)" >> /var/log/vmtareas.log
  fi
fi

if [ -n "$IP_ADDR" ] && ! command -v netplan >/dev/null 2>&1; then
  # Debian/Kali: perfil de NetworkManager con IP fija para cualquier tarjeta cableada
  DNS=$(echo "$IP_DNS" | sed 's/,/;/g')
  mkdir -p /etc/NetworkManager/system-connections /etc/NetworkManager/conf.d
  printf '[main]\nno-auto-default=*\n' > /etc/NetworkManager/conf.d/90-vmtareas.conf
  cat > /etc/NetworkManager/system-connections/vmtareas.nmconnection <<NET
[connection]
id=Cableada (IP fija)
type=ethernet
autoconnect=true
autoconnect-priority=100

[match]
interface-name=en*;eth*;

[ipv4]
method=manual
address1=$IP_ADDR/$IP_PREFIX${IP_GW:+,$IP_GW}
${DNS:+dns=$DNS;}
${DNS:+ignore-auto-dns=true}

[ipv6]
method=ignore
NET
  chmod 600 /etc/NetworkManager/system-connections/vmtareas.nmconnection
elif [ -n "$IP_ADDR" ]; then
  RENDER=""
  systemctl is-enabled NetworkManager >/dev/null 2>&1 && RENDER="  renderer: NetworkManager"
  DNS=$(echo "$IP_DNS" | sed 's/,/, /g')
  # Puerta de enlace y DNS opcionales (en un segmento LAN aislado no hay)
  RUTA=""; NS=""
  [ -n "$IP_GW" ] && RUTA=$(printf '      routes:\n        - to: default\n          via: %s' "$IP_GW")
  [ -n "$DNS" ] && NS=$(printf '      nameservers:\n        addresses: [%s]' "$DNS")
  rm -f /etc/netplan/*.yaml
  cat > /etc/netplan/01-vmtareas.yaml <<NET
network:
  version: 2
$RENDER
  ethernets:
    cableada:
      match:
        name: "en*"
      dhcp4: false
      addresses: [$IP_ADDR/$IP_PREFIX]
      optional: true
$RUTA
$NS
NET
  chmod 600 /etc/netplan/01-vmtareas.yaml
  netplan generate
fi

echo "$ID" > "$EST/temprano.done"
