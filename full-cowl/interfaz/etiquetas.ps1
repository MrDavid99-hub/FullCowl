# =====================================================================
#  Editor de etiquetas (ficha 18): las «pastillas» con ✕ y el campo para añadir.
#  Lo usan el panel de «Mis máquinas» y el paso «Nombre» de «Nueva máquina». Se carga después de base.ps1.
#  (Sin GetNewClosure: un cierre no ve las funciones del script. Cada editor es una tabla $est que viaja en el .Tag de sus
#  controles, así los eventos la encuentran sin variables sueltas.)
#
#  Uso:  $est = Nuevo-EditorEtiquetas
#        $est.AlCambiar = { param($est, $nuevas) ...; $true }   # opcional: $true = aceptado; con $false no se cambia nada
#        $est.Sugerir   = { @('web', 'sql') }                   # opcional: etiquetas ya usadas en otras máquinas
#        Etq-Poner $est @('web') @('Lab LAB1')                  # las suyas y las fijas (que no se pueden quitar)
#        Etq-Obtener $est                                       # las suyas
# =====================================================================
$xamlEditorEtq = @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Border x:Name="MarcoEtq" CornerRadius="9" Background="{DynamicResource T_superficie}" BorderBrush="{DynamicResource T_borde}" BorderThickness="1" Padding="5,3">
    <WrapPanel x:Name="PanelEtq" Orientation="Horizontal">
      <Grid x:Name="CajaCampoEtq" MinWidth="130" MinHeight="24" Margin="2">
        <TextBox x:Name="CampoEtq" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource T_texto}" CaretBrush="#39824D" SelectionBrush="#78EBDD" FontSize="12.5" VerticalContentAlignment="Center" Padding="3,2" MaxLength="60"/>
        <TextBlock x:Name="PhEtq" Text="Añadir etiqueta…" IsHitTestVisible="False" Foreground="{DynamicResource T_placeholder}" FontSize="12.5" VerticalAlignment="Center" Margin="6,0,0,0"/>
      </Grid>
    </WrapPanel>
  </Border>
  <TextBlock x:Name="AvisoEtq" Visibility="Collapsed" FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource T_peligro}" Margin="2,5,0,0"/>
  <WrapPanel x:Name="SugerEtq" Margin="0,7,0,0" Visibility="Collapsed"/>
</StackPanel>
'@

$xamlPastillaEtq = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="11" Background="{DynamicResource T_pista}" Margin="2" Padding="9,2,3,2">
  <StackPanel Orientation="Horizontal">
    <TextBlock x:Name="TxtPastilla" FontSize="12" FontWeight="Medium" Foreground="{DynamicResource T_acentoClaro}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="170"/>
    <Button x:Name="QuitarPastilla" Style="{StaticResource BotonQuitarEtq}" VerticalAlignment="Center"/>
  </StackPanel>
</Border>
'@

function Nuevo-EditorEtiquetas {
    $raizEtq = [Windows.Markup.XamlReader]::Parse($xamlEditorEtq)
    $est = @{
        Raiz = $raizEtq; E = (Elementos $raizEtq $xamlEditorEtq)
        Etiquetas = @(); Fijas = @(); Contexto = ''
        AlCambiar = $null; Sugerir = $null; Silencio = $false; Activo = $true
    }
    $campoEtq = $est.E.CampoEtq
    $campoEtq.Tag = $est
    [System.Windows.Automation.AutomationProperties]::SetName($campoEtq, 'Añadir etiqueta')
    $campoEtq.Add_TextChanged({ param($s, $a) Etq-AlEscribir $s.Tag })
    $campoEtq.Add_PreviewKeyDown({
        param($s, $a)
        if ($a.Key -eq [System.Windows.Input.Key]::Enter -or $a.Key -eq [System.Windows.Input.Key]::Return) {
            $a.Handled = $true
            [void](Etq-Anadir $s.Tag $s.Text)
        }
    })
    $campoEtq.Add_LostKeyboardFocus({ param($s, $a) if ($s.Text.Trim()) { [void](Etq-Anadir $s.Tag $s.Text) } })
    $campoEtq.Add_GotKeyboardFocus({ param($s, $a) $s.Tag.E.MarcoEtq.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'T_acento') })
    $campoEtq.Add_LostKeyboardFocus({ param($s, $a) $s.Tag.E.MarcoEtq.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'T_borde') })
    # Pinchar en el espacio libre del marco enfoca el campo
    $est.E.MarcoEtq.Tag = $est
    $est.E.MarcoEtq.Add_MouseLeftButtonDown({ param($s, $a) if ($s.Tag.Activo -and -not ($a.OriginalSource -is [System.Windows.Controls.TextBox])) { [void]$s.Tag.E.CampoEtq.Focus() } })
    Etq-Repintar $est
    return $est
}

