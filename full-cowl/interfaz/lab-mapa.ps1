#  Mapa de red de un laboratorio (ficha 13). Es UN solo componente: lo usa «Mis laboratorios» y, más adelante,
#  la vista previa de «Crear laboratorio».
#
#  - Construir-ModeloLab  : de las filas de «Mis máquinas» saca redes y máquinas.
#  - Dibujar-MapaLab      : pinta el modelo en un Canvas de 780 de ancho. Cada tarjeta es un botón con su
#                           identificador (Tag = vmx) y cada barra un Border con su clave de red (para el
#                           arrastre de la fase 2).
#  - Animar-MapaLab       : pulsos en los cables y destellos en las barras (solo con animaciones Normales).
#  Todo con colores con nombre (T_...): nada de colores fijos.

# ---------------------------------------------------------------- constantes (se pueden retocar a ojo)
$script:ConstMapa = @{
    Ancho = 780
    AnchoTarjeta = 156; AltoTarjeta = 60; Separacion = 16; LargoCable = 34
    MaxPorFila = 4
    PulsoCableMin = 1.7; PulsoCableMax = 3.1; PulsoCableViaje = 0.9     # s entre pulsos / lo que tarda en recorrer
    PulsoBarraMin = 4.6; PulsoBarraMax = 8.0; PulsoBarraViaje = 2.4
    DestelloCada = 9.0; DestelloViaje = 1.0                              # un destello por barra cada ~9 s
    MaxPuntos = 40                                                       # más puntos animados que esto: solo barras
}

$script:mapaAnim = New-Object System.Collections.ArrayList     # @{ T = transform; Prop; Anim }
$script:mapaCartas = @{}                                       # vmx -> botón
$script:mapaBarras = @{}                                       # clave de red -> barra
$script:mapaAnimando = $false


# ---------------------------------------------------------------- modelo
function Orden-TipoRed([string]$tipo) {
    switch ($tipo) { 'nat' { 0 } 'bridged' { 1 } 'hostonly' { 2 } 'custom' { 3 } 'pvn' { 4 } default { 5 } }
}

