# =====================================================================
#  Interfaz nueva: página «Inicio»
#  Saludo según la hora, estado de un vistazo, las cuatro acciones principales,
#  lo que está en marcha, avisos y las últimas máquinas con las que se trabajó.
#  Se pinta al entrar y cuando termina de leerse la lista de máquinas; «En marcha» se
#  refresca solo mientras se ve.
# =====================================================================
$InicioMarca.Source = $ImgLogo.Source
$script:avisosInicio = @()

function Nombre-Saludo {
    # El nombre de Ajustes; si no hay, el del usuario de Windows cuando parece un nombre
    $n = ([string]$Config.Nombre).Trim()
    if (-not $n) {
        $u = [Environment]::UserName
        if ($u -match '^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]{2,20}$') { $n = $u.Substring(0, 1).ToUpper() + $u.Substring(1).ToLower() }
    }
    return $n
}

function Saludo-Hora {
    # 6:00-13:59 días, 14:00-20:59 tardes, 21:00-5:59 noches (hora del sistema)
    $h = (Get-Date).Hour
    if ($h -ge 6 -and $h -lt 14) { return 'Buenos días' }
    if ($h -ge 14 -and $h -lt 21) { return 'Buenas tardes' }
    return 'Buenas noches'
}

function Pct-DeEstado($est) {
    # Porcentaje de una creación o importación; en las fases sin mensajes avanza por tiempo estimado
    $pct = [double]$est.pct
    if ([string]$est.estado -eq 'curso' -and [double]$est.hasta -gt $pct -and [double]$est.esperadoSeg -gt 0 -and $est.inicioFase) {
        $trans = ((Get-Date) - [datetime]$est.inicioFase).TotalSeconds
        $pct = $pct + ([double]$est.hasta - $pct) * [Math]::Min(0.95, $trans / [double]$est.esperadoSeg)
    }
    return [Math]::Min(100, [Math]::Max(0, $pct))
}

function Tareas-EnMarcha {
    # Lo que se está haciendo ahora: @{ Titulo; Detalle; Pct; Nav }
    $res = @()
    try {
        $est = Leer-EstadoReciente
        if ($est -and [string]$est.estado -eq 'curso' -and -not ($est.pid -and -not (Get-Process -Id ([int]$est.pid) -ErrorAction SilentlyContinue))) {
            $res += @{ Titulo = "Creando la base «$($est.nombre)»"; Detalle = [string]$est.paso; Pct = (Pct-DeEstado $est); Nav = $NavBase }
        }
    } catch {}
    try {
        $est = Leer-EstadoImp
        if ($est -and [string]$est.estado -eq 'curso' -and -not ($est.pid -and -not (Get-Process -Id ([int]$est.pid) -ErrorAction SilentlyContinue))) {
            $res += @{ Titulo = "Importando «$($est.nombre)»"; Detalle = [string]$est.paso; Pct = (Pct-DeEstado $est); Nav = $NavImportar }
        }
    } catch {}
    try {
        foreach ($ol in @(Leer-OperacionesLab)) {
            if ([string]$ol.estado -eq 'curso') { $res += @{ Titulo = "Estado inicial de «$($ol.lab)»"; Detalle = [string]$ol.paso; Pct = [double]$ol.pct; Nav = $NavLab } }
        }
    } catch {}
    foreach ($f in @($script:filas)) {
        if ($f -and $f.Configurando) { $res += @{ Titulo = "Configurando «$($f.Nombre)»"; Detalle = [string]$f.EstadoTexto; Pct = [double]$f.Progreso; Nav = $NavMaq } }
    }
    return $res
}

function Texto-Inicio([string]$texto, [double]$tam, [string]$color, [bool]$negrita = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $texto; $t.FontSize = $tam; $t.Foreground = Pincel $color; $t.TextWrapping = 'Wrap'
    if ($negrita) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $t
}

