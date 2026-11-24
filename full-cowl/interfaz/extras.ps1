# =====================================================================
#  Interfaz nueva: selector de «Extras» (ficha 20)
#  Buscador, pastillas por categoría y una tarjeta pequeña con interruptor por cada extra.
#  Lo usan «Nueva máquina» (dentro de su tarjeta) y el laboratorio (en un cuadro aparte).
#  Solo enseña el catálogo de comun.ps1 (Catalogo-Extras): aquí no se escribe ningún nombre de paquete.
#  El estado de cada selector va en una tabla ($st) que cuelga del Tag de sus controles, así los eventos
#  la encuentran sin variables sueltas.
# =====================================================================

function Nuevo-SelectorExtras($contenedor, $alCambiar = $null) {
    # $contenedor: un StackPanel vacío. Devuelve la tabla de estado del selector.
    $rec = [System.Windows.Application]::Current
    $st = @{ Catalogo = @(); Marcados = (New-Object System.Collections.ArrayList); Bloqueados = @{}; Cat = ''; SinInternet = $false
             AlCambiar = $alCambiar; Interruptores = @{}; Pintando = $false }
    $contenedor.Children.Clear()

    $bus = New-Object System.Windows.Controls.TextBox
    $bus.Style = $rec.FindResource('Busqueda')
    $bus.MaxWidth = 320; $bus.HorizontalAlignment = 'Left'; $bus.MinWidth = 220
    $bus.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $bus.ToolTip = 'Buscar un extra por su nombre'
    $bus.Tag = $st
    $bus.Add_TextChanged({ param($s, $a) try { Pintar-SelectorExtras $s.Tag } catch { Escribir-Log ("Extras (buscar): " + $_.Exception.Message) } })
    [void]$contenedor.Children.Add($bus)

    $panelCats = New-Object System.Windows.Controls.WrapPanel
    $panelCats.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    [void]$contenedor.Children.Add($panelCats)

    $avisoRed = New-Object System.Windows.Controls.TextBlock
    $avisoRed.TextWrapping = 'Wrap'; $avisoRed.Visibility = 'Collapsed'
    $avisoRed.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    Ref-Tema $avisoRed ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_aviso'
    [void]$contenedor.Children.Add($avisoRed)

    $panelExtras = New-Object System.Windows.Controls.WrapPanel
    [void]$contenedor.Children.Add($panelExtras)

    $sinExtras = New-Object System.Windows.Controls.TextBlock
    $sinExtras.Style = $rec.FindResource('Nota'); $sinExtras.Visibility = 'Collapsed'
    $sinExtras.Text = 'Ningún extra coincide con lo que buscas.'
    [void]$contenedor.Children.Add($sinExtras)

    $pieExtrasTxt = New-Object System.Windows.Controls.TextBlock
    $pieExtrasTxt.Style = $rec.FindResource('Nota'); $pieExtrasTxt.TextWrapping = 'Wrap'
    $pieExtrasTxt.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    [void]$contenedor.Children.Add($pieExtrasTxt)

    $st.Buscar = $bus; $st.Chips = $panelCats; $st.Aviso = $avisoRed; $st.Lista = $panelExtras; $st.Vacio = $sinExtras; $st.Pie = $pieExtrasTxt
    $st.Grupo = 'ExtrasCat' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    return $st
}

function Cargar-SelectorExtras($st, $base, $marcados) {
    # Pone el catálogo de esa base y marca lo pedido (lo que no vale para la base se descarta).
    # Devuelve los identificadores que se han quitado por no ser compatibles.
    $st.Catalogo = @(Catalogo-Extras $base)
    $ids = @($st.Catalogo | ForEach-Object { $_.Id })
    $quitados = @(@($marcados) | Where-Object { $_ -and $ids -notcontains [string]$_ } | ForEach-Object { [string]$_ })
    $st.Marcados.Clear()
    foreach ($x in @($marcados)) { if ($x -and $ids -contains [string]$x -and -not $st.Marcados.Contains([string]$x)) { [void]$st.Marcados.Add([string]$x) } }
    $st.Cat = ''
    $st.Pintando = $true
    try { $st.Buscar.Text = '' } finally { $st.Pintando = $false }
    Pintar-SelectorExtras $st
    return $quitados
}

