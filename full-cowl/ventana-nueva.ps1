# =====================================================================
#  Full Cowl · la ventana (WPF)
#
#  Ventana con menú lateral, tarjetas y animaciones: Inicio, Mis máquinas,
#  Laboratorio, Nueva máquina, Crear base, Importar y Ajustes. Desde la 2.0 es
#  la única (la «ventana de siempre», gui.ps1, se quitó).
#
#  Se abre con «Full Cowl.bat» → abrir-nueva.ps1, que antes
#  revisa que no haya errores en los scripts ni en las pantallas.
#  Archivos: interfaz\estilos.xaml (aspecto), interfaz\ventana.xaml (marco y
#  menú), interfaz\inicio.xaml + inicio.ps1 (Inicio), interfaz\maquinas.xaml + maquinas.ps1 (Mis máquinas), nueva.xaml +
#  nueva.ps1 (Nueva máquina), bases.xaml + bases.ps1 (Crear base),
#  laboratorio.xaml + laboratorio.ps1 (Laboratorio), ajustes.ps1 (Ajustes),
#  tipos.cs (tarjetas, en C#), inicio.cs + recursos\inicio (animación de inicio),
#  interfaz\dialogo-*.xaml (ventanitas), interfaz\base.ps1 (utilidades).
#  Si algo falla, queda apuntado en estado\interfaz.log
# =====================================================================
$ErrorActionPreference = 'Stop'
$dirFc = $PSScriptRoot
$dirInterfaz = Join-Path $PSScriptRoot 'interfaz'
$EsVentana = $true   # comun.ps1: la ventana se ocupa de avisar si falta la configuración

try {
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
# Código en C# (interfaz\*.cs): se compila una vez y queda en %TEMP%\FullCowl; las siguientes veces
# solo se carga, y la ventana se abre antes
function Cargar-Codigo([string]$archivo, [string]$tipo, [string[]]$referencias) {
    if ($tipo -as [type]) { return }
    $codigo = [IO.File]::ReadAllText((Join-Path $dirInterfaz $archivo), [Text.Encoding]::UTF8)
    $md5 = [Security.Cryptography.MD5]::Create()
    $huella = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($codigo + [string]$PSVersionTable.CLRVersion))) -replace '-', '').Substring(0, 12)
    $nombreCs = [IO.Path]::GetFileNameWithoutExtension($archivo)
    $dirDll = Join-Path ([IO.Path]::GetTempPath()) 'FullCowl'
    $dll = Join-Path $dirDll "FullCowl-$nombreCs-$huella.dll"
    $opciones = @{ TypeDefinition = $codigo }
    if ($referencias) { $opciones.ReferencedAssemblies = $referencias }
    try {
        if (-not (Test-Path $dll)) {
            if (-not (Test-Path $dirDll)) { [void](New-Item -ItemType Directory -Path $dirDll) }
            # Las de versiones anteriores sobran (si otra ventana abierta la usa, no se puede borrar y no pasa nada)
            Get-ChildItem $dirDll -Filter "FullCowl-$nombreCs-*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Add-Type @opciones -OutputAssembly $dll -OutputType Library
        }
        if (-not ($tipo -as [type])) { Add-Type -Path $dll }
    } catch {
        if ($tipo -as [type]) { return }
        # Si la carpeta temporal falla, en memoria (como antes); si es un fallo del código, salta aquí
        Remove-Item $dll -Force -ErrorAction SilentlyContinue
        Add-Type @opciones
    }
}
function Cargar-CodigoVarios([string[]]$archivos, [string]$tipo, [string[]]$referencias) {
    # Varios .cs en UN solo ensamblado (así unos no dependen de otros por nombre: la animación de inicio corre en otro
    # hilo y no encontraba el ensamblado aparte de los rayos)
    if ($tipo -as [type]) { return }
    $rutas = @($archivos | ForEach-Object { Join-Path $dirInterfaz $_ })
    $codigo = (@($rutas | ForEach-Object { [IO.File]::ReadAllText($_, [Text.Encoding]::UTF8) }) -join "`n") + [string]$PSVersionTable.CLRVersion
    $md5 = [Security.Cryptography.MD5]::Create()
    $huella = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($codigo))) -replace '-', '').Substring(0, 12)
    $nombre = (@($archivos | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) -join '+')
    $dirDll = Join-Path ([IO.Path]::GetTempPath()) 'FullCowl'
    $dll = Join-Path $dirDll "FullCowl-$nombre-$huella.dll"
    try {
        if (-not (Test-Path $dll)) {
            if (-not (Test-Path $dirDll)) { [void](New-Item -ItemType Directory -Path $dirDll) }
            Get-ChildItem $dirDll -Filter "FullCowl-$nombre-*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Add-Type -Path $rutas -ReferencedAssemblies $referencias -OutputAssembly $dll -OutputType Library
        }
        if (-not ($tipo -as [type])) { Add-Type -Path $dll }
    } catch {
        if ($tipo -as [type]) { return }
        Remove-Item $dll -Force -ErrorAction SilentlyContinue
        Add-Type -Path $rutas -ReferencedAssemblies $referencias
    }
}
Cargar-Codigo 'tipos.cs' 'FullCowlWpf.Maquina'
try { [void][FullCowlWpf.Nativo]::SetProcessDPIAware() } catch {}
# Identidad propia en la barra de tareas: sin esto, al reabrirse sola tras actualizar aparece el icono de PowerShell
try { [void][FullCowlWpf.Nativo]::SetCurrentProcessExplicitAppUserModelID('FullCowl.Interfaz') } catch {}