function Hacer-Clicable($elemento, $nav) {
    # Al pulsar, lleva a esa página del menú
    $elemento.Cursor = [System.Windows.Input.Cursors]::Hand
    $elemento.Background = [System.Windows.Media.Brushes]::Transparent
    $elemento.Tag = $nav
    $elemento.Add_MouseLeftButtonUp({ param($s, $e) if ($s.Tag) { $s.Tag.IsChecked = $true } })
}

# ---- Aviso al terminar una tarea larga (y, si se puede, un rayo suave en «En marcha»)
$script:tareasVistas = @{}
function Marcar-Tarea([string]$clave) {
    # Se llama mientras la tarea está en curso: así solo avisa de lo que se ha visto empezar en esta sesión
    if (-not $script:tareasVistas.ContainsKey($clave)) { $script:tareasVistas[$clave] = [DateTime]::Now }
}
function Tarea-Terminada([string]$clave, [string]$texto, $nav, [double]$segundos) {
    if (-not $script:tareasVistas.ContainsKey($clave)) { return }
    $ini = $script:tareasVistas[$clave]
    $script:tareasVistas.Remove($clave)
    if ($segundos -lt 10) { return }
    $script:navTareaFin = $nav
    Mostrar-Toast $texto 'ok' '' { if ($script:navTareaFin) { $script:navTareaFin.IsChecked = $true } } 'Ver'
    # Rayo: solo con animaciones Normales, rayos permitidos, Inicio visible y ventana a la vista
    try { if ($script:rayos -and $paginaInicio.IsVisible) { [void]$script:rayos.Chispazo($InicioMarcha) } } catch {}
}

function Pintar-Marcha {
    $tareas = @(Tareas-EnMarcha)
    $InicioChipTareas.Text = $(if ($tareas.Count) { Plural $tareas.Count 'tarea en marcha' 'tareas en marcha' } else { 'Nada en marcha' })
    $InicioMarcha.Children.Clear()
    if (-not $tareas.Count) {
        $inVm = New-Object System.Windows.Controls.StackPanel
        Poner-Vacio $inVm 'Ico_Actualizar' 'Nada en marcha' 'Cuando crees una base o importes algo, lo verás aquí.' '' $null $false $true
        $InicioMarcha.Children.Add($inVm) | Out-Null
        return
    }
    foreach ($t in $tareas) {
        $caja = New-Object System.Windows.Controls.StackPanel
        $caja.Margin = New-Object System.Windows.Thickness(0, 0, 0, 14)
        $fila = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::Auto
        $fila.ColumnDefinitions.Add($c1); $fila.ColumnDefinitions.Add($c2)
        $tit = Texto-Inicio $t.Titulo 13.5 $Colores.Texto $true
        $pctTxt = Texto-Inicio ('{0} %' -f [int]$t.Pct) 12.5 $Colores.Suave
        [System.Windows.Controls.Grid]::SetColumn($pctTxt, 1)
        $fila.Children.Add($tit) | Out-Null; $fila.Children.Add($pctTxt) | Out-Null
        $barra = New-Object System.Windows.Controls.ProgressBar
        $barra.Style = [System.Windows.Application]::Current.FindResource('Progreso')
        $barra.Minimum = 0; $barra.Maximum = 100; $barra.Value = $t.Pct
        $barra.Margin = New-Object System.Windows.Thickness(0, 7, 0, 0)
        $caja.Children.Add($fila) | Out-Null
        $caja.Children.Add($barra) | Out-Null
        if ($t.Detalle) {
            $det = Texto-Inicio $t.Detalle 12 $Colores.Suave
            $det.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
            $caja.Children.Add($det) | Out-Null
        }
        Hacer-Clicable $caja $t.Nav
        $InicioMarcha.Children.Add($caja) | Out-Null
    }
}