function Construir-ModeloLab($filas) {
    # $filas: filas de «Mis máquinas» (FullCowl.Maquina) de un mismo laboratorio
    $segs = $null; try { $segs = Leer-Segmentos } catch {}
    $redes = @{}
    $maquinas = New-Object System.Collections.ArrayList
    $dominio = ''
    foreach ($f in $filas) { $d = [string]$f.Datos.Dominio; if ($d -and -not $dominio) { $dominio = $d } }
    foreach ($f in $filas) {
        $dat = $f.Datos
        $claves = @()
        $tarjetas = @($dat.Tarjetas)
        if (-not $tarjetas.Count) { $tarjetas = @([pscustomobject]@{ Tipo = 'ninguna'; Vnet = ''; Pvn = '' }) }
        foreach ($t in $tarjetas) {
            $clave = $(if ($t.Tipo -eq 'ninguna') { 'ninguna' } else { Clave-Tarjeta $t })
            if (-not $redes.ContainsKey($clave)) {
                $nombre = ''; $inet = $false
                switch ($t.Tipo) {
                    'nat'      { $nombre = 'VMnet8 (NAT)'; $inet = $true }
                    'bridged'  { $nombre = 'Puente (red física)'; $inet = $true }
                    'hostonly' { $nombre = 'VMnet1 (solo anfitrión)' }
                    'custom'   { $nombre = $(if ($t.Vnet) { [string]$t.Vnet } else { 'VMnet' }) }
                    'pvn'      { $nombre = (Texto-Tarjeta $t $segs) }
                    default    { $nombre = 'Sin red' }
                }
                $redes[$clave] = [pscustomobject]@{ Clave = $clave; Tipo = [string]$t.Tipo; Nombre = $nombre; Internet = $inet; Ips = (New-Object System.Collections.ArrayList); Primeras = (New-Object System.Collections.ArrayList) }
            }
            $claves += $clave
            if ($dat.IP -and $claves.Count -eq 1) { [void]$redes[$clave].Ips.Add([string]$dat.IP) }
        }
        $esDc = [bool]([string]$dat.Dominio)
        $win = [bool]$dat.EsWindows
        $etiqueta = ''
        if ($dominio) { $etiqueta = $(if ($esDc) { 'Controlador' } elseif ($win) { 'Cliente del dominio' } else { '' }) }
        $dentro = [bool]($dominio -and ($esDc -or $win))
        [void]$maquinas.Add([pscustomobject]@{
            Fila = $f; Vmx = [string]$f.Vmx; Nombre = [string]$f.Nombre; Ip = [string]$dat.IP
            Encendida = [bool]$f.Encendida; Configurando = [bool]$f.Configurando; Pct = [double]$f.Progreso; Texto = [string]$f.EstadoTexto
            Redes = $claves; Etiqueta = $etiqueta; EsDc = $esDc; EnDominio = $dentro
        })
    }
    $listaRedes = @($redes.Values | Sort-Object @{ Expression = { Orden-TipoRed $_.Tipo } }, Nombre)
    foreach ($r in $listaRedes) {
        $r | Add-Member -NotePropertyName Subred -NotePropertyValue '' -Force
        $ip = @($r.Ips | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
        if ($ip.Count) { $p = $ip[0].Split('.'); $r.Subred = "$($p[0]).$($p[1]).$($p[2]).0/24" }
    }
    # Cada máquina bajo SU PRIMERA red (las demás salen como «también en…»); el controlador, primero
    foreach ($m in $maquinas) { [void]$redes[$m.Redes[0]].Primeras.Add($m) }
    return [pscustomobject]@{ Redes = $listaRedes; Maquinas = $maquinas; Dominio = $dominio; Todas = $redes }
}

# ---------------------------------------------------------------- dibujo
function Nuevo-Texto([string]$texto, [double]$tam, [string]$colorTema, [bool]$negrita = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $texto; $t.FontSize = $tam
    Ref-Tema $t ([System.Windows.Controls.TextBlock]::ForegroundProperty) $colorTema
    if ($negrita) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $t
}
function Poner-Pos($el, [double]$x, [double]$y) {
    [System.Windows.Controls.Canvas]::SetLeft($el, $x); [System.Windows.Controls.Canvas]::SetTop($el, $y)
}


function Nueva-Tarjeta-Maquina($m, [bool]$elegida, $c) {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Style = $script:estiloMapaMaq
    $btn.Width = $c.AnchoTarjeta; $btn.Height = $c.AltoTarjeta
    $btn.Tag = $m.Vmx
    $btn.Name = 'Maq_' + ($m.Nombre -replace '[^A-Za-z0-9_]', '_')
    Ref-Tema $btn ([System.Windows.Controls.Control]::BackgroundProperty) 'T_superficie'
    Ref-Tema $btn ([System.Windows.Controls.Control]::BorderBrushProperty) $(if ($elegida) { 'T_acento' } else { 'T_borde' })
    $btn.BorderThickness = New-Object System.Windows.Thickness($(if ($elegida) { 2 } else { 1 }))
    if (-not $m.Encendida -and -not $m.Configurando) { $btn.Opacity = 0.62 }
    $estado = $(if ($m.Configurando) { 'configurándose' } elseif ($m.Encendida) { 'encendida' } else { 'apagada' })
    $btn.SetValue([System.Windows.Automation.AutomationProperties]::NameProperty, "$($m.Nombre), $($m.Fila.Familia), $estado, $(if ($m.Ip) { $m.Ip } else { 'sin IP' })")
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $pas = Pastilla-Sistema $m.Fila 32
    $pas.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0); $pas.VerticalAlignment = 'Center'
    $col = New-Object System.Windows.Controls.StackPanel
    $col.VerticalAlignment = 'Center'; $col.Margin = New-Object System.Windows.Thickness(9, 0, 18, 0)
    [System.Windows.Controls.Grid]::SetColumn($col, 1)
    $nom = Nuevo-Texto $m.Nombre 12 'T_texto' $true
    $nom.TextTrimming = 'CharacterEllipsis'
    [void]$col.Children.Add($nom)
    $sub = $(if ($m.Configurando) { $m.Texto } elseif ($m.Ip) { $m.Ip } else { '' })
    $st = Nuevo-Texto $sub 11 'T_textoSuave'; $st.TextTrimming = 'CharacterEllipsis'
    [void]$col.Children.Add($st)
    [void]$g.Children.Add($pas); [void]$g.Children.Add($col)
    # punto de estado arriba a la derecha
    $pt = New-Object System.Windows.Shapes.Ellipse
    $pt.Width = 7; $pt.Height = 7; $pt.HorizontalAlignment = 'Right'; $pt.VerticalAlignment = 'Top'
    $pt.Margin = New-Object System.Windows.Thickness(0, 7, 8, 0)
    Ref-Tema $pt ([System.Windows.Shapes.Shape]::FillProperty) $(if ($m.Encendida) { 'T_acento' } else { 'T_pista' })
    [System.Windows.Controls.Grid]::SetColumnSpan($pt, 2)
    [void]$g.Children.Add($pt)
    # barra de progreso de 3 px (si se está configurando): va DEBAJO del texto, en su columna, para no tapar ni el logo ni el
    # nombre (antes iba pegada al borde de abajo de toda la tarjeta y pisaba las dos cosas)
    if ($m.Configurando) {
        $pctM = [Math]::Max(2, [Math]::Min(100, [double]$m.Pct))
        $fondo = New-Object System.Windows.Controls.Grid
        $fondo.Height = 3; $fondo.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        $cpA = New-Object System.Windows.Controls.ColumnDefinition; $cpA.Width = New-Object System.Windows.GridLength($pctM, 'Star')
        $cpB = New-Object System.Windows.Controls.ColumnDefinition; $cpB.Width = New-Object System.Windows.GridLength([Math]::Max(0.001, 100 - $pctM), 'Star')
        [void]$fondo.ColumnDefinitions.Add($cpA); [void]$fondo.ColumnDefinitions.Add($cpB)
        $pista = New-Object System.Windows.Controls.Border
        Ref-Tema $pista ([System.Windows.Controls.Border]::BackgroundProperty) 'T_pista'; $pista.CornerRadius = New-Object System.Windows.CornerRadius(2)
        [System.Windows.Controls.Grid]::SetColumnSpan($pista, 2)
        [void]$fondo.Children.Add($pista)
        $rel = New-Object System.Windows.Controls.Border
        Ref-Tema $rel ([System.Windows.Controls.Border]::BackgroundProperty) 'T_acento'; $rel.CornerRadius = New-Object System.Windows.CornerRadius(2)
        [void]$fondo.Children.Add($rel)
        [void]$col.Children.Add($fondo)
        # ancho aproximado de lo relleno (la columna de texto mide unos 85 px) para la franja de luz
        Brillo-Mapa $rel (85 * $pctM / 100)
    }
    $btn.Content = $g
    return $btn
}

