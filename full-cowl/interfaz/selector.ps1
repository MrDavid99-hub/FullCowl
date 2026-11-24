# =====================================================================
#  Interfaz nueva: selector visual de sistemas (cuadrícula de tarjetas)
#  Sirve a «Crear base» y a «Nueva máquina». Se le da una lista de opciones y qué hacer al elegir:
#    Pintar-Selector $panel $opciones $claveElegida { param($clave) ... } 'NombreDelGrupo'
#  Cada opción: @{ Clave; Nombre; Sub; Grupo; Etiqueta; EtiquetaAviso; Fila }  (Fila = lo que necesita Pastilla-Sistema)
# =====================================================================
$script:pintandoSelector = $false
$script:alSelSistema = {
    param($s, $a)
    if ($script:pintandoSelector) { return }
    if ($s.IsChecked -and $s.Tag) { & $s.Tag ([string]$s.DataContext) }
}

function Fila-IconoSistema($sistema) {
    # Lo que necesita la pastilla (símbolo, logo o glifo y color) para un sistema del catálogo
    $fam = Familia-Sistema ([string]$sistema.Clave)
    $estilo = Estilo-Icono $fam
    $f = [pscustomobject]@{ IconoGlifo = $estilo[0]; IconoFondo = $estilo[1]; IconoLogo = $null; IconoSimbolo = $null }
    $falsa = [pscustomobject]@{ Familia = $fam; Nombre = [string]$sistema.Clave; Base = [string]$sistema.Clave; Vmx = ''; EsBase = $true }
    $sis = $null
    try { $sis = Sistema-DeMaquina $falsa } catch {}
    if ($sis) { Poner-Simbolo $f $sis }
    else {
        $logo = $null
        try { $logo = Logo-DeMaquina $falsa } catch {}
        if ($logo) { $f.IconoLogo = $logo; $f.IconoGlifo = '' }
    }
    return $f
}

function Partir-NombreSistema([string]$nombre) {
    # «Windows Server 2022 (escritorio)» -> nombre y línea suave; «Ubuntu 24.04 con escritorio» también
    if ($nombre -match '^(.*?)\s*\((.*)\)\s*$') { return @($Matches[1], $Matches[2]) }
    if ($nombre -match '^(.*?)\s+(con escritorio)$') { return @($Matches[1], $Matches[2]) }
    return @($nombre, '')
}

function Grupo-Sistema($sistema) {
    if ([string]$sistema.Clave -like 'Parrot*') { return 'Linux' }   # es manual, pero es un Linux (como Kali)
    switch ([string]$sistema.Tipo) { 'windows' { return 'Windows' } 'ubuntu' { return 'Linux' } 'kali' { return 'Linux' } 'debian' { return 'Linux' } 'rhel' { return 'Linux' } 'arch' { return 'Linux' } 'manual' { return 'Redes y otros' } default { return 'Redes y otros' } }
}

