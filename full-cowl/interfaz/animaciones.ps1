# =====================================================================
#  Animaciones de la interfaz (ficha 22)
#  Una sola utilidad común para las seis animaciones. Todas obedecen al ajuste «Animaciones»:
#    Normales (nivel 2): todo · Reducidas y modo sobrio (nivel 1): solo fundidos · Ninguna (nivel 0): instantáneo.
#  Duración máxima 250 ms (salvo la pasada del brillo de la barra) y curva suave (la de Animar, en base.ps1).
#  Hundimiento y onda de los botones, levantar de tarjetas e interruptores van SOLO en estilos.xaml (sin código: la
#  primera versión los hacía con manejadores de clase y iba lenta y sin efecto). Aquí quedan el cambio de pantalla,
#  las tarjetas escalonadas, el marcador deslizante de los selectores, la ✓ de las casillas y el brillo de las barras.
#  Nada de esto debe poder romper la interfaz: todo va dentro de try/catch.
#  Lo carga ventana-nueva.ps1 justo después de tema.ps1 (antes de crear la ventana).
# =====================================================================

function Nivel-Animacion {
    # 2 = Normales, 1 = Reducidas (y modo sobrio), 0 = Ninguna
    switch (Animaciones-Modo) { 'Normales' { return 2 } 'Reducidas' { return 1 } default { return 0 } }
}

# ---------------------------------------------------------------- 1. cambio de pantalla
function Entrada-Pantalla($el) {
    # Cambio de pantalla SIN transición (David, 09/11/2026: el fundido no quedaba bien). Solo se asegura de que la página
    # quede entera a la vista aunque viniera de una animación anterior a medias.
    try {
        $el.BeginAnimation($propOpacidad, $null)
        if ($el.RenderTransform -is [System.Windows.Media.TranslateTransform]) { $el.RenderTransform.BeginAnimation($propY, $null) }
        $el.RenderTransform = [System.Windows.Media.Transform]::Identity
        $el.Opacity = 1
    } catch {}
}

# ---------------------------------------------------------------- 2. tarjetas que aparecen una a una
function Entrada-Escalonada($elementos) {
    # Fundido y escala 0,96 → 1 en 180 ms, con 30 ms entre una y otra (máximo 12 escalonadas; las demás entran con la última).
    # Reducidas: un único fundido de toda la lista. Ninguna: nada. El sitio de las tarjetas no cambia (la escala no mueve el diseño).
    try {
        $lista = @($elementos | Where-Object { $_ })
        if (-not $lista.Count) { return }
        $n = Nivel-Animacion
        $i = 0
        foreach ($el in $lista) {
            $el.BeginAnimation($propOpacidad, $null)
            if ($n -eq 0) { $el.Opacity = 1; continue }
            if ($n -eq 1) { $el.Opacity = 0; Animar $el $propOpacidad 1 120 0; continue }
            $esc = New-Object System.Windows.Media.ScaleTransform(0.96, 0.96)
            $el.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
            $el.RenderTransform = $esc
            $el.Opacity = 0
            $retraso = 30 * [Math]::Min($i, 11)
            Animar $el $propOpacidad 1 180 0 $retraso
            Animar $esc $propEscalaX 1 180 0.96 $retraso
            Animar $esc $propEscalaY 1 180 0.96 $retraso
            $i++
        }
    } catch { foreach ($el in @($elementos)) { if ($el) { $el.Opacity = 1 } } }
}

function Animar-Selector($panel) {
    # Las tarjetas de un selector de sistemas (Nueva máquina, Crear base) entran escalonadas al abrir la página
    try {
        $tarjetas = New-Object System.Collections.ArrayList
        $recoger = $null
        $recoger = {
            param($nodo)
            foreach ($h in @($nodo.Children)) {
                if ($h -is [System.Windows.Controls.RadioButton]) { [void]$tarjetas.Add($h) }
                elseif ($h -is [System.Windows.Controls.Panel]) { & $recoger $h }
            }
        }
        & $recoger $panel
        Entrada-Escalonada @($tarjetas)
    } catch {}
}