function Pastilla-Mapa([string]$texto, [double]$x, [double]$y) {
    # Pastilla pequeña de acento (etiquetas «Controlador», «Dominio…»)
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius(8); $b.Padding = New-Object System.Windows.Thickness(7, 1, 7, 1)
    Ref-Tema $b ([System.Windows.Controls.Border]::BackgroundProperty) 'T_acento'
    $t = Nuevo-Texto $texto 10.5 'T_sobreAcento' $true
    $b.Child = $t
    Poner-Pos $b $x $y
    [System.Windows.Controls.Panel]::SetZIndex($b, 6)
    return $b
}

function Pulso-Cable($canvas, [double]$x, [double]$y1, [double]$y2, [int]$sentido, [double]$desfase) {
    # Un punto que recorre el cable (el sentido alterna por cable)
    $c = $script:ConstMapa
    $d = New-Object System.Windows.Shapes.Ellipse
    $d.Width = 6; $d.Height = 6; $d.Opacity = 0; $d.IsHitTestVisible = $false
    Ref-Tema $d ([System.Windows.Shapes.Shape]::FillProperty) 'T_brillo'
    $tr = New-Object System.Windows.Media.TranslateTransform(0, 0)
    $d.RenderTransform = $tr
    Poner-Pos $d ($x - 3) $(if ($sentido -gt 0) { $y1 - 3 } else { $y2 - 3 })
    [System.Windows.Controls.Panel]::SetZIndex($d, 4)
    [void]$canvas.Children.Add($d)
    $largo = $y2 - $y1
    $ciclo = $c.PulsoCableMin + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * ($c.PulsoCableMax - $c.PulsoCableMin)
    [void]$script:mapaAnim.Add(@{ Obj = $d; Tr = $tr; Eje = 'Y'; Desde = 0; Hasta = $(if ($sentido -gt 0) { $largo } else { -$largo }); Viaje = $c.PulsoCableViaje; Ciclo = $ciclo; Desfase = $desfase })
}