function Calcular-Avisos {
    # Lo que conviene saber o hacer. Cada uno: @{ Icono; Color; Texto; Nav }
    $av = @()
    try {
        foreach ($b in @(Obtener-Bases)) {
            if ($b.ConAgente -and -not $b.ClaveTemporal) {
                $av += @{ Icono = 'Aviso'; Color = $Colores.Aviso; Nav = $NavBase
                          Texto = "La base «$($b.Nombre)» se hizo antes de la 2.0: la contraseña de las máquinas queda guardada dentro de ella. Conviene rehacerla en «Crear base»." }
            }
        }
    } catch {}
    $sinBase = @($script:maquinas | Where-Object { $_.Estado -eq 'Sin base' })
    if ($sinBase.Count) {
        $av += @{ Icono = 'Aviso'; Color = $Colores.Error; Nav = $NavMaq
                  Texto = "$(Plural $sinBase.Count 'máquina se ha quedado' 'máquinas se han quedado') sin su base (no arrancarán): $((@($sinBase | Select-Object -First 3 | ForEach-Object Nombre)) -join ', ')." }
    }
    try { $avAct = Aviso-Actualizacion; if ($avAct) { $av = @($avAct) + $av } } catch {}
    $d = $script:disco
    if ($d -and $d.Total -and ($d.Libre / $d.Total) -lt 0.1) {
        $av += @{ Icono = 'Aviso'; Color = $Colores.Error; Nav = $NavMaq
                  Texto = "Queda poco espacio en el disco $($d.Unidad): $(Formato-Tamano $d.Libre) libres. Borra máquinas que no uses." }
    }
    return $av
}

function Pintar-Avisos {
    $InicioAvisos.Children.Clear()
    if (-not $script:avisosInicio.Count) {
        $fila = New-Object System.Windows.Controls.StackPanel
        Poner-Vacio $fila 'Ico_Info' 'Todo en orden' 'No hay avisos ahora mismo.' '' $null $false $true
        $InicioAvisos.Children.Add($fila) | Out-Null
        return
    }
    foreach ($a in $script:avisosInicio) {
        $fila = New-Object System.Windows.Controls.Grid
        $fila.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(26)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $fila.ColumnDefinitions.Add($c1); $fila.ColumnDefinitions.Add($c2)
        $g = Nuevo-Icono $a.Icono 18 $a.Color
        $g.VerticalAlignment = 'Top'; $g.HorizontalAlignment = 'Left'; $g.Margin = New-Object System.Windows.Thickness(0, 0, 0, 0)
        $t = Texto-Inicio $a.Texto 12.5 $Colores.Texto
        if ($a.Boton) {
            # Aviso con botón (p. ej. «Actualizar ahora»)
            $pila = New-Object System.Windows.Controls.StackPanel
            $pila.Children.Add($t) | Out-Null
            $bt = New-Object System.Windows.Controls.Button
            $bt.Style = [System.Windows.Application]::Current.FindResource('BotonSecundario')
            $bt.Content = [string]$a.Boton; $bt.HorizontalAlignment = 'Left'; $bt.Height = 30; $bt.Padding = New-Object System.Windows.Thickness(14, 0, 14, 0)
            $bt.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
            $bt.Tag = [System.Windows.Application]::Current.FindResource('Ico_Actualizar')   # el icono del botón (el mismo de «Actualizar» de Mis máquinas)
            $bt.DataContext = $a.Accion
            $bt.Add_Click({ param($s2, $e2) try { & $s2.DataContext } catch { Escribir-Log ("Aviso: " + ($_ | Out-String)) } })
            $pila.Children.Add($bt) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($pila, 1)
            $fila.Children.Add($g) | Out-Null; $fila.Children.Add($pila) | Out-Null
            $InicioAvisos.Children.Add($fila) | Out-Null
            continue
        }
        [System.Windows.Controls.Grid]::SetColumn($t, 1)
        $fila.Children.Add($g) | Out-Null; $fila.Children.Add($t) | Out-Null
        Hacer-Clicable $fila $a.Nav
        $InicioAvisos.Children.Add($fila) | Out-Null
    }
}