# ---------------------------------------------------------------- 5. interruptores, selectores y casillas
$script:segPrevio = @{}
$script:cuerpoMarcar = {
    param($s, $e)
    try {
        if ($e.OriginalSource -ne $s) { return }
        $plt = $s.Template; if (-not $plt) { return }
        $n = Nivel-Animacion
        $marcado = [bool]$s.IsChecked
        # casilla: la marca ✓ aparece con un fundido corto (100 ms)
        $marca = $plt.FindName('Marca', $s)
        if ($marca -and $s -is [System.Windows.Controls.CheckBox]) {
            Animar $marca $propOpacidad $(if ($marcado) { 1 } else { 0 }) 100 $(if ($marcado) { 0 } else { 1 })
            return
        }
        # selector de pastillas: el marcador se desliza desde la opción anterior (180 ms)
        $marc = $plt.FindName('Marcador', $s)
        if ($marc) {
            $marc.BeginAnimation($propOpacidad, $null)
            if (-not $marcado) { return }   # (al desmarcarse, lo que manda es el estilo)
            $padre = $s.Parent
            $clave = $(if ($padre) { $padre.GetHashCode() } else { 0 })
            $prev = $script:segPrevio[$clave]
            $script:segPrevio[$clave] = $s
            if ($n -eq 0 -or -not $prev -or $prev -eq $s -or -not $s.IsLoaded -or -not $prev.IsLoaded) { return }
            if ($n -eq 1) { Animar $marc $propOpacidad 1 100 0; return }
            $dx = $prev.TranslatePoint((New-Object System.Windows.Point(0, 0)), $s).X
            $ratio = [Math]::Max(0.2, $prev.ActualWidth / [Math]::Max(1, $s.ActualWidth))
            Animar $marc.RenderTransform.Children[1] $propX 0 180 $dx
            Animar $marc.RenderTransform.Children[0] $propEscalaX 1 180 $ratio
        }
    } catch {}
}
$script:alMarcar = [System.Windows.RoutedEventHandler]$script:cuerpoMarcar
$script:alDesmarcar = [System.Windows.RoutedEventHandler]{
    param($s, $e)
    try {
        if ($e.OriginalSource -ne $s) { return }
        $plt = $s.Template; if (-not $plt) { return }
        if ($plt.FindName('Marca', $s) -and $s -is [System.Windows.Controls.CheckBox]) { & $script:cuerpoMarcar $s $e; return }
        $marc = $plt.FindName('Marcador', $s)
        if ($marc) { $marc.BeginAnimation($propOpacidad, $null) }
    } catch {}
}

