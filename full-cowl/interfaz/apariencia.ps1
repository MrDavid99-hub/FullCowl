# =====================================================================
#  Interfaz nueva: página «Apariencia» (Ajustes del menú)
#  Tema, modo sobrio, color de acento, vista y tamaño de Mis máquinas, tamaño de letra y animaciones. Todo se aplica
#  al momento, sin reiniciar, y se guarda en config.local.json (Tema, Sobrio, Acento, Vista, Tamano, Letra,
#  Animaciones, RayosInicio, AnimacionInicio, ColorTotal). A la derecha, una vista previa de Mis máquinas con la vista y el tamaño.
# =====================================================================
$script:cargandoAp = $false

function Ref-Color($elemento, $propiedad, [string]$clave) { $elemento.SetResourceReference($propiedad, $clave) }

function Aplicar-Letra {
    # Letra «Grande»: el contenido de las pantallas se amplía un 15 % (también iconos y logos, que van dentro)
    if ([string]$Config.Letra -eq 'Grande') { $Contenido.LayoutTransform = New-Object System.Windows.Media.ScaleTransform(1.15, 1.15) }
    else { $Contenido.LayoutTransform = [System.Windows.Media.Transform]::Identity }
}

# ---------------------------------------------------------------- muestras de acento
$script:muestrasAp = @{}
foreach ($na in @($script:Acentos.Keys)) {
    $rb = New-Object System.Windows.Controls.RadioButton
    $rb.Style = [System.Windows.Application]::Current.FindResource('Muestra')
    $rb.GroupName = 'ApAcento'; $rb.Tag = $na; $rb.ToolTip = $script:NombresAcento[$na]
    $rb.Add_Click({ param($s, $e) if (-not $script:cargandoAp) { Guardar-Apariencia @{ Acento = [string]$s.Tag } $true } })
    [void]$ApMuestras.Children.Add($rb)
    $script:muestrasAp[$na] = $rb
}

function Color-Muestra([string]$na) {
    $i = $(if ($script:temaActual -eq 'oscuro') { 1 } else { 0 })
    return $script:Acentos[$na][$i][0]
}

# ---------------------------------------------------------------- estado de los mandos según Config
function Leer-Apariencia {
    $script:cargandoAp = $true
    try {
        $sob = [bool]$Config.Sobrio
        $tm = [string]$Config.Tema
        $ApTemaClaro.IsChecked = ($tm -ne 'Oscuro' -and $tm -ne 'Automatico')
        $ApTemaOscuro.IsChecked = ($tm -eq 'Oscuro'); $ApTemaAuto.IsChecked = ($tm -eq 'Automatico')
        $ApSobrio.IsChecked = $sob
        $ac = [string]$Config.Acento; if (-not $script:Acentos.Contains($ac)) { $ac = 'FullCowl' }
        foreach ($na in $script:muestrasAp.Keys) {
            $rb = $script:muestrasAp[$na]
            $rb.Background = Pincel-Fijo $(if ($sob) { '#5F6A72' } else { Color-Muestra $na })
            $rb.IsChecked = ($na -eq $ac) -and -not $sob
            $rb.IsEnabled = -not $sob
        }
        $ApAcentoNombre.Text = $(if ($sob) { 'Gris (modo sobrio)' } else { $script:NombresAcento[$ac] })
        $total = ($Config.ColorTotal -ne $false)
        $ApColorTotal.IsChecked = $total; $ApColorAcento.IsChecked = -not $total
        $ApColorTotal.IsEnabled = -not $sob; $ApColorAcento.IsEnabled = -not $sob
        $ApAcentoNota.Text = $(if ($sob) { 'En modo sobrio todo es gris y no se puede cambiar el color.' } elseif ($total) { 'Cambia el fondo, el menú y las tarjetas según el color. Los rayos y los símbolos de los sistemas no cambian.' } else { 'Solo cambia el botón principal, el progreso, los iconos activos y los enlaces. El fondo y el menú siguen verdes.' })
        $ApVistaLista.IsChecked = ([string]$Config.Vista -eq 'Lista'); $ApVistaTarjetas.IsChecked = -not $ApVistaLista.IsChecked
        $tam = [string]$Config.Tamano
        $ApTamCompacto.IsChecked = ($tam -eq 'Compacto'); $ApTamGrande.IsChecked = ($tam -eq 'Grande')
        $ApTamNormal.IsChecked = ($tam -ne 'Compacto' -and $tam -ne 'Grande')
        $ApLetraGrande.IsChecked = ([string]$Config.Letra -eq 'Grande'); $ApLetraNormal.IsChecked = -not $ApLetraGrande.IsChecked
        $modo = Animaciones-Modo
        $ApAnimNormales.IsChecked = ($modo -eq 'Normales'); $ApAnimReducidas.IsChecked = ($modo -eq 'Reducidas'); $ApAnimNinguna.IsChecked = ($modo -eq 'Ninguna')
        $ApAnimNormales.IsEnabled = -not $sob
        $ApAnimNota.Text = $(if ($sob) { 'En modo sobrio solo hay fundidos suaves (como Reducidas); Ninguna los quita.' } else { 'Normales: todo. Reducidas: solo fundidos, sin movimiento, rayos ni brillos. Ninguna: nada se mueve.' })
        $ApRayos.IsChecked = ($Config.RayosInicio -ne $false); $ApRayos.IsEnabled = ($modo -eq 'Normales')
        $ApAnimAbrir.IsChecked = ($Config.AnimacionInicio -ne $false); $ApAnimAbrir.IsEnabled = ($modo -ne 'Ninguna')
    } finally { $script:cargandoAp = $false }
}