function Dibujar-MapaLab($canvas, $modelo, $vmxElegida, [double]$escala = 1.0, $alElegir = $null) {
    if (-not $alElegir) { $alElegir = { param($s, $a) Al-PulsarMaquinaLab $s } }
    $c = $script:ConstMapa
    Parar-AnimMapa
    $canvas.Children.Clear()
    $script:mapaAnim.Clear(); $script:mapaCartas.Clear(); $script:mapaBarras.Clear()
    if (-not $script:estiloMapaMaq) { $script:estiloMapaMaq = $paginaLab.FindResource('MapaMaq') }
    $W = [double]$c.Ancho
    $y = 18.0
    $hayNat = [bool]@($modelo.Redes | Where-Object { $_.Tipo -eq 'nat' }).Count
    $yInternet = 0; $xInternet = 0
    if ($hayNat) {
        $xInternet = $W / 2 - 62; $yInternet = $y
        $y += 38 + 30
    }
    $barraNat = $null; $cableNat = 0
    $fase = 0
    foreach ($red in $modelo.Redes) {
        $acentuada = [bool]$red.Internet
        $color = $(if ($acentuada) { 'T_acento' } else { 'T_textoSuave' })
        # etiqueta de la red: nombre en negrita + subred + si tiene Internet
        $et = New-Object System.Windows.Controls.TextBlock
        $et.FontSize = 12
        $r1 = New-Object System.Windows.Documents.Run($red.Nombre); $r1.FontWeight = [System.Windows.FontWeights]::SemiBold
        $r1.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'T_texto')
        $r2 = New-Object System.Windows.Documents.Run((' · ' + $(if ($red.Subred) { $red.Subred + ' · ' } else { '' }) + $(if ($red.Internet) { 'con Internet' } else { 'aislada, sin Internet' })))
        $r2.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'T_textoSuave')
        [void]$et.Inlines.Add($r1); [void]$et.Inlines.Add($r2)
        Poner-Pos $et 24 $y
        [void]$canvas.Children.Add($et)
        $barY = $y + 24
        $barra = New-Object System.Windows.Controls.Border
        $barra.Width = $W - 48; $barra.Height = 6; $barra.CornerRadius = New-Object System.Windows.CornerRadius(3)
        Ref-Tema $barra ([System.Windows.Controls.Border]::BackgroundProperty) $color
        $barra.Tag = $red.Clave; $barra.Name = 'Red_' + ($red.Clave -replace '[^A-Za-z0-9_]', '_')
        Poner-Pos $barra 24 $barY
        [void]$canvas.Children.Add($barra)
        $script:mapaBarras[$red.Clave] = $barra
        if ($red.Tipo -eq 'nat' -and -not $barraNat) { $barraNat = $barY }
        # ¿hay alguna encendida en esta red? (los pulsos de la barra)
        $conEncendida = [bool]@($modelo.Maquinas | Where-Object { $_.Encendida -and ($_.Redes -contains $red.Clave) }).Count
        if ($conEncendida) {
            $fase++
            $viajes = @(@{ Sent = 1; Ini = 0 }, @{ Sent = -1; Ini = 1 })
            foreach ($v in $viajes) {
                $p = New-Object System.Windows.Shapes.Ellipse
                $p.Width = 6; $p.Height = 6; $p.Opacity = 0; $p.IsHitTestVisible = $false
                Ref-Tema $p ([System.Windows.Shapes.Shape]::FillProperty) 'T_brillo'
                $tr = New-Object System.Windows.Media.TranslateTransform(0, 0); $p.RenderTransform = $tr
                Poner-Pos $p $(if ($v.Sent -gt 0) { 24 } else { $W - 30 }) ($barY)
                [System.Windows.Controls.Panel]::SetZIndex($p, 4)
                [void]$canvas.Children.Add($p)
                $ciclo = $c.PulsoBarraMin + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0 * ($c.PulsoBarraMax - $c.PulsoBarraMin)
                [void]$script:mapaAnim.Add(@{ Obj = $p; Tr = $tr; Eje = 'X'; Desde = 0; Hasta = $(if ($v.Sent -gt 0) { $W - 54 } else { -($W - 54) }); Viaje = $c.PulsoBarraViaje; Ciclo = $ciclo; Desfase = ($fase * 0.7 + $v.Ini * 1.9); Barra = $true })
            }
            # destello: una estela corta que cruza la barra una vez cada ~9 s
            $e = New-Object System.Windows.Controls.Border
            $e.Width = 46; $e.Height = 4; $e.Opacity = 0; $e.IsHitTestVisible = $false; $e.CornerRadius = New-Object System.Windows.CornerRadius(2)
            Ref-Tema $e ([System.Windows.Controls.Border]::BackgroundProperty) 'T_brillo'
            $e.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect
            $e.Effect.BlurRadius = 8; $e.Effect.ShadowDepth = 0; $e.Effect.Opacity = 0.6
            $e.Effect.Color = [System.Windows.Media.Color]::FromRgb(120, 235, 221)
            $tr2 = New-Object System.Windows.Media.TranslateTransform(0, 0); $e.RenderTransform = $tr2
            Poner-Pos $e 24 ($barY + 1)
            [System.Windows.Controls.Panel]::SetZIndex($e, 4)
            [void]$canvas.Children.Add($e)
            [void]$script:mapaAnim.Add(@{ Obj = $e; Tr = $tr2; Eje = 'X'; Desde = 0; Hasta = ($W - 48 - 46); Viaje = $c.DestelloViaje; Ciclo = $c.DestelloCada; Desfase = (1.5 + $fase * 2.7); Barra = $true; Destello = $true })
        }
        # máquinas de esta red (el controlador y los del dominio primero)
        $ms = @($red.Primeras | Sort-Object @{ Expression = { if ($_.EsDc) { 0 } elseif ($_.EnDominio) { 1 } else { 2 } } }, Nombre)
        $arriba = $barY + 6 + $c.LargoCable + 8
        $fila = 0; $i = 0
        $cajas = @{}
        while ($i -lt $ms.Count) {
            $n = [Math]::Min($c.MaxPorFila, $ms.Count - $i)
            $total = $n * $c.AnchoTarjeta + ($n - 1) * $c.Separacion
            $x0 = ($W - $total) / 2
            $yFila = $arriba + $fila * ($c.AltoTarjeta + $c.LargoCable)
            for ($k = 0; $k -lt $n; $k++) {
                $m = $ms[$i + $k]
                $x = $x0 + $k * ($c.AnchoTarjeta + $c.Separacion)
                $cx = $x + $c.AnchoTarjeta / 2
                # cable de la barra a la tarjeta
                $cab = New-Object System.Windows.Shapes.Rectangle
                $cab.Width = 2; $cab.Height = $yFila - ($barY + 6); Ref-Tema $cab ([System.Windows.Shapes.Shape]::FillProperty) $color
                Poner-Pos $cab ($cx - 1) ($barY + 6)
                [System.Windows.Controls.Panel]::SetZIndex($cab, 1)
                [void]$canvas.Children.Add($cab)
                $tarj = Nueva-Tarjeta-Maquina $m (@($vmxElegida) -contains $m.Vmx) $c
                $tarj.Add_Click($alElegir)
                $tarj.Add_PreviewMouseRightButtonDown({ param($s, $a) if (Menu-MaquinaLab $s $false) { $a.Handled = $true } })
                $tarj.Add_PreviewMouseRightButtonUp({ param($s, $a) if (Menu-MaquinaLab $s $true) { $a.Handled = $true } })
                Poner-Pos $tarj $x $yFila
                [System.Windows.Controls.Panel]::SetZIndex($tarj, 3)
                [void]$canvas.Children.Add($tarj)
                $script:mapaCartas[$m.Vmx] = $tarj
                if ($m.Etiqueta -and $m.EsDc) { [void]$canvas.Children.Add((Pastilla-Mapa $m.Etiqueta ($x + 10) ($yFila - 9))) }
                if ($m.Encendida) {
                    Pulso-Cable $canvas $cx ($barY + 6) $yFila $(if (($k + $fila) % 2 -eq 0) { 1 } else { -1 }) (0.4 * ($i + $k))
                }
                # «también en…» si tiene más tarjetas
                if ($m.Redes.Count -gt 1) {
                    $otras = @($m.Redes | Select-Object -Skip 1 | ForEach-Object { $modelo.Todas[$_].Nombre })
                    $tt = Nuevo-Texto ('también en ' + ($otras -join ', ')) 10 'T_textoSuave'
                    $tt.MaxWidth = $c.AnchoTarjeta; $tt.TextTrimming = 'CharacterEllipsis'
                    Poner-Pos $tt $x ($yFila + $c.AltoTarjeta + 2)
                    [void]$canvas.Children.Add($tt)
                }
                if ($m.EnDominio) { $cajas[$m.Vmx] = @{ X = $x; Y = $yFila; Fila = $fila } }
            }
            $i += $n; $fila++
        }
        # zona del dominio: rectángulo punteado que rodea a los del dominio de esta red (si caben en una fila)
        if ($modelo.Dominio -and $cajas.Count -and @($cajas.Values | Where-Object { $_.Fila -ne 0 }).Count -eq 0) {
            $xs = @($cajas.Values | ForEach-Object { $_.X }); $y0 = @($cajas.Values | ForEach-Object { $_.Y })[0]
            $minX = ($xs | Measure-Object -Minimum).Minimum - 14; $maxX = ($xs | Measure-Object -Maximum).Maximum + $c.AnchoTarjeta + 14
            $zona = New-Object System.Windows.Shapes.Rectangle
            $zona.Width = $maxX - $minX; $zona.Height = $c.AltoTarjeta + 28; $zona.RadiusX = 16; $zona.RadiusY = 16
            $zona.StrokeThickness = 1.5; $zona.StrokeDashArray = [System.Windows.Media.DoubleCollection]::Parse('4,3')
            Ref-Tema $zona ([System.Windows.Shapes.Shape]::StrokeProperty) 'T_acento'
            Ref-Tema $zona ([System.Windows.Shapes.Shape]::FillProperty) 'T_campo'
            $zona.Opacity = 0.55; $zona.IsHitTestVisible = $false
            Poner-Pos $zona $minX ($y0 - 14)
            [System.Windows.Controls.Panel]::SetZIndex($zona, 2)
            [void]$canvas.Children.Add($zona)
            [void]$canvas.Children.Add((Pastilla-Mapa ('Dominio ' + $modelo.Dominio) ($minX + 12) ($y0 - 24)))
        }
        $filas = [Math]::Max(1, [Math]::Ceiling($ms.Count / [double]$c.MaxPorFila))
        $y = $arriba + ($filas - 1) * ($c.AltoTarjeta + $c.LargoCable) + $c.AltoTarjeta + 34
        if (-not $ms.Count) { $y = $barY + 40 }
    }
    # Internet: pastilla con borde de acento y cable hasta la barra NAT
    if ($hayNat -and $barraNat) {
        $inet = New-Object System.Windows.Controls.Border
        $inet.Width = 124; $inet.Height = 38; $inet.CornerRadius = New-Object System.Windows.CornerRadius(19); $inet.BorderThickness = New-Object System.Windows.Thickness(1.5)
        Ref-Tema $inet ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_acento'
        Ref-Tema $inet ([System.Windows.Controls.Border]::BackgroundProperty) 'T_superficie'
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.HorizontalAlignment = 'Center'; $sp.VerticalAlignment = 'Center'
        $gl = New-Object System.Windows.Controls.TextBlock
        $gl.Text = [string][char]0xE774; $gl.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets'); $gl.FontSize = 14; $gl.VerticalAlignment = 'Center'
        Ref-Tema $gl ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_acento'
        $tx = Nuevo-Texto 'Internet' 13 'T_acento' $true; $tx.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0); $tx.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($gl); [void]$sp.Children.Add($tx); $inet.Child = $sp
        Poner-Pos $inet $xInternet $yInternet
        [System.Windows.Controls.Panel]::SetZIndex($inet, 3)
        [void]$canvas.Children.Add($inet)
        $cab = New-Object System.Windows.Shapes.Rectangle
        $cab.Width = 2; $cab.Height = $barraNat - ($yInternet + 38); Ref-Tema $cab ([System.Windows.Shapes.Shape]::FillProperty) 'T_acento'
        Poner-Pos $cab ($W / 2 - 1) ($yInternet + 38)
        [void]$canvas.Children.Add($cab)
        if (@($modelo.Maquinas | Where-Object { $_.Encendida }).Count) {
            Pulso-Cable $canvas ($W / 2) ($yInternet + 38) $barraNat -1 0.9
        }
    }
    $canvas.Height = [Math]::Max(370, $y + 10)
    $canvas.Width = $W
}

