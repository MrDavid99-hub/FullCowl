#!/bin/bash
# Instala el escritorio Xfce y las herramientas por defecto de Kali (varios GB). El espejo de Kali a veces está
# a medio sincronizar y apt falla con «Unable to fetch some archives»: se reintenta hasta 6 veces.
export DEBIAN_FRONTEND=noninteractive
echo "== Escritorio y herramientas de Kali =="

# Respuestas a las preguntas de algunos paquetes (en el instalador iban en el preseed)
cat <<'SEL' | debconf-set-selections
macchanger macchanger/automatically_run boolean false
wireshark-common wireshark-common/install-setuid boolean true
kismet-capture-common kismet-capture-common/install-setuid boolean true
kismet-capture-common kismet-capture-common/install-users string
sslh sslh/inetd_or_standalone select standalone
samba-common samba-common/dhcp boolean false
SEL

for intento in 1 2 3 4 5 6; do
  echo "-- Intento $intento de 6"
  apt-get update \
    && apt-get install -y --fix-missing -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
         kali-desktop-xfce kali-linux-default open-vm-tools-desktop \
    && break
  dpkg --configure -a || true
  echo "Ha fallado (suele ser el espejo a medio sincronizar). Reintento en 45 segundos..."
  sleep 45
done

if ! dpkg -s kali-desktop-xfce >/dev/null 2>&1 || ! dpkg -s kali-linux-default >/dev/null 2>&1; then
  echo "ERROR: no se pudieron instalar el escritorio y las herramientas de Kali tras 6 intentos." >&2
  exit 1
fi
echo "== Escritorio y herramientas instalados =="
