# Manual técnico y de usuario


> Versión del manual: **2.0.0** · Corresponde a la versión del programa que indica el archivo `VERSION`.
> Los cambios de cada versión están en [`CHANGELOG.md`](../CHANGELOG.md).

## Índice

1. [Qué es](#1-qué-es)
2. [Requisitos](#2-requisitos)
3. [Instalación y actualización](#3-instalación-y-actualización)
4. [Configuración de cada PC](#4-configuración-de-cada-pc)
5. [Full Cowl: la ventana](#5-full-cowl-la-ventana)
6. [Crear una base](#6-crear-una-base)
7. [Nueva máquina](#7-nueva-máquina)
8. [Mis máquinas](#8-mis-máquinas)
9. [Laboratorio y máquinas desechables](#9-laboratorio-y-máquinas-desechables)
12. [Funcionamiento interno](#12-funcionamiento-interno)
13. [Seguridad](#13-seguridad)
14. [Solución de problemas](#14-solución-de-problemas)
15. [Referencia de archivos](#15-referencia-de-archivos)

---

## 1. Qué es

Conjunto de herramientas para automatizar el trabajo de clase en ASIR con máquinas
virtuales y su documentación en Word.

| Herramienta | Carpeta | Para qué sirve |
|---|---|---|
| **Full Cowl** | `full-cowl/` | Crear máquinas *base* desatendidas a partir de una ISO, sacar de ellas máquinas listas para cada práctica en segundos y gestionarlas (red, usuarios, instantáneas, conexión, exportación). |

**Idea básica de Full Cowl:** instalar un sistema operativo lleva 20-40 minutos; clonarlo, segundos.
Por eso cada sistema se instala **una vez** como *base* (que no se arranca nunca) y cada práctica
usa **clones** de esa base, que se configuran solos en su primer arranque.

---

## 2. Requisitos

| Necesario para | Requisito |
|---|---|
| Todo | Windows 10 u 11 |
| Full Cowl | VMware Workstation Pro (incluye `vmrun` y OVF Tool) |
| Crear bases | [Packer](https://developer.hashicorp.com/packer) (lo descargan solos el instalador, el asistente o *Crear base*, de la web oficial y comprobado) y las ISO de los sistemas |
| Actualizar | En una copia del repositorio (con Git), Git (`winget install --id Git.Git -e --source winget`). Instalado con el comando o el ZIP, no hace falta. |

Recomendado: 16 GB de RAM o más y espacio en disco (cada base de Windows ocupa 10-20 GB;
los clones enlazados, muy poco al principio).

---

## 3. Instalación y actualización

### Instalar con un comando (repositorio público)

Quien no tenga una copia del repositorio instala Full Cowl pegando **una línea** en PowerShell, CMD o Terminal (la
dirección exacta está en el README público):

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/<usuario>/<repo>/main/instalar.ps1 | iex"
```

`instalar.ps1` (solo ASCII, sin BOM) descarga `Full-Cowl.zip` y `SHA256SUMS.txt` de la última *Release*, **comprueba el
SHA-256** (si no coincide, no instala nada) y ejecuta `full-cowl\instalacion\instalar-completo.ps1`, que enseña un resumen,
espera Enter y, en 5 pasos: carpeta (por defecto `%USERPROFILE%\Full Cowl`; avisa si es OneDrive o tiene tildes; nunca
*Archivos de programa*), copia del programa (si ya estaba, lo **actualiza sin tocar** `config.local.json`, `password.sec`,
`preferencias.json`, `segmentos.json`, `estado\`, `build\` ni las máquinas), VMware (si falta, avisa con el enlace y sigue),
**Packer** y accesos directos «Full Cowl» en el escritorio y el menú Inicio. **No pide administrador.** Registro en
`%TEMP%\FullCowl-instalacion.log`. Volver a ejecutarlo siempre es seguro. Alternativa: descargar el ZIP de *Releases*,
descomprimirlo y doble clic en **`Instalar Full Cowl.bat`** (SmartScreen puede avisar: «Más información» → «Ejecutar de
todas formas»).

**Packer** (ficha 33) se descarga de `releases.hashicorp.com` en la versión fijada en `full-cowl\recursos\versiones.json`,
se comprueba con su lista oficial de sumas SHA-256 y se guarda en `herramientas\packer\packer.exe` (sin `winget` ni
administrador; si la descarga falla, se prueba `winget` y si no, se explica cómo hacerlo a mano). Full Cowl usa primero
ese y, si no está, el del PATH. Lo hacen igual el instalador, el asistente (*Instalar Packer*) y *Crear base* (si falta,
lo instala antes de empezar).

### Accesos directos con icono

Los `.bat` no pueden tener icono propio, así que junto a cada uno hay un **acceso directo con
icono** (se pueden arrastrar al escritorio o anclar a la barra de tareas):

| Acceso directo | Abre | Icono |
|---|---|---|
| `full-cowl\Full Cowl.lnk` | Full Cowl, sin ninguna consola (desde la 2.0 es la única ventana) | emblema de Full Cowl |
| `Actualizar.lnk` | `Actualizar.bat` | flechas en círculo (turquesa) |

Los que abren scripts ocultos usan `conhost.exe --headless`, para que no salga ninguna consola
(tampoco con Windows Terminal como consola predeterminada). Los crea y corrige `crear-accesos.ps1`,
que se ejecuta al abrir Full Cowl (las dos ventanas) y al final de
`Actualizar.bat`. También arregla los del escritorio y los anclados a la barra de tareas que abran
estas herramientas (aunque apunten a una carpeta antigua), y refresca la caché de iconos de Windows.
Los iconos están en la carpeta `iconos\`.

### Actualizar

Doble clic en **`Actualizar.bat`** (en la carpeta de Full Cowl). Deja todos los scripts exactamente como la última
versión de GitHub y muestra la versión instalada. No toca nada propio del PC (ajustes, contraseña,
preferencias), porque Git lo ignora.

**Instalado con el comando o el ZIP (sin Git):** `Actualizar.bat` y el botón de Full Cowl funcionan igual, pero sin Git:
miran la versión en `raw.githubusercontent.com` (sin gastar el límite de la API de GitHub), descargan el ZIP de la última
*Release*, **comprueban su SHA-256** y copian solo los archivos de su `MANIFIESTO.txt` que han cambiado (y quitan los que
ya no están). Lo que no está en el manifiesto —tus ajustes, `estado\`, las máquinas— no se toca nunca. Un archivo del
programa cambiado a mano se sustituye; uno que ya no existe en la versión nueva y que cambiaste a mano se respeta.

### Desinstalar

**`Desinstalar Full Cowl.bat`** (en la carpeta de Full Cowl): quita el programa y sus accesos directos del escritorio,
el menú Inicio y la barra de tareas. **Nunca borra máquinas, bases ni ISO**: dice dónde están para que decidas tú
(o usa antes *Ajustes → Espacio y limpieza*). Pregunta si quitar también Packer y si borrar tus ajustes de este PC
(por defecto se conservan). Si Full Cowl está abierto, pide cerrarlo. En una copia del repositorio (con `.git`) no hace
nada: esa se borra a mano.

**Desde dentro de Full Cowl:** al abrirse busca en segundo plano (sin ventana y sin
retrasar nada) si hay una versión nueva; sin conexión o sin Git no dice nada. Si la hay, sale un aviso en
*Inicio* con lo nuevo y el botón **Actualizar ahora**, y un puntito junto a la versión del menú. Al pulsarlo
pide confirmación («Full Cowl se cerrará, se actualizará y se volverá a abrir»), se niega si hay una tarea en
marcha (crear base, importar…), avisa si hay archivos cambiados a mano, y al volver a abrir cuenta que se ha
actualizado. Si algo falla vuelve a abrir la versión de antes y lo explica (`full-cowl\estado\actualizar.log`).
En *Ajustes → Actualizaciones*: versión instalada, **Buscar actualizaciones** y qué hacer al abrir: *Avisarme*
(por defecto), *Actualizar solo* (antes de cargar la interfaz; nunca con tareas en marcha, cambios a mano ni
versión mayor, y si no hay conexión se abre igual) o *No buscar*. Si no hay Git, el aviso da el comando
`winget install --id Git.Git -e --source winget` con un botón para copiarlo. `Actualizar.bat` sigue valiendo (y es lo que
hay que usar si Full Cowl no arranca); los dos usan el mismo `actualizar.ps1`.

> Si se modifica a mano un script dentro de la carpeta de Full Cowl, ese cambio **se pierde** al actualizar.
> Los cambios de código se hacen en el repositorio.

---

## 4. Configuración de cada PC

### Asistente y botón Ajustes

La primera vez que se abre Full Cowl en un PC sale un **asistente de primer arranque** con pasos: Bienvenida, **Tu PC**
(comprueba VMware, Packer, Git y el espacio; **Instalar Packer** descarga el oficial y lo comprueba; **Instalar Git** usa winget y solo sale en una copia del repositorio), **Carpetas**,
**Tus máquinas** (usuario y contraseña, que se guarda cifrada y solo en este PC; también puede dejarse para cuando crees tu
primera máquina), **Tu aspecto** (nombre, tema, color y actualizaciones) y **Listo**. Si lo cierras a medias, lo guardado se
conserva y sigue en el próximo arranque. Se puede volver a verlo en Ajustes → Ayuda y registros → **Repetir el asistente de
primer arranque**. Lo que pide, en resumen:

| Campo | Qué es |
|---|---|
| **Carpeta de ISOs** | Donde están las ISO. Indica cuántas encuentra. Se pueden añadir más en cualquier momento. |
| **Carpeta de máquinas** | Donde se guardan las máquinas (cada una en su subcarpeta) y las bases (en `\_Bases`). Propone la que tenga configurada VMware. |
| **Usuario de las VMs** | Usuario que se crea **al hacer cada base** (administrador en Windows, `sudo` en Linux); sus máquinas lo heredan, porque son copias de la base. Solo minúsculas, números, `-` y `_`, empezando por letra (Linux no admite mayúsculas). Cambiarlo solo afecta a las bases nuevas: cada base recuerda con qué usuario se hizo (lo apunta en su `.vmx`) y Full Cowl entra en sus máquinas con ese. Para tener el usuario nuevo en todo, hay que volver a crear las bases. |

Se cambia después con el botón **Ajustes** del pie de la ventana.

### Acerca de

La ventanita **Acerca de Full Cowl** enseña la versión instalada (y si estás al día o hay una nueva, según la última
búsqueda; al abrirla no se conecta a Internet), quién la crea (David Cabello Grimaldi), con qué está hecha y el aviso de
marcas (los logos de cada sistema solo sirven para reconocerlo). Tiene botones para abrir las **Novedades** y el **Manual**,
**Buscar actualizaciones** y **Copiar información** (solo versiones: sin rutas, usuario ni contraseña). La **licencia** y los
botones de **GitHub** e **Informar de un problema** solo salen cuando el repositorio sea público (con `LICENSE` en la
carpeta y la dirección pública puesta en `Url-RepoPublico`, en `comun.ps1`). Se abre de tres formas: la tarjeta **Acerca de
Full Cowl** al final de la portada de **Ajustes**, **pulsando la versión** junto al logo del menú (con el menú desplegado) o
con la tecla **F1**. Se cierra con **Esc**, la X o **Cerrar**.

### Archivos de configuración

| Archivo | Se sube a GitHub | Contenido |
|---|---|---|
| `full-cowl/config.ps1` | Sí | Valores por defecto comunes: RAM (6144 MB), CPUs (4), memoria 3D (1024 MB), disco Windows (60 GB) y Linux (40 GB), zona horaria. |
| `full-cowl/config.local.json` | **No** | Lo propio del PC: `CarpetaISOs`, `CarpetaVMs`, `CarpetaBases` (opcional), `Usuario`, `Nombre` y `PaginaInicial` (saludo y página de arranque), `MenuPlegado`, `Tema` (Claro, Oscuro o Automatico), `AnimacionInicio` y, opcionalmente, la ISO preferida de cada sistema (`ISO_Win11Pro`, `ISO_Ubuntu2404`…). |
| `full-cowl/password.sec` | **No** | Contraseña de las VMs, cifrada (ver [13](#13-seguridad)). |

Cualquier clave de `config.ps1` se puede sobrescribir en `config.local.json` (por ejemplo `"RAM_MB": 8192`).

### Contraseña de las VMs

Se pide por consola la primera vez que se crea una base y se guarda cifrada en `password.sec`.
Para cambiarla, abrir `full-cowl\cambiar-password.bat` (pide la nueva dos veces y no se muestra).

- **Bases hechas desde la 2.0:** se instalan con una contraseña **aleatoria de un solo uso** (que no
  conoce nadie) y cada máquina recibe **la tuya** en su primer arranque. Por eso, si cambias
  `password.sec`, las máquinas que crees a partir de entonces ya llevan la nueva, sin rehacer la base.
- **Bases hechas antes (marcadas «hecha antes de la 2.0» en *Nueva máquina*):** conservan la contraseña
  con la que se instalaron, y está dentro de la base. Funcionan igual, pero para tener la protección
  nueva hay que rehacerlas en *Crear base*.

---

## 5. Full Cowl: la ventana

`full-cowl/Full Cowl.bat` (o el acceso directo **Full Cowl**) abre la ventana. Antes revisa que sus scripts y
pantallas no tengan errores (si los hay, los muestra y los guarda en `estado/interfaz.log`). Desde la **2.0** es la
única ventana: la «ventana de siempre» (`gui.ps1`, WinForms) se quitó, y los accesos directos antiguos se corrigen
solos para abrir esta.

| Apartado del menú | Para qué |
|---|---|
| **Inicio** | Resumen: máquinas encendidas, laboratorios, espacio y avisos (versión nueva, tareas en marcha). |
| **Importar** | Traer máquinas de otro PC (`.ova`, carpeta, `.zip`, `.7z`). |
| **Ajustes** | Apariencia, actualizaciones, este PC, espacio y limpieza, ayuda y *Acerca de*. |
| **Mis máquinas** | Lista y gestión de las máquinas, red del laboratorio, usuarios, espacio en disco. |
| **Laboratorio** | Crear varias máquinas de una vez, con red, IP y dominio; opcionalmente desechables. |
| **Nueva máquina** | Crear una máquina de práctica a partir de una base. |
| **Crear base** | Instalar un sistema desde su ISO, de forma desatendida. Se elige el sistema en una cuadrícula de tarjetas (con «Base creada» en los que ya tienes). Los pasos van numerados y a la derecha hay un resumen fijo con la estimación de tiempo y comprobaciones (Packer, VMware, ISO, espacio, contraseña). La RAM se da en GB y cada sistema trae lo recomendado (nota «Recomendado» y botón «Usar lo recomendado»). Con más de 12 tarjetas sale un buscador con filtros (Todos / Windows / Linux / Redes y otros). En las bases manuales un aviso recuerda que no hay IP automática. |

Las tareas largas se ejecutan en una **consola aparte** donde se ve el detalle; la ventana sigue
disponible. La ventana recuerda lo último elegido (`preferencias.json`).

También se puede trabajar sin ventana con `crear-base.bat` y `nueva-maquina.bat`, que preguntan por consola.

### Cómo es la ventana

Ventana WPF con menú lateral, tarjetas con sombra, animaciones y la letra **Inter** (libre, va en
`recursos/fuentes`).

- **Inicio** es la primera opción del menú (y con lo que se abre, salvo que en Ajustes elijas *Mis máquinas*):
  saludo según la hora del PC (6:00-13:59 «Buenos días», 14:00-20:59 «Buenas tardes», de 21:00 a 5:59
  «Buenas noches»), tres etiquetas (máquinas encendidas, espacio libre y tareas en marcha), cuatro botones
  grandes (*Nueva máquina*, *Laboratorio de dominio*, *Crear base* e *Importar*), el bloque **En marcha**
  (creación de base, importación y máquinas configurándose, con su barra; al pulsar una te lleva a su
  página), el bloque **Avisos** (bases hechas antes de la 2.0 que conviene rehacer, máquinas sin su base,
  poco espacio en disco) y, abajo, **Seguir con**: las 4 máquinas con las que trabajaste más hace poco
  (las de la carpeta modificada más tarde: al encender, apagar, crear o cambiar algo, VMware escribe ahí;
  no salen bases ni desechables). Al pulsar una, te lleva a *Mis máquinas* con ella elegida.
- **Iconos de línea:** el menú, los contadores de *Mis máquinas*, el buscador, el botón de actualizar, los botones
  del panel de la máquina (Encender, Apagar, Abrir, Carpeta, Instantáneas, Red, Conectar, Archivos, Usuarios),
  *Limpiar*, los avisos y las tarjetas de *Inicio* usan iconos finos y redondeados (`interfaz\iconos.xaml`, 22
  dibujos sobre una cuadrícula de 24 x 24) en lugar de los glifos de Windows. Su color es el de la letra de
  donde están, así que cambian solos con los colores. Los logos de sistema y los botones de la ventana no cambian.
- **Tema claro / oscuro / automático:** en *Ajustes* → *Tema*. Claro es el de siempre (por defecto); Oscuro usa una
  paleta de negros verdosos con teal; Automático sigue el tema de Windows y cambia solo si Windows cambia con Full
  Cowl abierto. El cambio se ve al momento (incluso con una tarea en marcha o un diálogo abierto) y se recuerda
  (`Tema` en `config.local.json`). Los colores tienen nombre en `interfaz\tema.ps1`.
- **Menú plegable:** el logo de arriba es un botón. Un clic pliega el menú (solo iconos; el nombre sale al
  pasar el ratón) o lo despliega. No se despliega solo al pasar el ratón. Se queda como lo dejes al
  cambiar de pantalla y la próxima vez que abras Full Cowl (se apunta en `config.local.json`, clave `MenuPlegado`).
- **Mis máquinas** ya está completa y hace lo mismo que la pestaña de siempre: encender, apagar (normal
  o forzado), abrir en VMware, carpeta, instantáneas, red del laboratorio, conectar (Escritorio remoto
  o SSH), pasar archivos, usuarios en masa, exportar, conservar desechables, borrar y limpiar restos.
  Elegir varias con Ctrl o Mayúsculas + clic: Encender, Apagar, Red y Borrar trabajan con todas.
  Las máquinas hechas con Full Cowl llevan la etiqueta **FC** (las bases, **BASE**). Las bases salen protegidas (solo *Carpeta*). **Importar** (menú, debajo de *Crear base*) trae máquinas
  completas de otro Full Cowl (ver «Importar máquinas» en la sección 8). El progreso de la configuración se ve en la tarjeta de
  cada máquina (con una barra) y en el panel de la derecha.
- La lista se **actualiza sola**: al encender o apagar, la tarjeta dice «Encendiendo…» o «Apagando…»
  y cambia en cuanto VMware termina (también si la enciendes o apagas desde VMware).
- *Usuarios* necesita entrar en la máquina: antes de empezar avisa si en este PC falta la contraseña
  de las VMs (se guarda al crear la primera base), si la máquina no la creó Full Cowl o si no responden
  sus VMware Tools. La contraseña de los usuarios nuevos se escribe oculta (el ojo la enseña) y no se
  guarda: viaja cifrada al script, que la borra al leerla.
- **Atajos:** F5 actualiza, Ctrl+F busca, Esc borra la búsqueda, Intro abre en VMware, Supr borra.
- **Nueva máquina** y **Crear base** recuerdan lo último elegido, en el mismo `preferencias.json`). *Crear base*
  enseña el progreso con una barra que avanza sola, y mientras se crea una base el menú lateral dice
  por qué porcentaje va («Crear base · 45 %»). Si sales de *Nueva máquina* y vuelves, lo que estabas
  rellenando se conserva.
- En *Nueva máquina*, la tarjeta **Configurándose** enseña cada máquina recién creada con su paso, una
  barra y un **contador** desde que se creó; cuando termina dice «Lista para usar» y cuánto tardó en
  total. En *Mis máquinas* el panel de la derecha también lleva ese contador.
- **Historial de tiempos:** cada base creada y cada máquina configurada queda apuntada con lo que
  tardó en `estado/tiempos.csv` (se abre con Excel; la limpieza de restos no lo borra). *Crear base*
  dice cuánto tardó la última vez ese sistema en este PC.
- Las tarjetas llevan el **logotipo** del sistema (Windows 11, Windows 10 y Server, Ubuntu) en blanco
  sobre su color.
- **Laboratorio** también está completo: las mismas opciones que la pestaña de siempre (máquinas,
  red, IP fijas seguidas, dominio con su controlador, plantillas, desechable). Debajo de cada máquina
  pone su papel en el dominio y la IP que recibirá. Para ajustar una máquina se pulsa en la vista
  previa (ver «Crear laboratorio»). El **progreso de cada laboratorio** (cuántas máquinas están listas,
  la media y un contador desde que empezó) se ve en *Mis laboratorios*, en su lista y en el mapa. (Las máquinas de un
  laboratorio ya no salen en el progreso de *Nueva máquina*.)
- **Sin consolas:** el acceso directo «Full Cowl» la abre sin ninguna ventana de
  PowerShell; las tareas largas (crear base, máquina, laboratorio…) sí abren su consola, a propósito.
  La primera vez tras actualizar tarda algo más: prepara su código y lo guarda en `%TEMP%\FullCowl`.
- **Animación al abrir:** el logo se monta con rayos alrededor (unos 2,5 segundos, mientras la ventana
  se carga). Un clic o una tecla la adelantan; se quita en *Ajustes*. No sale la primera vez en un PC
  (antes sale el asistente de Ajustes).
- **Apariencia** (en *Ajustes*; se ve al momento, y *Cancelar* lo deja como estaba): *Modo sobrio (para clase)* —
  colores grises apagados, acento gris fijo y sin animaciones, para proyectar delante del profesor—; *Tema* (Claro,
  Oscuro, Automático); *Color* (Full Cowl, Dorado, Azul, Violeta, Rojo, Grafito) y *El color cambia*: **Toda la interfaz** (por defecto:
  fondo, menú lateral, tarjetas, campos y bordes toman el color elegido, p. ej. granate con Rojo) o **Solo el acento**
  (botón principal, progreso, iconos activos y enlaces, con los fondos verdes de siempre). Los rayos, el logo, los
  símbolos de los sistemas y los colores de estado (borrar en rojo de peligro, encendida/apagada) no cambian; el modo
  sobrio ignora el color. Esmeralda ya no existe: quien la tuviera pasa a Full Cowl; *Animaciones* (Normales; Reducidas: sin rayos; Ninguna: sin rayos, sin animación
  de inicio y cambios instantáneos). Con el modo sobrio, el acento queda bloqueado y las animaciones se quedan en «Reducidas» (solo fundidos; se puede poner «Ninguna»).
  *Animaciones* (ficha 22): *Normales* = tarjetas que aparecen una a una, rayos pequeños alrededor de la barra al terminar una base o máquina, onda y hundimiento en botones, tarjetas que se levantan, interruptores y selectores que se deslizan y brillo en las barras de progreso; *Reducidas* = solo fundidos; *Ninguna* = todo instantáneo.
- **Rayos ocasionales en Inicio:** de vez en cuando (entre 6 y 18 segundos; el primero a los 4-8) salen 4-8
  rayos sueltos repartidos por toda la tarjeta de bienvenida. No tapan nada ni se pueden pinchar. Solo se
  dibujan con Inicio a la vista y la ventana activa, y no gastan procesador mientras no hay rayo. Se quitan en
  *Ajustes* («Rayos ocasionales en Inicio») y no salen si Windows tiene desactivadas las animaciones.
- **Ajustes** (abajo en el menú) es una **portada con cinco apartados**; cada tarjeta lleva a su página y arriba
  hay «‹ Ajustes» y pastillas para saltar de uno a otro (Escape también vuelve a la portada). Pulsar Ajustes en el
  menú lleva siempre a la portada, con un resumen en vivo de cada apartado.
  - **Apariencia:** lo de arriba. Se ve al momento.
  - **Actualizaciones:** estado («Está al día» / «Hay una nueva»), **Actualizar ahora**, **Buscar actualizaciones** y qué hacer al abrir.
  - **General:** tu nombre (para el saludo de Inicio; vacío = el de Windows) y con qué página se abre Full Cowl. Se aplica al momento.
  - **Este PC:** carpeta de ISOs, carpeta de máquinas, **carpeta de las fichas del laboratorio** (donde se proponen guardar; por defecto `Documentos\Full Cowl\Fichas`) y usuario de las máquinas, con **Guardar cambios** y
    **Descartar** (avisa si sales con cambios sin guardar). Avisa si `config.local.json` tiene un usuario que no
    vale (con mayúsculas: Full Cowl usa «alumno») y pide confirmación al cambiar de usuario: el nuevo solo vale
    para las bases nuevas. **Cambiar contraseña…** abre un cuadro con campos ocultos; la contraseña nunca se
    muestra ni se escribe en archivos de texto (se guarda cifrada en `password.sec`).
  - **Espacio y limpieza:** qué ocupa cada base, máquina e instantánea y borrar lo que sobra (ver [Espacio y limpieza](#espacio-y-limpieza)). También se abre desde el chip del disco de *Inicio*.
  - **Ayuda y registros:** versión, **Ver las novedades**, **Abrir el manual**, **Abrir la carpeta de registros** y
    **Repetir el asistente de primer arranque** y **Copiar información del equipo** (solo versiones de Full Cowl, Windows, VMware y Packer, para pegarla en un aviso de fallo).
  La primera vez en un PC sale el asistente de primer arranque (si no pudiera abrirse, el cuadro de ajustes sencillo).

Si algo falla, queda apuntado en `estado/interfaz.log`. Antes de abrirse revisa sus scripts y
pantallas: si hay un error, lo enseña en vez de no abrirse.

---

## 6. Crear una base

### Sistemas disponibles

| Sistema | Clave | ISO que busca (por nombre) | Intervención manual |
|---|---|---|---|
| Windows Server 2025 (escritorio) · *Nuevo* | `WinServer2025` | contiene `server` y `2025` | Ninguna |
| Windows Server 2022 (escritorio) | `WinServer2022` | contiene `server` y `2022` | Ninguna |
| Windows Server 2019 (escritorio) | `WinServer2019` | contiene `server` y `2019` | Ninguna |
| Windows 10 Pro | `Win10Pro` | `win10`, `windows_10`, `windows 10`… | Ninguna |
| Windows 11 Pro | `Win11Pro` | `win11`, `windows_11`… | Ninguna |
| Ubuntu 26.04 Server / con escritorio · *Nuevo* | `Ubuntu2604` / `Ubuntu2604Desk` | empieza por `ubuntu-26.04` y contiene `server` | Ninguna (empieza sola) |
| Ubuntu 24.04 Server | `Ubuntu2404` | empieza por `ubuntu-24.04` y contiene `server` | Ninguna (empieza sola) |
| Ubuntu 24.04 con escritorio | `Ubuntu2404Desk` | la misma (servidor + escritorio mínimo) | Ninguna (empieza sola) |
| Lubuntu 24.04 | `Lubuntu2404` | la misma (servidor + `lubuntu-desktop`) | Ninguna (empieza sola) |
| Ubuntu 22.04 Server / con escritorio | `Ubuntu2204` / `Ubuntu2204Desk` | empieza por `ubuntu-22.04` y contiene `server` | Ninguna (empieza sola) |
| Kali Linux | `Kali` | empieza por `kali-linux` y contiene `installer` | Escribir una línea al arrancar |
| Parrot Security / Home · *Nuevo · Manual* | `Parrot`, `ParrotHome` | `Parrot-security-…_amd64.iso` / `Parrot-home-…_amd64.iso` | Instalación manual guiada (modo Live → *Install Parrot*) |
| Debian 13 / 12, sin y con escritorio Xfce · *Nuevo* | `Debian13`, `Debian13Desk`, `Debian12`, `Debian12Desk` | `debian-13…netinst` / `debian-12…netinst` (ISO pequeña «netinst») | Escribir una línea al arrancar (ESC) |
| Rocky Linux 9, sin y con escritorio GNOME · *Nuevo* | `Rocky9`, `Rocky9Desk` | `Rocky-9…dvd…iso` (ISO «DVD», la grande) | Añadir un texto al arrancar (TAB) |
| AlmaLinux 9, sin y con escritorio GNOME · *Nuevo* | `Alma9`, `Alma9Desk` | `AlmaLinux-9…dvd…iso` (ISO «DVD») | Añadir un texto al arrancar (TAB) |
| OPNsense, pfSense (cortafuegos) · *Manual* | `OPNsense`, `pfSense` | `OPNsense-…dvd…iso` (descomprimida), `pfSense-CE-….iso` (descomprimida) | Instalación manual guiada, con 2 tarjetas de red |
| Proxmox VE · *Manual* | `Proxmox` | `proxmox-ve….iso` | Instalación manual guiada (virtualización anidada activada; datos de red listos para copiar) |
| FreeBSD · *Manual* | `FreeBSD` | `FreeBSD-…disc1/dvd1…iso` | Instalación manual guiada |
| Otro sistema · *Manual* | `Otro` | cualquier `.iso` | Instalación manual guiada |
| Arch Linux, mínimo y con escritorio Xfce · *Nuevo* | `Arch`, `ArchDesk` | `archlinux-…-x86_64.iso` | Añadir un texto al arrancar (TAB) |

Los sistemas marcados **Nuevo** (etiqueta en su tarjeta de *Crear base*) se acaban de añadir y todavía no están probados a fondo. **Cómo se ve la pantalla de *Crear base*:** hay **una tarjeta por sistema** (Windows Server, Windows, Ubuntu, Lubuntu, Kali…) y, al elegirla, aparecen debajo los chips de **Versión** y de **Edición** (por ejemplo Ubuntu → 26.04 / 24.04 / 22.04 y Server / Con escritorio). Por defecto solo salen los sistemas de los que **tienes la ISO** en tu carpeta o ya **tienen base creada**; el botón **Ver todos los sistemas** enseña también los demás, apagados y con «No hay ISO en tu carpeta». Si el elegido no tiene ISO sale **Dónde la consigo**, que abre la página oficial (no se descarga nada). Si no hay ninguna ISO detectada, se enseñan todos.

**Debian, Rocky/AlmaLinux y Arch** (nuevos): se instalan como Kali, escribiendo en el menú de arranque del instalador lo que te indica la ventana. En **Debian** (ISO netinst) y **Kali** se pulsa ESC y se escribe una línea entera; en **Rocky/Alma** (ISO DVD) y **Arch** se pulsa TAB y se añade un texto al final de la línea que sale. Es un texto con la IP de tu red NAT de VMware: cópialo tal cual (con teclado español, usa la segunda caja: `=` es ¡, `:` es Mayús+ñ, `/` es -). Rocky/Alma no instalan sin la ISO DVD; Debian necesita Internet durante la instalación; Arch lo descarga todo de Internet. Las máquinas clonadas de estas bases reciben nombre y IP fija como las de Kali. Los extras de «Nueva máquina» solo están completos en los sistemas con apt; en Rocky/Alma/Arch se instalan los más habituales (herramientas, Apache, Nginx, MariaDB, Samba, vsftpd, Fail2ban, Cockpit) y el resto lo dice en el registro.

**Parrot** (Security y Home) se instala con su instalador gráfico (Calamares), que no admite archivo de respuestas, así que va como **instalación manual guiada**: arranca en modo *Live*, pulsa *Install Parrot*, crea el usuario con el mismo nombre que usa Full Cowl y, al acabar, dentro de la máquina: `sudo apt install -y open-vm-tools-desktop openssh-server` y `sudo systemctl enable --now ssh`. Sale en el grupo *Linux*, con su logo. **Proxmox VE** también es manual (su instalación desatendida exige rehacer la ISO con una herramienta de Linux): la nota de *Crear base* enseña la **IP sugerida (.120 de tu red NAT), la puerta de enlace y el DNS** con un botón **Copiar**, y recuerda que el nombre debe ser completo (`pve.lab.local`) y que se entra por el navegador a `https://<IP>:8006` con `root`. La contraseña de `root` la pones tú: Full Cowl no la guarda. Recomendado: 8 GB de RAM, 4 procesadores y 64 GB de disco.

**Instalación manual guiada** (OPNsense, pfSense, Proxmox, FreeBSD, Parrot, Otro): Full Cowl crea la máquina vacía con la ISO y la abre en VMware. Instalas el sistema tú, con el usuario que te indica la nota, y cuando acabes pulsas **«Ya he terminado»** en el cuadro Progreso (o apagas desde dentro). Full Cowl apaga la máquina y la guarda como base. Estas bases se clonan tal cual: no se les cambia el nombre, la IP ni los usuarios por dentro. Si pulsas «Ya he terminado» antes de acabar la instalación, la base queda a medias y hay que rehacerla. Las ISO de OPNsense y pfSense vienen comprimidas (`.bz2`, `.gz`): descomprímelas antes (7-Zip).

Si hay varias ISO que encajan, se usa la preferida de `config.local.json` o la más reciente;
con **Examinar** se puede elegir cualquiera. Para Ubuntu hace falta la ISO **live-server**: la de
escritorio no admite instalación desatendida.

### Proceso

1. Pestaña **Crear base** → sistema, ISO y recursos (RAM y CPUs solo para la instalación;
   el disco lo heredan todos los clones).
   Debajo de RAM / CPU / Disco hay tres desplegables: **Idioma del sistema** (Español o Inglés de EE. UU.),
   **Teclado** (Español o Inglés EE. UU.; al cambiar el idioma se pone el suyo, pero se puede cambiar) y **Zona horaria**
   (16 zonas; por defecto la de este PC). Se recuerdan para la próxima vez. El **idioma se instala con la base**: todas las
   máquinas hechas con ella salen en ese idioma (para tener otro idioma hay que rehacer la base; hay **una base por sistema**,
   y el aviso «Ya existe» dice en qué idioma está la de ahora). En **Windows** el idioma de los menús lo pone la **ISO**: con
   una ISO solo en español, Windows se ve en español aunque pidas inglés, pero el teclado, los formatos (fechas, comas) y la
   hora sí son los elegidos (la ventana y el final de la creación lo avisan). En los sistemas de **instalación manual** no
   salen los desplegables: el idioma y la zona los eliges tú al instalar y la guía de pasos te dice qué elegir. Sin ventana
   (la consola) no se pregunta nada: español, teclado español y la zona de `config.ps1` (como siempre). Las bases salen
   con una etiqueta pequeña «ES · Madrid» / «EN · UTC»; las hechas antes de esto salen como «ES · Madrid» y siguen valiendo.
2. **Crear base** → Windows pide permisos de administrador (para leer las ediciones de la ISO).
3. La consola muestra el detalle; la ventana, una **barra de progreso** con la fase y el tiempo.
4. Al terminar, la base queda en `<carpeta de máquinas>\_Bases\<Clave>` con la instantánea `base`.

Tiempos orientativos: Windows Server 15-20 min, Windows 10/11 20-30 min, Ubuntu 20-30 min,
Kali 30-45 min.

**VMware Tools en las bases** (hacen falta para Red, Usuarios, Archivos, el apagado normal y el progreso):

- **Windows:** se instalan desde el CD `windows.iso`, sin Internet. Se busca primero en la carpeta de
  ISOs y luego en la de VMware Workstation (viene con el programa, junto a `vmrun.exe`); si no está,
  se intentan descargar.
- **Linux (Ubuntu, Lubuntu, Kali…):** se usa `open-vm-tools`, el paquete del propio sistema, que es lo
  que recomienda VMware. **Plan B** para sistemas antiguos sin ese paquete: si hay un `linux.iso` de
  VMware en la carpeta de ISOs (o en la de VMware), se conecta como CD y se instalan desde él
  (se copia el instalador, se desmonta el CD y se ejecuta `vmware-install.pl`).

**Windows** y **Ubuntu** se instalan en segundo plano (sin ventana); en Ubuntu, en cuanto la VM
arranca, Full Cowl abre su ventana en VMware para que veas cómo va (si no se abre: *File > Open* y el
`.vmx` de `_Bases\<Clave>`). **Kali** abre la ventana de la VM:

- **Ubuntu: empieza sola, no hay que escribir nada.** La máquina arranca con un CD pequeño de Full Cowl
  (`recursos\arranque\ubuntu-autoinstall.iso`, 6 MB) cuyo único trabajo es poner en marcha el instalador de **tu** ISO de
  Ubuntu añadiendo la palabra `autoinstall`, que es lo que evita la pregunta. Tu ISO no se toca. En *Crear base* es la casilla
  **Empezar sin escribir «yes» (recomendado)**.
  - Si a los 2-3 minutos la máquina enseña «FULL COWL: no he podido arrancar el CD de Ubuntu…» o no avanza: *Cancelar*,
    desmarca la casilla y vuelve a crear la base. Entonces se hace como antes: a los ~30 s pregunta
    `Continue with autoinstall? (yes|no)` → clic en la VM, `yes`, Enter.
  - Si falta el CD pequeño (aviso en rojo en la consola), se hace también como antes; `Actualizar.bat` lo repone.
  - Cómo arrancó cada vez queda apuntado en `estado\<Clave>-arranque.log`.
- **Kali:** en el menú azul del instalador pulsar **Esc** (sale un prompt `boot:`) y escribir la línea
  entera que enseña *Crear base* antes de empezar y la consola (`/install.amd/vmlinuz auto=true priority=critical
  url=http://<IP del PC>:8820/k.cfg initrd=/install.amd/initrd.gz`). No vale añadirla a la línea de «Install»: la de
  Kali lleva su propio `preseed/file` y el instalador ignora entonces nuestro `url=`.
  El menú usa teclado inglés: `=` es la tecla `¡`, `:` es `Mayús+ñ`, `/` es la tecla `-`.
  El instalador solo pone lo mínimo; el escritorio Xfce y las herramientas (varios GB) se instalan después, por
  SSH y con reintentos, porque el espejo de Kali a veces está a medio sincronizar.
  Si Windows pregunta si permite a `packer` en la red, aceptar.

### Cancelar

Botón **Cancelar** junto a la barra de progreso: detiene Packer, apaga la VM a medio crear y borra
su carpeta. Si se estaba rehaciendo una base existente, la anterior ya no existe.

### Reglas de oro

- **No arrancar nunca una base.** Para probar, crear un clon.
- **No borrar ni rehacer una base** que tenga clones *enlazados*: dejan de funcionar.
- Windows queda sin activar (clave genérica de instalación).

---

## 7. Nueva máquina

| Campo | Descripción |
|---|---|
| **Base** | Base de la que se clona, en tarjetas con su tamaño y cuántas máquinas salen de ella. «Antigua» = de una versión anterior, sin opciones extra (rehazla en *Crear base*). |
| **Nombre** | Nombre de la máquina y de su carpeta. |
| **Nombre de equipo** | Hostname dentro del sistema (se rellena solo; máx. 15 caracteres). |
| **Etiquetas** (opcional) | Palabras para encontrar la máquina luego con el filtro de *Mis máquinas* (ver [Notas y etiquetas](#notas-y-etiquetas)). |
| **Copia** | Dos tarjetas. *Enlazada*: segundos y ocupa poco, depende de la base. *Completa*: independiente, ocupa como la base. |
| **RAM / CPUs / Memoria 3D** | Recursos de la máquina, con − y +. La RAM va en **GB** (se admite 0,5, 1,5…). Memoria 3D (en MB) = 0 desactiva la aceleración 3D. |
| **Zona horaria** | Primera opción: **«La de la base (…)»**, que no cambia nada. Si eliges otra, la máquina la pone ella sola al configurarse (sin reiniciar; Windows con `tzutil`, Linux con `timedatectl`). Debajo pone el idioma, que viene de la base y no se cambia aquí. Con bases de instalación manual o antiguas no se puede cambiar. |
| **Resumen (derecha)** | Lo que se va a crear, cuánto tardará, qué falta y las comprobaciones ✓/✗. Con la ventana estrecha pasa debajo. |
| **IP fija** | IP, prefijo, puerta de enlace y DNS. Propone una libre de la red NAT de VMware. |
| **Active Directory** (Windows) | *Crear un dominio nuevo* (solo Windows Server; instala AD DS + DNS y será el controlador; exige IP fija) o *Unir a un dominio existente* (el controlador debe estar encendido; se une con tu usuario de las VMs y, si no puede, con el administrador del dominio, que en Windows en español se llama `Administrador`). |
| **Extras (opcional)** | Software (Linux) o roles y características (Windows) que se instalan **solos en el primer arranque**. Ver [Extras](#extras-opcional). |
| **Arrancarla al terminar** | Enciende la máquina al crearla. |
| **Desechable** | Se borra sola cuando la apagues (ver [máquinas desechables](#máquinas-desechables)). Siempre enlazada. |

### Extras (opcional)

La tarjeta **Extras (opcional)** sale plegada: pulsa **Elegir extras** para abrirla. Dentro hay un **buscador**, pastillas por
categoría y una tarjeta pequeña con **interruptor** por cada extra (nombre, una línea, «≈ 1 min» y «Necesita Internet» si toca).
Solo salen los que valen para la base elegida; si cambias a otra base del mismo tipo se conserva lo marcado y se avisa de lo que
se desmarca. Abajo, el total («3 extras · unos 4 min más al primer arranque»); el resumen de la derecha lleva los nombres.

| Sistema | Extras |
|---|---|
| **Ubuntu, Debian, Kali** (`apt`) | Web: Apache, Nginx, PHP · Bases de datos: MariaDB, PostgreSQL · Red: DNS (Bind9), DHCP, vsftpd, ProFTPD, Squid, OpenLDAP · Archivos: Samba, NFS · Herramientas: paquete de herramientas (net-tools, curl, vim, tree, git), Git, Docker, Fail2ban, Cockpit (`:9090`), Wireshark/tshark |
| **Rocky, Alma** (`dnf`) | Apache, Nginx, PHP, MariaDB, PostgreSQL, DNS (Bind), DHCP, vsftpd, Squid, Samba, NFS, herramientas, Git, Cockpit. Se arranca el servicio y se abre su puerto en el cortafuegos. |
| **Arch** (`pacman`) | Apache, Nginx, MariaDB (hay que prepararla a mano), vsftpd, Samba, herramientas, Git, Docker, Fail2ban, Cockpit |
| **Windows Server** | Red: ping, Escritorio remoto, OpenSSH (*), DNS, DHCP (sin configurar), Telnet · Web: IIS, FTP de IIS · Archivos: servidor de archivos + FSRM, impresión, copias de seguridad · Seguridad: rol AD DS (sin crear dominio), **servicios de certificados (AD CS, solo el rol)** · WDS, .NET 3.5 (*), Hyper-V |
| **Windows 10/11** | ping, Escritorio remoto, OpenSSH (*), Telnet, IIS, FTP de IIS, .NET 3.5 (*), Hyper-V, Sandbox, WSL, RSAT (*) |

`(*)` = se descarga de Windows Update. En Linux **todos necesitan Internet** (se bajan de los repositorios del sistema, en la
versión que traigan: no se fija versión). Hyper-V, Sandbox y WSL activan la virtualización dentro de la máquina (8 GB o más).

- **Actualizar el sistema** (solo Linux) es una casilla aparte, encima de la lista.
- **Sin contraseñas:** ningún extra pone contraseña. MariaDB y PostgreSQL quedan con acceso local (`sudo mariadb`,
  `sudo -u postgres psql`).
- **Con Active Directory → Crear un dominio**, «Servidor DNS» y «Rol AD DS» salen marcados y fijos («Ya lo instala Active
  Directory»).
- Apache/Nginx y ProFTPD/vsftpd usan el mismo puerto: la ventana avisa si se marcan juntos.
- **Cómo va cada uno:** en *Mis máquinas*, el panel de la máquina enseña «Extras: instalando 2 de 3…» y, por cada uno,
  ✓ (instalado), ✗ (falló) o … (instalando). **Un extra que falla no estropea la máquina:** se sigue con el siguiente. El
  registro queda dentro de la máquina: `/var/log/fullcowl-extras.log` (Linux) o `C:\ProgramData\VMTareas\extras.log` (Windows).
- **En el laboratorio:** en *Crear laboratorio*, pulsa una máquina de la vista previa y, en el panel *Esta máquina*, el botón
  **Extras…** abre la misma lista. *Aplicar a las demás* copia también los extras a las de la misma base. Si la red es
  *Aislada* o *Solo anfitrión* (sin Internet), los extras que lo necesitan salen apagados. Las plantillas y los `.fclab`
  guardan los extras de cada máquina.
- **Seguridad:** la lista es **cerrada**. Lo que llega de una plantilla, de un `.fclab` de otra persona o de un pedido se
  compara con el catálogo de Full Cowl (`Extras-Validos`) y lo desconocido se descarta; el programa que corre dentro de la
  máquina lo **vuelve a comprobar** contra su propio catálogo y nunca usa ese texto para montar una orden.

### Primer arranque

La máquina se crea con la instantánea **`inicio`** (volver a ella repite la configuración) y se
configura sola al arrancar:

- **Windows:** se personaliza (nuevo SID), pone el nombre de equipo y la IP, instala lo marcado y
  crea o une el dominio, reiniciando las veces necesarias. Mientras, en el escritorio aparece
  `CONFIGURANDO - NO APAGAR.txt`; al terminar, `Configuración de la VM.txt` con el resumen.
- **Linux:** nombre de equipo, IP fija y claves SSH nuevas antes de levantar la red; el software,
  en segundo plano (se puede entrar mientras). Progreso: `sudo tail -f /var/log/vmtareas.log`;
  al terminar aparece `~/configuracion-vm.txt`.

---

## 8. Mis máquinas

> **Símbolo de cada sistema.** Cada máquina lleva el logo o símbolo de su sistema. Si Full Cowl se equivoca, elige la máquina y cambia el desplegable **Símbolo** del panel de detalle (con ella apagada). «Automático» vuelve a deducirlo.

> **Vista y tamaño.** En Ajustes → Apariencia se elige ver las máquinas como *Tarjetas* o como *Lista* (con columnas Nombre, Sistema, Red, Estado, RAM y un botón rápido de encender/apagar) y el tamaño *Compacto*, *Normal* o *Grande*. La máquina seleccionada se mantiene al cambiar de vista.

### La lista

| Columna | Significado |
|---|---|
| Nombre | Nombre de la máquina. |
| Sistema | Familia del sistema. |
| Base | Base de la que sale. `(biblioteca)` = máquina de la biblioteca de VMware que no creó Full Cowl. |
| Tipo | **Base** (en negrita y arriba del todo), **Clon enlazado**, **Clon completo** o **Desechable** (se borrará al apagarse); solo **Clon** si no se puede saber (por ejemplo, una máquina antigua encendida). También reconoce los clones de versiones anteriores de Full Cowl. Vacío en las máquinas que no creó Full Cowl. |
| Estado | Encendida, apagada, suspendida o **Sin base** (clon enlazado cuya base ya no existe: no arrancará). Mientras una máquina nueva se configura sola pone **Configurando 3/5** (paso actual y total) y, al terminar, **Lista** durante media hora (o *Lista, con avisos* / *Error al configurar*). Eligiendo esa máquina, arriba sale el detalle: paso, qué hace y cuánto lleva. |
| Red | A qué red va cada tarjeta, por ejemplo `NAT + LAB-AD`. |
| IP fija | La primera IP fija configurada. |
| Tamaño | Lo que ocupa la máquina. Si su carpeta guarda también otras máquinas (por ejemplo un `.vmx` suelto en la carpeta de máquinas), solo cuenta sus propios archivos. |

**Las bases** salen en la lista para verlas, pero están **protegidas**: con una base elegida solo funciona
*Carpeta* (no se pueden encender, abrir en VMware, cambiar ni borrar desde aquí, porque se estropearían
sus clones). Se gestionan en [Crear base](#6-crear-una-base). El total de *Espacio en disco* de las
máquinas no las incluye.

**Varias a la vez:** `Ctrl+clic` o `Mayús+clic`. *Encender, Apagar, Red… y Borrar* trabajan con todas
las elegidas; el resto de botones, con una sola.

### Acciones rápidas y menú de clic derecho

Cada tarjeta lleva, arriba a la derecha, tres botones pequeños que **salen al pasar el ratón** o al llegar con el
teclado (Tab) y se ven siempre en pantallas táctiles. Su sitio está reservado: las tarjetas no se mueven.

| Botón | Qué hace |
|---|---|
| **Encender / Apagar** | Lo mismo que los botones de siempre. Mientras trabaja gira una ruedecita. (En la vista *Grande* ya tiene sus botones abajo y aquí no aparece.) |
| **Copiar IP** | Copia la IP al portapapeles y dice «Copiada: 192.168.206.51». Sin IP conocida está apagado y explica: «Aún no tiene IP: enciéndela y espera un momento». |
| **Conectar** | **Windows:** abre el Escritorio remoto (`mstsc /v:IP`) y avisa del usuario; **la contraseña la escribes tú**. Si el Escritorio remoto no está activo, lo explica. **Linux:** abre una ventana con `ssh usuario@IP` (en *Terminal de Windows* si está; si no, en una consola normal). La primera vez SSH pregunta por la «huella»: se escribe `yes`. La contraseña también la escribes tú. Apagado si la máquina está apagada, sin IP o es de un sistema sin conexión automática. |

**Full Cowl no guarda ni pasa la contraseña** a estos botones (no se usa `cmdkey` ni nada parecido). El botón **Conectar** del panel derecho
sigue como antes.

**Clic derecho** (o la tecla de menú, o Mayús+F10) sobre una máquina abre un menú con las mismas acciones más
**Copiar nombre**, **Copiar usuario@IP** (Linux), **Abrir carpeta de la máquina** y, si la máquina lleva servidor web,
**Abrir en el navegador** (`http://IP`). Con varias máquinas elegidas solo salen *Encender* y *Apagar*. En el mapa de
*Mis laboratorios* el clic derecho sobre cada máquina da Encender/Apagar, Copiar IP y Conectar. La IP es la fija de la
máquina si la tiene y, si no, la que dice VMware.

### Notas y etiquetas

Cada máquina (y cada base) puede llevar **etiquetas** y una **nota**, las dos opcionales, para encontrarla luego
y recordar para qué era. Se ponen en el panel derecho, apartado **Notas y etiquetas**, también con la máquina encendida.

- **Etiquetas.** Escribe una y pulsa `Enter` o una coma; salen como «píldoras» con una ✕ para quitarlas. Reglas:
  de 1 a 24 letras, hasta 8 por máquina, sin comas y sin distinguir mayúsculas (`Web` y `web` son la misma). Debajo
  del campo salen como sugerencia las que ya usan otras máquinas. Si una es demasiado larga o hay demasiadas, el
  campo avisa y lo escrito se queda donde está.
- **Nota.** Texto libre de hasta 500 letras, con contador. Se guarda sola al salir de la caja (sale «Guardado»
  un momento). **No escribas contraseñas:** la nota se guarda en el archivo de la máquina y la máquina puede leerla.
- **En la lista.** En las tarjetas salen hasta dos etiquetas y un «+N» si hay más, y un papelito si hay nota (al
  pasar el ratón se lee entera). Si no hay ni etiquetas ni nota, la tarjeta no cambia. En modo sobrio, las píldoras son grises.
- **Etiqueta «Lab …».** Las máquinas de un laboratorio llevan además una etiqueta fija «Lab NOMBRE». No se puede
  quitar desde el panel y desaparece si se borra el laboratorio (no se guarda: se calcula al leer).
- **Filtrar.** A la derecha de *Todas / Encendidas / Bases / Desechables / FC* (esta última enseña solo las máquinas hechas con Full Cowl, las que llevan la etiqueta **FC**) está **Etiquetas ▾**: casillas con cuántas
  máquinas tiene cada etiqueta. Con varias marcadas salen las máquinas que tengan **cualquiera** de ellas. Con el
  filtro puesto el botón se resalta y aparece **Quitar filtro**. Con 12 etiquetas o más el menú tiene su propio buscador.
- **Buscar.** El buscador (*Buscar máquina, base, IP o etiqueta*) mira también las etiquetas y el texto de la nota.
- **Máquinas nuevas.** Las copias **no heredan** las etiquetas ni la nota de su base. En *Nueva máquina*, paso
  «Nombre», hay un campo opcional **Etiquetas** para ponerlas ya al crearla.

### Botones

| Botón | Qué hace |
|---|---|
| **Encender / Apagar** | Apagar ofrece apagado normal (necesita VMware Tools) o forzado. |
| **Abrir en VMware** | Abre la máquina en Workstation (también con doble clic). |
| **Carpeta** | Abre su carpeta. |
| **Instantáneas…** | Crear, volver a una y borrar. |
| **Borrar** | Apaga si hace falta y borra la máquina. La carpeta solo se borra entera si contiene una única máquina. |
| **Red…** | Red del laboratorio (ver abajo). |
| **Conectar** | Windows: Escritorio remoto con el usuario y la contraseña ya puestos (se guardan en el Administrador de credenciales de Windows del PC). Linux: SSH. La máquina debe estar encendida y en una red a la que llegue el PC (NAT, solo anfitrión o puente). |
| **Archivos…** | Ver el escritorio de la VM, **enviar** archivos del PC a él y **traer** los elegidos al escritorio del PC. |
| **Usuarios…** | Usuarios en masa (ver abajo). |
| **Conservar** | Quita la marca de *desechable* a las elegidas: ya no se borrarán al apagarse. |
| **Exportar…** | (Importar está en su propio panel.) Exporta a un único `.ova` (por defecto en `<carpeta de máquinas>\_Exportadas`). Los clones enlazados salen completos. La máquina debe estar apagada. |

### Red del laboratorio

Aplica **la misma configuración de red a todas las máquinas elegidas**.

- **Tarjetas:** hasta 4 por máquina; cada una a *NAT* (con Internet), *Puente* (red de casa),
  *Solo anfitrión*, otra *VMnet* o un **segmento LAN**.
- **Segmentos LAN:** red aislada entre las máquinas que estén en el mismo segmento, sin Internet
  ni DHCP. Se crean desde el desplegable (*Nuevo segmento LAN…*) y se guardan también en VMware.
- **IP de cada tarjeta:** *No tocar*, *DHCP* o *IP fija*. Con IP fija se indica la primera y cada
  máquina recibe la siguiente (en orden alfabético): la ventana muestra cuál le toca a cada una.
- **Permitir ping entre ellas:** abre ICMP en el cortafuegos de Windows.

Las máquinas deben estar **apagadas** para cambiar sus tarjetas (la ventana se ofrece a apagarlas).
Si se cambia la IP, después se encienden y una consola la aplica dentro de cada sistema; en
Windows además se renombra el adaptador con el nombre de la red. Hace falta que las VMware Tools
respondan.

*Ejemplo — dominio en red aislada:* elegir el controlador y dos clientes → tarjeta 1 a
*Nuevo segmento LAN… → LAB-AD*, IP fija desde `192.168.100.10/24` → quedan en `.10`, `.11` y `.12`.

### Usuarios en masa

- **Por patrón:** prefijo y rango (`alumno01` … `alumno20`), contraseña y grupo comunes.
- **Desde CSV:** columnas `usuario;nombre;apellidos;password;grupo` (separador `;` o `,`, UTF-8 o
  el formato de Excel). *Crear CSV de ejemplo* deja uno listo para editar.
- **Destino según la máquina:** en un controlador de dominio, **Active Directory** (con unidad
  organizativa y grupos, que se crean si no existen); en otro Windows, usuarios **locales**;
  en Linux, usuarios con carpeta personal.
- Opción para que cambien la contraseña en el primer inicio de sesión.
- Active Directory exige contraseñas de 7+ caracteres con 3 tipos (mayúsculas, minúsculas,
  números, símbolos): la ventana avisa.

### Espacio en disco

Barra con lo que ocupan las bases, las máquinas, el resto del disco y lo libre; lo que ocupa cada
base y cuántas máquinas enlazadas tiene. **Limpiar restos** borra registros antiguos, cachés de
VMware de máquinas apagadas y temporales de los scripts, sin tocar ninguna máquina.

### Espacio y limpieza

En *Ajustes → Espacio y limpieza* (o pulsando el chip del disco en *Inicio*). Mide en segundo plano (se puede seguir usando
la pantalla; el resultado se guarda unos 5 minutos y **Volver a calcular** lo repite) y enseña:

- **Arriba:** la barra del disco de la carpeta de máquinas (Full Cowl / otros / libre) y lo que suman bases, máquinas e
  instantáneas. Las ISO salen solo como dato: **no se tocan**.
- **Bases:** tamaño, fecha y cuántas máquinas dependen de cada una. **Una base con máquinas enlazadas no se puede marcar**
  (dice cuáles son). Tampoco si alguna máquina no se pudo comprobar por estar encendida: apágala y vuelve a calcular.
- **Máquinas:** las de tu carpeta de máquinas, agrupadas por laboratorio, con estado, etiqueta (FC, Importada, Desechable) y base.
  **Las encendidas o abiertas en VMware no se pueden marcar**, ni las que tienen otras máquinas enlazadas colgando de ellas.
- **Instantáneas:** una fila por máquina que tenga. La `base` de las bases y el *Estado inicial del laboratorio* llevan la
  etiqueta **Necesaria** y no se marcan nunca (el estado inicial se quita desde *Laboratorio → ··· → Quitar el estado inicial*);
  tampoco las que tienen máquinas enlazadas. El tamaño es aproximado (≈).
- **Restos:** carpetas de la carpeta de máquinas (o de bases) **sin ningún `.vmx`**, restos de crear bases (`build\`), CD de
  configuración (`vmtareas.iso`) de máquinas ya configuradas, desechables apagadas que nadie borró y registros o candados de hace
  más de 30 días. **Marcar todos los restos** marca solo los claros (una carpeta con discos virtuales se marca a mano; una con
  archivos que no son de VMware no se puede marcar).
- **Abajo:** «Marcado: N elementos · liberarás X» y **Borrar lo marcado**. Pide confirmación con el recuento; para borrar una
  **base** hay que escribir además su nombre. Al terminar dice lo liberado y, si algo no se pudo, el motivo de cada cosa.

Solo borra dentro de la carpeta de máquinas, la de bases y las carpetas `build` y `estado` de Full Cowl, nunca a través de un
enlace o acceso a otra carpeta. Si tu carpeta de máquinas es una unidad entera (`D:\`) o una carpeta personal, no ofrece
«carpetas sin máquina» (podrían ser tuyas).

### Importar máquinas

Panel **Importar** (en el menú de la izquierda debajo de *Crear base*). Es la otra mitad de
*Exportar*: sirve para **pasar máquinas de un Full Cowl a otro**. Lo que se importa es una máquina
**completa e independiente** (no necesita ninguna base) que queda en tu carpeta de máquinas y sale en *Mis
máquinas* con el tipo **Importada**.

La pantalla sigue el mismo molde que *Crear base*: pasos numerados y un **resumen fijo** a la derecha con lo que falta y las comprobaciones (origen válido, nombre libre, espacio libre, contraseña guardada). En el paso 1 puedes **soltar** el archivo o la carpeta sobre la zona punteada, pulsarla para elegir un archivo, usar *Carpeta…* o escribir la ruta; al elegir sale una ficha con su nombre, tipo y tamaño.

| Qué eliges | Cómo se importa |
|---|---|
| Un `.ova` o `.ovf` (lo que saca *Exportar*, o de VMware/VirtualBox) | Con OVF Tool (viene con VMware Workstation). |
| Una carpeta con un `.vmx` | Se copia (con barra de progreso real). |
| Un `.zip` o `.7z` con esa carpeta | Se descomprime en una carpeta temporal y se coloca. El `.7z` necesita 7-Zip instalado. |

Se pide el **nombre** que tendrá en este PC (se valida igual que en *Nueva máquina*), el **usuario** de la
máquina (solo se usa si ella no lo trae apuntado) y si su **contraseña es la misma** que la de las máquinas de
este PC. Antes de empezar se comprueba el espacio libre y que el origen no esté abierto, suspendido ni sea un
**clon enlazado** (esos dependen de su base y fuera de su PC no funcionan: hay que exportarlos desde su Full
Cowl, que los saca completos). *Cancelar* para la copia y borra lo copiado; la máquina original no se toca.

Al terminar, Full Cowl le deja la máquina lista: identidad nueva (`uuid.action = create`, así VMware no
pregunta «¿movida o copiada?»), direcciones MAC nuevas, el nombre elegido y la marca de importada. Si trae
una IP fija que ya usa otra máquina de este PC, o una red que quizá no exista aquí, o no trae el agente de
Full Cowl, o su contraseña no es la de este PC, lo avisa al terminar (en el panel y en la consola).

Si la máquina viene de otro Full Cowl, *Exportar* guarda sus marcas (usuario, IP, agente…) dentro del `.ova`
y *Importar* las recupera; así conserva lo que Full Cowl puede hacer con ella. Si no se pudieran guardar, la
máquina se importa igual, pero sin esas marcas.

---

## 9. Laboratorio y máquinas desechables

La pestaña **Laboratorio** crea **varias máquinas de una vez**, todas en la misma red, con IP
seguidas y, si se quiere, un dominio ya montado. Pensado para prácticas puntuales: con la opción
**Desechable**, el laboratorio entero se borra solo del disco al apagarlo.

### Mis laboratorios (el mapa)
Laboratorio tiene dos pestañas. **Mis laboratorios** lista los que ya has creado y dibuja el elegido como un
**mapa de red**: cada red es una barra, cada máquina una tarjeta unida a su red por un cable, con Internet
arriba si la red es NAT y un recuadro punteado si hay dominio. Pulsa una máquina para ver sus datos y usar
sus botones (Encender/Apagar, Abrir, Red…, Usuarios…, Conectar); abajo están las acciones de todo el
laboratorio (Conservar, Volver al estado inicial, Exportar, **···**, Borrar). «Ver como lista» cambia el mapa por una lista. Los puntos que
corren por los cables solo se mueven con las animaciones en «Normales». La pestaña **Crear laboratorio** es
el formulario de siempre.

### Montar un laboratorio

| Campo | Descripción |
|---|---|
| **Nombre** | Nombre corto (máx. 8, por ejemplo `LAB1`). Va al principio del nombre de cada máquina: `LAB1-WS22-1`, `LAB1-W11-1`… |
| **Desechable** | Se borra todo cuando estén apagadas **todas** sus máquinas (ver abajo). Marcado por defecto. |
| **Arrancarlas** | Las enciende al terminar (el controlador de dominio primero). |
| **Guardar el estado inicial (recomendado)** | Marcada por defecto; se oculta con *Desechable*. Guarda cómo quedó el laboratorio al terminar de configurarse, para poder [volver a empezar con un clic](#volver-al-estado-inicial). Tarda un par de minutos más y ocupa poco. |
| **Empezar desde** | Chips: **En blanco** (vacía la lista), **Active Directory** (Windows Server de controlador + 2 clientes Windows, dominio `empresa.local`) y **Solo Linux** (Ubuntu + Kali); usan la base que tengas de cada tipo y avisan si falta alguna. Cada plantilla que guardes sale también como chip (con más de 3, en el desplegable *Mis plantillas*). *Guardar como plantilla* guarda el laboratorio actual (máquinas, red, IP, dominio); *Borrar plantilla* elimina la elegida. |
| **Máquinas** | Una fila por tipo de máquina («Kali · 4 GB · 2 CPUs cada una») con **− n +**: «+» copia la última de ese tipo y «−» quita la última. **Añadir otra base** despliega el formulario de siempre (base, cantidad, RAM, CPUs, vídeo 3D en MB; 0 = sin 3D → *Añadir*). **Ver las máquinas una a una** muestra la lista con base, RAM, CPUs, vídeo, papel en el dominio e IP, y *Quitar* / *Vaciar* / *Hacer controlador*. Para cambiar la memoria, procesadores o vídeo de **una** máquina, púlsala en la **vista previa** (panel *Esta máquina*; − y +, o escribir; *Aplicar a las demás* copia los valores a las del mismo tipo). Arriba, la RAM total frente a la del PC (en naranja si pasa del 80 %). |
| **Red** | Chips **Aislada (segmento LAN) / NAT (con Internet) / Solo anfitrión**. *Aislada* usa el segmento elegido o el primero que haya (si no hay, pide crearlo). **Otras redes**: puente, otras VMnet, otros segmentos y *Nuevo segmento LAN…*. |
| **IP** | *Automática (DHCP)* o *IP fija desde*: cada máquina recibe la siguiente (avisa si alguna ya la tiene otra máquina tuya). En NAT propone la red de VMware; en un segmento, `192.168.100.10/24` sin puerta de enlace. Los campos (primera IP, prefijo, puerta de enlace —opcional— y DNS) están en **Ajustes avanzados de la red**, plegado por defecto. |
| **Permitir ping entre ellas** | Abre ICMP en los Windows (dentro de *Ajustes avanzados de la red*). |
| **Crear un dominio** | Elige un **Windows Server** y pulsa **Hacer controlador** en la lista una a una, o marca **Es el controlador del dominio** en el panel *Esta máquina* de la vista previa: sale en verde y en negrita, sube al principio y recibe la primera IP. Los demás Windows pasan solos a *Cliente del dominio*; los Linux quedan *Fuera del dominio*. Si no eliges ninguno, lo es el primer Windows Server. Marcar un controlador activa la casilla del dominio. Exige IP fija; todos usan el controlador como DNS. La plantilla recuerda cuál era el controlador. |

**Crear laboratorio** abre una consola que crea las máquinas una tras otra (clones enlazados, en
segundos cada una), las arranca y muestra un resumen. Cada máquina se configura sola en su primer
arranque como en [Nueva máquina](#7-nueva-máquina). Con dominio, el controlador tarda unos
10-15 minutos en crearlo; los demás Windows esperan solos (hasta 30 min) y se unen.

*Ejemplo — práctica de Active Directory:* `1 × WinServer2022` + `2 × Win11Pro`, red *Nuevo
segmento LAN → LAB-AD*, IP fija desde `192.168.100.10/24`, dominio `empresa.local`, desechable.
Resultado: `LAB1-WS22-1` (.10, controlador), `LAB1-W11-1` (.11) y `LAB1-W11-2` (.12) unidos al
dominio. Al apagar las tres, desaparecen.

Las plantillas se guardan en `full-cowl/plantillas-laboratorio.json` (propio de cada PC).

### Volver al estado inicial

Sirve para repetir una práctica desde cero sin rehacer el laboratorio.

- **Cómo se guarda.** Con la casilla *Guardar el estado inicial* marcada, cuando **todas** las máquinas acaban de configurarse
  (el mismo momento del aviso «Laboratorio listo») un trabajo oculto las **apaga con calma**, hace una instantánea llamada
  `inicio-lab` en cada una y **vuelve a encender las que estaban encendidas**, todas a la vez. Se ve en *Inicio → En marcha* y
  arriba en *Mis laboratorios* («Guardando el estado inicial 2 de 4»). Si alguna máquina terminó «con avisos» no se guarda
  sola: arregla lo que falle y usa **···**. Los laboratorios **desechables no lo ofrecen** (se borran al apagarse).
- **Laboratorios que ya tenías.** En *Mis laboratorios*, menú **···** → *Guardar el estado de ahora como inicial*. Si hay máquinas
  encendidas pregunta: *Apagar y guardar (recomendado)* o *Guardar encendidas* (guarda también la memoria, que ocupa tanto como
  su RAM). **···** → *Quitar el estado inicial* lo borra (pide confirmación).
- **Volver.** Botón **Volver al estado inicial** (icono de deshacer). Sale apagado, con «Este laboratorio no tiene estado inicial
  guardado», si ninguna máquina lo tiene. El cuadro de confirmación lista cada máquina (✓ tiene estado inicial, ✗ no) y avisa de que
  **se perderá todo lo hecho dentro de las máquinas** desde que se creó el laboratorio. Casilla *Dejarlas encendidas al terminar*
  (marcada si estaban encendidas). Si solo lo tienen algunas, el cuadro avisa (en un laboratorio con dominio puede quedar descuadrado)
  y ofrece *Volver solo las N que se puede* o *Guardar su estado ahora*.
- **Qué hace por dentro.** Comprueba que todas las elegidas tienen `inicio-lab`; las apaga (60 s con calma y luego a la fuerza);
  `revertToSnapshot inicio-lab`; si hay que dejarlas encendidas, las arranca en orden (controlador primero, esperando a las VMware
  Tools). No se puede cancelar a mitad de una máquina. Si una falla, sigue con las demás y al final dice «3 bien, 1 con problema: …»
  (*Detalles* / *Copiar*).
- **En *Mis máquinas*,** el diálogo *Instantáneas* enseña `inicio-lab` como «Estado inicial del laboratorio», no deja usar ese nombre
  para una instantánea nueva y avisa al volver o borrar (en un laboratorio con dominio, de que volver una sola máquina puede
  dejarlo descuadrado).
- **Límites.** El estado inicial **no viaja** en el `.fclab` (es de cada PC). Nunca toca la instantánea `base` ni las de otros
  laboratorios. Ocupa poco si se guardó con las máquinas apagadas.

### Ficha del laboratorio (documento para la memoria)

En *Mis laboratorios*, con un laboratorio elegido, el botón **Ficha del laboratorio** crea un documento con las IP, los
usuarios y los roles de cada máquina, para pegarlo en la memoria de una práctica. **No enciende ni toca las máquinas.**

- **Formato:** *PDF* (A4 vertical, siempre en claro, para imprimir; con el esquema de la red dibujado) o *Texto* (un `.md` con
  tablas, para pegar en Word; sin el esquema).
- **Título** (por defecto «Laboratorio NOMBRE») y **autor** (por defecto el de *Ajustes → General → Tu nombre*).
- **Qué incluir:** esquema de la red, usuarios, recursos (RAM, procesadores y disco) y espacio para notas.
- **Guardar en:** la que tengas puesta en *Ajustes → Este PC → Carpeta de las fichas del laboratorio* (si no has puesto ninguna, `Documentos\Full Cowl\Fichas`; se crea sola) o, solo para esta vez, la que elijas con **Cambiar…**; **Abrir al terminar**.
- **Qué lleva:** cabecera, resumen, tabla de máquinas (sistema, rol, IP, red, usuario, recursos), dominio y red, roles y
  software que Full Cowl conoce, esquema, cómo conectarse a cada máquina y notas. La IP sale de lo que Full Cowl tiene
  apuntado; en las máquinas encendidas sin IP fija se pregunta a VMware (solo lectura); si no se sabe sale «sin IP».
- **Nunca lleva la contraseña** de las máquinas (el pie lo dice). Los nombres y notas se escriben escapados.
- **El PDF se hace con Microsoft Edge** (viene con Windows; si no, Chrome) sin abrir ventana. Si no hay navegador compatible o
  falla, se guarda la ficha como página web y te dice que la abras y pulses Ctrl+P → Guardar como PDF.
- Los **usuarios creados** con el botón *Usuarios…* **no** se guardan en ningún sitio, así que no salen (la columna *Usuario*
  es el de la base de cada máquina). Si el laboratorio tiene estado inicial guardado, el resumen dice «Estado inicial: Guardado el dd/mm/aaaa».

### Compartir un laboratorio

Una plantilla se puede pasar a otra persona (correo, Teams, Moodle) como un archivo **`.fclab`**. Lleva la **receta**
(qué máquinas, RAM, procesadores, red, dominio), **no los discos**: quien lo recibe monta el laboratorio con sus propias bases.
El archivo es texto (JSON) que puedes abrir con el Bloc de notas y **nunca lleva** rutas, tu usuario de Windows, el usuario
ni la contraseña de las máquinas, direcciones MAC ni nada de este PC (Full Cowl lo comprueba antes de guardar).

| Quiero | Cómo |
|---|---|
| **Exportar lo que estoy preparando** | Laboratorio → Crear laboratorio → **Plantillas ▾ → Exportar…** |
| **Exportar una plantilla** | Elige la plantilla y pulsa **···** → *Exportar…* (las guardadas también tienen *Renombrar* y *Borrar*) |
| **Exportar un laboratorio ya creado** | Laboratorio → Mis laboratorios → **Exportar como plantilla** |
| **Importar** | **Plantillas ▾ → Importar…**, o **arrastra el `.fclab` a la ventana** de Full Cowl |

Al importar sale una **pantalla de revisión** antes de crear nada: nombre, descripción, el **mapa** de cómo quedará y una
lista de lo que hace falta: «✓ Tienes la base WinServer2022» o «✗ Te falta la base Kali», con **Crear esa base** (te lleva a
*Crear base* con el sistema elegido) y **Quitar esta máquina**. También avisa si la RAM total supera la de tu PC, si hay
extras sin Internet o si el nombre ya existe (propone «nombre 2»). **Usar esta plantilla** la guarda entre las tuyas y la
carga en *Crear laboratorio* para que la cambies; **la creación sigue siendo un paso aparte**. Si el archivo está dañado, es
de un formato más nuevo («Actualiza Full Cowl») o trae campos raros, no rompe nada: avisa y los ignora.

Hay tres laboratorios listos para probar en la carpeta **`laboratorios/`** (Importar → *Ver laboratorios de ejemplo*):
dominio con 2 clientes, servidor web y cliente, y Kali y objetivo. Abrir un `.fclab` con doble clic desde el Explorador
todavía no funciona (por ahora, arrástralo a la ventana).

### Saber cuándo está listo (progreso)

Al crear un laboratorio se abre la ventana **Progreso de la configuración** (también con el botón
**Ver progreso** de la tarjeta *Laboratorio*). Muestra cada laboratorio con su barra total
(«1 de 3 listas») y, debajo, cada máquina con su paso, una barra y el tiempo que lleva. No bloquea:
se puede seguir usando Full Cowl con ella abierta. Las máquinas sueltas de *Nueva máquina* también
aparecen. Cuando terminan **todas** las máquinas de un laboratorio, Windows avisa abajo a la derecha:
*«Laboratorio 'LAB1' listo: ya puedes empezar a trabajar»* (aunque Full Cowl esté cerrado).

| Paso | Windows | Linux |
|---|---|---|
| 1 | Preparando el sistema (primer arranque tras sysprep) | Preparando el sistema |
| … | Cambiando el nombre · Configurando la red · Instalando roles y extras | Configurando la red (nombre e IP) |
| … | Controlador: *Creando el dominio* → *Arrancando el controlador* | Actualizando el sistema (si se pidió) |
| … | Cliente: *Esperando al controlador* → *Uniéndose al dominio* | Instalando servicios (si se pidieron) |
| fin | **Lista** (o *Lista, con avisos* / *Error al configurar*) | **Lista** |

Solo cuentan los pasos que se pidieron, así que «3 de 5» es real. Dentro de cada paso la barra
avanza según el tiempo estimado (el de crear el dominio, unos 9 min). **Necesita las VMware Tools**
en la máquina: con una base sin ellas sale «Sin datos» (rehacer la base). Solo funciona con las
máquinas creadas desde esta versión.

### Máquinas desechables

- **Cuándo se borran:** cuando **todas** las máquinas del grupo (el laboratorio, o la máquina suelta)
  llevan 30 s apagadas. Reiniciar no cuenta como apagar; una máquina **suspendida** no se borra.
  Solo se borran si llegaron a encenderse (crear sin arrancar no las borra).
- **Aviso:** Windows muestra un globo de Full Cowl: «Laboratorio 'LAB1' borrado (3 máquinas)».
- **Quién las vigila:** un proceso oculto (`vigilante.ps1`) que se pone en marcha al crear
  desechables y al abrir Full Cowl, y se cierra solo cuando no queda ninguna. Si el PC se apaga con
  ellas encendidas, se borran la próxima vez que se abra Full Cowl.
- **Máquina suelta:** casilla *Desechable* en [Nueva máquina](#7-nueva-máquina): se borra al apagarla.
- **Quedarse con alguna:** *Mis máquinas* → elegirla → **Conservar**. Deja de ser desechable (si
  estaba encendida, en cuanto se apague). El resto del laboratorio sí se borra. Las máquinas
  conservadas **siguen siendo del laboratorio**: salen en *Laboratorio → Mis laboratorios* aunque cierres
  Full Cowl (el laboratorio no se guarda aparte: son las máquinas con la misma marca de laboratorio).
- En *Mis máquinas* la columna *Tipo* dice **Desechable**.
- Las desechables son siempre **clones enlazados**.

---

## 12. Funcionamiento interno

### Componentes

```
Ventana (ventana-nueva.ps1 + interfaz\, WPF)
   │ escribe un "pedido" JSON en %TEMP% y abre una consola con el script que toca
   ▼
crear-base.ps1 ──► Packer ──► VMware Workstation (base + instantánea "base")
nueva-maquina.ps1 ──► vmrun clone ──► .vmx + CD VMTAREAS (vmtareas.iso)
laboratorio.ps1 ──► nueva-maquina.ps1 (una vez por máquina) ──► arranque
usuarios.ps1 / red-ip.ps1 ──► vmrun (operaciones dentro del invitado vía VMware Tools)
exportar.ps1 ──► OVF Tool (.ova)
importar.ps1 ──► OVF Tool / copia / descompresión ──► máquina completa marcada «importada»
vigilante.ps1 (oculto) ──► borra los grupos desechables apagados
```

### Bases (Packer)

| Sistema | Plantilla | Desatendido mediante |
|---|---|---|
| Windows | `packer/windows.pkr.hcl` | `autounattend.xml` (disquete; en Windows 11 también en CD, con las claves *LabConfig* para saltar TPM/arranque seguro). Comunicación por **WinRM**. Al final, `sysprep /generalize` lanzado por una tarea programada. |
| Ubuntu | `packer/ubuntu.pkr.hcl` | *autoinstall* (cloud-init) en un CD con etiqueta `CIDATA` creado con IMAPI2 de Windows. Comunicación por **SSH**. |
| Kali | `packer/kali.pkr.hcl` | *preseed* de Debian servido por el servidor HTTP de Packer (puerto 8820). |

Workstation ya no incluye VNC, así que Packer no puede teclear en la VM: de ahí la línea de Kali y, en
Ubuntu, la mini-ISO de arranque (GRUB con arranque BIOS y EFI; busca el CD que tiene `/casper/vmlinuz` y lo arranca con
`autoinstall`; Packer la pone como su CD y la ISO de Ubuntu va en `sata0:0`; fuente y script en `recursos\arranque\`). Los provisionadores (`packer/*/provision.*`) instalan el **agente de primer
arranque**, ajustan el sistema y lo limpian para clonar (sin claves SSH, `machine-id` vacío, sin
archivos de instalación). El progreso se escribe en `estado/<Clave>.json`, que lee la ventana.

### Clones y agente de primer arranque

`nueva-maquina.ps1` clona con `vmrun clone` desde la instantánea `base`, ajusta el `.vmx` (RAM,
CPUs, 3D, `guestinfo.*`) y crea un **CD `VMTAREAS`** con la configuración:

- **Windows:** `config.json` + `config.ps1` (copia de `clon/config-windows.ps1`). La tarea programada
  `VMTareas-Agente` (SYSTEM, al arrancar) lo ejecuta por pasos con marcas en
  `C:\ProgramData\VMTareas` para continuar tras cada reinicio.
- **Linux:** `config.env` + `temprano.sh` (servicio `vmtareas-temprano`, antes de la red: nombre e IP)
  + `config.sh` (servicio `vmtareas-config`, con red: paquetes).

**Extras (ficha 20).** La lista de extras va en el CD (`extras` de `config.json`; `PAQUETES` de `config.env`), ya filtrada por
`Extras-Validos`. El agente solo acepta identificadores `[a-z0-9]{1,24}` y los busca en su catálogo (`case` en `config.sh`,
`switch` en `config-windows.ps1`): lo que no está se marca `desconocido` y no se ejecuta nada. Publica cómo va en
`guestinfo.vmtareas.extras.estado` (`apache=ok;mariadb=instalando`; estados `espera`, `instalando`, `ok`, `fallo`,
`desconocido`), que el vigilante lee y guarda en `estado\progreso.json` (campo `extras`). El `.vmx` lleva
`guestinfo.vmtareas.extras` (lo pedido, separado por comas) **solo para enseñarlo**: el agente no lo lee.

Claves del `.vmx` que usa Full Cowl: `guestinfo.hostname`, `guestinfo.vmtareas.ip`,
`.dominio`, `.netbios`, `.base`, `.copia`, `.cdclave`, `.desechable` (identificador del grupo que se
borra junto), `.lab` (nombre del laboratorio), `.agente` (en las bases), `.etiquetas` (lista separada por
comas) y `.nota` (una línea; los saltos de línea van como `\n`, las barras como `\\` y el `|` como `|7C`).

### Laboratorios y desechables

`laboratorio.ps1` calcula la IP y el papel de cada máquina (controlador primero) y llama a
`nueva-maquina.ps1 -EnLote` para cada una, con la red de la primera tarjeta y la marca de desechable.
El agente admite IP fija **sin puerta de enlace ni DNS** (segmentos LAN) y marca las redes sin
identificar como privadas. `vigilante.ps1` (un solo proceso, *mutex* `FullCowlVigilante`) revisa
cada 10 s: agrupa las desechables por `guestinfo.vmtareas.desechable`, recuerda en
`estado\desechables.json` las que ya se encendieron y borra el grupo con `vmrun deleteVM` cuando todo
lleva 30 s apagado. *Conservar* con la máquina encendida se apunta en `estado\conservar.json`.
Registro: `estado\vigilante.log`.

**Progreso.** El agente de cada máquina publica su paso con `rpctool` (Windows) o `vmware-rpctool`
(Linux) en `guestinfo.vmtareas.progreso` = `1|paso|total|segundos estimados|inicio (epoch UTC)|estado|clave`
(estado: `curso`, `ok`, `fallos`, `error`; claves sin tildes, el texto lo pone la ventana). El
vigilante lo lee desde fuera con `vmrun readVariable <vmx> guestVar vmtareas.progreso` (sin contraseña)
para las máquinas encendidas con agente, y lo guarda en `estado\progreso.json`, que la ventana lee
sin llamar a `vmrun`. `nueva-maquina.ps1` apunta `guestinfo.vmtareas.creada` (para mostrar
«Preparando» antes de que la máquina diga nada) y `guestinfo.vmtareas.labid` (para agrupar el
laboratorio y avisar una sola vez). El vigilante sigue en marcha mientras haya desechables o
máquinas configurándose.

### Operaciones dentro de la VM

Usuarios, red y archivos usan `vmrun -gu <usuario> -gp <contraseña>` (copiar archivos, ejecutar
programas) a través de las **VMware Tools**. Se copia un script (`clon/usuarios-*`, `clon/red-*`)
y sus datos, se ejecuta como administrador (en Linux con `sudo`), se recoge el registro y se borran
los archivos temporales. En Windows van a `C:\Windows\Temp` (los demás usuarios no pueden leerlos);
en Linux, a una carpeta privada `~/.fullcowl-<id>` creada con `createDirectoryInGuest`, que se
borra entera con `deleteDirectoryInGuest` aunque algo falle.

### Red

- Tarjetas: claves `ethernetN.*` del `.vmx` (`connectionType` = `nat` / `bridged` / `hostonly` /
  `custom` + `vnet` / `pvn` + `pvnID`). Las tarjetas nuevas reciben **MAC fija** (rango de VMware
  `00:50:56:00:00:00`–`3F:FF:FF`) para reconocerlas dentro del sistema.
- Segmentos LAN: `%APPDATA%\VMware\preferences.ini` (`pref.namedPVNs*`) y `segmentos.json`.
- Redes VMnet: registro `HKLM\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib\VMnetConfig`.
- Dentro: Windows con los cmdlets `NetTCPIP`; Ubuntu con **netplan** (una entrada por MAC);
  Kali/Debian con perfiles de **NetworkManager**.

---

## 13. Seguridad

Revisión completa del código el 29/10/2026 (versión 1.3.1). Resumen de cómo se protege cada cosa:

**Contraseña de las VMs**

- **No está en el código ni en el repositorio.** Se guarda en `password.sec` cifrada con **DPAPI**
  de Windows: solo la puede descifrar el mismo usuario en el mismo PC. Copiada a otro equipo no sirve.
- A Packer se le pasa por **variable de entorno** (`PKR_VAR_password`, marcada como secreta), no por
  la línea de comandos; se vacía al terminar. Si Packer falla, `ultimo-error-packer.log` se guarda
  **con la contraseña tachada** (`********`).
- **La contraseña real no se usa para instalar la base** (desde la 2.0). Los archivos de instalación
  (respuestas de Windows, `user-data` de Ubuntu, preseed de Kali, el CD `cidata` y el disquete) llevan
  una contraseña **aleatoria de 24 caracteres de un solo uso**, que solo existe mientras se instala y
  que nadie ve ni usa después. Así la tuya no queda en esos archivos (que están en `build\` y se
  borran al terminar o cancelar), ni en el disco de la base (donde Windows guarda una copia del
  archivo de respuestas hasta que arranca la primera máquina), ni en las máquinas que exportes.
  Cada máquina recibe la real en su primer arranque, por el CD de configuración (ver más abajo). Dentro
  de la base se borran además los restos de la instalación (registros del instalador, cloud-init) y el
  inicio de sesión automático.
- **Kali:** el preseed se sirve por HTTP **solo en la red NAT de VMware (VMnet8)**, no en la wifi
  ni en la red de clase.
- **CD de configuración con la contraseña** (todas las máquinas de bases nuevas, y las de dominio de
  cualquier base): es el único sitio donde viaja la real. Se quita del `.vmx` y se borra cuando
  la máquina se apaga habiendo funcionado al menos media hora desde que se creó (se da por configurada;
  lo hacen el vigilante, *Nueva máquina* y el cierre de Full Cowl). Una máquina que aún lo lleva **no se puede exportar** a `.ova`. En Linux el CD se monta **solo
  legible por root**.
- *Conectar* (Escritorio remoto) deja la contraseña en el Administrador de credenciales de Windows
  solo **un minuto** (lo justo para conectar) y luego la borra.
- `vmrun` recibe la contraseña en su línea de órdenes (`-gp`), que solo ve tu propio usuario de
  Windows: es como funciona VMware y no se puede evitar.

**Máquinas que salen de las bases**

- **Windows:** antes de sysprep se cierra la administración remota que usa Packer (WinRM **sin
  cifrar y con autenticación básica**, puerto 5985, regla `WinRM-Packer`). Windows 10/11 quedan sin
  WinRM; Windows Server conserva el de serie (cifrado, Kerberos/Negotiate). Se mantiene
  `LocalAccountTokenFilterPolicy` (lo usan las operaciones de Full Cowl dentro de la VM).
- **Linux:** cada copia genera sus **propias claves SSH** y su `machine-id`. SSH acepta contraseña
  (lo usa *Conectar*): en una red puenteada, la máquina queda visible en tu red como un equipo más.
- El agente de Windows guarda su registro en `C:\ProgramData\VMTareas`, solo para administradores.

**Datos que llegan de fuera** (CSV, nombres, VMs)

- **Nombres de máquinas y de segmentos LAN:** solo letras, números, espacios y `. _ - ( )`.
- **Usuarios en masa:** usuarios, grupos y OU se validan antes de enviarlos (sin comillas, comas
  ni caracteres que se cuelen en las órdenes de Active Directory o de Linux).
- **Red…:** MAC, IP, prefijo, puerta y DNS se validan antes de enviarlos.
- **Nueva máquina** vuelve a validar IP, dominio, extras y paquetes aunque vengan de la ventana:
  acaban en scripts que se ejecutan como root/SYSTEM dentro de la VM.
- `config.local.json`: si trae un usuario, una zona horaria o números no válidos, se usan los
  valores por defecto.
- **Traer a mi PC:** el nombre del archivo lo da la VM, así que se limpia (`..\`, rutas, caracteres
  raros) y nunca se pisa un archivo existente. Una VM comprometida (por ejemplo en un laboratorio de
  seguridad) no puede escribir fuera de tu escritorio.
- **Usuarios en masa y Red en Linux** trabajan en una carpeta privada de la casa del usuario
  (`~/.fullcowl-…`), no en `/tmp`, y la borran al terminar aunque algo falle.

**Borrados**

- Las **desechables** solo se borran si están en tu carpeta de máquinas: una copia o una
  exportación de una desechable que esté en otro sitio nunca se borra sola.
- **Borrar** (y el vigilante) solo eliminan la carpeta entera si es una subcarpeta de tu carpeta de
  máquinas o si únicamente tiene archivos de VMware. Nunca una unidad, tu perfil, Documentos, el
  escritorio, Archivos de programa, la carpeta de bases ni la de Full Cowl.

**Otros**

- Los **pedidos** de la ventana a los scripts (archivos temporales en `%TEMP%`, que pueden llevar
  contraseñas de usuarios nuevos) van **cifrados con DPAPI** y se borran al leerlos.
- Las VMware Tools de Windows se instalan primero desde la carpeta de VMware (que solo puede
  cambiar un administrador) y solo si no está, desde la carpeta de ISOs.
- `.gitignore` excluye `config.local.json`, `password.sec`, preferencias, segmentos, plantillas,
  estado, `build\`, registros y accesos directos.
- Las claves de producto de Windows son las **genéricas de instalación** publicadas por Microsoft
  (permiten instalar, no activan).

**Riesgos que quedan (asumidos)**

- Las ISO no se comprueban (`iso_checksum = "none"`): descárgalas de las webs oficiales.
- Las bases no se actualizan solas: son para prácticas, no para usarlas en Internet como equipos reales.
- Mientras una máquina se configura, su CD (con la contraseña) es legible dentro de esa VM (en Linux, solo por root; en Windows, por los administradores). Se borra del PC cuando la máquina se apaga ya configurada: una máquina que se deja encendida días sigue teniendo el CD.
- Si una máquina de una base nueva no llegara a leer su CD (por ejemplo, se apaga en el primer arranque antes de configurarse), se queda con la contraseña temporal y no se puede entrar: hay que rehacer esa máquina.
- Full Cowl se ejecuta con tus permisos (y *Crear base* como administrador): no dejes que otros
  usuarios del PC puedan modificar la carpeta de Full Cowl.

---

## 14. Solución de problemas

| Síntoma | Causa / solución |
|---|---|
| El comando de instalación dice que no se puede descargar | Sin Internet o la red del centro bloquea GitHub (filtro web): prueba con otra red, o descarga el ZIP de *Releases* y usa `Instalar Full Cowl.bat`. |
| El instalador dice que la suma SHA-256 no coincide | La descarga llegó dañada (o alguien la cambió): no se instala nada. Vuelve a intentarlo más tarde. |
| Windows avisa al abrir `Instalar Full Cowl.bat` (SmartScreen) o el antivirus lo para | Es un script sin firmar: «Más información» → «Ejecutar de todas formas». Si el antivirus lo bloquea, añade la carpeta como excepción. |
| «No he podido instalar Packer» | Sin Internet, o `releases.hashicorp.com` bloqueado. A mano: descarga el ZIP de Windows de la versión que dice el mensaje y copia `packer.exe` en `herramientas\packer`. |
| La actualización dice «no coincide con su suma SHA-256» | La descarga llegó dañada: no se ha cambiado nada. Repite más tarde. |
| La ventana no se abre | Mirar `full-cowl/estado/interfaz.log`; el aviso indica el archivo y la línea. Si dice que hay errores en los archivos, `Actualizar.bat` los vuelve a traer. |
| Windows sale en español aunque pedí inglés | La ISO solo trae español (el idioma de los menús viene de la ISO). El teclado, los formatos y la hora sí son los pedidos. Para Windows en inglés, usa una ISO en inglés y rehaz la base. |
| *Conectar* dice «SSH no responde» en Kali | El servidor SSH estaba desactivado (Kali lo trae así y alguna actualización lo vuelve a apagar). Dentro de la máquina: `sudo systemctl enable --now ssh`. Las copias nuevas lo activan solas. |
| Mi base antigua dice «ES · Madrid» | Es lo normal: las bases hechas antes de poder elegir idioma son en español y con la zona de `config.ps1`. Siguen funcionando y sus máquinas pueden llevar otra zona horaria. |
| La máquina no ha cambiado de zona horaria | Mira el registro de la máquina (Windows: `C:\ProgramData\VMTareas\config.log`; Linux: `/var/log/vmtareas.log`): si sale «AVISO zona horaria», el sistema no conocía esa zona y se dejó la de la base. |
| **Conectar** por SSH dice que falta el cliente SSH | Windows 10/11 lo trae como función opcional: *Configuración → Aplicaciones → Características opcionales → Cliente OpenSSH*. Mientras tanto, abre una consola y escribe `ssh usuario@IP`. |
| «VMware no ha contestado en N segundos» | VMware estaba ocupado o colgado y Full Cowl ha dejado de esperar (antes la ventana se quedaba «No responde»). No se ha roto nada: solo se cierra la orden que lanzó Full Cowl, nunca VMware ni las máquinas. Espera un poco y repite; en acciones largas (borrar, instantáneas, copiar) mira primero si terminó igualmente. Si se repite, cierra VMware y ábrelo de nuevo. Queda apuntado en `full-cowl\estado\vmrun.log` (sin contraseñas). |
| *Volver al estado inicial* falla en una máquina | El resumen final dice cuál y por qué (*Detalles*). Casi siempre: la máquina estaba abierta en VMware con un cuadro pendiente o sin espacio en disco. Ciérralo y repite; las demás ya volvieron. |
| *Espacio y limpieza*: una base o una máquina no se puede marcar | La fila dice por qué (pasa el ratón o lee la línea naranja): máquinas que dependen de la base, máquina encendida o abierta en VMware, carpeta con otros archivos… Arréglalo y pulsa **Volver a calcular**. |
| El botón *Volver al estado inicial* sale apagado | El laboratorio no tiene estado inicial (se creó antes o sin la casilla). Menú **···** → *Guardar el estado de ahora como inicial*. |
| Ubuntu: la máquina enseña «FULL COWL: no he podido arrancar el CD de Ubuntu desde el CD de arranque» | El CD pequeño de arranque no encontró tu ISO. *Cancelar*, en *Crear base* desmarca **Empezar sin escribir «yes»** y repite (habrá que escribir `yes`). Haz una captura de esa pantalla para el aviso del fallo: abajo lista los discos que ve. |
| Un extra sale con ✗ en el panel de la máquina | No se pudo instalar: casi siempre la máquina no tenía Internet en ese momento (red aislada, DNS). La máquina funciona igual. Mira el registro dentro de ella (`/var/log/fullcowl-extras.log` o `C:\\ProgramData\\VMTareas\\extras.log`) e instálalo a mano, o vuelve a la instantánea `inicio` con Internet para repetirlo. |
| *Ficha del laboratorio*: «No se pudo crear el PDF» | No hay Edge ni Chrome (o tardó más de 30 s). La ficha queda como página web (`.html`) en la misma carpeta: ábrela y pulsa **Ctrl+P → Guardar como PDF**. También puedes elegir el formato *Texto*. |
| «No he podido guardar» al poner una etiqueta o una nota | VMware tiene el archivo de la máquina ocupado en ese momento. Prueba otra vez en unos segundos o apaga la máquina. Lo escrito se queda en pantalla. |
| PC nuevo: «No se puede enlazar el argumento con el parámetro 'Path' porque es una cadena vacía» | Fallo hasta el 05/11/2026 en la primera vez (antes de elegir las carpetas). `Actualizar.bat` lo arregla. |
| La consola dice «Falta configurar las carpetas de este PC» | Abrir `Full Cowl.bat` una vez y completar el asistente. |
| Packer: `Waiting for WinRM to become available...` más de 15 min | Abrir la VM (`File > Open` el `.vmx` de `_Bases\<Clave>`). Si hay un aviso de red, aceptarlo; si no, en PowerShell como administrador: `Enable-PSRemoting -SkipNetworkProfileCheck -Force` y `Restart-Service WinRM`. Packer continúa solo. Si `build\<Clave>\packer.log` repite «401 - invalid content type», WinRM ya está configurado pero sin reiniciar: basta `Restart-Service WinRM` (las bases nuevas ya lo hacen solas). |
| Packer: «== VMware Tools ==» sale dos o tres veces | Al instalarse, las Tools cambian el driver de red, se corta la conexión y Packer repite el paso. No pasa nada; desde ahora la repetición espera a la instalación en curso en vez de lanzar otra. |
| Windows Server: `Get-Service WinRM` sale *Running* | Es lo normal: Windows Server trae la administración remota de serie (cifrada, sirve para administrar servidores desde *Administrador del servidor*). Lo que se cierra es lo de Packer: `winrm get winrm/config/service` debe mostrar `AllowUnencrypted = false` y `Basic = false`. En Windows 10/11 sí sale *Stopped*. |
| Kali: «Falló un paso de la instalación: Seleccionar e instalar programas» (`Unable to fetch some archives`) | El espejo de Kali estaba a medio sincronizar. Desde la 2.0 el instalador solo pone lo mínimo y el escritorio se instala después con reintentos; si aun así falla, repetir la base un rato después. |
| Packer se queda en `Powering on virtual machine` (la VM sí arranca e incluso se instala, pero la barra no avanza) | VMware no le confirma a Packer que la encendió (fallo de `vmrun … gui`). Windows, Ubuntu y Kali ya se crean sin ventana para evitarlo (Ubuntu y Kali la abren después, para escribir `yes` o la línea de arranque): *Cancelar*, `Actualizar.bat` y repetir. |
| `ultimo-error-packer.log` | Registro detallado del último fallo de Packer (junto a los scripts). |
| Ubuntu: pantalla negra tras iniciar sesión | Se usa Xorg en lugar de Wayland; si pasa en una base antigua, rehacerla. |
| Kali sigue preguntando idioma o red | La línea del prompt `boot:` no se leyó bien: *VM > Power > Restart Guest* y repetirla (cuidado con el teclado inglés). La línea exacta con la IP de tu PC y las teclas del teclado español se ven en *Crear base* al elegir Kali, antes de crearla. |
| Windows: VMware Tools no instaladas (en VMware sale *Install VMware Tools*) | Las bases creadas antes del 29/10/2026 no las traían (fallaba la descarga): **rehacer la base** en *Crear base*. En una máquina ya creada, a mano: *VM > Install VMware Tools*. Hacen falta para Usuarios, Red (IP), Archivos y apagado normal. **No arrancar la base** para instalarlas: se estropea. |
| Una máquina sale como **Sin base** | Su base se borró o se rehízo: el clon enlazado ya no arranca. (Hasta octubre de 2026 también salía, por error, en clones enlazados hechos a mano en VMware; ya no.) |
| Una máquina aparece con un tamaño enorme (cientos de GB) | Fallo anterior: su `.vmx` está suelto en la carpeta de máquinas y se sumaban todas las demás. Arreglado: ejecutar `Actualizar.bat`. Conviene igualmente mover esa máquina a su propia carpeta. |
| Ubuntu tarda ~2 min en arrancar con «A start job is running for Wait for Network…» (`systemd-networkd-wait-online`) | Base de Ubuntu anterior al arreglo. Las bases nuevas y las máquinas nuevas ya no esperan (si las crea una base antigua, se corrige a partir del segundo arranque). En una máquina ya creada, dentro de ella: `sudo systemctl mask systemd-networkd-wait-online.service`. |
| Ubuntu con escritorio: al entrar sale «Welcome to Ubuntu» | Asistente de bienvenida de GNOME; se puede pasar con *Next* (solo sale una vez por usuario). Las bases de Ubuntu creadas a partir del 29/10/2026 por la noche ya no lo muestran. En una máquina ya creada: `sudo systemctl --global mask gnome-initial-setup-first-login.service`. |
| Ubuntu sale en inglés (el teclado sí es español) | Base anterior al 29/10/2026: no traía las traducciones. Rehacer la base. En una máquina ya creada: `sudo apt install language-pack-es language-pack-gnome-es`, luego `sudo update-locale LANG=es_ES.UTF-8` y cerrar sesión. |
| Las máquinas tienen el usuario «alumno» aunque en Ajustes pusiste otro | Las máquinas llevan el usuario **de su base**, no el de Ajustes: la base se hizo con «alumno» (por ejemplo, porque `config.local.json` decía «David», con mayúscula, y no valía). Ajustes y *Nueva máquina* dicen el usuario de cada base. Para tener el nuevo, vuelve a crear las bases. |
| «Falta la contraseña de las VMs» aunque ya creaste bases en ese PC, o la consola pide la contraseña cada vez | Fallo hasta el 31/10/2026: `password.sec` se guardaba bien pero no se podía leer. Arreglado, actualiza. Si sigue saliendo, el aviso trae un «Detalle»: si dice que no se pudo descifrar, la guardó otro usuario de Windows; borra `password.sec` y se pedirá de nuevo al crear la próxima base. |
| Usuarios o Red: «La máquina no devolvió el resultado» | La máquina no dejó ejecutar el programa (suele pasar justo al encenderla). Full Cowl lo reintenta solo durante algo más de un minuto; si aun así falla, el mensaje trae lo que respondió VMware y el detalle queda en `full-cowl/estado/invitado.log`. |
| Escritorio remoto: «Las credenciales no funcionaron» con tu cuenta del PC (cuenta Microsoft) | Hasta el 03/11/2026 la ventana proponía tu usuario de Windows. Ahora sale el de la máquina (`.\david` o `DOMINIO\david`): escribe la contraseña de las máquinas. Si sigue saliendo tu cuenta, en *Más opciones* → *Usar otra cuenta* escribe `.\` y el usuario de la máquina. |
| Instantáneas: la barra no termina nunca | VMware sigue guardando (con la máquina encendida y mucha memoria puede tardar varios minutos). Si de verdad se ha quedado parado, cierra la ventanita (avisa) y mira la máquina en VMware. |
| Red… o Usuarios: «el programa no tiene permisos de administrador» | El usuario de la VM debe ser administrador; probar con la máquina recién arrancada y la sesión iniciada. |
| Conectar: el Escritorio remoto no responde | Activarlo en la VM o crear la máquina con *Escritorio remoto (RDP)*. |
| Conectar: «solo está en segmentos LAN» | El PC no llega a esa red: añadir una tarjeta NAT con *Red…* o usar la ventana de VMware. |
| Una desechable no se borra al apagarla | Comprobar que están apagadas **todas** las del laboratorio y ninguna suspendida; si VMware tiene abierta su pestaña, cerrarla. Mirar `full-cowl\estado\vigilante.log`. Abrir Full Cowl pone en marcha el vigilante. |
| Progreso: «Sin datos» o la máquina no aparece | Su base no tiene VMware Tools (rehacer la base) o la máquina se creó antes de esta versión. Mirar `full-cowl\estado\vigilante.log`. |
| Usuarios en masa: «Hay datos no válidos en la lista» | Algún usuario, grupo u OU del CSV tiene caracteres no permitidos (comillas, comas, tildes en Linux…). El mensaje dice cuáles. |
| Importar: «es un clon ENLAZADO» | Esa máquina depende de la base de su PC. En el Full Cowl donde está: *Exportar* (saca copias completas) y se importa el `.ova`. |
| Importar: «no hay espacio suficiente» | Un `.ova` ocupa hasta el doble al importarlo. Libera sitio en el disco de las máquinas o cambia la carpeta en Ajustes. |
| Importar: OVF Tool no puede importar | Mirar los mensajes de la consola. Un `.ova` de VirtualBox o de otro programa a veces necesita VMware Workstation reciente; también se puede abrir directamente en VMware (File > Open). |
| Importada: Full Cowl no puede entrar (Usuarios, Red, Archivos) | La máquina trae otra contraseña u otro usuario, o no lleva las VMware Tools / el agente. Se enciende y usa con normalidad; para que Full Cowl entre, hay que poner la contraseña de las máquinas de este PC. |
| Exportar: «todavía lleva su CD de configuración» | La máquina se creó hace menos de 30 minutos. La consola pregunta si ya terminó de configurarse: responde `s` si ya la encendiste, comprobaste y apagaste (se quita el CD con la contraseña). Si aún no la has encendido, enciéndela, espera a que termine, apágala del todo y exporta. |
| Borrar: «no estas carpetas porque tienen otros archivos tuyos» | La máquina estaba fuera de tu carpeta de máquinas junto a otros archivos: se borró la máquina, revisa la carpeta a mano. |
| Kali: Packer no puede abrir el puerto 8820 | El servidor escucha solo en la red VMnet8: comprueba en *Editor de red virtual* de VMware que VMnet8 (NAT) está activa y conectada al PC. |
| Laboratorio: la lista solo rellena *Nombre* y *Base* | Fallo de la 1.2.0. Arreglado: ejecutar `Actualizar.bat`. |
| «No se puede convertir a NULL el tipo System.DateTime» una y otra vez al usar desechables | Fallo de la 1.2.0 (la barra de progreso de *Crear base* leía los archivos del vigilante). Arreglado: ejecutar `Actualizar.bat`. |
| Laboratorio: los Windows no se unen al dominio | El controlador tarda 10-15 min; esperan hasta 30 min. Si no, comprobar que todos están en la misma red y con IP fija. Se reintenta en cada arranque. El motivo sale en `C:\ProgramData\VMTareas\config.log` del cliente. |
| Unirse al dominio: «El nombre de usuario o la contraseña no son correctos» | Fallo hasta la 1.2.0: se usaba `Administrator`, que en Windows en español se llama `Administrador`. Arreglado para las máquinas nuevas. En una ya creada, a mano: `Add-Computer -DomainName <dominio> -Credential <NETBIOS>\<tu usuario> -Restart`. |
| VMware deshace un cambio de red | La máquina estaba abierta en una pestaña de VMware: cerrarla y repetir. |
| Un acceso directo muestra un icono antiguo o falta | Abrir Full Cowl o ejecutar `Actualizar.bat`: rehacen los accesos directos y refrescan los iconos. Si persiste, cerrar sesión de Windows y volver a entrar. |
| `Actualizar.bat` no actualiza | Cerrar Full Cowl y las consolas abiertas y repetir; comprobar la conexión. |
| «Actualizar ahora» no hace nada o Full Cowl no vuelve a abrirse | Ver `full-cowl\estado\actualizar.log`; abrir Full Cowl con su acceso directo o ejecutar `Actualizar.bat`. |

---

## 15. Referencia de archivos

```
Full Cowl\
├─ Actualizar.bat                 trae la última versión de GitHub (y revisa los accesos directos)
├─ actualizar.ps1                 la lógica de actualizar (la usan el .bat y el botón de Full Cowl)
├─ crear-accesos.ps1             accesos directos con icono
├─ iconos\                       iconos de los accesos directos
├─ VERSION                        versión del programa
├─ CHANGELOG.md                   historial de versiones
├─ README.md
├─ docs\MANUAL.md                 este manual
├─ full-cowl\
│  ├─ Full Cowl.bat               abre la ventana (abrir-nueva.ps1 → ventana-nueva.ps1)
│  ├─ interfaz\                    pantallas (.xaml), lógica (.ps1) y código C# (tipos.cs, inicio.cs, rayos.cs)
│  │                              de la ventana; el C# compilado se guarda en %TEMP%\FullCowl
│  ├─ crear-base.bat/.ps1         bases con Packer
│  ├─ nueva-maquina.bat/.ps1      clones
│  ├─ cambiar-password.bat/.ps1   cambia la contraseña de las VMs de este PC
│  ├─ usuarios.ps1                usuarios en masa (consola)
│  ├─ red-ip.ps1                  IP dentro de las máquinas (consola)
│  ├─ exportar.ps1                exportar a .ova (consola)
│  ├─ importar.ps1                importar un .ova/.ovf/.zip/.7z/carpeta (consola)
│  ├─ laboratorio.ps1             crea un laboratorio (consola)
│  ├─ vigilante.ps1               borra las desechables al apagarse (oculto)
│  ├─ ficha-laboratorio.ps1       crea la ficha del laboratorio (PDF o texto; sin ventana)
│  ├─ lab-estado.ps1              guarda / recupera / quita el estado inicial de un laboratorio (oculto)
│  ├─ limpieza.ps1                Espacio y limpieza: medir, dependencias y borrado seguro (sin ventana)
│  ├─ comun.ps1                   funciones compartidas
│  ├─ config.ps1                  valores por defecto
│  ├─ instalacion\                 instalador (instalar-completo.ps1), Packer (packer.ps1) y copia por manifiesto (programa.ps1)
│  ├─ clon\                       scripts que se ejecutan dentro de las VMs
│  ├─ packer\                     plantillas de Packer y de instalación desatendida
│  ├─ recursos\arranque\          ubuntu-autoinstall.iso (CD de arranque para Ubuntu sin «yes»), grub.cfg y hacer-iso.sh (para rehacerlo)
│  ├─ recursos\                   logo.png (emblema), titulo.png / titulo-claro.png (palabra FULL COWL), full-cowl-icono-4.ico, github\ (imágenes del README y del repositorio);
│  │                              fuentes\ (letra Inter y su licencia, para el diseño nuevo);
│  │                              inicio\ (piezas del logo para la animación)
│  │  — propios del PC (no se suben) —
│  ├─ config.local.json, password.sec, preferencias.json, segmentos.json,
│  │  plantillas-laboratorio.json
│  └─ estado\, build\, *.log
```

> **Problema: «Fallo al obtener … UserCheck/PortalMain» al actualizar una máquina Linux (en el centro).** El filtro de la red bloquea las descargas http. Cambia los repositorios a https: `sudo sed -i 's#http://#https://#' /etc/apt/sources.list` y luego `sudo apt update`.
