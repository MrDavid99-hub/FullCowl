# Seguridad

## Cómo avisar de un problema de seguridad

Si encuentras un fallo de seguridad, **no abras una incidencia pública**. Usa el aviso privado de GitHub:
pestaña **Security → Report a vulnerability** de este repositorio. Solo lo verá el autor.

Cuenta qué versión usas (archivo `VERSION`), qué pasos llevan al problema y qué esperabas que pasara.

**Nunca envíes contraseñas ni el archivo `password.sec`**, ni en un aviso privado ni en una incidencia. Tampoco hacen
falta: los registros de Full Cowl no las llevan.

## Qué hace Full Cowl con tus datos

- La contraseña de las máquinas se guarda **cifrada con DPAPI** de Windows (`full-cowl\password.sec`): solo tu usuario
  puede leerla, y solo en ese PC. No se sube a ningún sitio ni se escribe en archivos de configuración.
- Las bases se instalan con una contraseña aleatoria de un solo uso; cada máquina recibe la tuya en su primer
  arranque, por un CD temporal que se borra al terminar.
- Full Cowl no envía datos a nadie. Solo se conecta a internet para buscar actualizaciones (GitHub), descargar Packer
  (HashiCorp) y lo que tú pidas instalar dentro de las máquinas.
