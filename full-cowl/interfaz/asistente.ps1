# =====================================================================
#  Interfaz nueva: asistente de primer arranque (ficha 16)
#  Se abre solo la primera vez en un PC (cuando faltan las carpetas de ISOs y de máquinas) y desde
#  Ajustes → Ayuda y registros → «Repetir el asistente». Sustituye al diálogo de «Ajustes de este PC»
#  de la primera vez, a la contraseña por consola y al antiguo instalar.bat.
#
#  OJO: este archivo se carga ANTES que maquinas.ps1, selector.ps1, apariencia.ps1… porque el asistente
#  sale antes de crear la ventana principal. Aquí solo se pueden usar funciones de comun.ps1, base.ps1,
#  tema.ps1, actualizacion.ps1 y ajustes.ps1 (ni Mostrar-Toast ni Imagen existen todavía).
#  La contraseña nunca se escribe en ningún archivo legible ni en el registro: va de la caja a DPAPI.
# =====================================================================

# ---------------------------------------------------------------- contraseña de las máquinas (ventana)
function Cambiar-PasswordVms([string]$titulo = 'Contraseña de las máquinas', [string]$subtitulo = 'Solo para este PC') {
    # Pide la contraseña en una ventana (dos cajas ocultas) y la guarda cifrada (DPAPI). Devuelve $true si se guardó.
    # La contraseña no se muestra ni se escribe en ningún registro.
    $hbD = Nuevo-Dialogo 'dialogo-password.xaml' $titulo $subtitulo 520
    $hbGuardada = @{ Valor = $false }
    $hbMira = {
        $u = [Net.NetworkCredential]::new('', $hbD.PwUno.SecurePassword).Password
        $d = [Net.NetworkCredential]::new('', $hbD.PwDos.SecurePassword).Password
        $tipos = 0
        if ($u -cmatch '[A-Z]') { $tipos++ }; if ($u -cmatch '[a-z]') { $tipos++ }; if ($u -match '\d') { $tipos++ }; if ($u -match '[^A-Za-z0-9]') { $tipos++ }
        $largo = ($u.Length -ge 7); $mismas = ($u.Length -gt 0 -and $u -ceq $d)
        $u = $null; $d = $null
        $pon = {
            param($caja, [bool]$bien, [string]$texto)
            $caja.Text = $(if ($bien) { ([string][char]0x2713) + '  ' } else { ([string][char]0x25CB) + '  ' }) + $texto
            $caja.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($bien) { 'T_acentoClaro' } else { 'T_textoSuave' }))
        }
        & $pon $hbD.PwReg1 $largo '7 o más caracteres'
        & $pon $hbD.PwReg2 ($tipos -ge 3) '3 de 4 tipos: mayúsculas, minúsculas, números, símbolos'
        & $pon $hbD.PwReg3 $mismas 'Las dos son iguales'
    }
    $hbD.PwUno.Add_PasswordChanged($hbMira)
    $hbD.PwDos.Add_PasswordChanged($hbMira)
    & $hbMira
    $hbD.BtnPwNo.Add_Click({ $hbD.Ventana.Close() })
    $hbD.BtnPwOk.Add_Click({
        $hbUno = [Net.NetworkCredential]::new('', $hbD.PwUno.SecurePassword).Password
        $hbDos = [Net.NetworkCredential]::new('', $hbD.PwDos.SecurePassword).Password
        $hbMsg = ''
        if (-not $hbUno) { $hbMsg = 'No puede estar vacía.' }
        elseif ($hbUno -cne $hbDos) { $hbMsg = 'No coinciden.' }
        elseif ($hbUno.Contains("'")) { $hbMsg = "No puede contener comillas simples (')." }
        $hbUno = $null; $hbDos = $null
        if ($hbMsg) { $hbD.PwError.Text = $hbMsg; $hbD.PwError.Visibility = 'Visible'; return }
        try {
            $hbArchivo = Join-Path $dirFc 'password.sec'
            $hbTmp = "$hbArchivo.nuevo"
            $hbD.PwUno.SecurePassword | ConvertFrom-SecureString | Set-Content -LiteralPath $hbTmp
            Move-Item -LiteralPath $hbTmp -Destination $hbArchivo -Force
        } catch { $hbD.PwError.Text = 'No se pudo guardar la contraseña.'; $hbD.PwError.Visibility = 'Visible'; return }
        $hbGuardada.Valor = $true
        $hbD.Ventana.Close()
    })
    [void]$hbD.Ventana.ShowDialog()
    return [bool]$hbGuardada.Valor
}

function Asegurar-PasswordVms {
    # Antes de lanzar algo que necesita la contraseña de las máquinas: si no está guardada, se pide en una ventana
    # (nunca en la consola). Devuelve $false si la persona cancela.
    if (Obtener-Password -SinPreguntar) { return $true }
    return (Cambiar-PasswordVms 'Contraseña de las máquinas' 'Hace falta para entrar en ellas · solo para este PC')
}

# ---------------------------------------------------------------- comprobaciones del PC
function Actualizar-RutaProceso {
    # Después de instalar algo con winget, el PATH de este programa sigue siendo el de antes: se vuelve a leer
    try {
        $m = [Environment]::GetEnvironmentVariable('Path', 'Machine'); $u = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($m, $u) | Where-Object { $_ }) -join ';'
    } catch {}
}

function Espacio-LibreGb([string]$ruta) {
    # GB libres de la unidad de una ruta (aunque la carpeta aún no exista); -1 si no se sabe
    try {
        $raiz = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($ruta))
        if (-not $raiz) { return -1 }
        return [double](([IO.DriveInfo]$raiz).AvailableFreeSpace / 1GB)
    } catch { return -1 }
}