function Marcados-SelectorExtras($st) {
    # En el orden del catálogo. Los bloqueados («ya lo instala Active Directory») no cuentan: no hay que pedirlos.
    return @($st.Catalogo | Where-Object { $st.Marcados.Contains($_.Id) -and -not $st.Bloqueados.ContainsKey($_.Id) } | ForEach-Object { $_.Id })
}

function Bloquear-ExtrasSelector($st, [hashtable]$bloqueados) {
    # $bloqueados: id -> motivo. Salen marcados y sin poder tocarse.
    $antes = (@($st.Bloqueados.Keys | Sort-Object) -join ',')
    $st.Bloqueados = $(if ($bloqueados) { $bloqueados } else { @{} })
    if ($antes -ne (@($st.Bloqueados.Keys | Sort-Object) -join ',')) { Pintar-SelectorExtras $st }
}

function Poner-InternetSelector($st, [bool]$hayInternet) {
    # Sin Internet (red aislada o solo anfitrión) no se pueden marcar los que lo necesitan
    $sin = -not $hayInternet
    if ([bool]$st.SinInternet -eq $sin) { return }
    $st.SinInternet = $sin
    if ($sin) { foreach ($o in $st.Catalogo) { if ($o.Internet -and $st.Marcados.Contains($o.Id)) { $st.Marcados.Remove($o.Id) } } }
    Pintar-SelectorExtras $st
}

function Texto-ResumenExtras($catalogo, $ids) {
    # «3 extras · unos 4 min más al primer arranque»
    $sel = @($catalogo | Where-Object { @($ids) -contains $_.Id })
    if (-not $sel.Count) { return '' }
    $min = 0; foreach ($o in $sel) { $min += [int]$o.Min }
    return "$(Plural $sel.Count 'extra' 'extras') · unos $([Math]::Max(1, $min)) min más al primer arranque"
}

function Actualizar-PieSelector($st) {
    $ids = @(Marcados-SelectorExtras $st)
    $t = Texto-ResumenExtras $st.Catalogo $ids
    $st.Pie.Text = $(if ($t) { $t + '. Se instalan las versiones que traiga el sistema.' } else { 'Nada marcado: la máquina sale en limpio.' })
}

$script:alCatExtras = {
    param($s, $a)
    try { $d = $s.Tag; $d.St.Cat = [string]$d.Cat; Pintar-SelectorExtras $d.St -SoloLista } catch { Escribir-Log ("Extras (categoría): " + $_.Exception.Message) }
}
$script:alToggleExtra = {
    param($s, $a)
    try {
        $d = $s.Tag; $st = $d.St
        if ($st.Pintando) { return }
        if ($s.IsChecked) { if (-not $st.Marcados.Contains($d.Id)) { [void]$st.Marcados.Add($d.Id) } }
        else { $st.Marcados.Remove($d.Id) }
        Actualizar-PieSelector $st
        if ($st.AlCambiar) { & $st.AlCambiar }
    } catch { Escribir-Log ("Extras (marcar): " + $_.Exception.Message) }
}

