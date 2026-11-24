#!/bin/bash
# Se ejecuta DENTRO de una VM Linux como root (lo copia y lanza usuarios.ps1 desde el PC).
# $1 = carpeta privada con los datos: u.tsv (usuario, nombre completo, contraseña y grupo separados por
#      el carácter 0x1F; no por tabuladores: bash junta dos tabuladores seguidos y, con el nombre vacío,
#      la contraseña acababa en el nombre)
#      y c (1 = cambiar la contraseña al entrar). usuarios.ps1 ya ha validado nombres y grupos.
D=$1
[ -d "$D" ] || { echo "ERROR: falta la carpeta de datos"; exit 1; }
CAMBIAR=$(cat "$D/c" 2>/dev/null)
ok=0; mal=0
while IFS=$'\x1f' read -r u nombre pass grupo; do
  [ -z "$u" ] && continue
  if [ -n "$grupo" ] && ! getent group "$grupo" >/dev/null; then
    groupadd -- "$grupo" && echo "Grupo creado: $grupo"
  fi
  if id "$u" >/dev/null 2>&1; then
    # Si trae nombre completo, también se actualiza (el campo de comentario del usuario)
    if [ -n "$nombre" ]; then
      usermod -c "$nombre" -- "$u" && echo "YA EXISTE  $u (contraseña y nombre actualizados)"
    else
      echo "YA EXISTE  $u (contraseña actualizada)"
    fi
  elif useradd -m -s /bin/bash -c "$nombre" -- "$u"; then
    echo "CREADO     $u${nombre:+  ($nombre)}"
  else
    echo "FALLO      $u: no se pudo crear"; mal=$((mal+1)); continue
  fi
  if ! printf '%s:%s\n' "$u" "$pass" | chpasswd; then
    # (chpasswd no dice la contraseña, y aquí tampoco se escribe)
    echo "FALLO      $u: no se pudo poner la contraseña (¿no cumple la política de contraseñas?)"; mal=$((mal+1)); continue
  fi
  [ -n "$grupo" ] && usermod -aG "$grupo" "$u"
  [ "$CAMBIAR" = "1" ] && chage -d 0 "$u"
  ok=$((ok+1))
done < "$D/u.tsv"
echo
echo "Correctos: $ok   Con fallos: $mal"
rm -f "$D/u.tsv" "$D/c"