function Etq-Poner($est, $etiquetas, $fijas = @(), [string]$contexto = '') {
    # Pone las etiquetas de una máquina (y las fijas, como «Lab LAB1»). $contexto: a qué máquina pertenecen (su .vmx)
    $est.Etiquetas = @(Normalizar-Etiquetas $etiquetas)
    $est.Fijas = @($fijas | Where-Object { $_ })
    $est.Contexto = $contexto
    $est.Silencio = $true
    try { $est.E.CampoEtq.Text = '' } finally { $est.Silencio = $false }
    $est.E.AvisoEtq.Visibility = 'Collapsed'
    Etq-Repintar $est
}

function Etq-Obtener($est) { return @($est.Etiquetas) }

function Etq-Habilitar($est, [bool]$si) {
    $est.Activo = $si
    $est.E.CampoEtq.IsEnabled = $si
    Etq-Repintar $est
}

function Etq-Pendiente($est) {
    # Lo escrito en el campo que aún no se ha convertido en etiqueta (por ejemplo al pulsar «Crear»): devuelve $false si no vale
    if (-not $est.E.CampoEtq.Text.Trim()) { return $true }
    return (Etq-Anadir $est $est.E.CampoEtq.Text)
}

function Nueva-PastillaEtq($est, [string]$textoPastilla, [bool]$fijaPastilla) {
    $pastilla = [Windows.Markup.XamlReader]::Parse($xamlPastillaEtq)
    $pastilla.FindName('TxtPastilla').Text = $textoPastilla
    $botonQuitar = $pastilla.FindName('QuitarPastilla')
    if ($fijaPastilla) {
        $botonQuitar.Visibility = 'Collapsed'
        $pastilla.Padding = New-Object System.Windows.Thickness(9, 2, 9, 2)
        $pastilla.ToolTip = 'Etiqueta automática del laboratorio: desaparece si se borra el laboratorio. No se puede quitar desde aquí.'
    } else {
        $botonQuitar.Tag = @{ Est = $est; Texto = $textoPastilla }
        $botonQuitar.ToolTip = 'Quitar'
        [System.Windows.Automation.AutomationProperties]::SetName($botonQuitar, "Quitar etiqueta $textoPastilla")
        $botonQuitar.IsEnabled = $est.Activo
        $botonQuitar.Add_Click({ param($s, $a) [void](Etq-Quitar $s.Tag.Est $s.Tag.Texto) })
    }
    return $pastilla
}

function Etq-Repintar($est) {
    $panelEtq = $est.E.PanelEtq
    $cajaCampo = $est.E.CajaCampoEtq
    # Se cambian solo las pastillas: el campo de escribir se queda donde está para no perder el foco
    for ($i = $panelEtq.Children.Count - 1; $i -ge 0; $i--) { if (-not [object]::ReferenceEquals($panelEtq.Children[$i], $cajaCampo)) { $panelEtq.Children.RemoveAt($i) } }
    $pos = 0
    foreach ($f in $est.Fijas) { $panelEtq.Children.Insert($pos, (Nueva-PastillaEtq $est ([string]$f) $true)); $pos++ }
    foreach ($t in $est.Etiquetas) { $panelEtq.Children.Insert($pos, (Nueva-PastillaEtq $est ([string]$t) $false)); $pos++ }
    if (-not $panelEtq.Children.Contains($cajaCampo)) { [void]$panelEtq.Children.Add($cajaCampo) }
    $est.E.PhEtq.Visibility = $(if ($est.E.CampoEtq.Text) { 'Collapsed' } else { 'Visible' })
    Etq-Sugerencias $est
}

