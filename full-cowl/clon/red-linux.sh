#!/bin/bash
# Se ejecuta DENTRO de una VM Linux como root (lo copia y lanza red-ip.ps1 desde el PC).
# $1 = carpeta privada con r.tsv: mac, modo (fija|dhcp|igual), ip/prefijo, puerta, dns,dns y nombre,
# separados por el carácter 0x1F (con tabuladores, `read` junta dos seguidos si falta la puerta)
# (red-ip.ps1 ya ha validado MAC, IP, puerta, DNS y nombre)
TSV="$1/r.tsv"
[ -f "$TSV" ] || { echo "ERROR: faltan los datos de red"; exit 1; }
RESUMEN="$1/resumen"

dev_de_mac() {
  for d in /sys/class/net/*; do
    [ "$(cat "$d/address" 2>/dev/null)" = "$1" ] && { basename "$d"; return; }
  done
}

if command -v netplan >/dev/null 2>&1; then
  # ---- Ubuntu (netplan): se reescribe la configuración entera, una entrada por tarjeta
  RENDER=""
  systemctl is-enabled NetworkManager >/dev/null 2>&1 && RENDER="  renderer: NetworkManager"
  NUEVO=/etc/netplan/01-vmtareas.yaml.nuevo
  {
    echo "network:"
    echo "  version: 2"
    [ -n "$RENDER" ] && echo "$RENDER"
    echo "  ethernets:"
    n=0
    for d in /sys/class/net/*; do
      [ -e "$d/device" ] || continue          # solo tarjetas de verdad
      dev=$(basename "$d"); mac=$(cat "$d/address"); n=$((n+1))
      linea=$(awk -F'\037' -v m="$mac" 'tolower($1)==m {print; exit}' "$TSV")
      modo=$(echo "$linea" | cut -d $'\x1f' -f2); ipp=$(echo "$linea" | cut -d $'\x1f' -f3)
      gw=$(echo "$linea" | cut -d $'\x1f' -f4); dns=$(echo "$linea" | cut -d $'\x1f' -f5)
      if [ -z "$linea" ] || [ "$modo" = "igual" ]; then
        # Se deja como está ahora mismo
        if ip -4 -o addr show dev "$dev" scope global | grep -q dynamic || ! ip -4 -o addr show dev "$dev" scope global | grep -q inet; then
          modo=dhcp
        else
          modo=fija
          ipp=$(ip -4 -o addr show dev "$dev" scope global | awk '{print $4; exit}')
          gw=$(ip route show default dev "$dev" | awk '{print $3; exit}')
          dns=$(resolvectl dns "$dev" 2>/dev/null | sed 's/^[^:]*: *//' | tr ' ' ',')
        fi
      fi
      echo "    tarjeta$n:"
      echo "      match:"
      echo "        macaddress: \"$mac\""
      echo "      optional: true"       # no retrasar el arranque si una tarjeta no tiene red
      if [ "$modo" = "fija" ]; then
        echo "      dhcp4: false"
        echo "      addresses: [$ipp]"
        if [ -n "$gw" ]; then
          echo "      routes:"
          echo "        - to: default"
          echo "          via: $gw"
        fi
        [ -n "$dns" ] && echo "      nameservers:" && echo "        addresses: [$(echo "$dns" | sed 's/,/, /g')]"
        echo "IP FIJA    $dev: $ipp${gw:+  puerta $gw}${dns:+  DNS $dns}" >&2
      else
        echo "      dhcp4: true"
        echo "      dhcp-identifier: mac"
        echo "DHCP       $dev" >&2
      fi
    done
  } > "$NUEVO" 2>"$RESUMEN"
  rm -f /etc/netplan/*.yaml
  mv "$NUEVO" /etc/netplan/01-vmtareas.yaml
  chmod 600 /etc/netplan/01-vmtareas.yaml
  if netplan apply; then cat "$RESUMEN"; else echo "FALLO      netplan apply (revisa /etc/netplan/01-vmtareas.yaml)"; fi
  rm -f "$RESUMEN"
else
  # ---- Debian/Kali (NetworkManager): un perfil por tarjeta, reconocida por su MAC
  mkdir -p /etc/NetworkManager/system-connections
  while IFS=$'\x1f' read -r mac modo ipp gw dns nombre; do
    [ -z "$mac" ] && continue
    [ "$modo" = "fija" ] || [ "$modo" = "dhcp" ] || continue
    dev=$(dev_de_mac "$mac")
    [ -z "$dev" ] && { echo "FALLO      tarjeta $mac: Linux no la ve"; continue; }
    f="/etc/NetworkManager/system-connections/fullcowl-${mac//:/}.nmconnection"
    {
      echo "[connection]"
      echo "id=${nombre:-$dev}"
      echo "type=ethernet"
      echo "autoconnect=true"
      echo "autoconnect-priority=200"
      echo
      echo "[ethernet]"
      echo "mac-address=$mac"
      echo
      echo "[ipv4]"
      if [ "$modo" = "fija" ]; then
        echo "method=manual"
        echo "address1=$ipp${gw:+,$gw}"
        [ -n "$dns" ] && echo "dns=$(echo "$dns" | sed 's/,/;/g');" && echo "ignore-auto-dns=true"
      else
        echo "method=auto"
      fi
      echo
      echo "[ipv6]"
      echo "method=ignore"
    } > "$f"
    chmod 600 "$f"
    nmcli connection reload >/dev/null 2>&1
    nmcli connection up "${nombre:-$dev}" ifname "$dev" >/dev/null 2>&1 || nmcli device reapply "$dev" >/dev/null 2>&1
    if [ "$modo" = "fija" ]; then echo "IP FIJA    $dev: $ipp${gw:+  puerta $gw}${dns:+  DNS $dns}"; else echo "DHCP       $dev"; fi
  done < "$TSV"
fi
rm -f "$TSV"