function Pintar-Seguir {
    # Las 4 máquinas con las que se trabajó más hace poco: las de la carpeta modificada más tarde
    # (al encender, apagar, crear o cambiar algo VMware escribe ahí). Sin bases ni desechables.
    $InicioSeguir.Children.Clear()
    $recientes = @($script:maquinas | Where-Object { -not $_.EsBase -and -not $_.Desechable -and -not $_.Externa } |
        Sort-Object Modificada -Descending | Select-Object -First 4)
    # Sin máquinas (y ya leídas): bloque compacto en vez de esconder la tira
    $inSabe = [bool]$script:cargado
    $InicioSeguirCaja.Visibility = $(if ($recientes.Count -or $inSabe) { 'Visible' } else { 'Collapsed' })
    $InicioSeguirVacio.Visibility = $(if (-not $recientes.Count -and $inSabe) { 'Visible' } else { 'Collapsed' })
    if (-not $recientes.Count -and $inSabe) { Poner-Vacio $InicioSeguirVacio 'Ico_Maquinas' 'Aquí saldrán tus últimas máquinas' '' '' $null $false $true }
    foreach ($m in $recientes) {
        $fila = @($script:filas | Where-Object { $_.Vmx -eq $m.Vmx }) | Select-Object -First 1
        if (-not $fila) { continue }
        $boton = New-Object System.Windows.Controls.Button
        $boton.Style = [System.Windows.Application]::Current.FindResource('BaldosaInicio')
        $boton.Background = Pincel '#E6EEE8'; $boton.Foreground = Pincel $Colores.Texto
        $boton.Padding = New-Object System.Windows.Thickness(12, 10, 12, 10)
        $boton.Margin = New-Object System.Windows.Thickness(4, 0, 4, 0)
        $boton.HorizontalContentAlignment = 'Stretch'
        $boton.ToolTip = [string]$m.Nombre
        $g = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(38)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
        $icono = New-Object System.Windows.Controls.Border
        $icono.Width = 32; $icono.Height = 32; $icono.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $icono.Background = Pincel-Fijo $(if ($fila.IconoFondo) { $fila.IconoFondo } else { $Colores.Verde })
        $icono.HorizontalAlignment = 'Left'
        if ($fila.IconoSimbolo) {
            $vb = New-Object System.Windows.Controls.Viewbox; $vb.Width = 18; $vb.Height = 18
            $p = New-Object System.Windows.Shapes.Path
            $p.Data = $fila.IconoSimbolo; $p.Stroke = [System.Windows.Media.Brushes]::White; $p.StrokeThickness = 1.8
            $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'; $p.StrokeLineJoin = 'Round'
            $p.Width = 24; $p.Height = 24
            $vb.Child = $p
            $icono.Child = $vb
        } elseif ($fila.IconoLogo) {
            $p = New-Object System.Windows.Shapes.Path
            $p.Data = $fila.IconoLogo; $p.Fill = [System.Windows.Media.Brushes]::White; $p.Stretch = 'Uniform'
            $p.Width = 16; $p.Height = 16
            $icono.Child = $p
        } else {
            $gl = New-Object System.Windows.Controls.TextBlock
            $gl.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets'); $gl.Text = [string]$fila.IconoGlifo
            $gl.Foreground = [System.Windows.Media.Brushes]::White; $gl.FontSize = 15
            $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
            $icono.Child = $gl
        }
        $textos = New-Object System.Windows.Controls.StackPanel; $textos.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($textos, 1)
        $nom = Texto-Inicio ([string]$m.Nombre) 13 $Colores.Texto $true
        $nom.TextWrapping = 'NoWrap'; $nom.TextTrimming = 'CharacterEllipsis'
        $sub = Texto-Inicio ([string]$fila.EstadoTexto) 11.5 $fila.EstadoColor
        $sub.TextWrapping = 'NoWrap'
        $textos.Children.Add($nom) | Out-Null; $textos.Children.Add($sub) | Out-Null
        $g.Children.Add($icono) | Out-Null; $g.Children.Add($textos) | Out-Null
        $boton.Content = $g
        $boton.Tag = $fila
        $boton.Add_Click({
            param($s, $e)
            $fl = $s.Tag
            $NavMaq.IsChecked = $true
            try { $Lista.SelectedItems.Clear(); [void]$Lista.SelectedItems.Add($fl); $Lista.ScrollIntoView($fl) } catch {}
        })
        $InicioSeguir.Children.Add($boton) | Out-Null
    }
}