function Guardar-Apariencia([hashtable]$valores, [bool]$recargarLista = $false) {
    try { Guardar-ConfigLocal $valores } catch { Escribir-Log ("Apariencia: " + $_.Exception.Message) }
    Aplicar-Apariencia $recargarLista
}

function Aplicar-Apariencia([bool]$recargarLista = $false) {
    Aplicar-Tema (Tema-Efectivo); Poner-BordeVentana; Rayos-Permitir
    Aplicar-Letra
    Aplicar-VistaMaquinas
    Leer-Apariencia
    Pintar-VistaPrevia
    if ($recargarLista -and $script:cargado) { try { Cargar -Silencioso } catch {} }
    # Las tarjetas de sistemas de «Crear base» y «Nueva máquina» se pintan una vez: al cambiar modo sobrio o acento
    # hay que repintarlas (si no, se quedan con los colores de antes)
    foreach ($fn in 'Pintar-SelectorBase', 'Pintar-SelectorNueva') {
        if (Get-Command $fn -ErrorAction SilentlyContinue) { try { if ($fn -eq 'Pintar-SelectorNueva') { & $fn -Forzar } else { & $fn } } catch { Escribir-Log ("Repintar $fn tras cambiar la apariencia: " + $_.Exception.Message) } }
    }
}

# ---------------------------------------------------------------- vista previa
function Tx([string]$texto, [double]$tam, [string]$clave, [bool]$negrita = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $texto; $t.FontSize = $tam; $t.TextTrimming = 'CharacterEllipsis'; $t.VerticalAlignment = 'Center'
    Ref-Color $t ([System.Windows.Controls.TextBlock]::ForegroundProperty) $clave
    if ($negrita) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    return $t
}
function Circulo-Previa([string]$inicial, [string]$hex, [double]$lado) {
    $c = New-Object System.Windows.Controls.Border
    $c.Width = $lado; $c.Height = $lado; $c.CornerRadius = New-Object System.Windows.CornerRadius($lado / 2)
    $c.Background = Pincel-Fijo $(if ([bool]$Config.Sobrio) { '#5F6A72' } else { $hex })
    $l = New-Object System.Windows.Controls.TextBlock
    $l.Text = $inicial; $l.Foreground = [System.Windows.Media.Brushes]::White; $l.FontWeight = [System.Windows.FontWeights]::Bold
    $l.FontSize = [Math]::Max(11, $lado * 0.4); $l.HorizontalAlignment = 'Center'; $l.VerticalAlignment = 'Center'
    $c.Child = $l
    return $c
}
function Punto-Estado([bool]$enc) {
    $p = New-Object System.Windows.Shapes.Ellipse
    $p.Width = 8; $p.Height = 8; $p.VerticalAlignment = 'Center'
    Ref-Color $p ([System.Windows.Shapes.Shape]::FillProperty) $(if ($enc) { 'T_encendida' } else { 'T_bordeFuerte' })
    return $p
}
function Boton-Previa([string]$texto, [bool]$principal) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius(8); $b.Height = 28; $b.Padding = New-Object System.Windows.Thickness(10, 0, 10, 0)
    if ($principal) { Ref-Color $b ([System.Windows.Controls.Border]::BackgroundProperty) 'T_acento' }
    else { Ref-Color $b ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'; $b.BorderThickness = New-Object System.Windows.Thickness(1) }
    $t = Tx $texto 12 $(if ($principal) { 'T_sobreAcento' } else { 'T_texto' }) $true
    $t.HorizontalAlignment = 'Center'
    $b.Child = $t
    return $b
}