function Pintar-Selector($panel, $opciones, [string]$elegida, $alElegir, [string]$grupoRadio) {
    $script:pintandoSelector = $true
    try {
        $panel.Children.Clear()
        $recursos = [System.Windows.Application]::Current
        $grupos = [ordered]@{}
        foreach ($nombreG in @('Windows', 'Linux', 'Redes y otros')) { $grupos[$nombreG] = @($opciones | Where-Object { $_.Grupo -eq $nombreG }) }
        foreach ($nombreG in @($opciones | ForEach-Object { $_.Grupo } | Select-Object -Unique)) {
            if (-not $grupos.Contains($nombreG)) { $grupos[$nombreG] = @($opciones | Where-Object { $_.Grupo -eq $nombreG }) }
        }
        $primero = $true
        foreach ($nombreG in @($grupos.Keys)) {
            $lista = @($grupos[$nombreG])
            if (-not $lista.Count) { continue }
            $rot = New-Object System.Windows.Controls.TextBlock
            $rot.Text = $nombreG; $rot.FontSize = 12; $rot.FontWeight = [System.Windows.FontWeights]::SemiBold
            $rot.Margin = New-Object System.Windows.Thickness(0, $(if ($primero) { 0 } else { 6 }), 0, 8)
            Ref-Tema $rot ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
            [void]$panel.Children.Add($rot)
            $primero = $false
            $rej = New-Object System.Windows.Controls.Primitives.UniformGrid
            $rej.Columns = 3
            $rej.Margin = New-Object System.Windows.Thickness(0, 0, -10, 0)
            foreach ($op in $lista) {
                $rb = New-Object System.Windows.Controls.RadioButton
                $rb.Style = $recursos.FindResource('TarjetaSistema')
                $rb.GroupName = $grupoRadio
                $rb.DataContext = [string]$op.Clave
                $rb.Tag = $alElegir
                [System.Windows.Automation.AutomationProperties]::SetName($rb, ("{0}, {1}" -f $op.Nombre, $op.Sub).TrimEnd(' ', ','))
                $c = New-Object System.Windows.Controls.Grid
                $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(40)
                $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, 'Star')
                [void]$c.ColumnDefinitions.Add($c1); [void]$c.ColumnDefinitions.Add($c2)
                $pas = Pastilla-Sistema $op.Fila 40
                $pas.VerticalAlignment = 'Center'
                [void]$c.Children.Add($pas)
                $col = New-Object System.Windows.Controls.StackPanel
                $col.Margin = New-Object System.Windows.Thickness(11, 0, 0, 0); $col.VerticalAlignment = 'Center'
                $t1 = New-Object System.Windows.Controls.TextBlock
                $t1.Text = [string]$op.Nombre; $t1.FontSize = 13; $t1.FontWeight = [System.Windows.FontWeights]::SemiBold; $t1.TextTrimming = 'CharacterEllipsis'
                Ref-Tema $t1 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
                [void]$col.Children.Add($t1)
                foreach ($lineaSuave in @($op.Sub, $op.Sub2)) {
                    if (-not $lineaSuave) { continue }
                    $t2 = New-Object System.Windows.Controls.TextBlock
                    $t2.Text = [string]$lineaSuave; $t2.FontSize = 11.5; $t2.TextTrimming = 'CharacterEllipsis'; $t2.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
                    Ref-Tema $t2 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
                    [void]$col.Children.Add($t2)
                }
                [System.Windows.Controls.Grid]::SetColumn($col, 1); [void]$c.Children.Add($col)
                if ($op.Etiqueta) {
                    $et = New-Object System.Windows.Controls.Border
                    $et.CornerRadius = New-Object System.Windows.CornerRadius(8); $et.Padding = New-Object System.Windows.Thickness(7, 1, 7, 1)
                    $et.HorizontalAlignment = 'Right'; $et.VerticalAlignment = 'Top'; $et.Margin = New-Object System.Windows.Thickness(0, -13, -4, 0)
                    $colorTxt = $(if ($op.EtiquetaAviso) { 'T_aviso' } else { 'T_acentoClaro' })
                    Ref-Tema $et ([System.Windows.Controls.Border]::BackgroundProperty) 'T_neutro'
                    $tt = New-Object System.Windows.Controls.TextBlock
                    $tt.Text = [string]$op.Etiqueta; $tt.FontSize = 10.5; $tt.FontWeight = [System.Windows.FontWeights]::SemiBold
                    Ref-Tema $tt ([System.Windows.Controls.TextBlock]::ForegroundProperty) $colorTxt
                    $et.Child = $tt
                    [System.Windows.Controls.Grid]::SetColumnSpan($et, 2); [void]$c.Children.Add($et)
                }
                if ($op.Apagada) { $c.Opacity = 0.55 }   # (sin ISO: se puede elegir igualmente, pero se ve que falta)
                $rb.Content = $c
                $rb.IsChecked = ([string]$op.Clave -eq $elegida)
                $rb.Add_Checked($script:alSelSistema)
                [void]$rej.Children.Add($rb)
            }
            [void]$panel.Children.Add($rej)
        }
    } finally { $script:pintandoSelector = $false }
}