# ---------------------------------------------------------------- 6. barra de progreso con brillo
$script:barrasBrillo = @{}   # barra -> @{ Pct; Color } de las que tienen (o pueden tener) brillo
function Brillo-Barra($pb, [double]$pct, [string]$color) {
    # Lo llaman las funciones que ponen el progreso de una barra (Crear base, importar, máquinas nuevas, detalle).
    # Mientras la tarea avanza (0 < pct < 100, sin color de error) una franja de luz recorre lo relleno
    try {
        $script:barrasBrillo[$pb] = @{ Pct = $pct; Color = $color }
        Brillo-Evaluar $pb
    } catch {}
}
function Brillo-Evaluar($pb) {
    try {
        $dato = $script:barrasBrillo[$pb]
        $brillo = $pb.Template.FindName('Brillo', $pb)
        if (-not $brillo) { return }
        $n = Nivel-Animacion
        $franja = ($n -eq 2) -or ([bool]$Config.Sobrio -and $n -eq 1)
        $fallo = ($dato -and [string]$dato.Color -and ([string]$dato.Color -ieq [string]$Colores.Error))
        $minimizada = ($script:ventana -and $script:ventana.WindowState -eq [System.Windows.WindowState]::Minimized)
        $activo = $franja -and $dato -and $pb.IsVisible -and (-not $minimizada) -and (-not $fallo) -and ($dato.Pct -gt 0) -and ($dato.Pct -lt 100)
        if (-not $activo) {
            if ($brillo.Tag -eq 'on') { $brillo.RenderTransform.BeginAnimation($propX, $null); $brillo.Opacity = 0; $brillo.Tag = $null }
            return
        }
        if ($brillo.Tag -eq 'on') { return }
        $pista = [Math]::Max(120, [double]$pb.ActualWidth)
        $ancho = [Math]::Max(30, [Math]::Min(240, $pista * 0.25))
        $brillo.Width = $ancho
        $brillo.Background = Pincel-Brillo
        $brillo.Opacity = 1
        $brillo.RenderTransform.BeginAnimation($propX, (Animacion-Brillo $ancho $pista))
        $brillo.Tag = 'on'
    } catch {}
}
function Pincel-Brillo {
    $cc = ([System.Windows.Application]::Current.Resources['T_acentoClaro']).Color
    $deg = New-Object System.Windows.Media.LinearGradientBrush
    $deg.StartPoint = New-Object System.Windows.Point(0, 0.5); $deg.EndPoint = New-Object System.Windows.Point(1, 0.5)
    [void]$deg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromArgb(0, $cc.R, $cc.G, $cc.B), 0)))
    [void]$deg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromArgb(140, $cc.R, $cc.G, $cc.B), 0.5)))
    [void]$deg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromArgb(0, $cc.R, $cc.G, $cc.B), 1)))
    return $deg
}
function Animacion-Brillo([double]$ancho, [double]$pista) {
    # 1,6 s de pasada + 0,6 s de pausa, en bucle (solo se mueve una transformación sobre una capa recortada)
    $an = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $an.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $suave = New-Object System.Windows.Media.Animation.CubicEase; $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
    [void]$an.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(-$ancho, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero))))
    [void]$an.KeyFrames.Add((New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame($pista, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(1600)), $suave)))
    [void]$an.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($pista, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(2200)))))
    return $an
}
function Brillos-Revisar {
    # Al minimizar o restaurar la ventana: se paran o se retoman los brillos
    foreach ($pb in @($script:barrasBrillo.Keys)) { Brillo-Evaluar $pb }
}
function Brillo-Mapa($relleno, [double]$ancho) {
    # Barra de 3 px de las tarjetas del mapa del laboratorio (no es una ProgressBar): misma franja, recortada en lo relleno
    try {
        $n = Nivel-Animacion
        if (-not (($n -eq 2) -or ([bool]$Config.Sobrio -and $n -eq 1))) { return }
        $fr = New-Object System.Windows.Controls.Border
        $fr.Width = [Math]::Max(18, $ancho * 0.5); $fr.HorizontalAlignment = 'Left'; $fr.IsHitTestVisible = $false
        $fr.Background = Pincel-Brillo
        $tr = New-Object System.Windows.Media.TranslateTransform(-$fr.Width, 0)
        $fr.RenderTransform = $tr
        $relleno.ClipToBounds = $true
        $relleno.Child = $fr
        $tr.BeginAnimation($propX, (Animacion-Brillo $fr.Width ([Math]::Max(40, $ancho))))
    } catch {}
}

# ---------------------------------------------------------------- rayos pequeños alrededor de una barra al terminar
# Al acabar bien una tarea larga (Crear base, Nueva máquina), la barra «rebosa energía»: rayos cortos y finos que salen de su
# contorno, al estilo de la animación de inicio (rayos.cs: Contorno y el modo Barra). Al terminar sale una ráfaga (si se vio
# la tarea en marcha) y después un goteo continuo de 1-3 rayitos cada poco, mientras la barra se vea y la ventana esté activa
# (con la ventana en segundo plano, minimizada o en otra página no gasta nada). La capa es un Border transparente puesto
# encima de la barra y algo más grande que ella. Solo con animaciones Normales y la casilla «Rayos» de Apariencia.
$script:rayosBarra = @{}   # capa -> RayosSueltos
function Rayos-Barra($capaR, $barra, [bool]$rafaga = $false) {
    # Enciende el goteo (si no lo estaba) y, con $rafaga, lanza la ráfaga del final. Devuelve si se ha podido.
    try {
        if ((Animaciones-Modo) -ne 'Normales' -or $Config.RayosInicio -eq $false) { Parar-RayosBarra $capaR; return $false }
        if (-not ('FullCowlWpf.RayosSueltos' -as [type]) -or -not $capaR -or -not $barra) { return $false }
        $r = $script:rayosBarra[$capaR]
        if (-not $r) {
            $r = New-Object FullCowlWpf.RayosSueltos($capaR, $script:ventana)
            $r.Goteo = $false
            $osc = [int]($script:temaActual -eq 'oscuro')
            $halo = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString((Valor-Paleta 'encendida' $osc))
            $medio = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString((Valor-Paleta 'brillo' $osc))
            $claro = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#F2FFFC')
            $r.PonerColores($halo, $medio, $claro, 0.55)
            $r.Barra = $barra
            $script:rayosBarra[$capaR] = $r
        }
        if (-not $r.Permitido) { $r.Permitido = $true }
        if (-not $r.Goteo) { $r.Goteo = $true }
        if ($rafaga) { return [bool]$r.Contorno($barra) }
        return $true
    } catch { Escribir-Log ("Rayos de la barra: " + $_.Exception.Message); return $false }
}
function Parar-RayosBarra($capaR) {
    # La tarea ya no está «terminada bien» (empieza otra, falla, se quita la fila...): se acaban los rayos
    try {
        $r = $script:rayosBarra[$capaR]
        if ($r) { $r.Goteo = $false; $r.Permitido = $false }
    } catch {}
}
function Olvidar-RayosBarra($capaR) {
    # La fila se quita: además de parar, el objeto de rayos se desapunta de la ventana (Soltar, ficha 34) para que no
    # se quede vivo hasta cerrar Full Cowl. Solo para rayos de barras; los de Inicio y el asistente no pasan por aquí.
    try { $rayosFila = $script:rayosBarra[$capaR]; if ($rayosFila) { $rayosFila.Soltar() } } catch { try { Escribir-Log ("Soltar rayos: " + $_.Exception.Message) } catch {} }
    Parar-RayosBarra $capaR
    try { $script:rayosBarra.Remove($capaR) } catch {}
}

