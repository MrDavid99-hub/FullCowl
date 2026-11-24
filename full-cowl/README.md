# full-cowl/ · el programa

Se abre con `Full Cowl.bat` (o `Abrir Full Cowl.bat` de la raíz) → `abrir-nueva.ps1` → `ventana-nueva.ps1`.
Las tareas largas corren en su propia consola con los scripts de esta carpeta.

| Archivo o carpeta | Para qué sirve |
|---|---|
| `abrir-nueva.ps1`, `ventana-nueva.ps1` | Revisan los archivos y abren la ventana |
| `comun.ps1`, `config.ps1` | Funciones compartidas, catálogo de sistemas y valores por defecto |
| `crear-base.ps1` | Crea una base con Packer desde una ISO |
| `nueva-maquina.ps1` | Saca una máquina de una base y prepara su CD de configuración |
| `laboratorio.ps1`, `lab-estado.ps1`, `ficha-laboratorio.ps1` | Laboratorios, su estado inicial y su ficha |
| `usuarios.ps1`, `red-ip.ps1`, `exportar.ps1`, `importar.ps1`, `limpieza.ps1`, `vigilante.ps1` | Usuarios en masa, red, exportar/importar, limpieza y máquinas desechables |
| `crear-base.bat`, `nueva-maquina.bat`, `cambiar-password.bat` | Lo mismo por consola, sin ventana |
| `interfaz/` | Pantallas (`.xaml`) y su lógica (`.ps1`, `.cs`) |
| `clon/` | Lo que se ejecuta **dentro** de cada máquina en su primer arranque |
| `packer/` | Plantillas de Packer y de instalación desatendida |
| `instalacion/` | Instalador, Packer, copia por manifiesto y desinstalador |
| `recursos/` | Logos, fuentes, imágenes y `versiones.json` |

Propios de cada PC (no se suben ni se tocan al actualizar): `config.local.json`, `password.sec`, `preferencias.json`,
`segmentos.json`, `plantillas-laboratorio.json`, `estado/`, `build/`.