# ---------------------------------------------------------------- animación de inicio
# interfaz\inicio.cs: el logo se monta con rayos alrededor, en su propio hilo, mientras esta ventana se
# carga. Si algo falla, se abre sin animación y queda apuntado en estado\interfaz.log.
$script:conInicio = $false
$script:errorInicio = ''
$script:errorRayos = ''
$refsWpf = @([System.Windows.Window].Assembly.Location, [System.Windows.Media.Visual].Assembly.Location,
             [System.Windows.Threading.Dispatcher].Assembly.Location, [System.Xaml.XamlReader].Assembly.Location)
try {
    # Solo manda la casilla de Ajustes. (Antes tampoco salía si Windows tenía desactivados los «efectos
    # de animación», algo habitual en portátiles con el modo de rendimiento; no había forma de verla)
    $animar = $true
    $cfgLocal = Join-Path $dirFc 'config.local.json'
    if (-not (Test-Path $cfgLocal)) { $animar = $false }   # primera vez: antes sale Ajustes
    else { try { $cj = [IO.File]::ReadAllText($cfgLocal, [Text.Encoding]::UTF8) | ConvertFrom-Json; if ($cj.AnimacionInicio -eq $false -or $cj.Sobrio -eq $true -or $cj.Animaciones -eq 'Ninguna') { $animar = $false } } catch {} }
    if ($animar) {
        # Los rayos (que también usa Inicio) y la animación van en el MISMO ensamblado
        Cargar-CodigoVarios @('rayos.cs', 'inicio.cs') 'FullCowlWpf.Inicio' $refsWpf
        [FullCowlWpf.Inicio]::Empezar((Join-Path $dirFc 'recursos\inicio'), (Join-Path $dirFc 'recursos\fuentes'))
        $script:conInicio = $true
    }
} catch { $script:errorInicio = $_.Exception.Message }
# Rayos de la pantalla Inicio: si no vinieron con la animación, aparte. Si falla, solo se pierden los rayos
if (-not ('FullCowlWpf.RayosSueltos' -as [type])) {
    try { Cargar-Codigo 'rayos.cs' 'FullCowlWpf.RayosSueltos' $refsWpf } catch { $script:errorRayos = $_.Exception.Message }
}

. (Join-Path $dirFc 'comun.ps1')
. (Join-Path $dirInterfaz 'base.ps1')
. (Join-Path $dirInterfaz 'tema.ps1')
. (Join-Path $dirInterfaz 'animaciones.ps1')
. (Join-Path $dirInterfaz 'etiquetas.ps1')
$app = Iniciar-Aplicacion
Aplicar-Tema (Tema-Efectivo)
if ($script:errorInicio) { Escribir-Log "Animación de inicio desactivada: $($script:errorInicio)" }

. (Join-Path $dirInterfaz 'actualizacion.ps1')
. (Join-Path $dirInterfaz 'ajustes.ps1')
. (Join-Path $dirInterfaz 'asistente.ps1')

# La primera vez en este PC: asistente de primer arranque (ficha 16). Si no se pudiera abrir, el diálogo de siempre
$script:destinoAsistente = ''
if (-not (Config-Completa)) {
    if ($script:conInicio) { try { [FullCowlWpf.Inicio]::Cerrar() } catch {} }
    $asistenteAbierto = $false
    try {
        $resAsistente = Abrir-Asistente $false
        $asistenteAbierto = $true
        $script:destinoAsistente = [string]$resAsistente.Destino
    } catch { Escribir-Log ("Asistente de primer arranque: " + ($_ | Out-String)) }
    if (-not $asistenteAbierto) {
        if (-not (Abrir-Ajustes $true)) { return }
    } elseif (-not (Config-Completa)) { return }   # cerró a medias: lo guardado se conserva y sigue en el próximo arranque
    Aplicar-Tema (Tema-Efectivo)
}

