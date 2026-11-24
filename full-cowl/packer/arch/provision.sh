#!/bin/bash
# Se ejecuta (con sudo) dentro de la VM base de Arch antes de apagarla.
set -e

echo "== VMware Tools =="
if command -v vmtoolsd >/dev/null 2>&1; then
  echo "VMware Tools instaladas: $(vmtoolsd -v 2>/dev/null | head -1)"
else
  pacman -Sy --noconfirm open-vm-tools >/dev/null 2>&1 || true
  systemctl enable vmtoolsd >/dev/null 2>&1 || true
  command -v vmtoolsd >/dev/null 2>&1 || echo "AVISO: VMware Tools no se ha instalado: Red, Usuarios y Archivos no funcionaran en sus copias."
fi

echo "== Actualizaciones =="
pacman -Syu --noconfirm || echo "AVISO: no se pudo actualizar del todo"

echo "== Red: DHCP en cualquier tarjeta cableada (NetworkManager) =="
rm -f /etc/NetworkManager/system-connections/*
mkdir -p /etc/NetworkManager/conf.d
printf '[main]\nno-auto-default=*\n' > /etc/NetworkManager/conf.d/90-vmtareas.conf

echo "== Agente de primer arranque para los clones =="
mkdir -p /usr/local/lib/vmtareas
cat > /usr/local/lib/vmtareas/montar-cd <<'EOT'
#!/bin/bash
mountpoint -q /run/vmtareas-cd && exit 0
for i in $(seq 1 20); do
  dev=$(blkid -L VMTAREAS 2>/dev/null) && break
  sleep 1
done
[ -n "$dev" ] || exit 1
mkdir -p /run/vmtareas-cd
mount -o ro,uid=0,gid=0,mode=0500,dmode=0500 "$dev" /run/vmtareas-cd
EOT
cat > /usr/local/lib/vmtareas/temprano <<'EOT'
#!/bin/bash
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A
if /usr/local/lib/vmtareas/montar-cd && [ -f /run/vmtareas-cd/temprano.sh ]; then
  bash /run/vmtareas-cd/temprano.sh
  exit 0
fi
n=$(vmware-rpctool "info-get guestinfo.hostname" 2>/dev/null | tr -d '[:space:]') || exit 0
[ -z "$n" ] && exit 0
# (viene del .vmx: solo letras, numeros y guiones, que es lo que admite un nombre de equipo)
case $n in *[!A-Za-z0-9-]*) exit 0 ;; esac
[ "${#n}" -le 63 ] || exit 0
marca=/var/lib/vmtareas/hostname.done
[ -f "$marca" ] && [ "$(cat "$marca")" = "$n" ] && exit 0
hostnamectl set-hostname "$n"
mkdir -p /var/lib/vmtareas && echo "$n" > "$marca"
EOT
cat > /usr/local/lib/vmtareas/config <<'EOT'
#!/bin/bash
/usr/local/lib/vmtareas/montar-cd || exit 0
[ -f /run/vmtareas-cd/config.sh ] || exit 0
exec bash /run/vmtareas-cd/config.sh
EOT
chmod 755 /usr/local/lib/vmtareas/*
cat > /etc/systemd/system/vmtareas-temprano.service <<'EOT'
[Unit]
Description=VMTareas: nombre de equipo, IP y claves SSH del clon
After=local-fs.target systemd-udevd.service
Before=network-pre.target sshd.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/vmtareas/temprano

[Install]
WantedBy=multi-user.target
EOT
cat > /etc/systemd/system/vmtareas-config.service <<'EOT'
[Unit]
Description=VMTareas: actualizaciones y servicios del clon (en segundo plano)
After=network-online.target vmtareas-temprano.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/lib/vmtareas/config

[Install]
WantedBy=multi-user.target
EOT
systemctl enable vmtareas-temprano.service vmtareas-config.service

echo "== Limpieza para clonar =="
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/lib/vmtareas /var/log/journal/* /root/fullcowl-instalar.log
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
echo "Listo."