# ---------------------------------------------------------------- 3. que se vean la onda y el hundimiento
# La onda y el hundimiento van en estilos.xaml, pero muchos botones hacen trabajo pesado nada más pulsarlos (encender una
# máquina, leer discos...): la ventana se congela y la animación no llega a verse. Con animaciones Normales, el clic de los
# botones con esos efectos se retrasa un poco (200 ms los principales, 110 ms el resto) para que dé tiempo a verlos.
# Va con un manejador del evento Click, que solo salta al pulsar (no en cada movimiento del ratón).
$script:clicReenviado = $null
$script:clicEnEspera = $null
$script:alClicBoton = [System.Windows.RoutedEventHandler]{
    param($s, $e)
    try {
        if ($e.OriginalSource -ne $s) { return }
        if ($script:clicReenviado -eq $s) { $script:clicReenviado = $null; return }   # el clic de verdad, ya con la animación vista
        if ($e.Handled) { return }
        if ((Nivel-Animacion) -lt 2) { return }
        $plt = $s.Template; if (-not $plt) { return }
        $caja = $plt.FindName('Caja', $s)
        if (-not ($caja -and $caja.RenderTransform -is [System.Windows.Media.ScaleTransform])) { return }
        if ($script:clicEnEspera) { $e.Handled = $true; return }   # (un segundo clic mientras espera el primero no cuenta)
        $tm = New-Object System.Windows.Threading.DispatcherTimer
        $tm.Interval = [TimeSpan]::FromMilliseconds($(if ($plt.FindName('Onda', $s)) { 200 } else { 110 }))
        $tm.Tag = $s
        $tm.Add_Tick({
            param($reloj, $ev)
            $reloj.Stop()
            $btnC = $reloj.Tag
            $script:clicEnEspera = $null
            try {
                if ($btnC.IsEnabled) {
                    $script:clicReenviado = $btnC
                    $btnC.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $btnC)))
                }
            } catch { Escribir-Log ("Clic de botón: " + ($_ | Out-String)) } finally { $script:clicReenviado = $null }
        })
        $script:clicEnEspera = $s
        $tm.Start()
        $e.Handled = $true
    } catch {}
}

# ---------------------------------------------------------------- enganche (una sola vez)
# Solo casillas, selectores de pastillas y el clic de los botones (eventos que pasan poco). Lo que pasa a cada movimiento del
# ratón (levantar tarjetas, hundir botones) va en estilos.xaml.
try {
    $em = [System.Windows.EventManager]
    $em::RegisterClassHandler([System.Windows.Controls.Button], [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $script:alClicBoton, $true)
    foreach ($tipoT in @([System.Windows.Controls.RadioButton], [System.Windows.Controls.CheckBox])) {
        $em::RegisterClassHandler($tipoT, [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $script:alMarcar, $true)
        $em::RegisterClassHandler($tipoT, [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $script:alDesmarcar, $true)
    }
} catch { Escribir-Log ("Animaciones (ficha 22): no se pudieron enganchar los efectos: " + $_.Exception.Message) }