# ---------------------------------------------------------------- ventana y página
$xVentana = Leer-Xaml 'ventana.xaml'
$script:ventana = [Windows.Markup.XamlReader]::Parse($xVentana)
$ventana.FontFamily = $script:fuenteApp
# Fondo y letra de la ventana según el tema (puestos desde el código: en el propio XAML de la ventana daba error)
$ventana.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'T_fondo')
$ventana.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'T_texto')
Publicar-Elementos (Elementos $ventana $xVentana)

function Cargar-Pagina([string]$archivo) {
    # Lee una página (.xaml), la pone en la zona de contenido (oculta) y publica sus elementos
    $x = Leer-Xaml $archivo
    $pg = [Windows.Markup.XamlReader]::Parse($x)
    $pg.Visibility = 'Collapsed'
    [void]$Contenido.Children.Add($pg)
    Publicar-Elementos (Elementos $pg $x)
    return $pg
}
$paginaInicio = Cargar-Pagina 'inicio.xaml'
$paginaMaquinas = Cargar-Pagina 'maquinas.xaml'
$paginaNueva = Cargar-Pagina 'nueva.xaml'
$paginaBases = Cargar-Pagina 'bases.xaml'
$paginaLab = Cargar-Pagina 'laboratorio.xaml'
$paginaImp = Cargar-Pagina 'importar.xaml'
$paginaApariencia = Cargar-Pagina 'apariencia.xaml'
$paginaHub = Cargar-Pagina 'ajustes-hub.xaml'
# Apariencia es un apartado más de Ajustes: vive dentro de la página del hub
[void]$Contenido.Children.Remove($paginaApariencia)
[void]$HubSecciones.Children.Add($paginaApariencia)
$paginaApariencia.Visibility = 'Collapsed'
# Espacio y limpieza (ficha 30): otro apartado de Ajustes, con su propio .xaml
$paginaEspacio = Cargar-Pagina 'limpieza.xaml'
[void]$Contenido.Children.Remove($paginaEspacio)
[void]$HubSecciones.Children.Add($paginaEspacio)
$paginaEspacio.Visibility = 'Collapsed'

# ---------------------------------------------------------------- avisos flotantes
$script:toastMov = New-Object System.Windows.Media.TranslateTransform(0, 24)
$Toast.RenderTransform = $script:toastMov
$relojToast = New-Object System.Windows.Threading.DispatcherTimer
$relojToast.Add_Tick({
    Ocultar-Toast
})
function Ocultar-Toast {
    $relojToast.Stop()
    $Toast.IsHitTestVisible = $false
    Animar $Toast $propOpacidad 0 220
    Animar $script:toastMov $propY 24 260
}
function Mostrar-Toast($texto, [string]$tipo = 'ok', [string]$detalle = '', $accion = $null, [string]$textoEnlace = 'Detalles') {
    # Aviso que sube desde abajo y se va solo (más tiempo cuanto más largo es el texto).
    # Con $detalle (fallos): enlace «Detalles» y X, dura unos 8 s y no se va mientras el ratón está encima.
    $ToastTexto.Text = $texto
    $script:toastDetalle = $detalle
    $script:toastAccion = $accion
    $conDetalle = ([bool]$detalle -or [bool]$accion)
    $ToastDetalles.Text = $textoEnlace
    $ToastDetalles.Visibility = $(if ($conDetalle) { 'Visible' } else { 'Collapsed' })
    $ToastCerrar.Visibility = $(if ($conDetalle) { 'Visible' } else { 'Collapsed' })
    $Toast.IsHitTestVisible = $conDetalle
    switch ($tipo) {
        'aviso' { $ToastGlifo.Text = Glifo 0xE7BA; $ToastGlifo.Foreground = Pincel '#F2C14E' }
        'info'  { $ToastGlifo.Text = Glifo 0xE946; $ToastGlifo.Foreground = Pincel '#78EBDD' }
        default { $ToastGlifo.Text = Glifo 0xE73E; $ToastGlifo.Foreground = Pincel '#78EBDD' }
    }
    Animar $Toast $propOpacidad 1 220
    Animar $script:toastMov $propY 0 320
    $relojToast.Stop()
    $ms = $(if ($conDetalle) { 8000 } else { [Math]::Min(8000, 3000 + 35 * $texto.Length) })
    $relojToast.Interval = [TimeSpan]::FromMilliseconds($ms)
    $relojToast.Start()
}
$Toast.Add_MouseEnter({ $relojToast.Stop() })
$Toast.Add_MouseLeave({ if ($script:toastDetalle -or $script:toastAccion) { $relojToast.Start() } })
$ToastCerrar.Add_MouseLeftButtonUp({ Ocultar-Toast })
$ToastDetalles.Add_MouseLeftButtonUp({
    $hbAcc = $script:toastAccion
    $hbDet = $script:toastDetalle
    Ocultar-Toast
    if ($hbAcc) { & $hbAcc } else { Error-Amable $script:toastQue $script:toastHacer $hbDet }
})