function Etq-Sugerencias($est) {
    # Etiquetas que ya se usan en otras máquinas (las más usadas primero), filtradas por lo que se va escribiendo
    $cajaSuger = $est.E.SugerEtq
    $cajaSuger.Children.Clear()
    $usadas = @()
    if ($est.Activo -and $est.Sugerir -and $est.Etiquetas.Count -lt $script:EtqMaxPorMaquina) {
        try { $usadas = @(& $est.Sugerir) } catch { $usadas = @() }
    }
    $ya = @(@($est.Etiquetas) + @($est.Fijas) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $escrito = $est.E.CampoEtq.Text.Trim()
    $mostrar = @($usadas | Where-Object { $_ -and ($ya -notcontains ([string]$_).ToLowerInvariant()) -and (-not $escrito -or ([string]$_).StartsWith($escrito, [StringComparison]::OrdinalIgnoreCase)) } | Select-Object -First 6)
    if (-not $mostrar.Count) { $cajaSuger.Visibility = 'Collapsed'; return }
    $rotulo = New-Object System.Windows.Controls.TextBlock
    $rotulo.Text = 'Ya usadas:'; $rotulo.FontSize = 11.5; $rotulo.Margin = New-Object System.Windows.Thickness(2, 3, 6, 0)
    $rotulo.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_textoSuave')
    [void]$cajaSuger.Children.Add($rotulo)
    foreach ($sug in $mostrar) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = [System.Windows.Application]::Current.FindResource('BotonSugerirEtq')
        $b.Content = "+ $sug"
        $b.Tag = @{ Est = $est; Texto = [string]$sug }
        [System.Windows.Automation.AutomationProperties]::SetName($b, "Añadir etiqueta $sug")
        $b.Add_Click({ param($s, $a) [void](Etq-Anadir $s.Tag.Est $s.Tag.Texto) })
        [void]$cajaSuger.Children.Add($b)
    }
    $cajaSuger.Visibility = 'Visible'
}

function Etq-AlEscribir($est) {
    if ($est.Silencio) { return }
    $texto = $est.E.CampoEtq.Text
    $est.E.PhEtq.Visibility = $(if ($texto) { 'Collapsed' } else { 'Visible' })
    if ($texto.Contains(',')) { [void](Etq-Anadir $est $texto); return }   # la coma añade lo escrito
    $est.E.AvisoEtq.Visibility = 'Collapsed'
    Etq-Sugerencias $est
}

function Etq-Anadir($est, [string]$texto) {
    # Añade lo escrito (puede traer varias separadas por comas). Devuelve $true si todo ha ido bien.
    # Si algo no vale (demasiado larga, demasiadas) se avisa y se deja lo escrito en el campo; si no se pudo guardar, igual
    if (-not $est.Activo) { return $false }
    $aviso = ''
    $nuevas = @($est.Etiquetas)
    $conocidas = @(@($est.Fijas) + @($est.Etiquetas) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $restoSinAnadir = @()
    foreach ($parte in ($texto -split ',')) {
        $t = Limpiar-Etiqueta $parte
        if (-not $t) { continue }
        if ($aviso) { $restoSinAnadir += $parte; continue }
        if ($t.Length -gt $script:EtqMaxLetras) { $aviso = "«$t» tiene $($t.Length) letras: el máximo son $($script:EtqMaxLetras). Acórtala."; $restoSinAnadir += $parte; continue }
        if ($conocidas -contains $t.ToLowerInvariant()) { continue }   # ya la tenía: no se repite
        if ($nuevas.Count -ge $script:EtqMaxPorMaquina) { $aviso = "Como mucho $($script:EtqMaxPorMaquina) etiquetas por máquina."; $restoSinAnadir += $parte; continue }
        $nuevas += $t
        $conocidas += $t.ToLowerInvariant()
    }
    $cambiaron = ($nuevas.Count -ne $est.Etiquetas.Count)
    if ($cambiaron -and $est.AlCambiar) {
        $aceptado = $false
        try { $aceptado = [bool](& $est.AlCambiar $est $nuevas) } catch { $aceptado = $false }
        if (-not $aceptado) { return $false }   # el texto escrito se queda en el campo
    }
    $est.Etiquetas = $nuevas
    $est.Silencio = $true
    try { $est.E.CampoEtq.Text = ($restoSinAnadir -join ',') } finally { $est.Silencio = $false }
    if ($aviso) { $est.E.AvisoEtq.Text = $aviso; $est.E.AvisoEtq.Visibility = 'Visible' } else { $est.E.AvisoEtq.Visibility = 'Collapsed' }
    Etq-Repintar $est
    return (-not $aviso)
}

function Etq-Quitar($est, [string]$texto) {
    if (-not $est.Activo) { return $false }
    $nuevas = @($est.Etiquetas | Where-Object { $_ -ne $texto })
    if ($est.AlCambiar) {
        $aceptado = $false
        try { $aceptado = [bool](& $est.AlCambiar $est $nuevas) } catch { $aceptado = $false }
        if (-not $aceptado) { return $false }
    }
    $est.Etiquetas = $nuevas
    Etq-Repintar $est
    return $true
}