function Estado-Pc([string]$rutaDisco) {
    $r = @()
    $vm = $null; try { $vm = Buscar-Vmrun -Silencioso } catch {}
    $r += @{ Clave = 'vmware'; Nombre = 'VMware Workstation Pro'; Insignia = 'Necesario'; Ok = [bool]$vm
             Texto = $(if ($vm) { 'Instalado.' } else { 'No lo encuentro. Hay que instalarlo aparte (no se instala desde aquí) y luego pulsar «Volver a comprobar».' }); Accion = '' }
    $pk = [bool](Obtener-Packer)
    $r += @{ Clave = 'packer'; Nombre = 'Packer'; Insignia = 'Necesario'; Ok = $pk
             Texto = $(if ($pk) { 'Instalado. Es el que crea las bases desde las ISO.' } else { 'Es el que crea las bases desde las ISO. Se instala desde aquí (descarga oficial de HashiCorp, comprobada).' }); Accion = 'Instalar Packer' }
    # Git solo hace falta en una copia del repositorio (con carpeta .git); instalado por descarga se actualiza sin él (ficha 33)
    $conGit = Test-Path -LiteralPath (Join-Path (Split-Path $dirFc) '.git')
    $gt = [bool](Get-Command git -ErrorAction SilentlyContinue)
    if ($conGit) { $r += @{ Clave = 'git'; Nombre = 'Git'; Insignia = 'Opcional'; Ok = $gt
             Texto = $(if ($gt) { 'Instalado: Full Cowl se podrá actualizar sola.' } else { 'Solo sirve para que Full Cowl se actualice sola. Puedes seguir sin él.' }); Accion = 'Instalar Git' } }
    $libre = Espacio-LibreGb $rutaDisco
    $r += @{ Clave = 'disco'; Nombre = 'Espacio en disco'; Insignia = 'Recomendado'; Ok = ($libre -lt 0 -or $libre -ge 60)
            Texto = $(if ($libre -lt 0) { 'No he podido medirlo.' } elseif ($libre -ge 60) { "$([int]$libre) GB libres donde se guardarán las máquinas." } else { "Solo quedan $([int]$libre) GB: una base ocupa entre 10 y 40 GB. Mejor elige otro disco en el paso de carpetas." }); Accion = '' }
    return $r
}

function Fila-IconoAsistente($sistema) {
    # Lo que necesita Pastilla-Sistema (base.ps1) para un sistema del catálogo, sin depender de maquinas.ps1
    # (que todavía no está cargado cuando sale el asistente). Se parece a Fila-IconoSistema de selector.ps1
    $sobrio = [bool]$Config.Sobrio
    $app = [System.Windows.Application]::Current
    $f = [pscustomobject]@{ IconoGlifo = [string][char]0xE756; IconoFondo = $(if ($sobrio) { '#5F6A72' } else { '#9C9C54' }); IconoLogo = $null; IconoSimbolo = $null }
    $clave = [string]$sistema.Clave
    if ($clave -like 'WinServer*') { $f.IconoGlifo = [string][char]0xE7F4; if (-not $sobrio) { $f.IconoFondo = '#12261A' }; $f.IconoLogo = $app.FindResource('LogoWindows10'); $f.IconoGlifo = '' }
    elseif ($clave -like 'Win11*') { if (-not $sobrio) { $f.IconoFondo = '#39824D' }; $f.IconoLogo = $app.FindResource('LogoWindows11'); $f.IconoGlifo = '' }
    elseif ($clave -like 'Win*') { if (-not $sobrio) { $f.IconoFondo = '#39824D' }; $f.IconoLogo = $app.FindResource('LogoWindows10'); $f.IconoGlifo = '' }
    elseif ($clave -like 'Lubuntu*') { $f.IconoLogo = $app.FindResource('LogoLubuntu'); $f.IconoGlifo = ''; if (-not $sobrio) { $f.IconoFondo = '#0068C8' } }
    elseif ($clave -like 'Ubuntu*') { $f.IconoLogo = $app.FindResource('LogoUbuntu'); $f.IconoGlifo = '' }
    elseif ($clave -like 'Kali*') { $f.IconoLogo = $app.FindResource('LogoKali'); $f.IconoGlifo = ''; if (-not $sobrio) { $f.IconoFondo = '#2F6FDE' } }
    elseif ($clave -like 'Parrot*') { $f.IconoLogo = $app.FindResource('LogoParrot'); $f.IconoGlifo = ''; if (-not $sobrio) { $f.IconoFondo = '#1FA9D6' } }
    elseif ($clave -like 'Debian*') { $f.IconoLogo = $app.FindResource('LogoDebian'); $f.IconoGlifo = ''; if (-not $sobrio) { $f.IconoFondo = '#C2185B' } }
    elseif ($clave -like 'Rocky*' -or $clave -like 'Alma*') { $f.IconoLogo = $app.FindResource('LogoRocky'); $f.IconoGlifo = ''; if (-not $sobrio) { $f.IconoFondo = '#10B981' } }
    elseif ($clave -like 'Arch*') { $f.IconoLogo = $app.FindResource('LogoArch'); $f.IconoGlifo = ''; if (-not $sobrio) { $f.IconoFondo = '#1793D1' } }
    return $f
}