function Error-Toast($ex) {
    # Fallo inesperado: frase llana en el aviso y, en «Detalles», lo técnico (sin datos personales)
    $hbT = Texto-Amable $ex
    $script:toastQue = $hbT.Que; $script:toastHacer = $hbT.Hacer
    Mostrar-Toast $hbT.Que 'aviso' (Texto-Detalle $ex)
}

# Números que suben de 0 a su valor (como un marcador)
function Contar($bloque, [double]$fin, [string]$formato = '{0:N0}') {
    $st = @{ Bloque = $bloque; Fin = $fin; Formato = $formato; Inicio = [DateTime]::Now; Reloj = (New-Object System.Windows.Threading.DispatcherTimer) }
    $st.Reloj.Interval = [TimeSpan]::FromMilliseconds(16)
    $st.Reloj.Add_Tick({
        $p = [Math]::Min(1.0, ([DateTime]::Now - $st.Inicio).TotalMilliseconds / 700)
        $suav = 1 - [Math]::Pow(1 - $p, 3)
        $st.Bloque.Text = $st.Formato -f ($st.Fin * $suav)
        if ($p -ge 1) { $st.Reloj.Stop() }
    }.GetNewClosure())
    $st.Reloj.Start()
}

# ---------------------------------------------------------------- marco de la ventana
function Imagen($ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return $null }
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.UriSource = New-Object System.Uri($ruta)
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.EndInit()
    $bi.Freeze()
    return $bi
}
$ImgLogo.Source = Imagen (Join-Path $dirFc 'recursos\logo.png')
$ImgTitulo.Source = Imagen (Join-Path $dirFc 'recursos\titulo.png')
try { $ventana.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri((Join-Path $dirFc 'recursos\full-cowl-icono-4.ico')))) } catch {}
$versionApp = ''
try { $versionApp = ([IO.File]::ReadAllText((Join-Path (Split-Path $dirFc) 'VERSION'))).Trim() } catch {}
$TxtVersion.Text = $(if ($versionApp) { "v$versionApp" } else { '' })

# Que quepa en pantallas pequeñas
$zona = [System.Windows.SystemParameters]::WorkArea
$ventana.MinWidth = [Math]::Min(1060, $zona.Width)
$ventana.Width = [Math]::Min(1260, $zona.Width - 40)
$ventana.Height = [Math]::Min(800, $zona.Height - 40)

# Windows 11: esquinas redondeadas y borde suave de la propia ventana (en Windows 10 no hace nada)
function Poner-BordeVentana {
    # Borde fino de la propia ventana (Windows 11), del color del tema
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($ventana)).Handle
        if ($hwnd -eq [IntPtr]::Zero) { return }
        $colorBorde = $(if ($script:temaActual -eq 'oscuro') { 0x00393C2E } else { 0x00CDD6C9 })   # #2E3C39 / #C9D6CD en formato de Windows (azul-verde-rojo)
        [void][FullCowlWpf.Nativo]::DwmSetWindowAttribute($hwnd, 34, [ref]$colorBorde, 4)
    } catch {}
}
$ventana.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($ventana)).Handle
        $esquinas = 2
        [void][FullCowlWpf.Nativo]::DwmSetWindowAttribute($hwnd, 33, [ref]$esquinas, 4)
        Poner-BordeVentana
    } catch {}
})
$BtnMin.Add_Click({ $ventana.WindowState = [System.Windows.WindowState]::Minimized })
$BtnMax.Add_Click({
    if ($ventana.WindowState -eq [System.Windows.WindowState]::Maximized) { $ventana.WindowState = [System.Windows.WindowState]::Normal }
    else { $ventana.WindowState = [System.Windows.WindowState]::Maximized }
})
$BtnCerrar.Add_Click({ $ventana.Close() })
$ventana.Add_StateChanged({
    # Maximizada, Windows la agranda unos píxeles más allá de la pantalla: se compensa con un margen
    if ($ventana.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $Raiz.Margin = New-Object System.Windows.Thickness(7)
        $BtnMax.Content = Glifo 0xE923
    } else {
        $Raiz.Margin = New-Object System.Windows.Thickness(0)
        $BtnMax.Content = Glifo 0xE922
    }
    try { Brillos-Revisar } catch {}   # minimizada, el brillo de las barras se para (ficha 22)
})

