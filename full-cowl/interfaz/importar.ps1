# =====================================================================
#  Interfaz nueva: página «Importar»
#  Lanza importar.ps1 en una consola aparte y enseña su progreso, que lee de
#  estado\importar.json cada 2 segundos (igual que «Crear base»).
# =====================================================================

$script:lanzandoImp = $false
$script:impAbajo = $false
$script:cacheOrigenImp = @{ Ruta = ''; Tam = 0.0 }
$script:cacheComprobImp = @{ Hora = [datetime]::MinValue; Pass = $false }
$archivoEstadoImp = Join-Path $dirEstadoFc 'importar.json'

function Nota-Imp([string]$texto, [string]$color = '') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $texto; $t.TextWrapping = 'Wrap'; $t.FontSize = 13; $t.LineHeight = 20
    $t.Margin = New-Object System.Windows.Thickness(0, 0, 0, 9)
    $t.Foreground = Pincel $(if ($color) { $color } else { $Colores.Texto })
    [void]$ImpNotas.Items.Add($t)
}

function Pintar-NotasImp {
    $ImpNotas.Items.Clear()
    Nota-Imp '•  Se importa una máquina COMPLETA e independiente: no depende de ninguna base, así que sirve para pasar máquinas de un Full Cowl a otro.'
    Nota-Imp '•  Vale un .ova o .ovf (lo que saca «Exportar»), un .zip o .7z con la carpeta de la máquina, o la carpeta misma con su .vmx.'
    Nota-Imp '•  Los clones ENLAZADOS no se pueden importar (dependen de su base). En el Full Cowl de origen, expórtalos con «Exportar»: salen completos.'
    Nota-Imp '•  Hace falta sitio libre en el disco de las máquinas (un .ova suele ocupar el doble al importarlo).'
    Nota-Imp '•  La máquina entra con la contraseña que tuviera. Si no es la de este PC, enciéndela y úsala con normalidad, pero Full Cowl no podrá entrar en ella (Usuarios, Red, Archivos).'
    Nota-Imp '•  No hace falta apagar nada de este PC. La máquina original no se toca.'
    Nota-Imp '•  Si cierras Full Cowl, la importación sigue en su consola. No cierres esa consola: cancelaría la importación.' $Colores.Aviso
}

function Entrar-Importar {
    Pintar-NotasImp
    if (-not $ImpUsuario.Text) { $ImpUsuario.Text = [string]$Config.Usuario }
    Actualizar-ProgresoImp
    Actualizar-ResumenImp
}