# ---------------------------------------------------------------- el asistente
function Abrir-Asistente([bool]$repetir = $false) {
    # Devuelve @{ Terminado = $true/$false; Destino = 'base' | 'importar' | 'inicio' | '' }
    $x = Leer-Xaml 'asistente.xaml'
    $v = [Windows.Markup.XamlReader]::Parse($x)
    $v.FontFamily = $script:fuenteApp
    $v.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'T_fondo')
    $v.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'T_texto')
    $a = Elementos $v $x
    if ($repetir) {
        $duena = @([System.Windows.Application]::Current.Windows | Where-Object { $_.IsActive -and $_.IsVisible }) | Select-Object -First 1
        if ($duena) { $v.Owner = $duena; $v.WindowStartupLocation = 'CenterOwner' }
    }
    # Marca (logo y letras de Full Cowl)
    foreach ($par in @(@('AsLogo', 'logo.png'), @('AsTitulo', 'titulo.png'))) {
        try {
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit(); $bi.UriSource = New-Object System.Uri((Join-Path $dirFc ('recursos\' + $par[1]))); $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
            $a[$par[0]].Source = $bi
        } catch {}
    }
    $nombresPaso = @('Tu PC', 'Carpetas', 'Tus máquinas', 'Tu aspecto', 'Listo')
    $estado = @{ Paso = 0; Terminado = $false; Destino = ''; Instalando = $null; Cargando = $true }
    $usuarioAntes = [string]$Config.Usuario
    $rutaPw = Join-Path $dirFc 'password.sec'
    $pwYaGuardada = (Test-Path -LiteralPath $rutaPw)

    # ------------------------------------------------ valores de partida
    $isosPropuesta = [string]$Config.CarpetaISOs
    $candIsos = @('D:\ISOs', 'D:\ISO', 'C:\ISOs')
    if (-not $isosPropuesta) { foreach ($cand in $candIsos) { if (Test-Path -LiteralPath $cand) { $isosPropuesta = $cand; break } } }
    $a.AsIsos.Text = $isosPropuesta
    $a.AsVms.Text = $(if ($Config.CarpetaVMs) { [string]$Config.CarpetaVMs } else { Carpeta-VmsVmware })
    $a.AsUsuario.Text = $usuarioAntes
    $a.AsNombre.Text = [string]$Config.Nombre
    $temaCfg = [string]$Config.Tema
    $a.AsTemaClaro.IsChecked = ($temaCfg -ne 'Oscuro' -and $temaCfg -ne 'Automatico')
    $a.AsTemaOscuro.IsChecked = ($temaCfg -eq 'Oscuro'); $a.AsTemaAuto.IsChecked = ($temaCfg -eq 'Automatico')
    $a.AsSobrio.IsChecked = [bool]$Config.Sobrio
    $modosAct = @('Avisar', 'Solo', 'No')
    $modoAct = Modo-Actualizaciones
    $a.AsActAvisar.IsChecked = ($modoAct -eq 'Avisar' -or $modosAct -notcontains $modoAct)
    $a.AsActSolo.IsChecked = ($modoAct -eq 'Solo'); $a.AsActNo.IsChecked = ($modoAct -eq 'No')
    $textosAct = @{ Avisar = 'Al abrir, busca y te avisa en Inicio (lo normal).'; Solo = 'Al abrir, se actualiza sola y te lo cuenta.'; No = 'No busca nada: tú decides cuándo.' }
    $pintarNotaAct = {
        $k = $(if ($a.AsActSolo.IsChecked) { 'Solo' } elseif ($a.AsActNo.IsChecked) { 'No' } else { 'Avisar' })
        $a.AsActNota.Text = $textosAct[$k]
    }
    & $pintarNotaAct

    # ------------------------------------------------ rayos alrededor del logo (rayos.cs; si algo falla, el asistente sale sin ellos)
    $rayosAs = $null
    $colorearRayos = {
        if (-not $rayosAs) { return }
        try {
            $oscuro = [int]($script:temaActual -eq 'oscuro')
            $halo = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Paleta['encendida'][$oscuro])
            $medio = [System.Windows.Media.ColorConverter]::ConvertFromString($script:Paleta['brillo'][$oscuro])
            $claro = [System.Windows.Media.ColorConverter]::ConvertFromString('#F2FFFC')
            $rayosAs.PonerColores([System.Windows.Media.Color]$halo, [System.Windows.Media.Color]$medio, [System.Windows.Media.Color]$claro)
            # Animaciones «Ninguna» o modo sobrio: sin rayos
            $rayosAs.Permitido = (($Config.RayosInicio -ne $false) -and ((Animaciones-Modo) -eq 'Normales'))
        } catch { Escribir-Log ("Asistente, colores de rayos: " + $_.Exception.Message) }
    }
    try {
        if ('FullCowlWpf.RayosSueltos' -as [type]) {
            $rayosAs = New-Object FullCowlWpf.RayosSueltos($a.AsRayos, $v)
            $rayosAs.Marca = $a.AsLogo
            $rayosAs.ModoAro = $true
            & $colorearRayos
        }
    } catch { $rayosAs = $null; Escribir-Log ("Asistente, rayos desactivados: " + ($_ | Out-String)) }

    # ------------------------------------------------ indicador de pasos (panel izquierdo)
    $pintarPasos = {
        $a.AsPasos.Children.Clear()
        for ($k = 1; $k -le 5; $k++) {
            $hecho = ($estado.Paso -gt $k); $actual = ($estado.Paso -eq $k)
            $fila = New-Object System.Windows.Controls.Grid
            $fila.Margin = New-Object System.Windows.Thickness(0, 0, 0, 20)
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(40)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, 'Star')
            [void]$fila.ColumnDefinitions.Add($c1); [void]$fila.ColumnDefinitions.Add($c2)
            $circ = New-Object System.Windows.Controls.Border
            $circ.Width = 30; $circ.Height = 30; $circ.CornerRadius = New-Object System.Windows.CornerRadius(15); $circ.BorderThickness = New-Object System.Windows.Thickness(2)
            $circ.HorizontalAlignment = 'Left'
            $num = New-Object System.Windows.Controls.TextBlock
            $num.HorizontalAlignment = 'Center'; $num.VerticalAlignment = 'Center'; $num.FontWeight = [System.Windows.FontWeights]::SemiBold; $num.FontSize = 13
            if ($hecho) {
                $num.Text = [string][char]0x2713
                $circ.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'T_menuAcento')
                $circ.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'T_menuAcento')
                $num.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(4, 18, 12))
            } else {
                $num.Text = [string]$k
                $circ.Background = [System.Windows.Media.Brushes]::Transparent
                $circ.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, $(if ($actual) { 'T_menuAcento' } else { 'T_textoMenu' }))
                $num.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($actual) { 'T_menuAcento' } else { 'T_textoMenu' }))
                if (-not $actual) { $circ.Opacity = 0.55 }
            }
            $circ.Child = $num
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = $nombresPaso[$k - 1]; $txt.FontSize = 15; $txt.VerticalAlignment = 'Center'
            $txt.FontWeight = $(if ($actual) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Normal })
            $txt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($actual) { 'T_menuAcento' } else { 'T_textoMenu' }))
            if (-not $actual -and -not $hecho) { $txt.Opacity = 0.7 }
            [System.Windows.Controls.Grid]::SetColumn($txt, 1)
            [void]$fila.Children.Add($circ); [void]$fila.Children.Add($txt)
            [void]$a.AsPasos.Children.Add($fila)
        }
    }

    # ------------------------------------------------ paso 1: comprobaciones
    $rutaParaDisco = { $(if ($a.AsVms.Text.Trim()) { $a.AsVms.Text.Trim() } else { Carpeta-VmsVmware }) }
    $instalar = $null
    $pintarChecks = {
        $a.AsChecks.Children.Clear()
        foreach ($c in (Estado-Pc (& $rutaParaDisco))) {
            $tarj = New-Object System.Windows.Controls.Border
            $tarj.CornerRadius = New-Object System.Windows.CornerRadius(12); $tarj.Padding = New-Object System.Windows.Thickness(14, 12, 14, 12); $tarj.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
            $tarj.BorderThickness = New-Object System.Windows.Thickness(1)
            Ref-Tema $tarj ([System.Windows.Controls.Border]::BackgroundProperty) 'T_superficie'
            Ref-Tema $tarj ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'
            $g = New-Object System.Windows.Controls.Grid
            foreach ($ancho in @('Auto', '*', 'Auto', 'Auto')) {
                $cd = New-Object System.Windows.Controls.ColumnDefinition
                $cd.Width = $(if ($ancho -eq '*') { New-Object System.Windows.GridLength(1, 'Star') } else { [System.Windows.GridLength]::Auto })
                [void]$g.ColumnDefinitions.Add($cd)
            }
            $cir = New-Object System.Windows.Controls.Border
            $cir.Width = 28; $cir.Height = 28; $cir.CornerRadius = New-Object System.Windows.CornerRadius(14); $cir.VerticalAlignment = 'Top'; $cir.Margin = New-Object System.Windows.Thickness(0, 1, 12, 0)
            Ref-Tema $cir ([System.Windows.Controls.Border]::BackgroundProperty) $(if ($c.Ok) { 'T_acento' } else { 'T_aviso' })
            $sig = New-Object System.Windows.Controls.TextBlock
            $sig.Text = $(if ($c.Ok) { [string][char]0x2713 } else { '!' }); $sig.FontWeight = [System.Windows.FontWeights]::Bold; $sig.FontSize = 14
            $sig.HorizontalAlignment = 'Center'; $sig.VerticalAlignment = 'Center'
            if ($c.Ok) { Ref-Tema $sig ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_sobreAcento' }
            else { $sig.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(26, 20, 3)) }
            $cir.Child = $sig
            [void]$g.Children.Add($cir)
            $col = New-Object System.Windows.Controls.StackPanel
            $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $c.Nombre; $t1.FontWeight = [System.Windows.FontWeights]::SemiBold; $t1.FontSize = 14
            Ref-Tema $t1 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
            $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = $c.Texto; $t2.FontSize = 12.5; $t2.TextWrapping = 'Wrap'; $t2.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
            Ref-Tema $t2 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
            [void]$col.Children.Add($t1); [void]$col.Children.Add($t2)
            [System.Windows.Controls.Grid]::SetColumn($col, 1); [void]$g.Children.Add($col)
            $ins = New-Object System.Windows.Controls.Border
            $ins.CornerRadius = New-Object System.Windows.CornerRadius(9); $ins.Padding = New-Object System.Windows.Thickness(8, 1, 8, 1); $ins.VerticalAlignment = 'Top'; $ins.Margin = New-Object System.Windows.Thickness(10, 2, 0, 0)
            Ref-Tema $ins ([System.Windows.Controls.Border]::BackgroundProperty) 'T_neutro'
            $it = New-Object System.Windows.Controls.TextBlock; $it.Text = $c.Insignia; $it.FontSize = 11.5; $it.FontWeight = [System.Windows.FontWeights]::Medium
            Ref-Tema $it ([System.Windows.Controls.TextBlock]::ForegroundProperty) $(if ($c.Insignia -eq 'Necesario') { 'T_acentoClaro' } else { 'T_textoSuave' })
            $ins.Child = $it
            [System.Windows.Controls.Grid]::SetColumn($ins, 2); [void]$g.Children.Add($ins)
            if (-not $c.Ok -and $c.Accion) {
                $b = New-Object System.Windows.Controls.Button
                $b.Style = [System.Windows.Application]::Current.FindResource($(if ($c.Insignia -eq 'Necesario') { 'BotonPrimario' } else { 'BotonSecundario' }))
                $b.Content = $c.Accion; $b.Height = 32; $b.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0); $b.VerticalAlignment = 'Top'
                $b.DataContext = [string]$c.Clave
                $b.IsEnabled = -not $estado.Instalando
                $b.Add_Click({ param($s, $ev) & $instalar ([string]$s.DataContext) })
                [System.Windows.Controls.Grid]::SetColumn($b, 3); [void]$g.Children.Add($b)
            }
            $tarj.Child = $g
            [void]$a.AsChecks.Children.Add($tarj)
        }
    }

    # winget en segundo plano: la ventana sigue respondiendo y un reloj mira cuándo ha terminado
    $relojInst = New-Object System.Windows.Threading.DispatcherTimer
    $relojInst.Interval = [TimeSpan]::FromMilliseconds(500)
    $instalar = {
        param([string]$clave)
        if ($estado.Instalando) { return }
        $info = switch ($clave) {
            'packer' { @{ Id = 'Hashicorp.Packer'; Nombre = 'Packer'; Enlace = 'https://developer.hashicorp.com/packer/install' } }
            'git'    { @{ Id = 'Git.Git'; Nombre = 'Git'; Enlace = 'https://git-scm.com/download/win' } }
            default  { $null }
        }
        if (-not $info) { return }
        if ($clave -eq 'packer') {
            # Packer: descarga oficial comprobada (instalacion\instalar-packer.ps1), sin winget ni administrador
            try {
                $resPk = Join-Path ([IO.Path]::GetTempPath()) 'FullCowl-packer-resultado.json'
                try { Remove-Item -LiteralPath $resPk -Force -ErrorAction SilentlyContinue } catch {}
                $psi = New-Object System.Diagnostics.ProcessStartInfo((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),
                    "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dirFc 'instalacion\instalar-packer.ps1')`" -Resultado `"$resPk`"")
                $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
                $proc = [System.Diagnostics.Process]::Start($psi)
                $estado.Instalando = @{ Proc = $proc; Sal = $proc.StandardOutput.ReadToEndAsync(); Err = $proc.StandardError.ReadToEndAsync(); Info = $info; Clave = $clave; Resultado = $resPk }
            } catch {
                Error-Amable 'No he podido empezar a instalar Packer.' "Descárgalo de $($info.Enlace) e instálalo a mano." $_.Exception.Message
                return
            }
            $a.AsInstalarBarra.Visibility = 'Visible'
            $a.AsInstalarTexto.Text = 'Descargando Packer de HashiCorp y comprobándolo… puede tardar un minuto.'
            $a.BtnAsRecomprobar.IsEnabled = $false
            & $pintarChecks
            $relojInst.Start()
            return
        }
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Error-Amable "Este PC no tiene winget, así que no puedo instalar $($info.Nombre) desde aquí." "Descárgalo de $($info.Enlace) e instálalo a mano; luego pulsa «Volver a comprobar»." ''
            return
        }
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo($winget.Source, "install --id $($info.Id) -e --source winget --accept-source-agreements --accept-package-agreements")
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            try { $proc.StandardInput.Close() } catch {}
            $estado.Instalando = @{ Proc = $proc; Sal = $proc.StandardOutput.ReadToEndAsync(); Err = $proc.StandardError.ReadToEndAsync(); Info = $info; Clave = $clave }
        } catch {
            Error-Amable "No he podido lanzar winget para instalar $($info.Nombre)." "Descárgalo de $($info.Enlace) e instálalo a mano." $_.Exception.Message
            return
        }
        $a.AsInstalarBarra.Visibility = 'Visible'
        $a.AsInstalarTexto.Text = "Instalando $($info.Nombre)… puede tardar un minuto. Si Windows pide permiso, acéptalo."
        $a.BtnAsRecomprobar.IsEnabled = $false
        & $pintarChecks
        $relojInst.Start()
    }
    $relojInst.Add_Tick({
        $it = $estado.Instalando
        if (-not $it -or -not $it.Proc.HasExited) { return }
        $relojInst.Stop()
        $codigo = $it.Proc.ExitCode
        $salida = ("$($it.Sal.Result)" + "`n" + "$($it.Err.Result)").Trim()
        try { $it.Proc.Dispose() } catch {}
        $estado.Instalando = $null
        $a.AsInstalarBarra.Visibility = 'Collapsed'
        $a.BtnAsRecomprobar.IsEnabled = $true
        Actualizar-RutaProceso
        $ahora = Estado-Pc (& $rutaParaDisco) | Where-Object { $_.Clave -eq $it.Clave } | Select-Object -First 1
        if ($ahora -and $ahora.Ok) { $a.AsInstalarTexto.Text = "$($it.Info.Nombre) recién instalado." }
        else {
            $a.AsInstalarTexto.Text = ''
            Escribir-Log ("instalar $($it.Info.Id): código $codigo")
            $msgPk = ''
            if ($it.Resultado) { try { $msgPk = [string]([IO.File]::ReadAllText($it.Resultado, [Text.Encoding]::UTF8) | ConvertFrom-Json).Mensaje } catch {} }
            if ($msgPk) { Error-Amable "No se ha podido instalar $($it.Info.Nombre)." $msgPk $salida }
            else { Error-Amable "No se ha podido instalar $($it.Info.Nombre) con winget." "Descárgalo de $($it.Info.Enlace) e instálalo a mano; luego pulsa «Volver a comprobar»." $salida }
        }
        & $pintarChecks
    })

    # ------------------------------------------------ paso 2: carpetas
    $revisarCarpetas = {
        $ri = $a.AsIsos.Text.Trim()
        $a.AsIsosPildoras.Children.Clear()
        if ($ri -and (Test-Path -LiteralPath $ri)) {
            $isos = @(Get-ChildItem -LiteralPath $ri -Filter *.iso -ErrorAction SilentlyContinue)
            $a.AsIsosNota.Text = "$(Plural $isos.Count 'ISO encontrada' 'ISO encontradas'). Se detectan solas: puedes añadir más cuando quieras."
            Ref-Tema $a.AsIsosNota ([System.Windows.Controls.TextBlock]::ForegroundProperty) $(if ($isos.Count) { 'T_acentoClaro' } else { 'T_textoSuave' })
            $vistos = @{}
            foreach ($s in @(Obtener-Sistemas)) {
                if ($vistos.ContainsKey([string]$s.Patron)) { continue }
                if (@($isos | Where-Object { $_.Name -match $s.Patron }).Count) {
                    $vistos[[string]$s.Patron] = $true
                    $pil = New-Object System.Windows.Controls.Border
                    $pil.CornerRadius = New-Object System.Windows.CornerRadius(11); $pil.Padding = New-Object System.Windows.Thickness(6, 3, 10, 3); $pil.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
                    Ref-Tema $pil ([System.Windows.Controls.Border]::BackgroundProperty) 'T_neutro'
                    $pt = New-Object System.Windows.Controls.TextBlock; $pt.Text = ([string]$s.Nombre -replace '\s*\(.*\)\s*$', '').Trim(); $pt.FontSize = 12; $pt.FontWeight = [System.Windows.FontWeights]::Medium
                    Ref-Tema $pt ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
                    $pt.VerticalAlignment = 'Center'
                    $pil.Child = $pt
                    try {
                        $fp = New-Object System.Windows.Controls.StackPanel; $fp.Orientation = 'Horizontal'
                        $ico = Pastilla-Sistema (Fila-IconoAsistente $s) 20
                        $ico.Margin = New-Object System.Windows.Thickness(0, 0, 7, 0); $ico.VerticalAlignment = 'Center'
                        $pil.Child = $null   # (el texto ya era hijo de la píldora: hay que soltarlo antes de meterlo en otro panel)
                        [void]$fp.Children.Add($ico); [void]$fp.Children.Add($pt)
                        $pil.Child = $fp
                    } catch { Escribir-Log ("Asistente, símbolo de ISO: " + $_.Exception.Message); try { if ($fp) { $fp.Children.Clear() }; $pil.Child = $pt } catch {} }
                    [void]$a.AsIsosPildoras.Children.Add($pil)
                }
            }
        } else {
            $a.AsIsosNota.Text = $(if ($ri) { 'Esa carpeta no existe.' } else { 'Elige la carpeta donde tienes las ISO.' })
            Ref-Tema $a.AsIsosNota ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_peligro'
        }
        $rv = $a.AsVms.Text.Trim()
        if ($rv) {
            $a.AsVmsNota.Text = "Cada máquina en su subcarpeta; las bases en $(Join-Path $rv '_Bases')." + $(if (-not (Test-Path -LiteralPath $rv)) { ' (Se creará.)' } else { '' }) + ' Mejor un disco con espacio.'
            Ref-Tema $a.AsVmsNota ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
            $libre = Espacio-LibreGb $rv
            $a.AsVmsLibre.Text = $(if ($libre -ge 0) { "$([int]$libre) GB libres en $([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($rv)).TrimEnd('\'))" } else { '' })
        } else {
            $a.AsVmsNota.Text = 'Elige una carpeta.'
            Ref-Tema $a.AsVmsNota ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_peligro'
            $a.AsVmsLibre.Text = ''
        }
    }
    $a.AsIsos.Add_TextChanged({ try { & $revisarCarpetas } catch {} })
    $a.AsVms.Add_TextChanged({ try { & $revisarCarpetas } catch {} })
    $a.BtnAsIsos.Add_Click({ Elegir-Carpeta $a.AsIsos 'Carpeta donde tienes las ISO de los sistemas' $v })
    $a.BtnAsVms.Add_Click({ Elegir-Carpeta $a.AsVms 'Carpeta donde se guardarán las máquinas virtuales' $v })

    # ------------------------------------------------ paso 3: usuario y contraseña
    $leerPw = {
        # (texto de las cajas, solo en memoria)
        if ($a.BtnAsVer.IsChecked) { return @($a.AsPw1Ver.Text, $a.AsPw2Ver.Text) }
        return @($a.AsPw1.Password, $a.AsPw2.Password)
    }
    $pintarRequisitos = {
        $uno, $dos = & $leerPw
        $luego = [bool]$a.AsPwLuego.IsChecked
        $conservar = ($pwYaGuardada -and -not $uno -and -not $dos)
        $pon = {
            param($caja, [bool]$bien, [string]$texto)
            $caja.Text = $(if ($bien) { ([string][char]0x2713) + '  ' } else { ([string][char]0x25CB) + '  ' }) + $texto
            $caja.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($bien) { 'T_acentoClaro' } else { 'T_textoSuave' }))
        }
        & $pon $a.AsReg1 ($uno.Length -ge 8) '8 o más caracteres'
        & $pon $a.AsReg2 (($uno -cmatch '[A-Z]') -and ($uno -cmatch '[a-z]') -and ($uno -match '\d')) 'Mayúsculas, minúsculas y números (Windows Server lo exige)'
        & $pon $a.AsReg3 ($uno.Length -gt 0 -and -not $uno.Contains("'")) "Sin comillas simples (')"
        & $pon $a.AsReg4 ($uno.Length -gt 0 -and $uno -ceq $dos) 'Las dos son iguales'
        $uno = $null; $dos = $null
        foreach ($rg in $a.AsReg1, $a.AsReg2, $a.AsReg3, $a.AsReg4) { $rg.Opacity = $(if ($luego) { 0.4 } else { 1 }) }
        foreach ($ct in $a.AsPw1, $a.AsPw1Ver, $a.AsPw2, $a.AsPw2Ver, $a.BtnAsVer) { $ct.IsEnabled = -not $luego }
        $a.AsPwActual.Visibility = $(if ($pwYaGuardada -and -not $luego) { 'Visible' } else { 'Collapsed' })
        $a.AsPwActual.Text = 'Ya hay una contraseña guardada en este PC. Déjalo en blanco para conservarla, o escribe una nueva para cambiarla.'
    }
    $a.AsPw1.Add_PasswordChanged({ & $pintarRequisitos })
    $a.AsPw2.Add_PasswordChanged({ & $pintarRequisitos })
    $a.AsPw1Ver.Add_TextChanged({ & $pintarRequisitos })
    $a.AsPw2Ver.Add_TextChanged({ & $pintarRequisitos })
    $a.AsPwLuego.Add_Click({ & $pintarRequisitos })
    $a.BtnAsVer.Add_Checked({
        $a.AsPw1Ver.Text = $a.AsPw1.Password; $a.AsPw2Ver.Text = $a.AsPw2.Password
        $a.AsPw1.Visibility = 'Collapsed'; $a.AsPw2.Visibility = 'Collapsed'
        $a.AsPw1Ver.Visibility = 'Visible'; $a.AsPw2Ver.Visibility = 'Visible'
    })
    $a.BtnAsVer.Add_Unchecked({
        $a.AsPw1.Password = $a.AsPw1Ver.Text; $a.AsPw2.Password = $a.AsPw2Ver.Text
        $a.AsPw1Ver.Text = ''; $a.AsPw2Ver.Text = ''
        $a.AsPw1Ver.Visibility = 'Collapsed'; $a.AsPw2Ver.Visibility = 'Collapsed'
        $a.AsPw1.Visibility = 'Visible'; $a.AsPw2.Visibility = 'Visible'
    })

    # ------------------------------------------------ paso 4: aspecto en vivo
    $indiceTema = { if ($script:temaActual -eq 'oscuro') { 1 } else { 0 } }
    $muestras = @{}
    $pintarMuestras = {
        $sob = [bool]$Config.Sobrio
        $ac = [string]$Config.Acento; if (-not $script:Acentos.Contains($ac)) { $ac = 'FullCowl' }
        foreach ($na in @($muestras.Keys)) {
            $rb = $muestras[$na]
            $rb.Background = Pincel-Fijo $(if ($sob) { '#5F6A72' } else { $script:Acentos[$na][(& $indiceTema)][0] })
            $rb.IsChecked = (($na -eq $ac) -and -not $sob)
            $rb.IsEnabled = -not $sob
        }
        & $colorearRayos
    }
    foreach ($na in @($script:Acentos.Keys)) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = [System.Windows.Application]::Current.FindResource('Muestra')
        $rb.GroupName = 'AsAcento'; $rb.DataContext = [string]$na; $rb.ToolTip = $script:NombresAcento[$na]
        $rb.Add_Click({
            param($s, $ev)
            try { Guardar-ConfigLocal @{ Acento = [string]$s.DataContext }; Aplicar-Tema (Tema-Efectivo); & $pintarMuestras } catch { Escribir-Log ("Asistente, acento: " + ($_ | Out-String)) }
        })
        [void]$a.AsMuestras.Children.Add($rb)
        $muestras[$na] = $rb
    }
    $ponerTema = {
        param([string]$modo)
        try { Guardar-ConfigLocal @{ Tema = $modo }; Aplicar-Tema (Tema-Efectivo); & $pintarMuestras } catch { Escribir-Log ("Asistente, tema: " + ($_ | Out-String)) }
    }
    $a.AsTemaClaro.Add_Click({ & $ponerTema 'Claro' })
    $a.AsTemaOscuro.Add_Click({ & $ponerTema 'Oscuro' })
    $a.AsTemaAuto.Add_Click({ & $ponerTema 'Automatico' })
    $a.AsSobrio.Add_Click({
        try { Guardar-ConfigLocal @{ Sobrio = [bool]$a.AsSobrio.IsChecked }; Aplicar-Tema (Tema-Efectivo); & $pintarMuestras } catch { Escribir-Log ("Asistente, sobrio: " + ($_ | Out-String)) }
    })
    $ponerAct = {
        param([string]$modo)
        try { Guardar-ConfigLocal @{ Actualizaciones = $modo } } catch {}
        & $pintarNotaAct
    }
    $a.AsActAvisar.Add_Click({ & $ponerAct 'Avisar' })
    $a.AsActSolo.Add_Click({ & $ponerAct 'Solo' })
    $a.AsActNo.Add_Click({ & $ponerAct 'No' })

    # ------------------------------------------------ paso 5: resumen
    $pintarResumen = {
        $nombre = $a.AsNombre.Text.Trim()
        if (-not $nombre) { $nombre = $env:USERNAME }
        $a.AsListoTitulo.Text = "Todo listo, $nombre"
        $a.AsResumen.Children.Clear()
        $fila = {
            param([string]$clave, [string]$valor)
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(130)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, 'Star')
            [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
            $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $clave; $t1.FontSize = 12.5
            Ref-Tema $t1 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
            $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = $valor; $t2.FontSize = 13; $t2.FontWeight = [System.Windows.FontWeights]::Medium; $t2.TextTrimming = 'CharacterEllipsis'
            Ref-Tema $t2 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
            [System.Windows.Controls.Grid]::SetColumn($t2, 1)
            [void]$g.Children.Add($t1); [void]$g.Children.Add($t2)
            [void]$a.AsResumen.Children.Add($g)
        }
        $ri = [string]$Config.CarpetaISOs; $nIsos = 0
        try { $nIsos = @(Get-ChildItem -LiteralPath $ri -Filter *.iso -ErrorAction SilentlyContinue).Count } catch {}
        & $fila 'ISOs' "$(Plural $nIsos 'ISO' 'ISOs') · $(Split-Path $ri -Leaf)"
        & $fila 'Máquinas' (Split-Path ([string]$Config.CarpetaVMs) -Leaf)
        & $fila 'Usuario' ([string]$Config.Usuario)
        & $fila 'Contraseña' $(if (Test-Path -LiteralPath $rutaPw) { 'Guardada, cifrada, solo en este PC' } else { 'La pondrás al crear tu primera máquina' })
        & $fila 'Packer' $(if (Obtener-Packer) { 'Instalado' } else { 'Falta (se necesita para crear bases)' })
        $tn = switch ([string]$Config.Tema) { 'Oscuro' { 'Oscuro' } 'Automatico' { 'Automático' } default { 'Claro' } }
        & $fila 'Aspecto' ($tn + $(if ([bool]$Config.Sobrio) { ' · modo sobrio' } else { ' · ' + $script:NombresAcento[$(if ($script:Acentos.Contains([string]$Config.Acento)) { [string]$Config.Acento } else { 'FullCowl' })] }))
        & $fila 'Actualizaciones' $(switch (Modo-Actualizaciones) { 'Solo' { 'Se actualiza sola' } 'No' { 'No busca' } default { 'Te avisa' } })
    }

    # ------------------------------------------------ navegación
    $paneles = @($a.Paso0, $a.Paso1, $a.Paso2, $a.Paso3, $a.Paso4, $a.Paso5)
    $mostrar = {
        param([int]$n)
        $estado.Paso = $n
        for ($k = 0; $k -lt $paneles.Count; $k++) { $paneles[$k].Visibility = $(if ($k -eq $n) { 'Visible' } else { 'Collapsed' }) }
        & $pintarPasos
        $a.BtnAsAtras.Visibility = $(if ($n -ge 1) { 'Visible' } else { 'Collapsed' })
        $a.BtnAsSiguiente.Visibility = $(if ($n -ge 1 -and $n -le 4) { 'Visible' } else { 'Collapsed' })
        $a.BtnAsSiguiente.Content = $(if ($n -eq 4) { 'Terminar' } else { 'Siguiente' })
        $a.AsPie.Text = $(switch ($n) { 0 { 'Son 4 pasos y tardas un par de minutos.' } 5 { 'Puedes cambiar todo esto cuando quieras en Ajustes.' } default { "Paso $n de 4" } })
        if ($n -eq 1) { & $pintarChecks }
        if ($n -eq 2) { & $revisarCarpetas }
        if ($n -eq 3) { & $pintarRequisitos }
        if ($n -eq 5) {
            & $pintarResumen
            # Cierre: se acaba el goteo y sale un último rayo
            if ($rayosAs) { try { $rayosAs.Goteo = $false; [void]$rayosAs.Chispazo($a.AsLogo) } catch { Escribir-Log ("Asistente, rayo final: " + $_.Exception.Message) } }
        } elseif ($rayosAs) { try { $rayosAs.Goteo = $true } catch {} }
    }

    $guardarPaso = {
        # Valida y guarda lo del paso actual. Devuelve $false si algo falta (y ya ha avisado)
        switch ([int]$estado.Paso) {
            1 {
                $falta = @(Estado-Pc (& $rutaParaDisco) | Where-Object { $_.Insignia -eq 'Necesario' -and -not $_.Ok } | ForEach-Object { $_.Nombre })
                if ($falta.Count) { Aviso "Antes de seguir hace falta: $($falta -join ' y ').`n`nInstálalo (Packer, con el botón; VMware, aparte) y pulsa «Volver a comprobar»." 'Falta algo necesario'; return $false }
                if ($estado.Instalando) { Aviso 'Espera a que termine la instalación.'; return $false }
            }
            2 {
                $ri = $a.AsIsos.Text.Trim(); $rv = $a.AsVms.Text.Trim()
                if (-not $ri -or -not (Test-Path -LiteralPath $ri -PathType Container)) { Aviso 'La carpeta de ISOs no existe. Elígela con «Examinar…».'; return $false }
                if (-not $rv) { Aviso 'Elige la carpeta de las máquinas.'; return $false }
                try { New-Item -ItemType Directory -Force -Path $rv | Out-Null } catch { Aviso "No se pudo crear la carpeta de máquinas:`n$($_.Exception.Message)"; return $false }
                # ¿Se puede escribir en ella?
                $prueba = Join-Path $rv ('.fc-prueba-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
                try { Set-Content -LiteralPath $prueba -Value 'x' -ErrorAction Stop; Remove-Item -LiteralPath $prueba -Force -ErrorAction SilentlyContinue }
                catch { Aviso "No se puede escribir en esa carpeta de máquinas. Elige otra donde tu usuario pueda crear archivos.`n`n$($_.Exception.Message)"; return $false }
                Guardar-ConfigLocal @{ CarpetaISOs = $ri; CarpetaVMs = $rv }
            }
            3 {
                $u = $a.AsUsuario.Text.Trim()
                if ($u -cnotmatch '^[a-z_][a-z0-9_-]{0,19}$') { Aviso 'Usuario no válido: minúsculas, números, guion o guion bajo (máximo 20), empezando por letra.'; return $false }
                if (-not $a.AsPwLuego.IsChecked) {
                    $uno, $dos = & $leerPw
                    if ($uno -or $dos -or -not $pwYaGuardada) {
                        $msg = ''
                        if (-not $uno) { $msg = 'Escribe la contraseña (o marca «Prefiero ponerla cuando cree mi primera máquina»).' }
                        elseif ($uno.Length -lt 8) { $msg = 'La contraseña tiene que tener 8 o más caracteres.' }
                        elseif (-not (($uno -cmatch '[A-Z]') -and ($uno -cmatch '[a-z]') -and ($uno -match '\d'))) { $msg = 'La contraseña necesita mayúsculas, minúsculas y números.' }
                        elseif ($uno.Contains("'")) { $msg = "La contraseña no puede llevar comillas simples (')." }
                        elseif ($uno -cne $dos) { $msg = 'Las dos contraseñas no coinciden.' }
                        $uno = $null; $dos = $null
                        if ($msg) { Aviso $msg; return $false }
                        try {
                            # De la caja a DPAPI: nunca en texto claro en ningún archivo
                            if ($a.BtnAsVer.IsChecked) { $a.BtnAsVer.IsChecked = $false }
                            $tmp = "$rutaPw.nuevo"
                            $a.AsPw1.SecurePassword | ConvertFrom-SecureString | Set-Content -LiteralPath $tmp
                            Move-Item -LiteralPath $tmp -Destination $rutaPw -Force
                            $script:pwGuardadaAsistente = $true
                        } catch { Aviso 'No se pudo guardar la contraseña.'; return $false }
                        $a.AsPw1.Clear(); $a.AsPw2.Clear()
                        $pwYaGuardada = $true
                    }
                    $uno = $null; $dos = $null
                }
                if ($u -cne $usuarioAntes -and $repetir) {
                    if (@(Obtener-Bases).Count) {
                        if (-not (Pregunta "¿Cambiar el usuario de «$usuarioAntes» a «$u»?`n`nSolo afecta a las bases nuevas. Las que ya tienes (y sus máquinas) siguen con su usuario; Full Cowl lo recuerda." 'Cambiar el usuario' 'Cambiar' 'Cancelar')) { return $false }
                        Marcar-UsuarioBases $usuarioAntes
                    }
                }
                Guardar-ConfigLocal @{ Usuario = $u }
                $usuarioAntes = $u
            }
            4 {
                try { Guardar-ConfigLocal @{ Nombre = $a.AsNombre.Text.Trim() } } catch {}
            }
        }
        return $true
    }

    $avanzar = {
        if ($estado.Paso -lt 1 -or $estado.Paso -gt 4) { return }
        if (-not (& $guardarPaso)) { return }
        & $mostrar ($estado.Paso + 1)
    }
    $retroceder = { if ($estado.Paso -ge 1) { & $mostrar ($estado.Paso - 1) } }
    $a.BtnAsEmpezar.Add_Click({ & $mostrar 1 })
    $a.BtnAsSiguiente.Add_Click({ & $avanzar })
    $a.BtnAsAtras.Add_Click({ & $retroceder })
    $a.BtnAsRecomprobar.Add_Click({ $a.AsInstalarTexto.Text = ''; & $pintarChecks })
    $v.Add_KeyDown({
        param($s, $ev)
        if ($ev.Key -eq [System.Windows.Input.Key]::Escape) { & $retroceder; $ev.Handled = $true }
    })

    $terminar = {
        param([string]$destino)
        $estado.Destino = $destino
        $estado.Terminado = $true
        try { Guardar-ConfigLocal @{ AsistenteHecho = $true } } catch {}
        $v.Close()
    }
    $a.BtnAsBase.Add_Click({ & $terminar 'base' })
    $a.BtnAsImportar.Add_Click({ & $terminar 'importar' })
    $a.BtnAsInicio.Add_Click({ & $terminar 'inicio' })
    $v.Add_Closing({
        param($s, $ev)
        if ($estado.Instalando) {
            if (-not (Pregunta 'Se está instalando algo. Si cierras ahora, la instalación sigue por su cuenta.' 'Instalando' 'Cerrar igualmente' 'Esperar')) { $ev.Cancel = $true; return }
        }
        # Cerrar en el último paso cuenta como terminar (el asistente ya no vuelve a salir)
        if ($estado.Paso -eq 5 -and -not $estado.Terminado) { $estado.Terminado = $true; $estado.Destino = 'inicio'; try { Guardar-ConfigLocal @{ AsistenteHecho = $true } } catch {} }
    })

    # Carpeta y dueño: al abrir, si hace falta, que salga delante
    & $pintarMuestras
    & $pintarRequisitos
    & $mostrar 0
    $estado.Cargando = $false
    [void]$v.ShowDialog()
    try { $relojInst.Stop() } catch {}
    if ($rayosAs) { try { $rayosAs.Permitido = $false } catch {} }
    return @{ Terminado = [bool]$estado.Terminado; Destino = [string]$estado.Destino }
}
