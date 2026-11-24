#!/bin/bash
# CD de configuración del clon (Ubuntu) - se ejecuta como root con la red ya levantada,
# en segundo plano (puedes iniciar sesión mientras). Registro: /var/log/vmtareas.log
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
if [ "$(cat "$EST/config.done" 2>/dev/null)" = "$ID" ]; then
  # Ya configurada (arranques posteriores): avisar de que está lista
  if [ -f "$EST/config.fallos" ]; then progreso "$TOTAL" 0 fallos lista; else progreso "$TOTAL" 0 ok lista; fi
  # (lo que se publica por las VMware Tools se pierde al apagar: se repite lo que quedó apuntado)
  if [ -s "$EST/extras.estado" ] && command -v vmware-rpctool >/dev/null 2>&1; then
    vmware-rpctool "info-set guestinfo.vmtareas.extras.estado $(tr -cd 'a-z0-9=;' < "$EST/extras.estado" | head -c 900)" >/dev/null 2>&1 || true
  fi
  exit 0
fi
if [ "$ACTUALIZAR" != "true" ] && [ -z "$PAQUETES" ]; then
  echo "$ID" > "$EST/config.done"
  progreso "$TOTAL" 0 ok lista
  exit 0
fi

exec >>/var/log/vmtareas.log 2>&1
echo "=== $(date '+%F %T') Configurando el clon ==="
CASA=/home/$USUARIO
AVISO="$CASA/CONFIGURANDO-NO-APAGAR.txt"
echo "Instalando actualizaciones y servicios. Progreso: sudo tail -f /var/log/vmtareas.log" > "$AVISO"
chown "$USUARIO:" "$AVISO" 2>/dev/null

export DEBIAN_FRONTEND=noninteractive
# Gestor de paquetes del sistema: apt (Ubuntu, Debian, Kali), dnf (Rocky, Alma) o pacman (Arch)
if command -v apt-get >/dev/null 2>&1; then GESTOR=apt
elif command -v dnf >/dev/null 2>&1; then GESTOR=dnf
elif command -v pacman >/dev/null 2>&1; then GESTOR=pacman
else GESTOR=ninguno; fi
APT="apt-get -y -q -o DPkg::Lock::Timeout=900 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Espera a tener Internet (hasta 5 min)
for i in $(seq 1 60); do { getent hosts archive.ubuntu.com || getent hosts http.kali.org || getent hosts deb.debian.org || getent hosts dl.rockylinux.org || getent hosts geo.mirror.pkgbuild.com; } >/dev/null && break; sleep 5; done

PASO=3
gestor_actualizar() {
  case $GESTOR in
    apt) $APT update ;;
    dnf) dnf -y -q makecache ;;
    pacman) pacman -Sy --noconfirm ;;
  esac
}
gestor_instalar_pq() {
  case $GESTOR in
    apt) $APT install "$@" ;;
    dnf) dnf -y -q install "$@" ;;
    pacman) pacman -S --noconfirm --needed "$@" ;;
    *) return 1 ;;
  esac
}
gestor_actualizar_todo() {
  case $GESTOR in
    apt) $APT full-upgrade ;;
    dnf) dnf -y -q upgrade ;;
    pacman) pacman -Syu --noconfirm ;;
    *) return 1 ;;
  esac
}
gestor_limpiar() {
  case $GESTOR in
    apt) $APT autoremove ;;
    dnf) dnf -y -q autoremove ;;
    *) return 0 ;;
  esac
}
gestor_actualizar
if [ "$ACTUALIZAR" = "true" ]; then
  progreso "$PASO" 900 curso actualizar; PASO=$((PASO + 1))
  echo "--- Actualizando el sistema"
  gestor_actualizar_todo && HECHOS="Sistema actualizado" || FALLOS="Actualizacion"
fi