function Proponer-NombreImp {
    # Nombre sugerido a partir del archivo o la carpeta (sin repetir uno que ya exista)
    $o = $ImpOrigen.Text.Trim()
    if (-not $o) { return }
    $b = [IO.Path]::GetFileNameWithoutExtension($o.TrimEnd('\'))
    if (Test-Path -LiteralPath $o -PathType Container) { $b = Split-Path $o.TrimEnd('\') -Leaf }
    $b = ($b -replace '[^\p{L}\p{Nd} ._()-]', '-').Trim(' ', '.', '-')
    if (-not $b) { return }
    $cand = $b; $n = 2
    while ($Config.CarpetaVMs -and (Test-Path -LiteralPath (Join-Path $Config.CarpetaVMs $cand))) { $cand = "$b ($n)"; $n++ }
    $ImpNombre.Text = $cand
}

function Revisar-NombreImp {
    $n = $ImpNombre.Text.Trim()
    if (-not $n) { $ImpNombreNota.Text = ''; return }
    $motivo = Validar-NombreMaquina $n
    if ($motivo) { $ImpNombreNota.Text = $motivo; $ImpNombreNota.Foreground = Pincel $Colores.Error }
    else { $ImpNombreNota.Text = 'Nombre libre.'; $ImpNombreNota.Foreground = Pincel $Colores.Ok }
}
$ImpNombre.Add_TextChanged({ try { Revisar-NombreImp } catch {} })

function Elegir-OrigenImp([string]$ruta) {
    # Un .vmx suelto significa «la carpeta que lo contiene»
    $ruta = $ruta.Trim().Trim('"')
    if (-not $ruta) { return }
    if ($ruta -like '*.vmx' -and (Test-Path -LiteralPath $ruta -PathType Leaf)) { $ruta = Split-Path $ruta }
    $ImpOrigen.Text = $ruta
    Proponer-NombreImp
}

function Elegir-ArchivoImp {
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Title = 'Elige la máquina a importar'
    $d.Filter = 'Máquinas virtuales (*.ova;*.ovf;*.zip;*.7z;*.vmx)|*.ova;*.ovf;*.zip;*.7z;*.vmx|Todos los archivos (*.*)|*.*'
    if ($d.ShowDialog($script:ventana)) { Elegir-OrigenImp $d.FileName }
}
$BtnImpArchivo.Add_Click({ Elegir-ArchivoImp })
$BtnImpCarpeta.Add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Elige la carpeta de la máquina (la que tiene el .vmx)'
    $fb.ShowNewFolderButton = $false
    $duena = New-Object System.Windows.Forms.NativeWindow
    try {
        $duena.AssignHandle((New-Object System.Windows.Interop.WindowInteropHelper($script:ventana)).Handle)
        if ($fb.ShowDialog($duena) -eq 'OK') { $ImpOrigen.Text = $fb.SelectedPath; Proponer-NombreImp }
    } finally { $duena.ReleaseHandle(); $fb.Dispose() }
})

function Importar-Maquina {
    $origen = $ImpOrigen.Text.Trim()
    $nombre = $ImpNombre.Text.Trim()
    if (-not $Config.CarpetaVMs) { Aviso 'Elige primero la carpeta de máquinas en Ajustes.'; return }
    if (-not $origen -or -not (Test-Path -LiteralPath $origen)) { Aviso 'Elige un archivo o una carpeta que exista (botones «Archivo…» o «Carpeta…»).'; return }
    $esCarpeta = Test-Path -LiteralPath $origen -PathType Container
    $ext = [IO.Path]::GetExtension($origen).TrimStart('.').ToLower()
    if (-not $esCarpeta -and @('ova', 'ovf', 'zip', '7z') -notcontains $ext) { Aviso "No sé importar archivos .$ext. Elige un .ova, .ovf, .zip, .7z o una carpeta con un .vmx."; return }
    $motivo = Validar-NombreMaquina $nombre
    if ($motivo) { Aviso $motivo; return }
    $usuario = $ImpUsuario.Text.Trim()
    if ($usuario -and $usuario -cnotmatch '^[a-z_][a-z0-9_-]{0,19}$') { Aviso 'El usuario tiene que ir en minúsculas, sin espacios ni acentos (por ejemplo: alumno).'; return }
    $est = Leer-EstadoImp
    if ($est -and [string]$est.estado -eq 'curso' -and $est.pid -and (Get-Process -Id ([int]$est.pid) -ErrorAction SilentlyContinue)) {
        Aviso 'Ya hay una importación en marcha. Espera a que termine o cancélala.'; return
    }
    if (-not $ImpMismaClave.IsChecked) {
        if (-not (Pregunta "Si su contraseña no es la de las máquinas de este PC, la máquina se importa igual, pero Full Cowl no podrá entrar en ella (crear usuarios, cambiar la red, pasar archivos).`n`n¿Importar igualmente?" 'Contraseña distinta' 'Importar')) { return }
    }
    $pedido = [ordered]@{ origen = $origen; nombre = $nombre; usuario = $usuario; mismaClave = [bool]$ImpMismaClave.IsChecked }
    Remove-Item $archivoEstadoImp -Force -ErrorAction SilentlyContinue
    Lanzar 'importar.ps1' $pedido
    $script:lanzandoImp = $true
    Poner-ProgresoImp 0 $Colores.Verde
    $ImpPct.Text = '0 %'; $ImpTiempo.Text = ''
    $ImpProgTexto.Foreground = Pincel $Colores.Texto
    $ImpProgTexto.Text = "$nombre  ·  empezando"
    $ImpProgDet.Text = 'El detalle completo sale en la consola que se ha abierto.'
    Mostrar-Toast "Importando «$nombre»: el progreso sale aquí y en la consola que se ha abierto."
}
$BtnImportar.Add_Click({ Importar-Maquina })

# ---------------------------------------------------------------- zona de soltar, ficha y resumen
function Info-OrigenImp {
    $o = $ImpOrigen.Text.Trim()
    $i = @{ Ruta = $o; Existe = $false; EsCarpeta = $false; Ext = ''; Tam = 0.0; VmxOk = $true; Leaf = '' }
    if (-not $o -or -not (Test-Path -LiteralPath $o -ErrorAction SilentlyContinue)) { return $i }
    $i.Existe = $true; $i.Leaf = Split-Path $o.TrimEnd('\') -Leaf
    $i.EsCarpeta = Test-Path -LiteralPath $o -PathType Container
    if ($i.EsCarpeta) {
        if ($script:cacheOrigenImp.Ruta -ne $o) { $script:cacheOrigenImp = @{ Ruta = $o; Tam = [double](Tamano-Carpeta $o) } }
        $i.Tam = $script:cacheOrigenImp.Tam
        $v = @(Get-ChildItem -LiteralPath $o -Filter *.vmx -File -ErrorAction SilentlyContinue)
        if (-not $v.Count) { foreach ($sub in @(Get-ChildItem -LiteralPath $o -Directory -ErrorAction SilentlyContinue)) { $v += @(Get-ChildItem -LiteralPath $sub.FullName -Filter *.vmx -File -ErrorAction SilentlyContinue) } }
        $i.VmxOk = ($v.Count -ge 1)
    } else {
        $i.Ext = [IO.Path]::GetExtension($o).TrimStart('.').ToLower()
        try { $i.Tam = [double](Get-Item -LiteralPath $o).Length } catch {}
    }
    return $i
}

function Texto-TipoImp($i) {
    if ($i.EsCarpeta) { return 'Carpeta de máquina' }
    switch ($i.Ext) { 'ova' { return 'Exportación .ova' } 'ovf' { return 'Exportación .ovf' } 'zip' { return 'Archivo .zip' } '7z' { return 'Archivo .7z' } default { return "Archivo .$($i.Ext)" } }
}

function Actualizar-FichaImp {
    $i = Info-OrigenImp
    $ImpZonaVacia.Visibility = $(if ($i.Existe) { 'Collapsed' } else { 'Visible' })
    $ImpZonaFicha.Visibility = $(if ($i.Existe) { 'Visible' } else { 'Collapsed' })
    $ImpZona.Cursor = $(if ($i.Existe) { [System.Windows.Input.Cursors]::Arrow } else { [System.Windows.Input.Cursors]::Hand })
    if ($i.Existe) {
        $ImpFichaGlifo.Text = $(if ($i.EsCarpeta) { Glifo 0xE8B7 } else { Glifo 0xE7C3 })
        $ImpFichaNombre.Text = $i.Leaf
        $ImpFichaSub.Text = (Texto-TipoImp $i) + $(if ($i.Tam -gt 0) { '  ·  ' + (Formato-Tamano $i.Tam) } else { '' })
    }
}

function Actualizar-ResumenImp {
    try {
        $i = Info-OrigenImp
        $nombre = $ImpNombre.Text.Trim()
        $motivo = $(if ($nombre) { Validar-NombreMaquina $nombre } else { 'Falta el nombre de la máquina.' })
        $usuario = $ImpUsuario.Text.Trim()
        $userMal = ($usuario -and $usuario -cnotmatch '^[a-z_][a-z0-9_-]{0,19}$')
        $extOk = ($i.EsCarpeta -or @('ova', 'ovf', 'zip', '7z') -contains $i.Ext)
        $ImpResLineas.Children.Clear()
        [void]$ImpResLineas.Children.Add((Fila-Resumen 'Origen' $(if ($i.Existe) { $i.Leaf } else { '—' })))
        [void]$ImpResLineas.Children.Add((Fila-Resumen 'Tipo' $(if ($i.Existe) { Texto-TipoImp $i } else { '—' })))
        [void]$ImpResLineas.Children.Add((Fila-Resumen 'Tamaño' $(if ($i.Existe -and $i.Tam -gt 0) { Formato-Tamano $i.Tam } else { '—' })))
        [void]$ImpResLineas.Children.Add((Fila-Resumen 'Nombre' $(if ($nombre) { $nombre } else { '—' })))
        [void]$ImpResLineas.Children.Add((Fila-Resumen 'Usuario' $(if ($usuario) { $usuario } else { 'El que traiga' })))
        [void]$ImpResLineas.Children.Add((Fila-Resumen 'Contraseña' $(if ($ImpMismaClave.IsChecked) { 'La de este PC' } else { 'Distinta' })))

        $est = $(if ($i.Existe -and -not $i.EsCarpeta -and @('ova', 'ovf') -contains $i.Ext) { 'Un .ova o .ovf se convierte al importarlo: puede tardar bastante.' } elseif ($i.Existe -and -not $i.EsCarpeta) { 'Se descomprime en la carpeta de máquinas.' } else { 'Se copia la carpeta a la de máquinas de este PC.' })
        $ultima = $null
        try { $ultima = Ultimo-Tiempo 'importar' '' } catch {}
        if ($ultima) { $est += "`nLa última vez en este PC: $ultima." }
        $ImpResEstimacion.Text = $est

        $falta = ''
        if (-not $ImpOrigen.Text.Trim()) { $falta = 'Falta elegir qué importar.' }
        elseif (-not $i.Existe) { $falta = 'Ese archivo o carpeta no existe.' }
        elseif (-not $extOk) { $falta = "No sé importar archivos .$($i.Ext)." }
        elseif ($i.EsCarpeta -and -not $i.VmxOk) { $falta = 'En esa carpeta no hay ningún .vmx.' }
        elseif ($motivo) { $falta = $motivo }
        elseif ($userMal) { $falta = 'El usuario tiene que ir en minúsculas, sin espacios ni acentos.' }
        $ImpResAviso.Text = $falta
        $ImpResAviso.Visibility = $(if ($falta) { 'Visible' } else { 'Collapsed' })

        if (([datetime]::Now - $script:cacheComprobImp.Hora).TotalSeconds -gt 15) {
            $script:cacheComprobImp.Pass = (Test-Path (Join-Path $dirFc 'password.sec'))
            $script:cacheComprobImp.Hora = [datetime]::Now
        }
        $ImpResChecks.Children.Clear()
        [void]$ImpResChecks.Children.Add((Fila-Comprobacion ($i.Existe -and $extOk -and ($i.VmxOk)) 'Origen elegido y válido' 'Elige un .ova, .ovf, .zip, .7z o una carpeta con un .vmx.'))
        [void]$ImpResChecks.Children.Add((Fila-Comprobacion (-not $motivo) $(if ($nombre) { 'Nombre válido y libre' } else { 'Nombre elegido' }) $(if ($motivo) { $motivo } else { '' })))
        $libre = -1.0
        try { $libre = ([IO.DriveInfo]([IO.Path]::GetPathRoot([string]$Config.CarpetaVMs))).AvailableFreeSpace / 1GB } catch {}
        if ($libre -ge 0) {
            $factor = $(if ($i.Existe -and -not $i.EsCarpeta -and @('ova', 'ovf') -contains $i.Ext) { 2.2 } else { 1.1 })
            $hace = [Math]::Ceiling(($i.Tam / 1GB) * $factor + 1)
            [void]$ImpResChecks.Children.Add((Fila-Comprobacion ($libre -ge $hace) "Espacio libre: $([int]$libre) GB (hacen falta unos $hace)" 'Libera espacio o cambia la carpeta de máquinas en Ajustes → Este PC.'))
        }
        [void]$ImpResChecks.Children.Add((Fila-Comprobacion $script:cacheComprobImp.Pass 'Contraseña de las máquinas guardada' 'Se te pedirá al empezar (se guarda cifrada).'))
    } catch { Escribir-Log ("Resumen de Importar: " + ($_ | Out-String)) }
}

function Colocar-ResumenImp {
    try {
        $ancho = $PaginaImp.ActualWidth
        if ($ancho -lt 50) { return }
        $abajo = ($ancho -lt 1000)
        if ($abajo -eq $script:impAbajo) { return }
        $script:impAbajo = $abajo
        $ImpResHost.Content = $null
        [void]$ImpPila.Children.Remove($ImpResTarjeta)
        if ($abajo) {
            $ImpResTarjeta.Margin = New-Object System.Windows.Thickness(0, 0, 0, 18)
            $ImpPila.Children.Insert([Math]::Max(0, $ImpPila.Children.Count - 1), $ImpResTarjeta)
            $ImpResHost.Visibility = 'Collapsed'
            $ImpColRes.Width = New-Object System.Windows.GridLength(0); $ImpColGap.Width = New-Object System.Windows.GridLength(0)
        } else {
            $ImpResTarjeta.Margin = New-Object System.Windows.Thickness(0, 2, 0, 28)
            $ImpResHost.Content = $ImpResTarjeta
            $ImpResHost.Visibility = 'Visible'
            $ImpColRes.Width = New-Object System.Windows.GridLength(300); $ImpColGap.Width = New-Object System.Windows.GridLength(18)
        }
    } catch { Escribir-Log ("Colocar resumen de Importar: " + ($_ | Out-String)) }
}

# Soltar archivos o carpetas sobre la zona
$ImpZona.Add_DragEnter({ param($s, $a)
    try { $a.Effects = [System.Windows.DragDropEffects]::Copy; Ref-Tema $ImpZonaBorde ([System.Windows.Shapes.Shape]::StrokeProperty) 'T_acento' } catch {}
    $a.Handled = $true })
$ImpZona.Add_DragOver({ param($s, $a)
    try { $a.Effects = [System.Windows.DragDropEffects]::Copy } catch {}
    $a.Handled = $true })
$ImpZona.Add_DragLeave({ param($s, $a) try { Ref-Tema $ImpZonaBorde ([System.Windows.Shapes.Shape]::StrokeProperty) 'T_borde' } catch {} })
$ImpZona.Add_Drop({ param($s, $a)
    try {
        Ref-Tema $ImpZonaBorde ([System.Windows.Shapes.Shape]::StrokeProperty) 'T_borde'
        $ficheros = $a.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($ficheros -and @($ficheros).Count) {
            if (([string]@($ficheros)[0]).ToLower().EndsWith('.fclab')) { Importar-Fclab ([string]@($ficheros)[0]); $a.Handled = $true; return }   # (una receta de laboratorio, no una máquina)
            if (@($ficheros).Count -gt 1) { Mostrar-Toast 'Se importa una máquina cada vez: he cogido la primera.' 'info' }
            Elegir-OrigenImp ([string]@($ficheros)[0])
        }
    } catch { Escribir-Log ("Soltar en Importar: " + ($_ | Out-String)) }
    $a.Handled = $true })
$ImpZona.Add_MouseLeftButtonUp({ param($s, $a) if ($ImpZonaVacia.Visibility -eq 'Visible') { Elegir-ArchivoImp } })
$BtnImpQuitar.Add_Click({ $ImpOrigen.Text = ''; $ImpNombre.Text = '' })

$ImpOrigen.Add_TextChanged({ try { Actualizar-FichaImp; Actualizar-ResumenImp } catch { Escribir-Log ("Importar: " + ($_ | Out-String)) } })
$ImpNombre.Add_TextChanged({ Actualizar-ResumenImp })
$ImpUsuario.Add_TextChanged({ Actualizar-ResumenImp })
$ImpMismaClave.Add_Click({ Actualizar-ResumenImp })
$PaginaImp.Add_SizeChanged({ Colocar-ResumenImp })
$BtnImportar2.Add_Click({ Importar-Maquina })

# ---------------------------------------------------------------- progreso
function Leer-EstadoImp {
    if (-not (Test-Path $archivoEstadoImp)) { return $null }
    $fi = Get-Item $archivoEstadoImp
    if ($fi.LastWriteTime -lt (Get-Date).AddHours(-12)) { return $null }
    try { $est = [IO.File]::ReadAllText($fi.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
    if ($est -is [psobject] -and $est.estado -and $est.inicio) { return $est }
    return $null
}

function Poner-ProgresoImp([double]$pct, [string]$color) {
    $ImpBarra.Foreground = Pincel $color
    $an = New-Object System.Windows.Media.Animation.DoubleAnimation
    $an.To = $pct
    $an.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(200))
    $suave = New-Object System.Windows.Media.Animation.CubicEase
    $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $an.EasingFunction = $suave
    $ImpBarra.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $an)
    Brillo-Barra $ImpBarra $pct $color
}

$BtnImpCancelar.Add_Click({
    $est = Leer-EstadoImp
    if (-not $est -or [string]$est.estado -ne 'curso') { return }
    if (-not (Pregunta "¿Cancelar la importación de «$($est.nombre)»?`n`nSe borrará lo que se haya copiado. La máquina original no se toca." 'Cancelar importación' 'Cancelar la importación' 'Seguir importando' 'BotonRojo')) { return }
    try { [IO.File]::WriteAllText((Join-Path $dirEstadoFc 'importar.abortar'), (Get-Date).ToString('o')) }
    catch { Error-Msg "No se pudo pedir la cancelación: $_"; return }
    $BtnImpCancelar.IsEnabled = $false
    $ImpProgDet.Text = 'Cancelando: parando la copia y borrando lo copiado…'
})

function Actualizar-ProgresoImp {
    $est = Leer-EstadoImp
    if (-not $est) {
        $BtnImpCancelar.Visibility = 'Collapsed'
        $NavImportar.Content = 'Importar'
        if (-not $script:lanzandoImp) {
            $ImpProgTexto.Foreground = Pincel $Colores.Texto
            $ImpProgTexto.Text = 'Sin importaciones recientes.'
            $ImpTiempo.Text = ''; $ImpPct.Text = ''; $ImpProgDet.Text = ''
            Poner-ProgresoImp 0 $Colores.Verde
        }
        return
    }
    $script:lanzandoImp = $false
    $estadoI = [string]$est.estado
    $pct = [double]$est.pct
    $ahora = Get-Date
    if ($estadoI -eq 'curso') {
        if ([double]$est.hasta -gt $pct -and [double]$est.esperadoSeg -gt 0 -and $est.inicioFase) {
            $trans = ($ahora - [datetime]$est.inicioFase).TotalSeconds
            $pct = $pct + ([double]$est.hasta - $pct) * [Math]::Min(0.95, $trans / [double]$est.esperadoSeg)
        }
        if ($est.pid -and -not (Get-Process -Id ([int]$est.pid) -ErrorAction SilentlyContinue)) { $estadoI = 'interrumpida' }
    }
    $pct = [Math]::Min(100, [Math]::Max(0, $pct))
    $ImpPct.Text = "$([int]$pct) %"
    $fin = if ($estadoI -ne 'curso' -and $est.actualizado) { [datetime]$est.actualizado } else { $ahora }
    $ImpTiempo.Text = "Tiempo: $(Formato-Tiempo ($fin - [datetime]$est.inicio).TotalSeconds)"
    $cancelando = ($estadoI -eq 'curso') -and (Test-Path (Join-Path $dirEstadoFc 'importar.abortar'))
    $BtnImpCancelar.Visibility = $(if ($estadoI -eq 'curso') { 'Visible' } else { 'Collapsed' })
    $BtnImpCancelar.IsEnabled = -not $cancelando
    $NavImportar.Content = $(if ($estadoI -eq 'curso') { "Importar  ·  $([int]$pct) %" } else { 'Importar' })
    switch ($estadoI) {
        'curso' {
            Marcar-Tarea "importar|$($est.nombre)|$($est.inicio)"
            Poner-ProgresoImp $pct $Colores.Verde
            $ImpProgTexto.Foreground = Pincel $Colores.Texto
            $ImpProgTexto.Text = "$($est.nombre)  ·  $($est.paso)"
            $ImpProgDet.Text = $(if ($cancelando) { 'Cancelando: parando la copia y borrando lo copiado…' } else { 'El detalle completo sale en la consola. No la cierres hasta que termine.' })
        }
        'cancelada' {
            Poner-ProgresoImp $pct $Colores.Suave
            $ImpProgTexto.Foreground = Pincel $Colores.Aviso
            $ImpProgTexto.Text = "$($est.nombre)  ·  cancelada en: $($est.paso)"
            $ImpProgDet.Text = $(if ($est.mensaje) { [string]$est.mensaje } else { 'Lo copiado se ha borrado. Puedes volver a importar cuando quieras.' })
        }
        'ok' {
            Apuntar-Tiempo "importar|$($est.nombre)|$($est.inicio)" 'importar' ([string]$est.nombre) '' ($fin - [datetime]$est.inicio).TotalSeconds 'ok'
            Tarea-Terminada "importar|$($est.nombre)|$($est.inicio)" "«$([string]$est.nombre)» importada" $NavMaq ($fin - [datetime]$est.inicio).TotalSeconds
            Poner-ProgresoImp 100 $Colores.Ok
            $ImpProgTexto.Foreground = Pincel $Colores.Ok
            $ImpProgTexto.Text = "$($est.nombre)  ·  importada"
            $texto = "Terminó el $($fin.ToString('dd/MM')) a las $($fin.ToString('HH:mm')), en $(Formato-Tiempo ($fin - [datetime]$est.inicio).TotalSeconds). Ya sale en «Mis máquinas»."
            if ($est.mensaje) { $texto += "  " + [string]$est.mensaje }
            $ImpProgDet.Text = $texto
        }
        'error' {
            Poner-ProgresoImp $pct $Colores.Error
            $ImpProgTexto.Foreground = Pincel $Colores.Error
            $ImpProgTexto.Text = "$($est.nombre)  ·  ha fallado en: $($est.paso)"
            $ImpProgDet.Text = ([string]$est.mensaje -replace '\s+', ' ')
        }
        default {
            Poner-ProgresoImp $pct $Colores.Error
            $ImpProgTexto.Foreground = Pincel $Colores.Error
            $ImpProgTexto.Text = "$($est.nombre)  ·  interrumpida en: $($est.paso)"
            $ImpProgDet.Text = 'La consola se cerró antes de terminar. Si ha quedado una carpeta a medias en la carpeta de máquinas, bórrala.'
        }
    }
}

$relojImp = New-Object System.Windows.Threading.DispatcherTimer
$relojImp.Interval = [TimeSpan]::FromSeconds(2)
$relojImp.Add_Tick({ try { Actualizar-ProgresoImp } catch {} })