# ---------------------------------------------------------------- menú lateral
$script:navs = @($NavInicio, $NavMaq, $NavLab, $NavNueva, $NavBase, $NavImportar)
$script:nombresNav = @{ NavInicio = 'Inicio'; NavMaq = 'Mis máquinas'; NavLab = 'Laboratorio'; NavNueva = 'Nueva máquina'; NavBase = 'Crear base'; NavImportar = 'Importar' }
$NavIndicador.RenderTransform = New-Object System.Windows.Media.TranslateTransform
# Lo que cada página hace al entrar (leer discos, VMware, pintar tarjetas...) es trabajo pesado en el hilo de la ventana. Si se
# hace en el mismo clic, la ventana se congela y el indicador del menú da un salto. Al pulsar en el menú se cambia de página
# al instante (con lo que ya tenía) y la puesta al día va un poco después, cuando el indicador ya ha llegado. Si se pulsa
# otra página antes, la anterior ya no se pone al día.
$script:entradaPendiente = $null
$relojEntrar = New-Object System.Windows.Threading.DispatcherTimer
$relojEntrar.Interval = [TimeSpan]::FromMilliseconds(230)
$relojEntrar.Add_Tick({
    $relojEntrar.Stop()
    $pend = $script:entradaPendiente; $script:entradaPendiente = $null
    if ($pend) { try { Poner-AlDiaPagina $pend } catch { Escribir-Log ("Al entrar en $pend`: " + ($_ | Out-String)) } }
})
function Poner-AlDiaPagina([string]$nombre) {
    switch ($nombre) {
        'NavInicio' { Entrar-Inicio }
        'NavMaq'   {
            # (si se acaban de leer las máquinas, no se vuelven a leer solo por entrar)
            if ($script:cargado -and (-not $script:finCarga -or ((Get-Date) - $script:finCarga).TotalSeconds -gt 20)) { Cargar -Silencioso }
        }
        'NavNueva' { Entrar-Nueva }
        'NavBase'  { Cambio-Sistema; Actualizar-ProgresoBase }
        'NavLab'   { Entrar-Lab }
        'NavImportar' { Entrar-Importar }
    }
    # Las tarjetas de sistemas entran una a una al abrir la página (ficha 22)
    $selE = $(switch ($nombre) { 'NavNueva' { $NuevaSelector } 'NavBase' { $BaseSelector } default { $null } })
    if ($selE) { $selE.Opacity = 1; Animar-Selector $selE }
}
function Cambiar-Pagina($nav, [bool]$diferir = $false) {
    # Saliendo de Ajustes con cambios sin guardar en «Este PC»: se pregunta
    if ($paginaHub.Visibility -eq 'Visible' -and $script:seccionHub -eq 'pc' -and -not (Salir-DePcSeguro)) {
        foreach ($nvH in $script:navs) { $nvH.IsChecked = $false }
        $BtnAjustes.IsChecked = $true
        return
    }
    $BtnAjustes.IsChecked = $false
    $NavIndicador.Visibility = 'Visible'
    $paginaHub.Visibility = 'Collapsed'
    $i = [array]::IndexOf($script:navs, $nav)
    Animar $NavIndicador.RenderTransform $propY ($i * 48) 220
    $Migas.Text = "Full Cowl  ›  $($script:nombresNav[$nav.Name])"
    $pg = $script:paginasNav[$nav.Name]
    foreach ($otra in $script:paginasNav.Values) { if ($otra -ne $pg) { $otra.Visibility = 'Collapsed' } }
    $pg.Visibility = 'Visible'
    Entrada-Pantalla $pg   # (sin transición: David la quitó; solo deja la página a la vista)
    $relojEntrar.Stop()
    if ($diferir) {
        # Las tarjetas de sistemas se esconden ya, para que no se vean un momento y luego «vuelvan a entrar»
        if ((Nivel-Animacion) -gt 0) {
            $selE = $(switch ($nav.Name) { 'NavNueva' { $NuevaSelector } 'NavBase' { $BaseSelector } default { $null } })
            if ($selE) { $selE.Opacity = 0 }
        }
        $script:entradaPendiente = $nav.Name
        $relojEntrar.Start()
    } else {
        # Desde el código (p. ej. «Crear esa base» de un laboratorio): al momento, porque lo que viene después cuenta con ello
        $script:entradaPendiente = $null
        Poner-AlDiaPagina $nav.Name
    }
}
# Pulsado en el menú (ratón o teclado): la puesta al día de la página se hace un poco después (ver arriba)
foreach ($nv in $script:navs) { $nv.Add_Checked({ param($s, $e) Cambiar-Pagina $s ([bool]($s.IsMouseOver -or $s.IsKeyboardFocused)) }) }

