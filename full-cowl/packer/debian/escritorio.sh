#!/bin/bash
# Instala el escritorio Xfce en la base de Debian con escritorio (solo si DESKTOP=true).
# Se reintenta hasta 6 veces: el espejo a veces está a medio sincronizar y apt falla con «Unable to fetch some archives».
export DEBIAN_FRONTEND=noninteractive
if [ "$DESKTOP" != "true" ]; then echo "== Sin escritorio (variante Server) =="; exit 0; fi
echo "== Escritorio Xfce de Debian =="
# Paquetes de idioma segun el idioma que dejo el instalador (ficha 36): task-spanish o task-english
case "$(sed -n 's/^LANG=["]\{0,1\}\([A-Za-z_]*\).*/\1/p' /etc/default/locale 2>/dev/null | head -1)" in
  en_US) TAREAS_IDIOMA="task-english" ;;
  *)     TAREAS_IDIOMA="task-spanish task-spanish-desktop" ;;
esac
for intento in 1 2 3 4 5 6; do
  echo "-- Intento $intento de 6"
  apt-get update \
    && apt-get install -y --fix-missing -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
         task-xfce-desktop $TAREAS_IDIOMA open-vm-tools-desktop \
    && break
  dpkg --configure -a || true
  echo "Ha fallado (suele ser el espejo). Reintento en 45 segundos..."
  sleep 45
done
if ! dpkg -s task-xfce-desktop >/dev/null 2>&1; then
  echo "ERROR: no se pudo instalar el escritorio Xfce tras 6 intentos." >&2
  exit 1
fi
# NetworkManager lleva la red (como en Kali y en Ubuntu con escritorio)
systemctl enable NetworkManager >/dev/null 2>&1 || true
echo "== Escritorio instalado =="