function Marcar-CartaElegida($vmxElegida) {
    # Cambia el borde sin repintar el mapa entero
    foreach ($k in @($script:mapaCartas.Keys)) {
        $b = $script:mapaCartas[$k]
        $sel = (@($vmxElegida) -contains $k)
        Ref-Tema $b ([System.Windows.Controls.Control]::BorderBrushProperty) $(if ($sel) { 'T_acento' } else { 'T_borde' })
        $b.BorderThickness = New-Object System.Windows.Thickness($(if ($sel) { 2 } else { 1 }))
    }
}

# ---------------------------------------------------------------- animación (pulsos y destellos)
function Parar-AnimMapa {
    foreach ($a in @($script:mapaAnim)) {
        try {
            $prop = $(if ($a.Eje -eq 'Y') { [System.Windows.Media.TranslateTransform]::YProperty } else { [System.Windows.Media.TranslateTransform]::XProperty })
            $a.Tr.BeginAnimation($prop, $null)
            $a.Obj.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
            $a.Obj.Opacity = 0
        } catch {}
    }
    $script:mapaAnimando = $false
}

function Arrancar-AnimMapa {
    if ($script:mapaAnimando) { return }
    $c = $script:ConstMapa
    $lista = @($script:mapaAnim)
    # Tope: si hay demasiados puntos, solo barras y destellos (sin pulsos en los cables)
    if ($lista.Count -gt $c.MaxPuntos) { $lista = @($lista | Where-Object { $_.Barra }) }
    foreach ($a in $lista) {
        $t = [double]$a.Viaje; $ciclo = [double]$a.Ciclo
        $kfp = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $kfp.Duration = New-Object System.Windows.Duration([TimeSpan]::FromSeconds($ciclo))
        $kfp.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $kfp.BeginTime = [TimeSpan]::FromSeconds([double]$a.Desfase)
        foreach ($par in @(@(0.0, [double]$a.Desde), @($t, [double]$a.Hasta), @($ciclo, [double]$a.Hasta))) {
            [void]$kfp.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($par[1], [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($par[0])))))
        }
        $kfo = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $kfo.Duration = New-Object System.Windows.Duration([TimeSpan]::FromSeconds($ciclo))
        $kfo.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $kfo.BeginTime = $kfp.BeginTime
        $tope = $(if ($a.Destello) { 0.85 } else { 0.8 })
        foreach ($par in @(@(0.0, 0.0), @(($t * 0.15), $tope), @(($t * 0.85), $tope), @($t, 0.0), @($ciclo, 0.0))) {
            [void]$kfo.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($par[1], [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($par[0])))))
        }
        $prop = $(if ($a.Eje -eq 'Y') { [System.Windows.Media.TranslateTransform]::YProperty } else { [System.Windows.Media.TranslateTransform]::XProperty })
        $a.Tr.BeginAnimation($prop, $kfp)
        $a.Obj.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $kfo)
    }
    $script:mapaAnimando = $true
}