# Menú plegable: el logo es el botón (un solo clic; no se despliega al pasar el ratón). Plegado, solo
# iconos (80 px) con su nombre al pasar el ratón; desplegado, 248 px. Se recuerda en config.local.json.
$script:menuPlegado = ($Config.MenuPlegado -eq $true)
$script:propAnchoMenu = [System.Windows.FrameworkElement]::WidthProperty
$script:propAltoMenu = [System.Windows.FrameworkElement]::HeightProperty
$relojMenu = New-Object System.Windows.Threading.DispatcherTimer
$relojMenu.Interval = [TimeSpan]::FromMilliseconds(320)
$relojMenu.Add_Tick({
    $relojMenu.Stop()
    # Ya plegado del todo, lo que sobra se quita para que no estorbe
    if ($script:menuPlegado) { $MenuTitulo.Visibility = 'Collapsed' }
})
function Poner-Menu([bool]$plegado, [bool]$animar) {
    $script:menuPlegado = $plegado
    $ancho = $(if ($plegado) { 80 } else { 248 })
    $sobran = @($MenuTitulo)
    if ($animar) {
        # El contenido no se mueve: solo cambia el ancho del marco (que recorta) y los textos se funden
        Animar $Menu $script:propAnchoMenu $ancho 300
        if ($plegado) {
            foreach ($el in $sobran) { Animar $el $propOpacidad 0 140 }
            $relojMenu.Stop(); $relojMenu.Start()
        } else {
            $relojMenu.Stop()
            foreach ($el in $sobran) { $el.Visibility = 'Visible'; Animar $el $propOpacidad 1 220 0 120 }
        }
    } else {
        $Menu.BeginAnimation($script:propAnchoMenu, $null)
        $Menu.Width = $ancho
        foreach ($el in $sobran) {
            $el.BeginAnimation($propOpacidad, $null)
            $el.Opacity = $(if ($plegado) { 0 } else { 1 })
            $el.Visibility = $(if ($plegado) { 'Collapsed' } else { 'Visible' })
        }
    }
    # Plegado, cada icono dice su nombre al pasar el ratón
    foreach ($nv in @($script:navs) + @($BtnAjustes)) {
        $nombreNav = $(if ($nv -eq $BtnAjustes) { 'Ajustes' } else { $script:nombresNav[$nv.Name] })
        $nv.ToolTip = $(if ($plegado) { $nombreNav } else { $null })
    }
    $BtnPlegar.ToolTip = $(if ($plegado) { 'Desplegar el menú' } else { 'Plegar el menú' })
}
$BtnPlegar.Add_Click({
    Poner-Menu (-not $script:menuPlegado) $true
    try { Guardar-ConfigLocal @{ MenuPlegado = [bool]$script:menuPlegado } } catch {}
})
Poner-Menu $script:menuPlegado $false

function Mostrar-Ajustes {
    # El botón Ajustes del menú lleva siempre a la portada del hub (no recuerda el último apartado)
    foreach ($nv in $script:navs) { $nv.IsChecked = $false }
    $BtnAjustes.IsChecked = $true
    $NavIndicador.Visibility = 'Collapsed'
    foreach ($otra in $script:paginasNav.Values) { $otra.Visibility = 'Collapsed' }
    $paginaHub.Visibility = 'Visible'
    Ir-Seccion 'portada'
}
$BtnAjustes.Add_Click({ Mostrar-Ajustes })
$BtnNueva.Add_Click({ $NavNueva.IsChecked = $true })

# ---------------------------------------------------------------- páginas
. (Join-Path $dirInterfaz 'maquinas.ps1')
. (Join-Path $dirInterfaz 'selector.ps1')
. (Join-Path $dirInterfaz 'extras.ps1')
. (Join-Path $dirInterfaz 'nueva.ps1')
. (Join-Path $dirInterfaz 'bases.ps1')
. (Join-Path $dirInterfaz 'laboratorio.ps1')
. (Join-Path $dirInterfaz 'lab-mapa.ps1')
. (Join-Path $dirInterfaz 'lab-mis.ps1')
. (Join-Path $dirInterfaz 'lab-prev.ps1')
. (Join-Path $dirInterfaz 'lab-compartir.ps1')
. (Join-Path $dirFc 'ficha-laboratorio.ps1')
. (Join-Path $dirInterfaz 'lab-ficha.ps1')
. (Join-Path $dirInterfaz 'lab-estado.ps1')
. (Join-Path $dirInterfaz 'importar.ps1')
. (Join-Path $dirInterfaz 'inicio.ps1')
. (Join-Path $dirInterfaz 'apariencia.ps1')
. (Join-Path $dirInterfaz 'limpieza.ps1')
. (Join-Path $dirInterfaz 'ajustes-hub.ps1')
. (Join-Path $dirInterfaz 'acerca.ps1')
$script:paginasNav = @{ NavInicio = $paginaInicio; NavMaq = $paginaMaquinas; NavLab = $paginaLab; NavNueva = $paginaNueva; NavBase = $paginaBases; NavImportar = $paginaImp }