function Pintar-SelectorExtras($st, [switch]$SoloLista) {
    if ($st.Pintando) { return }
    $st.Pintando = $true
    try {
        $rec = [System.Windows.Application]::Current
        $cats = @($CategoriasExtras | Where-Object { $c = $_; @($st.Catalogo | Where-Object { $_.Cat -eq $c }).Count })
        if ($st.Cat -and $cats -notcontains $st.Cat) { $st.Cat = '' }
        if (-not $SoloLista) {
            $st.Chips.Children.Clear()
            foreach ($c in @('') + $cats) {
                $rb = New-Object System.Windows.Controls.RadioButton
                $rb.Style = $rec.FindResource('Chip'); $rb.GroupName = $st.Grupo
                $rb.Content = $(if ($c) { $c } else { 'Todos' })
                $rb.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
                $rb.IsChecked = ($c -eq $st.Cat)
                $rb.Tag = @{ St = $st; Cat = $c }
                $rb.Add_Click($script:alCatExtras)
                [void]$st.Chips.Children.Add($rb)
            }
            $st.Chips.Visibility = $(if ($cats.Count -gt 1) { 'Visible' } else { 'Collapsed' })
        }
        $st.Aviso.Visibility = $(if ($st.SinInternet -and @($st.Catalogo | Where-Object { $_.Internet }).Count) { 'Visible' } else { 'Collapsed' })
        $st.Aviso.Text = 'Esta red no tiene Internet: los extras que lo necesitan salen apagados. Elige NAT o puente para poder marcarlos.'

        $buscado = ([string]$st.Buscar.Text).Trim().ToLower()
        $st.Lista.Children.Clear(); $st.Interruptores = @{}
        $n = 0
        foreach ($o in $st.Catalogo) {
            if ($st.Cat -and $o.Cat -ne $st.Cat) { continue }
            if ($buscado -and -not (("$($o.Nombre) $($o.Desc) $($o.Cat)").ToLower().Contains($buscado))) { continue }
            $n++
            $bloqueo = [string]$st.Bloqueados[$o.Id]
            $sinNet = [bool]($st.SinInternet -and $o.Internet)

            $bd = New-Object System.Windows.Controls.Border
            $bd.Width = 262; $bd.CornerRadius = New-Object System.Windows.CornerRadius(10)
            $bd.Padding = New-Object System.Windows.Thickness(12, 10, 10, 10)
            $bd.Margin = New-Object System.Windows.Thickness(0, 0, 10, 10)
            $bd.BorderThickness = New-Object System.Windows.Thickness(1)
            Ref-Tema $bd ([System.Windows.Controls.Border]::BackgroundProperty) 'T_campo'
            Ref-Tema $bd ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'
            $g = New-Object System.Windows.Controls.Grid
            $c0 = New-Object System.Windows.Controls.ColumnDefinition
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
            [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1)

            $sp = New-Object System.Windows.Controls.StackPanel
            $tn = New-Object System.Windows.Controls.TextBlock
            $tn.Text = [string]$o.Nombre; $tn.FontWeight = 'SemiBold'; $tn.TextTrimming = 'CharacterEllipsis'
            Ref-Tema $tn ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
            $td = New-Object System.Windows.Controls.TextBlock
            $td.Text = [string]$o.Desc; $td.TextWrapping = 'Wrap'; $td.FontSize = 12
            $td.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
            Ref-Tema $td ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
            $tm = New-Object System.Windows.Controls.TextBlock
            $tm.FontSize = 11.5; $tm.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0); $tm.TextWrapping = 'Wrap'
            $partes = @()
            if ([int]$o.Min -gt 0) { $partes += "≈ $($o.Min) min" }
            if ($bloqueo) { $partes = @($bloqueo) }
            elseif ($sinNet) { $partes += 'Necesita Internet: elige NAT o puente' }
            elseif ($o.Internet) { $partes += 'Necesita Internet' }
            $tm.Text = ($partes -join ' · ')
            Ref-Tema $tm ([System.Windows.Controls.TextBlock]::ForegroundProperty) $(if ($sinNet) { 'T_aviso' } else { 'T_textoSuave' })
            [void]$sp.Children.Add($tn); [void]$sp.Children.Add($td)
            if ($tm.Text) { [void]$sp.Children.Add($tm) }
            [void]$g.Children.Add($sp)

            $tg = New-Object System.Windows.Controls.Primitives.ToggleButton
            $tg.Style = $rec.FindResource('Interruptor')
            $tg.VerticalAlignment = 'Top'; $tg.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
            $tg.IsChecked = [bool]($bloqueo -or $st.Marcados.Contains($o.Id))
            $tg.IsEnabled = -not ($bloqueo -or $sinNet)
            $tg.ToolTip = $(if ($bloqueo) { $bloqueo } elseif ($sinNet) { 'Necesita Internet: elige NAT o puente' } else { [string]$o.Nombre })
            [System.Windows.Automation.AutomationProperties]::SetName($tg, [string]$o.Nombre)
            $tg.Tag = @{ St = $st; Id = [string]$o.Id }
            $tg.Add_Click($script:alToggleExtra)
            [System.Windows.Controls.Grid]::SetColumn($tg, 1)
            [void]$g.Children.Add($tg)
            if ($bloqueo -or $sinNet) { $sp.Opacity = 0.65 }
            $bd.Child = $g
            [void]$st.Lista.Children.Add($bd)
            $st.Interruptores[$o.Id] = $tg
        }
        $st.Vacio.Visibility = $(if ($n -eq 0 -and $st.Catalogo.Count) { 'Visible' } else { 'Collapsed' })
    } finally { $st.Pintando = $false }
    Actualizar-PieSelector $st
}