function Pintar-Inicio {
    $nombre = Nombre-Saludo
    $InicioSaludo.Text = (Saludo-Hora) + $(if ($nombre) { ", $nombre" } else { '' })
    $nEnc = @($script:maquinas | Where-Object { $_.Encendida -and -not $_.EsBase }).Count
    $InicioChipEnc.Text = $(if ($nEnc) { Plural $nEnc 'máquina encendida' 'máquinas encendidas' } else { 'Ninguna encendida' })
    $d = $script:disco
    $InicioChipLibre.Text = $(if ($d -and $d.Total) { '{0:N0} GB libres' -f ($d.Libre / 1GB) } else { 'Espacio sin leer' })
    $script:avisosInicio = @(Calcular-Avisos)
    Pintar-Avisos
    Pintar-Marcha
    Pintar-Seguir
}

# ---------------------------------------------------------------- rayos ocasionales (rayos.cs)
# Si algo falla (o no se pudo compilar), Inicio funciona igual, sin rayos
$script:rayos = $null
function Colores-Rayos {
    if (-not $script:rayos) { return }
    $oscuro = ($script:temaActual -eq 'oscuro')
    $halo = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Paleta['encendida'][[int]$oscuro])
    $medio = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Paleta['brillo'][[int]$oscuro])
    $claro = [System.Windows.Media.ColorConverter]::ConvertFromString('#F2FFFC')
    $script:rayos.PonerColores([System.Windows.Media.Color]$halo, [System.Windows.Media.Color]$medio, [System.Windows.Media.Color]$claro)
}
function Rayos-Permitir {
    # El mando «Animaciones» manda más que la casilla: solo hay rayos en «Normales»
    if ($script:rayos) { $script:rayos.Permitido = (($Config.RayosInicio -ne $false) -and ((Animaciones-Modo) -eq 'Normales')) }
}
try {
    if ($script:errorRayos) { throw $script:errorRayos }
    if ('FullCowlWpf.RayosSueltos' -as [type]) {
        $script:rayos = New-Object FullCowlWpf.RayosSueltos($InicioRayos, $ventana)
        $script:rayos.Marca = $InicioMarca
        Colores-Rayos
        Rayos-Permitir
    }
} catch { $script:rayos = $null; Escribir-Log ("Rayos de Inicio desactivados: " + ($_ | Out-String)) }

function Entrar-Inicio {
    try { Pintar-Inicio } catch { Escribir-Log ("Inicio: " + ($_ | Out-String)) }
}

# El chip del disco abre Ajustes → Espacio y limpieza (ficha 30)
$InicioChipDisco.Add_MouseLeftButtonUp({ try { Mostrar-Ajustes; Ir-Seccion 'espacio' } catch { Escribir-Log ("Chip de disco: " + $_.Exception.Message) } })
$BaldNueva.Add_Click({ $NavNueva.IsChecked = $true })
$BaldLab.Add_Click({ $NavLab.IsChecked = $true })
$BaldBase.Add_Click({ $NavBase.IsChecked = $true })
$BaldImp.Add_Click({ $NavImportar.IsChecked = $true })
