# Historial de versiones

Versiones publicadas de Full Cowl. Cada una se puede descargar en la página de *Releases*.

## 2.0.3 · 26/11/2026

- **Cambio en cómo se abre Full Cowl:** antes se abría sin ninguna consola, pero algunos antivirus de empresa (Check Point en equipos de institutos) confundían esa forma de arrancar con un malware conocido y lo bloqueaban. Ahora se abre con una consola de PowerShell **minimizada** en la barra de tareas (no la cierres: es la de Full Cowl) y sin saltarse la directiva de ejecución; el instalador deja la directiva recomendada por Microsoft (`RemoteSigned`) para tu usuario. Si en tu equipo el antivirus lo sigue bloqueando, quien lo gestione puede añadir una excepción para la carpeta de Full Cowl.

## 2.0.2 · 24/11/2026

- **Arreglo:** las ISO guardadas en subcarpetas (por ejemplo `ISOs\Windows`, `ISOs\Linux`) no se encontraban. Ahora se buscan también dentro de las subcarpetas, hasta 3 niveles, en todas las pantallas.
- **Arreglo:** al actualizar desde la aplicación o con `Actualizar.bat`, a veces decía que había fallado aunque sí se había actualizado. Ahora informa bien, y si la versión nueva aún se está preparando en GitHub, lo dice.
- **`Actualizar.bat`** cierra Full Cowl solo si está abierto y lo vuelve a abrir al terminar. Si no puede copiar algún archivo, lo reintenta y dice cuál y por qué.

## 2.0.1 · 24/11/2026

- **Arreglo:** en un equipo recién instalado, Full Cowl podía no abrirse la primera vez y mostraba «No se puede enlazar el argumento con el parámetro 'Path' porque es una cadena vacía». Ya se abre con normalidad. Si instalaste la 2.0.0, usa «Buscar actualizaciones» o vuelve a ejecutar el comando de instalación.
- El aviso que sale cuando la ventana no se puede abrir es ahora más claro y dice qué hacer.

## 2.0.0 · 24/11/2026

Primera versión pública.

- **Interfaz nueva**: Inicio con el resumen del día, menú lateral plegable, tema claro, oscuro o automático, modo sobrio para clase, colores de acento, tamaño de letra y animaciones.
- **Instalar con un comando** (o con un ZIP): sin administrador, sin Git, con la descarga comprobada (SHA-256). Packer se descarga solo de la web oficial.
- **Actualizarse desde la propia aplicación**, también sin Git, y **desinstalar** sin tocar tus máquinas.
- **Asistente de primer arranque**: comprueba el PC, elige carpetas, usuario y contraseña (cifrada solo en tu PC) y aspecto.
- **Más sistemas**: Windows Server 2025/2022/2019, Windows 10/11, Ubuntu 26.04/24.04/22.04 (servidor o escritorio), Lubuntu, Debian 13/12, Rocky y AlmaLinux 9, Arch y Kali, y guías de instalación manual para Parrot, Proxmox, pfSense, OPNsense y FreeBSD.
- **Idioma, teclado y zona horaria** al crear cada base (español o inglés), y zona horaria por máquina.
- **Mis máquinas** en tarjetas o en lista, con acciones rápidas, notas y etiquetas.
- **Laboratorio visual**: mapa de red con las máquinas conectadas, estado inicial al que volver y ficha del laboratorio para la memoria de la práctica.
- **Laboratorios compartibles** (`.fclab`) y ejemplos listos para probar.
- **Extras**: programas y roles que se instalan solos en el primer arranque de cada máquina.
- **Importar y exportar** máquinas entre PC (`.ova`, carpeta, `.zip`, `.7z`).
- **Espacio y limpieza**: qué ocupa cada base, máquina e instantánea, y borrar lo que sobra.
- **Más seguro**: las bases se instalan con una contraseña de un solo uso y cada máquina recibe la tuya al arrancar; si VMware no contesta, Full Cowl deja de esperar en vez de quedarse colgado.

## 1.x · octubre de 2026 (versiones anteriores, no públicas)

- **1.4.0** · bases probadas y *Mis máquinas* más clara.
- **1.3.1** · revisión de seguridad.
- **1.3.0** · progreso de la configuración de cada máquina, en directo.
- **1.2.0** · laboratorios de varias máquinas a la vez y máquinas desechables.
- **1.1.1** · logo nuevo.
- **1.1.0** · manual técnico y de usuario.
- **1.0.1** · actualizar deja siempre la versión de GitHub.
- **1.0.0** · primera versión.
