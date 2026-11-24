# clon/ · lo que se ejecuta dentro de cada máquina

En su primer arranque, cada máquina lee un CD temporal (`VMTAREAS`) con su configuración y lo aplica:

| Archivo | Sistema | Qué hace |
|---|---|---|
| `config-windows.ps1` | Windows | Contraseña, zona horaria, nombre, red, roles, dominio y extras (con reinicios) |
| `temprano.sh` | Linux | Antes de la red: contraseña, nombre, IP fija, zona horaria y SSH |
| `config.sh` | Linux | Después: actualizar el sistema y los extras |

El CD lleva la contraseña y se borra cuando la máquina termina.