function Pintar-VistaPrevia {
    $demo = @(
        @{ N = 'Kali-Lab01';   I = 'K'; S = 'Kali Linux';         R = 'NAT';        M = '4 GB'; E = $true;  C = '#2A9D8F' }
        @{ N = 'Win11-Clase';  I = 'W'; S = 'Windows 11 Pro';     R = 'Puente';     M = '8 GB'; E = $true;  C = '#39824D' }
        @{ N = 'Ubuntu-Web';   I = 'U'; S = 'Ubuntu Server 24.04'; R = 'NAT';       M = '2 GB'; E = $false; C = '#9C9C54' }
        @{ N = 'SRV-Dominio';  I = 'S'; S = 'Windows Server 2022'; R = 'Red interna'; M = '4 GB'; E = $false; C = '#1F5F7A' }
        @{ N = 'Debian-Base';  I = 'D'; S = 'Debian 12';          R = 'NAT';        M = '2 GB'; E = $false; C = '#A0284A' }
        @{ N = 'Parrot-Audit'; I = 'P'; S = 'Parrot Security';    R = 'Host-only';  M = '4 GB'; E = $true;  C = '#2A9D8F' }
    )
    $vista = $(if ([string]$Config.Vista -eq 'Lista') { 'Lista' } else { 'Tarjetas' })
    $tam = $(if (@('Compacto', 'Normal', 'Grande') -contains [string]$Config.Tamano) { [string]$Config.Tamano } else { 'Normal' })
    $ApPrevia.Child = $null
    if ($vista -eq 'Tarjetas') {
        $m = $script:MedidasMaq.Tarjetas[$tam]
        $cols = @{ Compacto = 3; Normal = 2; Grande = 1 }[$tam]
        $rej = New-Object System.Windows.Controls.Primitives.UniformGrid; $rej.Columns = $cols
        $negSep = -1 * [double]$m.Sep
        $rej.Margin = New-Object System.Windows.Thickness(0, 0, $negSep, 0)
        foreach ($d in $demo) {
            $caja = New-Object System.Windows.Controls.Border
            $caja.CornerRadius = New-Object System.Windows.CornerRadius(11); $caja.BorderThickness = New-Object System.Windows.Thickness(1)
            Ref-Color $caja ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'
            Ref-Color $caja ([System.Windows.Controls.Border]::BackgroundProperty) 'T_neutro'
            $caja.Padding = New-Object System.Windows.Thickness($m.Pad); $caja.Margin = New-Object System.Windows.Thickness(0, 0, $m.Sep, $m.Sep)
            $pila = New-Object System.Windows.Controls.StackPanel
            $fila = New-Object System.Windows.Controls.StackPanel; $fila.Orientation = 'Horizontal'
            $fila.Children.Add((Circulo-Previa $d.I $d.C $m.Circ)) | Out-Null
            $txt = New-Object System.Windows.Controls.StackPanel; $txt.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0); $txt.VerticalAlignment = 'Center'
            $txt.Children.Add((Tx $d.N 13 'T_texto' $true)) | Out-Null
            if ($m.Detalle) { $txt.Children.Add((Tx $d.S 11.5 'T_textoSuave')) | Out-Null }
            else {
                $es = New-Object System.Windows.Controls.StackPanel; $es.Orientation = 'Horizontal'; $es.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
                $es.Children.Add((Punto-Estado $d.E)) | Out-Null
                $te = Tx $(if ($d.E) { 'Encendida' } else { 'Apagada' }) 11.5 'T_textoSuave'; $te.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
                $es.Children.Add($te) | Out-Null
                $txt.Children.Add($es) | Out-Null
            }
            $fila.Children.Add($txt) | Out-Null
            $pila.Children.Add($fila) | Out-Null
            if ($m.Detalle) {
                $es = New-Object System.Windows.Controls.StackPanel; $es.Orientation = 'Horizontal'; $es.Margin = New-Object System.Windows.Thickness(0, 9, 0, 0)
                $es.Children.Add((Punto-Estado $d.E)) | Out-Null
                $te = Tx "$(if ($d.E) { 'Encendida' } else { 'Apagada' })  ·  $($d.R)  ·  $($d.M)" 11.5 'T_textoSuave'; $te.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
                $es.Children.Add($te) | Out-Null
                $pila.Children.Add($es) | Out-Null
            }
            if ($m.Botones) {
                $bots = New-Object System.Windows.Controls.UniformGrid; $bots.Rows = 1; $bots.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
                $b1 = Boton-Previa $(if ($d.E) { 'Apagar' } else { 'Encender' }) (-not $d.E); $b1.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
                $b2 = Boton-Previa 'Abrir' $false; $b2.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
                $bots.Children.Add($b1) | Out-Null; $bots.Children.Add($b2) | Out-Null
                $pila.Children.Add($bots) | Out-Null
            }
            $caja.Child = $pila
            $rej.Children.Add($caja) | Out-Null
        }
        $ApPrevia.Child = $rej
    } else {
        $m = $script:MedidasMaq.Lista[$tam]
        $filasPrevia = New-Object System.Windows.Controls.StackPanel
        $columnas = {
            param($g)
            $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(1, 'Star'); $c0.MinWidth = 130; $g.ColumnDefinitions.Add($c0)
            foreach ($w in @(120, 80, 100, 56)) { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = New-Object System.Windows.GridLength($w); $g.ColumnDefinitions.Add($c) }
        }
        $cab = New-Object System.Windows.Controls.Grid; $cab.Margin = New-Object System.Windows.Thickness(12, 0, 12, 6)
        & $columnas $cab
        $col = 0
        foreach ($h in @('NOMBRE', 'SISTEMA', 'RED', 'ESTADO', 'RAM')) {
            $t = Tx $h 10.5 'T_textoSuave' $true
            [System.Windows.Controls.Grid]::SetColumn($t, $col); $cab.Children.Add($t) | Out-Null; $col++
        }
        $filasPrevia.Children.Add($cab) | Out-Null
        foreach ($d in $demo) {
            $caja = New-Object System.Windows.Controls.Border
            $caja.CornerRadius = New-Object System.Windows.CornerRadius(10); $caja.BorderThickness = New-Object System.Windows.Thickness(1)
            Ref-Color $caja ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'
            Ref-Color $caja ([System.Windows.Controls.Border]::BackgroundProperty) 'T_neutro'
            $caja.Height = [Math]::Round($m.Alto * 0.78); $caja.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)
            $caja.Padding = New-Object System.Windows.Thickness(12, 0, 12, 0)
            $g = New-Object System.Windows.Controls.Grid
            & $columnas $g
            $nom = New-Object System.Windows.Controls.StackPanel; $nom.Orientation = 'Horizontal'; $nom.VerticalAlignment = 'Center'
            $nom.Children.Add((Circulo-Previa $d.I $d.C ([Math]::Round($m.Circ * 0.85)))) | Out-Null
            $tn = Tx $d.N 12.5 'T_texto' $true; $tn.Margin = New-Object System.Windows.Thickness(9, 0, 0, 0); $nom.Children.Add($tn) | Out-Null
            $es = New-Object System.Windows.Controls.StackPanel; $es.Orientation = 'Horizontal'; $es.VerticalAlignment = 'Center'
            $es.Children.Add((Punto-Estado $d.E)) | Out-Null
            $te = Tx $(if ($d.E) { 'Encendida' } else { 'Apagada' }) 11.5 'T_textoSuave'; $te.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0); $es.Children.Add($te) | Out-Null
            $celdas = @($nom, (Tx $d.S 11.5 'T_textoSuave'), (Tx $d.R 11.5 'T_textoSuave'), $es, (Tx $d.M 11.5 'T_textoSuave'))
            for ($k = 0; $k -lt $celdas.Count; $k++) { [System.Windows.Controls.Grid]::SetColumn($celdas[$k], $k); $g.Children.Add($celdas[$k]) | Out-Null }
            $caja.Child = $g
            $filasPrevia.Children.Add($caja) | Out-Null
        }
        $ApPrevia.Child = $filasPrevia
    }
}