# ---------------------------------------------------------------- Extras (ficha 20)
# CATÁLOGO CERRADO. La lista de identificadores llega en $PAQUETES (config.env del CD). Cada identificador:
#   1) tiene que ser solo letras minúsculas y números (si no, se ignora sin usarlo para nada);
#   2) se compara con las listas de abajo (case): solo si coincide se ejecutan órdenes ESCRITAS AQUÍ.
# El identificador nunca forma parte de una orden (nada de eval ni de montar órdenes con texto de fuera):
# lo que no está en el catálogo se anota como «desconocido» y se sigue con el siguiente.
# Un extra que falla no estropea la máquina: se marca, queda en el registro y se intenta el siguiente.
LOGX=/var/log/fullcowl-extras.log
declare -A EST_EXTRA
ORDEN_EXTRAS=""
publicar_extras() {   # guestinfo.vmtareas.extras.estado = apache=ok;mariadb=instalando  (lo lee Full Cowl desde fuera)
  local t="" k
  for k in $ORDEN_EXTRAS; do t="$t${t:+;}$k=${EST_EXTRA[$k]}"; done
  printf '%s\n' "$t" > "$EST/extras.estado"
  command -v vmware-rpctool >/dev/null 2>&1 || return 0
  vmware-rpctool "info-set guestinfo.vmtareas.extras.estado $t" >/dev/null 2>&1 || true
}
pq() { gestor_instalar_pq "$@"; }
servicio() { systemctl enable --now "$@"; }
abrir() {   # Rocky/Alma traen el cortafuegos puesto: se abre el servicio instalado
  command -v firewall-cmd >/dev/null 2>&1 || return 0
  firewall-cmd -q --state 2>/dev/null || return 0
  local s
  for s in "$@"; do firewall-cmd -q --permanent --add-service="$s" || true; done
  firewall-cmd -q --reload || true
}
nombre_extra() {
  case $1 in
    herramientas) echo "Herramientas (net-tools, curl, vim, tree, git)" ;;
    apache) echo "Apache" ;;            nginx) echo "Nginx" ;;
    php) echo "PHP" ;;                  mariadb) echo "MariaDB" ;;
    postgresql) echo "PostgreSQL" ;;    proftpd) echo "ProFTPD" ;;
    vsftpd) echo "vsftpd (FTP)" ;;      samba) echo "Samba" ;;
    bind9) echo "Bind9 (DNS)" ;;        dhcp) echo "Servidor DHCP" ;;
    nfs) echo "Servidor NFS" ;;         squid) echo "Squid (proxy)" ;;
    ldap) echo "OpenLDAP" ;;            cockpit) echo "Cockpit (https://IP:9090)" ;;
    fail2ban) echo "Fail2ban" ;;        wireshark) echo "Wireshark / tshark" ;;
    docker) echo "Docker" ;;            git) echo "Git" ;;
    *) echo "extra" ;;
  esac
}
# Devuelven 0 = instalado, 1 = falló, 2 = no está en el catálogo de este sistema
extra_apt() {
  case $1 in
    herramientas) pq net-tools curl wget vim htop tree git ;;
    apache)     pq apache2 ;;
    nginx)      pq nginx ;;
    php)        if dpkg -s apache2 >/dev/null 2>&1; then pq php libapache2-mod-php php-mysql; else pq php-fpm php-cli php-mysql; fi ;;
    mariadb)    pq mariadb-server ;;      # sin contraseña: acceso local con «sudo mariadb»
    postgresql) pq postgresql ;;          # sin contraseña: acceso local con «sudo -u postgres psql»
    proftpd)    if apt-cache show proftpd-core >/dev/null 2>&1; then pq proftpd-core; else pq proftpd-basic; fi ;;
    vsftpd)     pq vsftpd ;;
    samba)      pq samba smbclient ;;
    bind9)      pq bind9 bind9-utils ;;
    dhcp)       pq isc-dhcp-server ;;
    nfs)        pq nfs-kernel-server ;;
    squid)      pq squid ;;
    ldap)       pq slapd ldap-utils ;;
    cockpit)    pq cockpit ;;
    fail2ban)   pq fail2ban ;;
    git)        pq git ;;
    wireshark)  echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
                if ls /usr/share/xsessions/*.desktop >/dev/null 2>&1; then pq wireshark; else pq tshark; fi || return 1
                usermod -aG wireshark "$USUARIO" 2>/dev/null; return 0 ;;
    docker)     pq docker.io || return 1; usermod -aG docker "$USUARIO" 2>/dev/null; return 0 ;;
    *) return 2 ;;
  esac
}
extra_dnf() {
  case $1 in
    herramientas) pq net-tools curl wget vim-enhanced tree git ;;
    apache)     pq httpd && servicio httpd && abrir http https ;;
    nginx)      pq nginx && servicio nginx && abrir http https ;;
    php)        pq php php-mysqlnd || return 1; systemctl try-restart httpd 2>/dev/null; return 0 ;;
    mariadb)    pq mariadb-server && servicio mariadb ;;
    postgresql) pq postgresql-server || return 1
                [ -f /var/lib/pgsql/data/PG_VERSION ] || postgresql-setup --initdb || return 1
                servicio postgresql ;;
    vsftpd)     pq vsftpd && servicio vsftpd && abrir ftp ;;
    samba)      pq samba samba-client && servicio smb && abrir samba ;;
    bind9)      pq bind bind-utils && servicio named && abrir dns ;;
    dhcp)       pq dhcp-server ;;         # sin configurar: no se arranca
    nfs)        pq nfs-utils && servicio nfs-server && abrir nfs ;;
    squid)      pq squid && servicio squid && abrir squid ;;
    cockpit)    pq cockpit && servicio cockpit.socket && abrir cockpit ;;
    git)        pq git ;;
    *) return 2 ;;
  esac
}
extra_pacman() {
  case $1 in
    herramientas) pq net-tools curl wget vim htop tree git ;;
    apache)     pq apache && servicio httpd ;;
    nginx)      pq nginx && servicio nginx ;;
    mariadb)    pq mariadb ;;             # en Arch hay que prepararla a mano (mariadb-install-db)
    samba)      pq samba ;;
    vsftpd)     pq vsftpd ;;
    fail2ban)   pq fail2ban ;;
    cockpit)    pq cockpit && servicio cockpit.socket ;;
    git)        pq git ;;
    docker)     pq docker && servicio docker || return 1; usermod -aG docker "$USUARIO" 2>/dev/null; return 0 ;;
    *) return 2 ;;
  esac
}

LISTA_EXTRAS=()
read -r -a LISTA_EXTRAS <<< "$PAQUETES"     # (sin expandir comodines)
VALIDOS=()
for p in "${LISTA_EXTRAS[@]}"; do
  case $p in
    ""|*[!a-z0-9]*) echo "--- Identificador de extra no válido: se ignora"; continue ;;
  esac
  [ "${#p}" -le 24 ] || { echo "--- Identificador de extra demasiado largo: se ignora"; continue; }
  [ -n "${EST_EXTRA[$p]}" ] && continue    # repetido
  VALIDOS+=("$p"); EST_EXTRA[$p]=espera; ORDEN_EXTRAS="$ORDEN_EXTRAS $p"
  [ "${#VALIDOS[@]}" -ge 30 ] && break
done
if [ "${#VALIDOS[@]}" -gt 0 ]; then
  progreso "$PASO" 300 curso paquetes
  publicar_extras
  : >> "$LOGX"; chmod 640 "$LOGX" 2>/dev/null
fi
for p in "${VALIDOS[@]}"; do
  nombre=$(nombre_extra "$p")
  EST_EXTRA[$p]=instalando; publicar_extras
  echo "--- Instalando $nombre"
  echo "=== $(date '+%F %T') $p ($nombre)" >> "$LOGX"
  (
    case $GESTOR in
      apt) extra_apt "$p" ;;
      dnf) extra_dnf "$p" ;;
      pacman) extra_pacman "$p" ;;
      *) exit 2 ;;
    esac
  ) 2>&1 | tee -a "$LOGX"
  rc=${PIPESTATUS[0]}
  case $rc in
    0) EST_EXTRA[$p]=ok; echo "=== $p: instalado" >> "$LOGX"
       HECHOS="$HECHOS
$nombre" ;;
    2) EST_EXTRA[$p]=desconocido; echo "=== $p: no está en el catálogo de este sistema ($GESTOR); no se hace nada" | tee -a "$LOGX"
       FALLOS="$FALLOS
$p (no disponible en este sistema)" ;;
    *) EST_EXTRA[$p]=fallo; echo "=== $p: FALLO (código $rc)" | tee -a "$LOGX"
       FALLOS="$FALLOS
$nombre" ;;
  esac
  publicar_extras
done
gestor_limpiar

{
  echo "Configuracion automatica del clon - $(date '+%F %T')"
  echo
  echo "Hecho:"; echo "${HECHOS:-  (nada)}" | sed '/^$/d; s/^/  - /'
  [ -n "$FALLOS" ] && { echo; echo "Fallo (revisa /var/log/vmtareas.log):"; echo "$FALLOS" | sed '/^$/d; s/^/  - /'; }
  echo
  echo "IP: $(hostname -I)"
} > "$CASA/configuracion-vm.txt"
chown "$USUARIO:" "$CASA/configuracion-vm.txt" 2>/dev/null
rm -f "$AVISO"
# Despues de actualizar/instalar paquetes: una actualizacion de Kali puede haber desactivado SSH (16/11/2026)
if systemctl cat ssh.service >/dev/null 2>&1 && ! systemctl is-enabled ssh.service >/dev/null 2>&1 && ! systemctl is-enabled ssh.socket >/dev/null 2>&1; then
  systemctl enable --now ssh.service >/dev/null 2>&1 && echo "SSH estaba desactivado tras actualizar: activado" >> /var/log/vmtareas.log
fi
echo "$ID" > "$EST/config.done"
if [ -n "$FALLOS" ]; then touch "$EST/config.fallos"; progreso "$TOTAL" 0 fallos lista
else rm -f "$EST/config.fallos"; progreso "$TOTAL" 0 ok lista; fi
echo "=== $(date '+%F %T') Terminado ==="
wall "Configuracion del clon terminada. Detalles en ~/configuracion-vm.txt" 2>/dev/null