# Tema «Automático»: si Windows cambia de claro a oscuro con Full Cowl abierto, se cambia también
$relojTema = New-Object System.Windows.Threading.DispatcherTimer
$relojTema.Interval = [TimeSpan]::FromSeconds(4)
$relojTema.Add_Tick({
    try {
        if ([string]$Config.Tema -ne 'Automatico') { return }
        $nuevoTema = Tema-Efectivo
        if ($nuevoTema -ne $script:temaActual) {
            Aplicar-Tema $nuevoTema; Poner-BordeVentana
            # Lo que se pintó desde el código (tarjetas, avisos...) se vuelve a pintar
            if ($script:cargado) { Cargar -Silencioso }
            if ($paginaInicio.IsVisible) { Pintar-Inicio }
            if ($paginaLab.IsVisible) { $script:labIniciado = $false; Entrar-Lab }
        }
    } catch {}
})

# Cada segundo: los contadores de tiempo de lo que se está configurando (solo de la página que se ve)
$relojSegundo = New-Object System.Windows.Threading.DispatcherTimer
$relojSegundo.Interval = [TimeSpan]::FromSeconds(1)
$relojSegundo.Add_Tick({
    try {
        $script:tickInicio++
        if ($paginaInicio.IsVisible -and $script:tickInicio % 3 -eq 0) { Pintar-Marcha }
        if ($paginaMaquinas.IsVisible) { $sel = @($Lista.SelectedItems); if ($sel.Count -eq 1) { Pintar-ProgresoDetalle $sel[0] } }
        if ($paginaNueva.IsVisible) { Pintar-ProgresoNueva }
        if ($paginaLab.IsVisible) { Pintar-ProgresoLab; Pintar-OperacionLab }
        if ($script:tickInicio % 2 -eq 0) { Vigilar-OperacionesLab }
    } catch {}
})

# ---------------------------------------------------------------- teclado, errores y arranque
$ventana.Add_PreviewKeyDown({
    param($s, $e)
    $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
    $desplegado = ([System.Windows.Input.Keyboard]::FocusedElement -is [System.Windows.Controls.ComboBox]) -and [System.Windows.Input.Keyboard]::FocusedElement.IsDropDownOpen
    if ($e.Key -eq [System.Windows.Input.Key]::Escape -and $paginaHub.Visibility -eq 'Visible' -and $script:seccionHub -ne 'portada' -and -not $desplegado) { Ir-Seccion 'portada'; $e.Handled = $true }
    elseif ($e.Key -eq [System.Windows.Input.Key]::F5) { Cargar; $e.Handled = $true }
    elseif ($e.Key -eq [System.Windows.Input.Key]::F1) { $e.Handled = $true; Mostrar-Acerca }   # ficha 37
    elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::F) { [void]$Buscar.Focus(); $Buscar.SelectAll(); $e.Handled = $true }
    elseif ($e.Key -eq [System.Windows.Input.Key]::Escape -and $Buscar.Text) { $Buscar.Text = ''; $e.Handled = $true }
})

# Un fallo dentro de un botón no debe cerrar la ventana: se apunta y se avisa
$ErrorActionPreference = 'Continue'
$ventana.Dispatcher.Add_UnhandledException({
    param($s, $e)
    Escribir-Log ("Error en la ventana: " + $e.Exception.ToString())
    $e.Handled = $true
    try { Terminar-Espera; Error-Toast $e } catch {}
})

$ventana.Add_Loaded({
    $movInicio = New-Object System.Windows.Media.TranslateTransform(0, 10)
    $Contenido.RenderTransform = $movInicio
    Animar $Raiz $propOpacidad 1 320 0
    Animar $movInicio $propY 0 420
    # Página con la que se abre (Ajustes: «Al abrir Full Cowl, empezar en»)
    $navInicial = $(if ([string]$Config.PaginaInicial -eq 'Maquinas') { $NavMaq } else { $NavInicio })
    if ($script:destinoAsistente -eq 'base') { $navInicial = $NavBase } elseif ($script:destinoAsistente -eq 'importar') { $navInicial = $NavImportar }
    $navInicial.IsChecked = $true
    Cargar
})