# ---------------------------------------------------------------- mandos
$ApTemaClaro.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Tema = 'Claro' } $true } })
$ApTemaOscuro.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Tema = 'Oscuro' } $true } })
$ApTemaAuto.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Tema = 'Automatico' } $true } })
$ApSobrio.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Sobrio = [bool]$ApSobrio.IsChecked } $true } })
$ApColorTotal.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ ColorTotal = $true } $true } })
$ApColorAcento.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ ColorTotal = $false } $true } })
$ApVistaTarjetas.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Vista = 'Tarjetas' } } })
$ApVistaLista.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Vista = 'Lista' } } })
$ApTamCompacto.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Tamano = 'Compacto' } } })
$ApTamNormal.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Tamano = 'Normal' } } })
$ApTamGrande.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Tamano = 'Grande' } } })
$ApLetraNormal.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Letra = 'Normal' } } })
$ApLetraGrande.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Letra = 'Grande' } } })
$ApAnimNormales.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Animaciones = 'Normales' } } })
$ApAnimReducidas.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Animaciones = 'Reducidas' } } })
$ApAnimNinguna.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ Animaciones = 'Ninguna' } } })
$ApRayos.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ RayosInicio = [bool]$ApRayos.IsChecked } } })
$ApAnimAbrir.Add_Click({ if (-not $script:cargandoAp) { Guardar-Apariencia @{ AnimacionInicio = [bool]$ApAnimAbrir.IsChecked } } })

Leer-Apariencia
Aplicar-Letra