function Mapa-PuedeAnimar($hospedador) {
    # Solo con animaciones Normales, las de Windows activas, el mapa a la vista y la ventana en primer plano
    try {
        if ((Animaciones-Modo) -ne 'Normales') { return $false }
        if (-not [System.Windows.SystemParameters]::ClientAreaAnimation) { return $false }
        if (-not $hospedador.IsVisible) { return $false }
        if ($script:ventana.WindowState -eq 'Minimized' -or -not $script:ventana.IsActive) { return $false }
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------- tamaño del mapa
# Los mapas miden 780 de ancho: si el hueco es más estrecho se encogen (hasta el mínimo, para que se lea) y, si aun
# así no caben, sale la barra de desplazamiento. En un hueco grande se quedan en su tamaño.
$script:escalasCanvas = @{}
function Ajustar-EscalaCanvas($scroll, $canvas, [double]$minimo = 0.7) {
    $hueco = $scroll.ActualWidth
    if ($hueco -lt 50) { return }
    $esc = [Math]::Min(1.0, [Math]::Max($minimo, ($hueco - 6) / 780.0))
    $clave = [string]$canvas.Name
    $antes = 0.0
    if ($script:escalasCanvas.ContainsKey($clave)) { $antes = [double]$script:escalasCanvas[$clave] }
    if ([Math]::Abs($esc - $antes) -lt 0.005) { return }
    $script:escalasCanvas[$clave] = $esc
    $canvas.LayoutTransform = New-Object System.Windows.Media.ScaleTransform($esc, $esc)
}