function Elegir-ExtrasDialogo($base, $marcados, [bool]$hayInternet = $true, [hashtable]$bloqueados = $null, [string]$subtitulo = '') {
    # Cuadro con el mismo selector (para el laboratorio). Devuelve la lista elegida o $null si se cancela.
    $cuerpo = @'
<StackPanel>
  <ScrollViewer MaxHeight="430" VerticalScrollBarVisibility="Auto" Margin="0,0,0,14">
    <StackPanel x:Name="ExtDlgPanel" Margin="0,0,6,0"/>
  </ScrollViewer>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
    <Button x:Name="BtnExtDlgNo" Style="{StaticResource BotonSecundario}" Content="Cancelar" Height="34" MinWidth="96" Margin="0,0,8,0" IsCancel="True"/>
    <Button x:Name="BtnExtDlgOk" Style="{StaticResource BotonPrimario}" Content="Aceptar" Height="34" MinWidth="96" IsDefault="True"/>
  </StackPanel>
</StackPanel>
'@
    $e = Nuevo-Dialogo $cuerpo 'Extras de la máquina' $subtitulo 620
    $st = Nuevo-SelectorExtras $e.ExtDlgPanel
    if ($bloqueados) { $st.Bloqueados = $bloqueados }
    $st.SinInternet = -not $hayInternet
    [void](Cargar-SelectorExtras $st $base $marcados)
    if (-not $hayInternet) { foreach ($o in $st.Catalogo) { if ($o.Internet -and $st.Marcados.Contains($o.Id)) { $st.Marcados.Remove($o.Id) } }; Pintar-SelectorExtras $st }
    $script:extrasDlgElegido = $null
    $e.BtnExtDlgOk.Tag = @{ St = $st; Ventana = $e.Ventana }
    $e.BtnExtDlgOk.Add_Click({ param($s, $a) $script:extrasDlgElegido = @{ Lista = @(Marcados-SelectorExtras $s.Tag.St) }; $s.Tag.Ventana.Close() })
    $e.BtnExtDlgNo.Add_Click({ param($s, $a) [System.Windows.Window]::GetWindow($s).Close() })
    [void]$e.Ventana.ShowDialog()
    if ($script:extrasDlgElegido) { return ,@($script:extrasDlgElegido.Lista) }
    return $null
}

# ---------------------------------------------------------------- cómo va cada extra (panel de la máquina)
function Lineas-EstadoExtras($datosMaq, $entradaProgreso) {
    # Devuelve @{ Texto; Fallos } con una línea por extra pedido: ✓ instalado, ✗ falló, … instalando.
    # $datosMaq.Extras = lo pedido al crear (marca del .vmx); $entradaProgreso.extras = lo que dice la máquina.
    $pedidos = @(([string]$datosMaq.Extras) -split ',' | Where-Object { $_ -cmatch '^[a-z0-9]{1,24}$' })
    if (-not $pedidos.Count) { return $null }
    $estado = @{}
    if ($entradaProgreso -and $entradaProgreso.extras) { foreach ($x in @(Leer-EstadoExtras ([string]$entradaProgreso.extras))) { $estado[$x.Id] = $x.Estado } }
    $lineas = @(); $fallos = 0; $hechos = 0; $activo = ''
    foreach ($id in $pedidos) {
        $nombre = Nombre-Extra $id
        switch ([string]$estado[$id]) {
            'ok'          { $lineas += "✓  $nombre"; $hechos++ }
            'fallo'       { $lineas += "✗  $nombre (falló)"; $fallos++ }
            'desconocido' { $lineas += "✗  $nombre (no disponible en este sistema)"; $fallos++ }
            'instalando'  { $lineas += "…  $nombre (instalando)"; $activo = $nombre }
            'espera'      { $lineas += "·  $nombre (en espera)" }
            default       { $lineas += "·  $nombre" }
        }
    }
    $cab = $(if ($activo) { "Extras: instalando $([Math]::Min($pedidos.Count, $hechos + $fallos + 1)) de $($pedidos.Count)…" }
             elseif ($estado.Count -and ($hechos + $fallos) -eq $pedidos.Count) { $(if ($fallos) { "Extras: $hechos bien, $fallos con problema" } else { 'Extras: todos instalados' }) }
             else { 'Extras pedidos' })
    return @{ Texto = ($cab + "`n" + ($lineas -join "`n")); Fallos = $fallos }
}
