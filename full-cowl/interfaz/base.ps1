# =====================================================================
#  Interfaz nueva (WPF): utilidades comunes
#  Lo carga ventana-nueva.ps1. Aquí no se usa $PSScriptRoot: las carpetas
#  vienen en $dirFc (full-cowl) y $dirInterfaz (full-cowl\interfaz).
# =====================================================================

$archivoLogInterfaz = Join-Path $dirFc 'estado\interfaz.log'
function Escribir-Log($texto) {
    try {
        $dirLog = Split-Path $archivoLogInterfaz
        if (-not (Test-Path $dirLog)) { [void](New-Item -ItemType Directory -Path $dirLog) }
        Add-Content -LiteralPath $archivoLogInterfaz -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}" -f (Get-Date), $texto) -Encoding UTF8
    } catch {}
}

# ---------------------------------------------------------------- estilos y XAML
function Iniciar-Aplicacion {
    # Un objeto Application para que los estilos (estilos.xaml) sirvan en todas las ventanas
    $app = [System.Windows.Application]::Current
    if (-not $app) { $app = New-Object System.Windows.Application }
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    $dic = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $dirInterfaz 'estilos.xaml'), [Text.Encoding]::UTF8))
    $app.Resources.MergedDictionaries.Add($dic)
    # Logotipos (trazados vectoriales)
    $app.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $dirInterfaz 'logos.xaml'), [Text.Encoding]::UTF8)))
    # Iconos de línea (trazados vectoriales; se pintan con el estilo «Icono»)
    $app.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $dirInterfaz 'iconos.xaml'), [Text.Encoding]::UTF8)))
    # Letra Inter (va en recursos\fuentes, licencia OFL); si faltara, Segoe UI
    $dirFuentes = Join-Path $dirFc 'recursos\fuentes'
    if (Test-Path (Join-Path $dirFuentes 'Inter-Regular.ttf')) {
        $script:fuenteApp = New-Object System.Windows.Media.FontFamily((New-Object System.Uri(($dirFuentes.TrimEnd('\') + '\'))), './#Inter, Segoe UI')
    } else {
        $script:fuenteApp = New-Object System.Windows.Media.FontFamily('Segoe UI')
    }
    return $app
}

function Leer-Xaml($nombre) { return [IO.File]::ReadAllText((Join-Path $dirInterfaz $nombre), [Text.Encoding]::UTF8) }

function Elementos($nodo, [string]$xaml) {
    # Tabla nombre -> elemento de todo lo que tenga x:Name (lo de dentro de plantillas no se encuentra y se ignora)
    $t = @{}
    foreach ($n in @([regex]::Matches($xaml, 'x:Name="(\w+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) {
        $el = $nodo.FindName($n)
        if ($null -ne $el) { $t[$n] = $el }
    }
    return $t
}

function Publicar-Elementos([hashtable]$tabla) {
    # Cada elemento pasa a ser una variable ($Lista, $Buscar...) para usarlo en los eventos
    foreach ($k in $tabla.Keys) { Set-Variable -Name $k -Value $tabla[$k] -Scope Script }
}

# ---------------------------------------------------------------- utilidades
function Animar($obj, $prop, [double]$hasta, [double]$ms, $desde = $null, [double]$retraso = 0) {
    # Con las animaciones en «Ninguna» (o modo sobrio) el cambio es instantáneo
    if ($script:sinAnimaciones) { $obj.BeginAnimation($prop, $null); $obj.SetValue($prop, $hasta); return }
    $an = New-Object System.Windows.Media.Animation.DoubleAnimation
    $an.To = $hasta
    if ($null -ne $desde) { $an.From = [double]$desde }
    $an.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($ms))
    $an.BeginTime = [TimeSpan]::FromMilliseconds($retraso)
    $suave = New-Object System.Windows.Media.Animation.CubicEase
    $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $an.EasingFunction = $suave
    $obj.BeginAnimation($prop, $an)
}
$propOpacidad = [System.Windows.UIElement]::OpacityProperty
$propX = [System.Windows.Media.TranslateTransform]::XProperty
$propY = [System.Windows.Media.TranslateTransform]::YProperty
$propEscalaX = [System.Windows.Media.ScaleTransform]::ScaleXProperty
$propEscalaY = [System.Windows.Media.ScaleTransform]::ScaleYProperty

function Nuevo-Icono([string]$nombre, [double]$tam = 18, [string]$color = '#14231A') {
    # Icono de línea (iconos.xaml) del tamaño y color pedidos: Nuevo-Icono 'Aviso' 18 '#8A6D1F'
    $ic = New-Object System.Windows.Controls.ContentControl
    $ic.Style = [System.Windows.Application]::Current.FindResource('Icono')
    $ic.Width = $tam; $ic.Height = $tam
    $ic.Foreground = Pincel $color
    Poner-Icono $ic $nombre
    return $ic
}
function Poner-Icono($control, [string]$nombre) {
    # Cambia el dibujo de un icono ya creado
    $control.Content = [System.Windows.Application]::Current.FindResource("Ico_$nombre")
}
function Pincel($hex) {
    # Pincel del color pedido, traducido al tema actual (tema.ps1)
    return New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString((Hex-Tema $hex)))
}
function Pincel-Fijo($hex) {
    # Pincel que no cambia con el tema (por ejemplo, el fondo de los iconos de sistema)
    return New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}
function Glifo([int]$codigo) { return [string][char]$codigo }
function Numero($texto, [int]$defecto = -1) { $v = 0; if ([int]::TryParse(([string]$texto).Trim(), [ref]$v)) { return $v } return $defecto }
function Plural([int]$n, $uno, $varios) { if ($n -eq 1) { return "1 $uno" } return "$n $varios" }
function Valor-O-Guion($v) { if ([string]$v) { return [string]$v } return '—' }

# Colores de Full Cowl (como texto #RRGGBB, para filas y pinceles)
$Colores = @{
    Verde = '#39824D'; VerdeOscuro = '#2D6A3E'; Turquesa = '#78EBDD'; Oliva = '#9C9C54'
    Cabecera = '#12261A'; Texto = '#14231A'; Suave = '#5F6F65'; Borde = '#DCE6DF'
    Ok = '#2F7A45'; Aviso = '#8A6D1F'; Error = '#C62828'
}

# Cursor de espera mientras algo bloquea un momento la ventana. Se usa así (todo en el mismo sitio,
# para que las variables que se rellenan dentro sigan valiendo después):
#   Iniciar-Espera; try { ... } finally { Terminar-Espera }
function Iniciar-Espera { [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait }
function Terminar-Espera { [System.Windows.Input.Mouse]::OverrideCursor = $null }

function Lanzar($nombreScript, $pedido) {
    # Igual que la ventana de siempre: el pedido va cifrado (DPAPI) y el script se abre en una consola aparte
    $archivo = Guardar-Pedido $pedido
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dirFc $nombreScript)`" -Pedido `"$archivo`""
    Start-Process powershell.exe -ArgumentList $argumentos
}

function Formato-Tiempo($seg) {
    # 754 -> «12:34»; con horas, «1:02:03»
    $t = [TimeSpan]::FromSeconds([Math]::Max(0, [int]$seg))
    if ($t.TotalHours -ge 1) { return '{0}:{1:mm\:ss}' -f [int][Math]::Floor($t.TotalHours), $t }
    return '{0:mm\:ss}' -f $t
}

# ---------------------------------------------------------------- historial de tiempos
# Lo que tarda cada base en crearse y cada máquina en quedar lista, para comparar sistemas y mejorar.
# estado\tiempos.csv (separado por «;», se abre con Excel). La limpieza de restos no lo borra.
$archivoTiempos = Join-Path $dirFc 'estado\tiempos.csv'
$script:tiemposApuntados = @{}
try {
    foreach ($lineaT in @([IO.File]::ReadAllLines($archivoTiempos, [Text.Encoding]::UTF8) | Select-Object -Skip 1)) {
        $camposT = $lineaT.Split(';'); if ($camposT.Count -ge 8) { $script:tiemposApuntados[$camposT[7]] = $true }
    }
} catch {}

function Apuntar-Tiempo([string]$clave, [string]$tipo, [string]$nombre, [string]$sistema, [double]$segundos, [string]$resultado, [string]$detalle = '') {
    # Una línea por cosa terminada (la clave evita apuntarla dos veces)
    if (-not $clave -or $script:tiemposApuntados.ContainsKey($clave) -or $segundos -le 0) { return }
    $script:tiemposApuntados[$clave] = $true
    try {
        $dirT = Split-Path $archivoTiempos
        if (-not (Test-Path $dirT)) { [void](New-Item -ItemType Directory -Path $dirT) }
        $nuevo = -not (Test-Path $archivoTiempos)
        $limpiar = { param($v) ([string]$v) -replace '[;\r\n]', ' ' }
        $linea = @((Get-Date).ToString('dd/MM/yyyy HH:mm'), $tipo, (& $limpiar $nombre), (& $limpiar $sistema),
                   ('{0:N1}' -f ($segundos / 60)), (Formato-Tiempo $segundos), (& $limpiar $resultado), (& $limpiar $clave), (& $limpiar $detalle)) -join ';'
        $texto = $(if ($nuevo) { "fecha;tipo;nombre;sistema;minutos;tiempo;resultado;clave;detalle`r`n" } else { '' }) + $linea + "`r`n"
        [IO.File]::AppendAllText($archivoTiempos, $texto, [Text.UTF8Encoding]::new($nuevo))
    } catch {}
}

function Ultimo-Tiempo([string]$tipo, [string]$sistema) {
    # Lo que tardó la última vez que salió bien (texto «12:34»), o $null si no hay datos
    $res = $null
    try {
        foreach ($l in @([IO.File]::ReadAllLines($archivoTiempos, [Text.Encoding]::UTF8) | Select-Object -Skip 1)) {
            $c = $l.Split(';')
            if ($c.Count -ge 7 -and $c[1] -eq $tipo -and $c[3] -eq $sistema -and $c[6] -eq 'ok') { $res = $c[5] }
        }
    } catch {}
    return $res
}

# ---------------------------------------------------------------- preferencias
# Lo último que elegiste, en el mismo archivo que la ventana de siempre (preferencias.json)
$archivoPrefs = Join-Path $dirFc 'preferencias.json'
$script:prefs = $null
try { $script:prefs = [IO.File]::ReadAllText($archivoPrefs, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}

function Pref([string[]]$ruta, $defecto) {
    # Lee un valor anidado de las preferencias sin fallar si no existe
    $o = $script:prefs
    foreach ($paso in $ruta) {
        if ($null -eq $o) { return $defecto }
        $prop = $o.PSObject.Properties[$paso]
        if (-not $prop) { return $defecto }
        $o = $prop.Value
    }
    if ($null -eq $o) { return $defecto }
    return $o
}

# Desplegables con clave (ficha 36: idioma, teclado y zona de Crear base y Nueva máquina)
function Llenar-ComboClave($combo, $filas, [string]$elegida) {
    # Desplegable con el nombre a la vista y la clave de la tabla escondida en Tag (nunca texto libre)
    $combo.Items.Clear()
    foreach ($f in $filas) {
        $it = New-Object System.Windows.Controls.ComboBoxItem
        $it.Content = [string]$f.Nombre; $it.Tag = [string]$f.Clave
        [void]$combo.Items.Add($it)
        if ([string]$f.Clave -eq $elegida) { $combo.SelectedItem = $it }
    }
    if ($null -eq $combo.SelectedItem -and $combo.Items.Count) { $combo.SelectedIndex = 0 }
}
function Clave-Combo($combo) {
    if ($combo.SelectedItem -and $combo.SelectedItem.Tag) { return [string]$combo.SelectedItem.Tag }
    return ''
}

function Guardar-Prefs($datos) {
    try {
        [IO.File]::WriteAllText($archivoPrefs, ($datos | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($true))
        $script:prefs = [IO.File]::ReadAllText($archivoPrefs, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {}
}

# ---------------------------------------------------------------- diálogos
# Marco común: tarjeta blanca con sombra, título, subtítulo y botón de cerrar. El cuerpo (archivo
# dialogo-*.xaml) trae su contenido y su pie con los botones.
$marcoDialogo = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="%TITULO%" SizeToContent="WidthAndHeight" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterOwner" FontSize="13" Foreground="#14231A"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Ideal">
  <Grid x:Name="Exterior" Margin="22" RenderTransformOrigin="0.5,0.5">
    <Border CornerRadius="14" Background="{DynamicResource T_superficie}">
      <Border.Effect>
        <DropShadowEffect BlurRadius="26" ShadowDepth="5" Direction="270" Opacity="0.24" Color="#12261A"/>
      </Border.Effect>
    </Border>
    <Border CornerRadius="14" Background="{DynamicResource T_superficie}" BorderBrush="{DynamicResource T_borde}" BorderThickness="1" Width="%ANCHO%">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Grid x:Name="CabeceraDlg" Background="Transparent" Margin="24,20,10,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <ContentControl x:Name="PastillaDlg" Visibility="Collapsed" Margin="0,0,14,0" VerticalAlignment="Center" Focusable="False" IsTabStop="False"/>
          <StackPanel Grid.Column="1" Margin="0,0,46,0" VerticalAlignment="Center">
            <TextBlock x:Name="TituloDlg" Style="{StaticResource TituloDialogo}" TextWrapping="Wrap"/>
            <TextBlock x:Name="SubtituloDlg" Style="{StaticResource Nota}" Margin="0,3,0,0"/>
          </StackPanel>
          <Button x:Name="BtnXDlg" Grid.Column="1" Style="{StaticResource BotonCerrar}" Content="&#xE8BB;" HorizontalAlignment="Right" VerticalAlignment="Top" Width="38" Height="32" Margin="0,-8,0,0"/>
        </Grid>
        <ContentControl Grid.Row="1" Focusable="False" IsTabStop="False">
%CUERPO%
        </ContentControl>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

function Nuevo-Dialogo([string]$cuerpo, [string]$titulo, [string]$subtitulo = '', [int]$ancho = 460) {
    # $cuerpo: nombre de un archivo dialogo-*.xaml o el propio XAML. Devuelve una tabla con los
    # elementos con nombre y la ventana en .Ventana
    $xCuerpo = if ($cuerpo -like '*.xaml') { Leer-Xaml $cuerpo } else { $cuerpo }
    $titXml = [System.Security.SecurityElement]::Escape($titulo)
    $x = $marcoDialogo.Replace('%TITULO%', $titXml).Replace('%ANCHO%', [string]$ancho).Replace('%CUERPO%', $xCuerpo)
    $v = [Windows.Markup.XamlReader]::Parse($x)
    $v.FontFamily = $script:fuenteApp
    $v.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'T_texto')
    # Encima de la ventana activa (si un diálogo abre otro, el nuevo sale sobre el primero)
    $duena = @([System.Windows.Application]::Current.Windows | Where-Object { $_.IsActive -and $_.IsVisible }) | Select-Object -First 1
    if (-not $duena -and $script:ventana -and $script:ventana.IsVisible) { $duena = $script:ventana }
    if ($duena) { $v.Owner = $duena } else { $v.WindowStartupLocation = 'CenterScreen' }
    $e = Elementos $v $x
    $e.Ventana = $v
    $e.TituloDlg.Text = $titulo
    if ($subtitulo) { $e.SubtituloDlg.Text = $subtitulo } else { $e.SubtituloDlg.Visibility = 'Collapsed' }
    $e.BtnXDlg.Add_Click({ param($s, $a) [System.Windows.Window]::GetWindow($s).Close() })
    $e.CabeceraDlg.Add_MouseLeftButtonDown({ param($s, $a) try { [System.Windows.Window]::GetWindow($s).DragMove() } catch {} })
    # Entra con un pequeño zoom y fundido
    $v.Add_Loaded({
        param($s, $a)
        $ext = $s.FindName('Exterior')
        $esc = New-Object System.Windows.Media.ScaleTransform(0.96, 0.96)
        $ext.RenderTransform = $esc
        Animar $ext $propOpacidad 1 200 0
        Animar $esc $propEscalaX 1 260
        Animar $esc $propEscalaY 1 260
    })
    $v.Add_KeyDown({ param($s, $a) if ($a.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })
    return $e
}

function Poner-PastillaDlg($e, $m) {
    # Símbolo del sistema de la máquina en la cabecera del diálogo (si algo falla, el diálogo sale igual, sin símbolo)
    try {
        $fam = [string]$m.Familia
        $estilo = Estilo-Icono $fam
        $f = [pscustomobject]@{ IconoGlifo = $estilo[0]; IconoFondo = $estilo[1]; IconoLogo = $null; IconoSimbolo = $null }
        $sis = $null
        try { $sis = Sistema-DeMaquina $m } catch {}
        if ($sis) { Poner-Simbolo $f $sis }
        else {
            $logo = $null
            try { $logo = Logo-DeMaquina $m } catch {}
            if ($logo) { $f.IconoLogo = $logo; $f.IconoGlifo = '' }
        }
        $e.PastillaDlg.Content = Pastilla-Sistema $f 40
        $e.PastillaDlg.Visibility = 'Visible'
    } catch { Escribir-Log ("Símbolo en el diálogo: " + ($_ | Out-String)) }
}

$cuerpoMensaje = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Margin="24,16,24,22">
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border x:Name="IconoMsg" Width="40" Height="40" CornerRadius="20" VerticalAlignment="Top">
      <TextBlock x:Name="GlifoMsg" FontFamily="Segoe MDL2 Assets" FontSize="17" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="1" Margin="14,2,0,0">
      <TextBlock x:Name="TextoMsg" TextWrapping="Wrap" LineHeight="20"/>
      <Expander x:Name="DetExp" Header="Detalles técnicos" Visibility="Collapsed" Margin="0,12,0,0" Foreground="{DynamicResource T_textoSuave}">
        <TextBox x:Name="DetTxt" IsReadOnly="True" TextWrapping="Wrap" MaxHeight="130" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0" FontSize="12" Background="{DynamicResource T_campo}" Foreground="{DynamicResource T_texto}" BorderBrush="{DynamicResource T_linea}" Padding="8,6"/>
      </Expander>
    </StackPanel>
  </Grid>
  <Border Grid.Row="1" Background="{DynamicResource T_pie}" BorderBrush="{DynamicResource T_linea}" BorderThickness="0,1,0,0" CornerRadius="0,0,14,14" Padding="24,14">
    <StackPanel x:Name="BotonesMsg" Orientation="Horizontal" HorizontalAlignment="Right"/>
  </Border>
</Grid>
'@

function Mensaje([string]$texto, [string]$titulo = 'Full Cowl', [string]$tipo = 'aviso', $botones = $null, [string]$detalle = '') {
    # Aviso o pregunta con el estilo nuevo. $botones: lista de @{ Texto; Valor; Estilo }; el último es
    # el principal. Devuelve el Valor del botón pulsado ($null si se cierra con la X o Esc).
    if (-not $botones) { $botones = @(@{ Texto = 'Entendido'; Valor = 'ok'; Estilo = 'BotonPrimario' }) }
    $e = Nuevo-Dialogo $cuerpoMensaje $titulo '' 470
    $aspecto = switch ($tipo) {
        'pregunta' { @(0xE9CE, '#E3F1E7', '#2D6A3E') }
        'error'    { @(0xEA39, '#FDECEC', '#C62828') }
        'ok'       { @(0xE73E, '#E3F1E7', '#2D6A3E') }
        default    { @(0xE7BA, '#FBF3DD', '#8A6D1F') }
    }
    $e.GlifoMsg.Text = Glifo $aspecto[0]
    $e.IconoMsg.Background = Pincel $aspecto[1]
    $e.GlifoMsg.Foreground = Pincel $aspecto[2]
    $e.TextoMsg.Text = $texto
    if ($detalle) {
        $e.DetTxt.Text = $detalle
        $e.DetExp.Visibility = 'Visible'
        # «Copiar» deja el texto técnico en el portapapeles sin cerrar el aviso
        $botones = @(@{ Texto = 'Copiar detalles'; Valor = 'copiar'; Estilo = 'BotonSecundario' }) + @($botones)
    }
    $estado = @{ Valor = $null }
    $i = 0
    foreach ($b in $botones) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $b.Texto
        $btn.Style = [System.Windows.Application]::Current.FindResource($(if ($b.Estilo) { $b.Estilo } else { 'BotonSecundario' }))
        $btn.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
        $btn.MinWidth = 104
        $btn.Tag = $null
        $btn.DataContext = $b.Valor
        if ($i -eq $botones.Count - 1) { $btn.IsDefault = $true }
        $btn.Add_Click({
            param($s, $a)
            if ([string]$s.DataContext -eq 'copiar') {
                try { Set-Clipboard -Value $e.DetTxt.Text; $s.Content = 'Copiado' } catch {}
                return
            }
            $estado.Valor = $s.DataContext
            [System.Windows.Window]::GetWindow($s).Close()
        }.GetNewClosure())
        [void]$e.BotonesMsg.Children.Add($btn)
        $i++
    }
    [void]$e.Ventana.ShowDialog()
    return $estado.Valor
}
function Aviso($texto, $titulo = 'Full Cowl') { [void](Mensaje $texto $titulo 'aviso') }
# ---- Pantallas vacías: icono en círculo, título, frase y (si hay algo que hacer) un botón
function Poner-Vacio($panel, [string]$icono, [string]$titulo, [string]$frase = '', [string]$textoBoton = '', $alPulsar = $null, [bool]$primario = $true, [bool]$compacto = $false) {
    # $panel: StackPanel donde se pinta. Compacto: icono a la izquierda y texto a la derecha, sin botón.
    $panel.Children.Clear()
    $rec = [System.Windows.Application]::Current
    $circ = New-Object System.Windows.Controls.Border
    $tam = $(if ($compacto) { 48 } else { 72 })
    $circ.Width = $tam; $circ.Height = $tam; $circ.CornerRadius = New-Object System.Windows.CornerRadius($tam / 2)
    $circ.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'T_campo')
    $ic = New-Object System.Windows.Controls.ContentControl
    $ic.Style = $rec.FindResource('Icono'); $ic.Content = $rec.FindResource($icono)
    $ic.Width = $(if ($compacto) { 28 } else { 40 }); $ic.Height = $ic.Width
    $ic.HorizontalAlignment = 'Center'; $ic.VerticalAlignment = 'Center'
    $ic.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'T_textoSuave')
    $ic.Focusable = $false; $ic.IsTabStop = $false
    $circ.Child = $ic
    $tt = New-Object System.Windows.Controls.TextBlock
    $tt.Text = $titulo; $tt.FontSize = 16; $tt.FontWeight = [System.Windows.FontWeights]::SemiBold; $tt.TextWrapping = 'Wrap'
    $tt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_texto')
    $ff = $null
    if ($frase) {
        $ff = New-Object System.Windows.Controls.TextBlock
        $ff.Text = $frase; $ff.FontSize = 13; $ff.TextWrapping = 'Wrap'; $ff.MaxWidth = 360
        $ff.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_textoSuave')
    }
    if ($compacto) {
        $panel.Orientation = 'Horizontal'
        $circ.Margin = New-Object System.Windows.Thickness(0, 0, 14, 0)
        $col = New-Object System.Windows.Controls.StackPanel; $col.VerticalAlignment = 'Center'
        $tt.FontSize = 14
        [void]$col.Children.Add($tt)
        if ($ff) { $ff.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0); [void]$col.Children.Add($ff) }
        [void]$panel.Children.Add($circ); [void]$panel.Children.Add($col)
        return
    }
    $panel.Orientation = 'Vertical'
    $circ.HorizontalAlignment = 'Center'
    $tt.HorizontalAlignment = 'Center'; $tt.TextAlignment = 'Center'; $tt.Margin = New-Object System.Windows.Thickness(0, 16, 0, 0)
    [void]$panel.Children.Add($circ); [void]$panel.Children.Add($tt)
    if ($ff) { $ff.HorizontalAlignment = 'Center'; $ff.TextAlignment = 'Center'; $ff.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0); [void]$panel.Children.Add($ff) }
    if ($textoBoton -and $alPulsar) {
        $bt = New-Object System.Windows.Controls.Button
        $bt.Content = $textoBoton; $bt.HorizontalAlignment = 'Center'; $bt.Margin = New-Object System.Windows.Thickness(0, 18, 0, 0)
        $bt.Style = $rec.FindResource($(if ($primario) { 'BotonPrimario' } else { 'BotonSecundario' }))
        $bt.Add_Click($alPulsar)
        [void]$panel.Children.Add($bt)
    }
}
function Error-Msg($texto, $titulo = 'Full Cowl') { [void](Mensaje $texto $titulo 'error') }

# ---- Errores amables: qué ha pasado, qué puedes hacer y los detalles técnicos plegados
function Limpiar-Detalle([string]$t) {
    # Quita del texto técnico lo personal: carpeta de usuario y nombre de usuario de Windows
    if (-not $t) { return '' }
    foreach ($r in @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA)) { if ($r) { $t = $t.Replace($r, '%USERPROFILE%') } }
    if ($env:USERNAME) { $t = $t -replace [regex]::Escape($env:USERNAME), 'usuario' }
    return $t
}
function Texto-Amable($ex) {
    # Traduce una excepción a @{ Que; Hacer }; si no la reconoce, el mensaje de «error desconocido»
    $m = ''; try { $m = [string]$ex.Exception.Message } catch {}
    if (-not $m -and $ex) { $m = [string]$ex.Message }
    $t = ''; try { $t = $ex.Exception.GetType().Name } catch {}
    if ($t -eq 'FileNotFoundException' -or $m -match 'no se encuentra|cannot find|not find|No existe el archivo') {
        return @{ Que = 'No encuentro un archivo que hace falta.'; Hacer = 'Comprueba que no lo has movido. Si falta del todo, pulsa «Actualizar» en Ajustes.' } }
    if ($t -eq 'DirectoryNotFoundException' -or $t -eq 'UnauthorizedAccessException' -or $m -match 'acceso denegado|access.+denied|ruta de acceso') {
        return @{ Que = 'No puedo usar una de las carpetas.'; Hacer = 'Elige otra en Ajustes → Este PC.' } }
    if ($m -match 'vmrun|VMware') {
        return @{ Que = 'No consigo hablar con VMware.'; Hacer = 'Comprueba que VMware está instalado y abierto; vuelve a intentarlo.' } }
    if ($m -match 'espacio en disco|not enough space|There is not enough space|disco.+lleno') {
        return @{ Que = 'Queda poco espacio en el disco.'; Hacer = 'Libera espacio o cambia la carpeta de máquinas en Ajustes → Este PC.' } }
    if ($m -match 'lock|bloquead|en uso|being used by another') {
        return @{ Que = 'Una máquina está ocupada con otra tarea.'; Hacer = 'Espera a que termine y vuelve a intentarlo.' } }
    return @{ Que = 'Algo no ha salido como esperaba.'; Hacer = 'Pulsa «Detalles técnicos», copia el texto y mándaselo al chat de código.' }
}
function Texto-Detalle($ex) {
    $d = ''
    try { $d = [string]$ex.Exception.ToString() } catch {}
    if (-not $d -and $ex) { $d = [string]$ex }
    $d = Limpiar-Detalle $d
    return ($d + "`nRegistro: estado\interfaz.log")
}
function Error-Amable([string]$que, [string]$hacer, [string]$detalle = '', [string]$titulo = 'Full Cowl') {
    [void](Mensaje "$que`n`n$hacer" $titulo 'error' $null (Limpiar-Detalle $detalle))
}
function Pregunta($texto, $titulo = 'Full Cowl', $si = 'Sí, continuar', $no = 'Cancelar', $estiloSi = 'BotonPrimario') {
    $r = Mensaje $texto $titulo 'pregunta' @(@{ Texto = $no; Valor = 'no'; Estilo = 'BotonSecundario' }, @{ Texto = $si; Valor = 'si'; Estilo = $estiloSi })
    return ($r -eq 'si')
}

$cuerpoTexto = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Margin="24,14,24,22">
    <TextBlock x:Name="TextoPedir" Style="{StaticResource Nota}" FontSize="13" Margin="0,0,0,10"/>
    <TextBox x:Name="CampoPedir" Style="{StaticResource Campo}"/>
  </StackPanel>
  <Border Grid.Row="1" Background="{DynamicResource T_pie}" BorderBrush="{DynamicResource T_linea}" BorderThickness="0,1,0,0" CornerRadius="0,0,14,14" Padding="24,14">
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnNoPedir" Style="{StaticResource BotonSecundario}" Content="Cancelar" MinWidth="104"/>
      <Button x:Name="BtnOkPedir" Style="{StaticResource BotonPrimario}" Content="Aceptar" MinWidth="104" Margin="8,0,0,0" IsDefault="True"/>
    </StackPanel>
  </Border>
</Grid>
'@
function Pedir-Texto([string]$titulo, [string]$texto, [string]$defecto = '') {
    # Sustituye al InputBox de siempre. Devuelve el texto o $null si se cancela.
    $e = Nuevo-Dialogo $cuerpoTexto $titulo '' 440
    $e.TextoPedir.Text = $texto
    $e.CampoPedir.Text = $defecto
    $estado = @{ Valor = $null }
    $e.BtnNoPedir.Add_Click({ param($s, $a) [System.Windows.Window]::GetWindow($s).Close() })
    $e.BtnOkPedir.Add_Click({ param($s, $a) $estado.Valor = $e.CampoPedir.Text; [System.Windows.Window]::GetWindow($s).Close() }.GetNewClosure())
    $e.Ventana.Add_ContentRendered({ [void]$e.CampoPedir.Focus(); $e.CampoPedir.SelectAll() }.GetNewClosure())
    [void]$e.Ventana.ShowDialog()
    return $estado.Valor
}

# ---------------------------------------------------------------- piezas visuales compartidas
function Ref-Tema($objeto, $propiedad, [string]$nombre) { $objeto.SetResourceReference($propiedad, $nombre) }

function Pastilla-Sistema($fila, [double]$lado) {
    # Símbolo del sistema en su pastilla de color (en modo sobrio, gris: IconoFondo viene vacío)
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $lado; $b.Height = $lado; $b.CornerRadius = New-Object System.Windows.CornerRadius($lado * 0.28)
    # Color del sistema tal cual (sin pasarlo por el cambio de tema, que lo volvía casi blanco). Si es tan oscuro
    # que no se ve sobre el mapa, o no hay color, la pastilla toma el acento del tema (o el gris del modo sobrio).
    $pintado = $false
    if ($fila.IconoFondo) {
        try {
            $col = [System.Windows.Media.ColorConverter]::ConvertFromString([string]$fila.IconoFondo)
            $lum = (0.2126 * $col.R + 0.7152 * $col.G + 0.0722 * $col.B) / 255.0
            if ($lum -ge 0.16) { $b.Background = New-Object System.Windows.Media.SolidColorBrush($col); $pintado = $true }
        } catch {}
    }
    if (-not $pintado) { Ref-Tema $b ([System.Windows.Controls.Border]::BackgroundProperty) 'T_acento' }
    $b.Padding = New-Object System.Windows.Thickness($lado * 0.2)
    $vb = New-Object System.Windows.Controls.Viewbox; $vb.Stretch = 'Uniform'
    $p = New-Object System.Windows.Shapes.Path
    if ($fila.IconoSimbolo) {
        $p.Data = $fila.IconoSimbolo
        $p.Stroke = [System.Windows.Media.Brushes]::White; $p.StrokeThickness = 1.8
        $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'; $p.StrokeLineJoin = 'Round'
        $p.Width = 24; $p.Height = 24
        $vb.Child = $p; $b.Child = $vb
    } elseif ($fila.IconoLogo) {
        $p.Data = $fila.IconoLogo; $p.Fill = [System.Windows.Media.Brushes]::White; $p.Stretch = 'Uniform'; $p.Width = 20; $p.Height = 20
        $vb.Child = $p; $b.Child = $vb
    } else {
        $g = New-Object System.Windows.Controls.TextBlock
        $g.Text = [string]$fila.IconoGlifo; $g.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets')
        $g.Foreground = [System.Windows.Media.Brushes]::White; $g.HorizontalAlignment = 'Center'; $g.VerticalAlignment = 'Center'
        $b.Child = $g
    }
    return $b
}

# ---------------------------------------------------------------- vmrun desde la ventana (ficha 34)
# Las acciones de la ventana llaman a vmrun con límite de tiempo (Vmrun-ConLimite, comun.ps1). Lo normal es que
# conteste en menos de un segundo y no cambia nada. Si tarda más de 1,5 s, mientras se espera la ventana se sigue
# pintando (para que Windows no la marque «No responde») pero con el ratón y el teclado bloqueados, así no se puede
# pulsar otra cosa a medias. Si algo de esto falla, se queda en la espera simple de siempre (con su límite).
$script:latidoVmrun = @{ Reloj = $null; Bloqueadas = $null; Roto = $false }
function Bloquear-Ventanas {
    # Deja sin ratón ni teclado las ventanas de Full Cowl que estén activas ahora. Devuelve cuáles (para soltarlas luego).
    # (las dos funciones de Windows se preparan la primera vez que hacen falta, no al abrir Full Cowl)
    if (-not ('FullCowlWin.Ventanas' -as [type])) {
        Add-Type -Namespace FullCowlWin -Name Ventanas -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr hWnd, bool bEnable);
[DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
'@
    }
    $bloqueadas = @()
    foreach ($fuente in @([System.Windows.PresentationSource]::CurrentSources)) {
        try {
            $asa = ([System.Windows.Interop.HwndSource]$fuente).Handle
            if ($asa -ne [IntPtr]::Zero -and [FullCowlWin.Ventanas]::IsWindowEnabled($asa)) {
                [void][FullCowlWin.Ventanas]::EnableWindow($asa, $false)
                $bloqueadas += $asa
            }
        } catch {}
    }
    return $bloqueadas
}
function Soltar-Ventanas {
    foreach ($asa in @($script:latidoVmrun.Bloqueadas)) {
        try { if ($asa) { [void][FullCowlWin.Ventanas]::EnableWindow($asa, $true) } } catch {}
    }
    $script:latidoVmrun.Bloqueadas = $null; $script:latidoVmrun.Reloj = $null
}
$script:pulsoVmrun = {
    if ($script:latidoVmrun.Roto) { return }
    if (-not $script:latidoVmrun.Reloj) { $script:latidoVmrun.Reloj = [System.Diagnostics.Stopwatch]::StartNew(); return }
    if ($script:latidoVmrun.Reloj.Elapsed.TotalMilliseconds -lt 1500) { return }
    try {
        if ($null -eq $script:latidoVmrun.Bloqueadas) { $script:latidoVmrun.Bloqueadas = @(Bloquear-Ventanas) }
        $script:ventana.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    } catch {
        $script:latidoVmrun.Roto = $true
        try { Escribir-Log ("Latido de vmrun: " + $_.Exception.Message) } catch {}
    }
}
function Vmrun-Ventana($argumentos, [int]$segundos = 0) {
    # vmrun -T ws <argumentos> con límite. Devuelve lo mismo que Vmrun-ConLimite (mirar .Agotado antes que .Codigo)
    Soltar-Ventanas
    try { return (Vmrun-ConLimite $script:vmrun (@('-T', 'ws') + @($argumentos)) $segundos $script:pulsoVmrun) }
    finally { Soltar-Ventanas }
}
function Aviso-VmrunAgotado($resultado, [switch]$Larga) {
    # «VMware no ha contestado» en llano. En Detalles solo va la operación: nunca los argumentos (podrían llevar la contraseña)
    $hacerAhora = 'Puede que siga trabajando: espera un poco y vuelve a mirar. Si se repite, cierra VMware y ábrelo de nuevo.'
    if ($Larga) { $hacerAhora += ' La operación puede haber terminado igualmente.' }
    Error-Amable "VMware no ha contestado en $([int]$resultado.Limite) segundos." $hacerAhora "Operación de VMware: $($resultado.Operacion). Sin respuesta tras $($resultado.Segundos) s; se cerró solo la orden lanzada (VMware y las máquinas no se tocan)."
}

# ---------------------------------------------------------------- cifras libres (RAM en GB, − y +)
function Gb-Texto([double]$mb) { return ($mb / 1024.0).ToString('0.#', [Globalization.CultureInfo]::InvariantCulture) }
function Texto-AMb([string]$texto) {
    # «4», «4,5» o «4.5» (GB) -> MB; -1 si no es un número
    $v = 0.0
    if ([double]::TryParse($texto.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
        # Sin esto, escribir muchas cifras («12344444») pasaba de lo que cabe en un entero y saltaba un error (09/11/2026)
        if ([double]::IsNaN($v) -or $v -lt 0) { return -1 }
        return [int][Math]::Round([Math]::Min($v * 1024, 2000000000.0))
    }
    return -1
}
function Paso-Cifra($caja, [double]$delta, [double]$minimo, [double]$maximo) {
    $v = 0.0
    if (-not [double]::TryParse(([string]$caja.Text).Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v = $minimo - $delta }
    $v = [Math]::Min($maximo, [Math]::Max($minimo, $v + $delta))
    $caja.Text = $v.ToString('0.#', [Globalization.CultureInfo]::InvariantCulture)
}