# Vigilante de máquinas desechables (si no queda ninguna, se cierra solo)
try { Iniciar-Vigilante } catch {}
# Accesos directos con icono (también el de esta interfaz), sin ventana y sin esperar
try {
    $crearAccesos = Join-Path (Split-Path $dirFc) 'crear-accesos.ps1'
    if (Test-Path $crearAccesos) { Iniciar-Oculto 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$crearAccesos`"" }
} catch {}
$relojProgreso.Start()
$relojEstado.Start()
$relojBase.Start()
$relojImp.Start()
$relojSegundo.Start()
$relojTema.Start()
# Actualizaciones: cuando la ventana ya se ve (y la animación ha terminado) se cuenta si acaba de actualizarse y se busca
$relojActInicial = New-Object System.Windows.Threading.DispatcherTimer
$relojActInicial.Interval = [TimeSpan]::FromSeconds(2)
$relojActInicial.Add_Tick({
    $relojActInicial.Stop()
    try { Empezar-Actualizaciones } catch { Escribir-Log ("Actualizaciones: " + ($_ | Out-String)) }
})
$relojActInicial.Start()
try { Actualizar-ProgresoBase } catch {}
try { Actualizar-ProgresoImp } catch {}
# La animación de inicio termina cuando todo está cargado; se quita cuando la ventana ya se ve
if ($script:conInicio) {
    try {
        [FullCowlWpf.Inicio]::Listo()
        [void][FullCowlWpf.Inicio]::Esperar(6000)
        if ([FullCowlWpf.Inicio]::Error) { Escribir-Log "Animación de inicio: $([FullCowlWpf.Inicio]::Error)" }
    } catch {}
    # Ya se ve: se pone delante (si no, al irse la animación Windows daría el primer plano a la ventana
    # de detrás, por ejemplo el Explorador desde el que se abrió) y se quita la animación
    $ventana.Add_ContentRendered({
        try { [FullCowlWpf.Inicio]::DarPaso((New-Object System.Windows.Interop.WindowInteropHelper($ventana)).Handle) }
        catch { try { [FullCowlWpf.Inicio]::Cerrar() } catch {} }
        try { $ventana.Activate() | Out-Null } catch {}
    })
}
[void]$ventana.ShowDialog()
# Al cerrar: los CD de configuración que llevan la contraseña de máquinas ya configuradas y apagadas se borran
# (el vigilante lo hace mientras vigila, pero así no depende de que esté en marcha)
try { foreach ($maqCd in @(Leer-Clones)) { if (-not $maqCd.Externa) { try { Limpiar-CdClave $maqCd } catch {} } } } catch {}
$relojProgreso.Stop()
$relojEstado.Stop()
$relojLab.Stop()
try { Parar-AnimMapa } catch {}
$relojBase.Stop()
$relojImp.Stop()
$relojSegundo.Stop()
$relojTema.Stop()
try { $relojEspacio.Stop(); if ($script:ezHilo) { $script:ezHilo.Dispose() }; if ($script:ezEspacio) { $script:ezEspacio.Dispose() } } catch {}
try { if ($script:procLista) { $script:procLista.Dispose() } } catch {}
try { if ($script:hilo) { $script:hilo.Dispose() }; if ($script:espacio) { $script:espacio.Dispose() } } catch {}

} catch {
    try { [FullCowlWpf.Inicio]::Cerrar() } catch {}
    $detalle = ($_ | Out-String) + $_.ScriptStackTrace
    try { $ie = $_.Exception; while ($ie.InnerException) { $ie = $ie.InnerException; $detalle += "`r`nInterna: " + $ie.GetType().FullName + ': ' + $ie.Message }
          $r = [System.Windows.Application]::Current.Resources['T_fondo']; $detalle += "`r`nT_fondo: " + $(if ($null -eq $r) { 'no existe' } else { $r.GetType().FullName }) } catch {}
    try {
        $dirLog = Join-Path $PSScriptRoot 'estado'
        if (-not (Test-Path $dirLog)) { [void](New-Item -ItemType Directory -Path $dirLog) }
        Add-Content -LiteralPath (Join-Path $dirLog 'interfaz.log') -Value ("[{0:dd/MM/yyyy HH:mm:ss}] No se pudo abrir la interfaz nueva: {1}" -f (Get-Date), $detalle) -Encoding UTF8
    } catch {}
    try {
        [void][System.Windows.MessageBox]::Show("No se pudo abrir la interfaz nueva.`n`n$($_.Exception.Message)`n`nEl detalle está en full-cowl\estado\interfaz.log. La ventana de siempre («Full Cowl.bat») sigue funcionando.", 'Full Cowl', 'OK', 'Error')
    } catch {}
}
