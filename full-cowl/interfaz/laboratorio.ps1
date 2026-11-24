# =====================================================================
#  Interfaz nueva: página «Laboratorio»
#  Antes era una pestaña de la ventana de siempre (gui.ps1, quitada en la 2.0): varias
#  máquinas de golpe, en la misma red y, si quieres, con su dominio. Lanza
#  laboratorio.ps1 y enseña el progreso de cada laboratorio.
# =====================================================================

$archivoPlantillasLab = Join-Path $dirFc 'plantillas-laboratorio.json'
$script:filasLab = New-Object System.Collections.ArrayList     # cada fila: @{ base; nombre; ram; cpus; vram }
$script:dcLab = $null                                           # la fila elegida como controlador de dominio
$script:opcRedLab = New-Object System.Collections.ArrayList
$script:basesLab = @()
$script:plantillasLab = @()
$textoNuevoSeg = 'Nuevo segmento LAN…'
$ramPC = 0
try { $ramPC = [double](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory } catch {}
$abrevBase = @{ WinServer2025 = 'WS25'; Ubuntu2604 = 'UBU26'; Ubuntu2604Desk = 'UBD26'; WinServer2022 = 'WS22'; WinServer2019 = 'WS19'; Win10Pro = 'W10'; Win11Pro = 'W11'; Ubuntu2404 = 'UBU24'
                Ubuntu2404Desk = 'UBD24'; Lubuntu2404 = 'LUB24'; Ubuntu2204 = 'UBU22'; Ubuntu2204Desk = 'UBD22'; Kali = 'KALI'; ParrotHome = 'PARHOME' }
$vramDefLab = if ($null -ne $Config.VRAM_MB) { [int]$Config.VRAM_MB } else { 1024 }
$LabVram.Text = [string]$vramDefLab

function Base-PorNombreLab($n) { return ($script:basesLab | Where-Object { $_.Nombre -eq $n } | Select-Object -First 1) }

function Nombre-LabLibre {
    # LAB1, LAB2... el primero que no se use en ninguna carpeta de máquinas
    for ($k = 1; $k -lt 1000; $k++) {
        $n = "LAB$k"
        if (-not (Get-ChildItem $Config.CarpetaVMs -Directory -Filter "$n-*" -ErrorAction SilentlyContinue)) { return $n }
    }
    return 'LAB'
}

function Nombre-MaquinaLab($base) {
    $lab = $LabNombre.Text.Trim(); if (-not $lab) { $lab = 'LAB' }
    $ab = if ($abrevBase.ContainsKey($base)) { $abrevBase[$base] } else { ($base -replace '[^A-Za-z0-9]', '').ToUpper() }
    $usados = @($script:filasLab | ForEach-Object { $_.nombre })
    for ($k = 1; $k -lt 100; $k++) {
        $n = "$lab-$ab-$k"
        if ($usados -notcontains $n -and -not (Test-Path (Join-Path $Config.CarpetaVMs $n))) { return $n }
    }
    return "$lab-$ab-$(Get-Random -Maximum 999)"
}

function Puede-SerDc($fila) { $b = Base-PorNombreLab $fila.base; return [bool]($b -and $b.EsWindows -and $b.EsServidor) }

function Dc-Lab {
    # El controlador: el que se marcó (si sigue en la lista y es un Windows Server); si no, el primer Windows Server
    if ($script:dcLab -and @($script:filasLab | Where-Object { $_ -eq $script:dcLab }).Count -and (Puede-SerDc $script:dcLab)) { return $script:dcLab }
    $script:dcLab = $null
    foreach ($fila in $script:filasLab) { if (Puede-SerDc $fila) { return $fila } }
    return $null
}

function Orden-Lab {
    # Filas con su papel en el dominio; el controlador primero (recibe la primera IP)
    $conDom = [bool]$LabConDominio.IsChecked
    $dc = if ($conDom) { Dc-Lab } else { $null }
    $r = @()
    foreach ($fila in $script:filasLab) {
        $b = Base-PorNombreLab $fila.base
        $papel = ''
        if ($conDom) {
            if ($dc -and $fila -eq $dc) { $papel = 'dc' }
            elseif ($b -and $b.EsWindows) { $papel = 'miembro' }
            else { $papel = 'fuera' }
        }
        $r += [pscustomobject]@{ Fila = $fila; Papel = $papel }
    }
    return @(@($r | Where-Object { $_.Papel -eq 'dc' }) + @($r | Where-Object { $_.Papel -ne 'dc' }))
}

function Refrescar-Lab {
    # (al cambiar algunas casillas desde aquí se vuelve a llamar sola: se evita dar vueltas)
    if ($script:refrescandoLab) { return }
    $script:refrescandoLab = $true
    try { Refrescar-LabAhora } finally { $script:refrescandoLab = $false }
}

function Refrescar-LabAhora {
    # Un dominio necesita IP fija
    if ($LabConDominio.IsChecked) { $LabFija.IsChecked = $true; $LabDhcp.IsEnabled = $false } else { $LabDhcp.IsEnabled = $true }
    $LabIpCampos.IsEnabled = [bool]$LabFija.IsChecked
    $LabDominioCampos.IsEnabled = [bool]$LabConDominio.IsChecked
    $orden = @(Orden-Lab)
    $ipBase = $null
    if ($LabFija.IsChecked -and (Es-IPv4 $LabIp.Text.Trim())) { $ipBase = $LabIp.Text.Trim().Split('.') }
    $elegidas = @($LabLista.SelectedItems | ForEach-Object { $_.Datos })
    $vistas = New-Object 'System.Collections.Generic.List[object]'
    for ($k = 0; $k -lt $orden.Count; $k++) {
        $o = $orden[$k]; $fila = $o.Fila
        $b = Base-PorNombreLab $fila.base
        $v = New-Object FullCowlWpf.FilaLab
        $v.Datos = $fila
        $v.Nombre = [string]$fila.nombre
        $v.Detalle = "$($fila.base)  ·  $($fila.ram) MB  ·  $(Plural ([int]$fila.cpus) 'CPU' 'CPUs')  ·  $(if ([int]$fila.vram -gt 0) { "vídeo $($fila.vram) MB" } else { 'sin 3D' })"
        $fam = if ($b) { [string]$b.Familia } else { '' }
        $estilo = Estilo-Icono $fam
        $v.IconoGlifo = $estilo[0]; $v.IconoFondo = $estilo[1]
        $falsa = [pscustomobject]@{ Familia = $fam; Nombre = $fila.nombre; Base = $fila.base; Vmx = $(if ($b) { $b.Vmx } else { '' }); EsBase = $true }
        $sis = Sistema-DeMaquina $falsa
        if ($sis) { Poner-Simbolo $v $sis }
        else {
            $logo = Logo-DeMaquina $falsa
            if ($logo) { $v.IconoLogo = $logo; $v.IconoGlifo = '' }
        }
        switch ($o.Papel) {
            'dc'      { $v.PapelTexto = 'Controlador de dominio'; $v.PapelColor = Hex-Tema '#2D6A3E'; $v.PapelFondo = Hex-Tema '#E3F1E7' }
            'miembro' { $v.PapelTexto = 'Cliente del dominio'; $v.PapelColor = Hex-Tema '#14231A'; $v.PapelFondo = Hex-Tema '#EEF2EF' }
            'fuera'   { $v.PapelTexto = 'Fuera del dominio'; $v.PapelColor = Hex-Tema '#5F6F65'; $v.PapelFondo = Hex-Tema '#EEF2EF' }
            default   { $v.PapelTexto = 'Sin dominio'; $v.PapelColor = Hex-Tema '#5F6F65'; $v.PapelFondo = Hex-Tema '#EEF2EF' }
        }
        $v.Ip = $(if ($ipBase) { "$($ipBase[0]).$($ipBase[1]).$($ipBase[2]).$([int]$ipBase[3] + $k)" } else { 'DHCP' })
        $vistas.Add($v)
    }
    $LabLista.ItemsSource = $vistas
    foreach ($v in $vistas) { if ($elegidas -contains $v.Datos) { [void]$LabLista.SelectedItems.Add($v) } }
    $LabVacio.Visibility = $(if ($vistas.Count) { 'Collapsed' } else { 'Visible' })

    # Explicación del dominio, según cómo esté la lista
    if (-not $LabConDominio.IsChecked) {
        $LabDominioNota.Text = 'Elige un Windows Server y pulsa «Hacer controlador»; los demás Windows se unen solos.'
        $LabDominioNota.Foreground = Pincel $Colores.Suave
    } else {
        $dcActual = Dc-Lab
        if (-not $dcActual) {
            $LabDominioNota.Text = 'Falta un Windows Server en el laboratorio para hacer de controlador.'
            $LabDominioNota.Foreground = Pincel $Colores.Aviso
        } else {
            $nCli = @($orden | Where-Object { $_.Papel -eq 'miembro' }).Count
            $LabDominioNota.Text = "Controlador: $($dcActual.nombre)  ·  $(if ($nCli -eq 1) { '1 cliente se une solo' } else { "$nCli clientes se unen solos" })."
            $LabDominioNota.Foreground = Pincel $Colores.Ok
        }
    }
    Estado-BotonesLab
    try { Pintar-TiposLab $vistas } catch { Escribir-Log ("Tipos de máquina: " + ($_ | Out-String)) }
    try { Pintar-PrevLab $vistas $orden } catch { Escribir-Log ("Vista previa: " + ($_ | Out-String)) }
    $ramTotal = [double](($script:filasLab | ForEach-Object { [double]$_.ram }) | Measure-Object -Sum).Sum
    if ($script:filasLab.Count) {
        $t = "$(Plural $script:filasLab.Count 'máquina' 'máquinas')  ·  $([Math]::Round($ramTotal / 1024, 1)) GB de RAM"
        if ($ramPC) { $t += " (tu PC tiene $([Math]::Round($ramPC / 1GB)) GB)" }
        $LabInfo.Text = $t
        $LabInfo.Foreground = Pincel $(if ($ramPC -and $ramTotal * 1MB -gt $ramPC * 0.8) { $Colores.Aviso } else { $Colores.Suave })
    } else { $LabInfo.Text = '' }
}

function Estado-BotonesLab {
    $sel = @($LabLista.SelectedItems)
    $BtnLabDc.IsEnabled = $sel.Count -eq 1 -and (Puede-SerDc $sel[0].Datos)
    $BtnLabQuitar.IsEnabled = $sel.Count -ge 1
    $BtnLabVaciar.IsEnabled = $script:filasLab.Count -gt 0
}

# ---------------------------------------------------------------- una fila por tipo de máquina, con − n +
# (el nombre de la base va en DataContext: el estilo de los botones usa Tag como icono)
$script:anadirAbierto = $false
$script:unaAUnaAbierto = $false
$script:alMenosTipo = { param($s, $a) Cambiar-TipoLab ([string]$s.DataContext) -1 }
$script:alMasTipo = { param($s, $a) Cambiar-TipoLab ([string]$s.DataContext) 1 }

function Cambiar-TipoLab([string]$nombreBase, [int]$signo) {
    # «+» copia la última máquina de ese tipo (mismos ajustes); «−» quita la última
    $grupo = @($script:filasLab | Where-Object { $_.base -eq $nombreBase })
    if (-not $grupo.Count) { return }
    $ultima = $grupo[$grupo.Count - 1]
    if ($signo -gt 0) {
        if ($grupo.Count -ge 20) { Aviso 'Como mucho 20 máquinas de la misma base.'; return }
        if (-not $LabNombre.Text.Trim()) { $LabNombre.Text = Nombre-LabLibre }
        [void]$script:filasLab.Add(@{ base = $nombreBase; nombre = (Nombre-MaquinaLab $nombreBase); ram = $ultima.ram; cpus = $ultima.cpus; vram = $ultima.vram; extras = @($ultima.extras | Where-Object { $_ }) })
    } else {
        $script:filasLab.Remove($ultima)
    }
    Refrescar-Lab
}

function Pintar-TiposLab([object[]]$listaV) {
    $LabTipos.Children.Clear()
    $grupos = [ordered]@{}
    foreach ($vt in $listaV) {
        $nb = [string]$vt.Datos.base
        if (-not $grupos.Contains($nb)) { $grupos[$nb] = New-Object System.Collections.ArrayList }
        [void]$grupos[$nb].Add($vt)
    }
    $sec = [System.Windows.Application]::Current
    foreach ($nb in @($grupos.Keys)) {
        $gr = $grupos[$nb]
        $ram0 = [int]$gr[0].Datos.ram; $cpu0 = [int]$gr[0].Datos.cpus
        $iguales = (@($gr | Where-Object { [int]$_.Datos.ram -ne $ram0 -or [int]$_.Datos.cpus -ne $cpu0 }).Count -eq 0)
        $gb = $ram0 / 1024.0
        $txt = $(if ($iguales) { "$($gb.ToString('0.#', [Globalization.CultureInfo]::InvariantCulture)) GB · $(Plural $cpu0 'CPU' 'CPUs') cada una" } else { 'con ajustes distintos (se ven en la vista previa)' })
        $caja = New-Object System.Windows.Controls.Border
        $caja.CornerRadius = New-Object System.Windows.CornerRadius(10); $caja.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
        $caja.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        Ref-Tema $caja ([System.Windows.Controls.Border]::BackgroundProperty) 'T_campo'
        $rej = New-Object System.Windows.Controls.Grid
        foreach ($ancho in @('Auto', '*', 'Auto')) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $(if ($ancho -eq 'Auto') { [System.Windows.GridLength]::Auto } else { New-Object System.Windows.GridLength(1, 'Star') })
            [void]$rej.ColumnDefinitions.Add($cd)
        }
        $pas = Pastilla-Sistema $gr[0] 32
        $pas.VerticalAlignment = 'Center'
        $rej.Children.Add($pas) | Out-Null
        $col = New-Object System.Windows.Controls.StackPanel
        $col.Margin = New-Object System.Windows.Thickness(10, 0, 10, 0); $col.VerticalAlignment = 'Center'
        $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $nb; $t1.FontWeight = 'SemiBold'; $t1.TextTrimming = 'CharacterEllipsis'
        Ref-Tema $t1 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
        $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = $txt; $t2.FontSize = 12; $t2.TextTrimming = 'CharacterEllipsis'
        Ref-Tema $t2 ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
        [void]$col.Children.Add($t1); [void]$col.Children.Add($t2)
        [System.Windows.Controls.Grid]::SetColumn($col, 1); [void]$rej.Children.Add($col)
        $cont = New-Object System.Windows.Controls.StackPanel; $cont.Orientation = 'Horizontal'; $cont.VerticalAlignment = 'Center'
        $bm = New-Object System.Windows.Controls.Button
        $bm.Style = $sec.FindResource('BotonSecundario'); $bm.Content = [string][char]0x2212; $bm.Width = 30; $bm.Height = 30; $bm.Padding = New-Object System.Windows.Thickness(0)
        $bm.DataContext = $nb; $bm.Add_Click($script:alMenosTipo)
        $num = New-Object System.Windows.Controls.TextBlock; $num.Text = [string]$gr.Count; $num.Width = 34; $num.TextAlignment = 'Center'; $num.VerticalAlignment = 'Center'; $num.FontWeight = 'SemiBold'
        Ref-Tema $num ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
        $bp = New-Object System.Windows.Controls.Button
        $bp.Style = $sec.FindResource('BotonSecundario'); $bp.Content = '+'; $bp.Width = 30; $bp.Height = 30; $bp.Padding = New-Object System.Windows.Thickness(0)
        $bp.DataContext = $nb; $bp.Add_Click($script:alMasTipo)
        [void]$cont.Children.Add($bm); [void]$cont.Children.Add($num); [void]$cont.Children.Add($bp)
        [System.Windows.Controls.Grid]::SetColumn($cont, 2); [void]$rej.Children.Add($cont)
        $caja.Child = $rej
        [void]$LabTipos.Children.Add($caja)
    }
    $hay = ($listaV.Count -gt 0)
    $LabTipos.Visibility = $(if ($hay) { 'Visible' } else { 'Collapsed' })
    $BtnLabMas.Visibility = $(if ($hay) { 'Visible' } else { 'Collapsed' })
    $LabAnadirPanel.Visibility = $(if ($script:anadirAbierto -or -not $hay) { 'Visible' } else { 'Collapsed' })
    $LabVerUna.Visibility = $(if ($hay) { 'Visible' } else { 'Collapsed' })
    $LabUnaAUna.Visibility = $(if ($hay -and $script:unaAUnaAbierto) { 'Visible' } else { 'Collapsed' })
    $LabVerUna.Text = $(if ($script:unaAUnaAbierto) { 'Ocultar las máquinas una a una ▾' } else { 'Ver las máquinas una a una ▸' })
}
$BtnLabMas.Add_Click({ $script:anadirAbierto = -not $script:anadirAbierto; Refrescar-Lab })
$LabVerUna.Add_MouseLeftButtonUp({ $script:unaAUnaAbierto = -not $script:unaAUnaAbierto; Refrescar-Lab })

# ---------------------------------------------------------------- red: chips Aislada / NAT / Solo anfitrión
$script:alChipRed = { param($s, $a) Elegir-ChipRedLab ([string]$s.Tag) }
$script:avanzadoAbierto = $false

function Clave-ChipRedLab {
    $i = $LabRed.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:opcRedLab.Count) { return '' }
    switch ($script:opcRedLab[$i].Tipo) { 'nat' { return 'nat' } 'hostonly' { return 'hostonly' } 'pvn' { return 'aislada' } default { return '' } }
}

function Pintar-ChipsRedLab {
    $LabChipsRed.Children.Clear()
    $activa = Clave-ChipRedLab
    foreach ($ch in @(@{ c = 'aislada'; t = 'Aislada (segmento LAN)' }, @{ c = 'nat'; t = 'NAT (con Internet)' }, @{ c = 'hostonly'; t = 'Solo anfitrión' })) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $LabChipsRed.FindResource('ChipLab')
        $rb.GroupName = 'LabChipRed'; $rb.Content = $ch.t; $rb.Tag = $ch.c
        $rb.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)
        $rb.IsChecked = ($ch.c -eq $activa)
        $rb.Add_Click($script:alChipRed)
        [void]$LabChipsRed.Children.Add($rb)
    }
}

function Elegir-ChipRedLab([string]$clave) {
    $idx = -1
    if ($clave -eq 'aislada') {
        # El segmento que ya estaba elegido, o el primero que haya; si no hay ninguno, se pide crearlo
        if ((Clave-ChipRedLab) -eq 'aislada') { $idx = $LabRed.SelectedIndex }
        else {
            for ($k = 0; $k -lt $script:opcRedLab.Count; $k++) { if ($idx -lt 0 -and $script:opcRedLab[$k].Tipo -eq 'pvn') { $idx = $k } }
            if ($idx -lt 0) { $idx = $script:opcRedLab.Count }          # «Nuevo segmento LAN…»
        }
    } else {
        for ($k = 0; $k -lt $script:opcRedLab.Count; $k++) { if ($idx -lt 0 -and $script:opcRedLab[$k].Clave -eq $clave) { $idx = $k } }
    }
    if ($idx -ge 0) { $LabRed.SelectedIndex = $idx }
    Pintar-ChipsRedLab
}

function Poner-AvanzadoLab {
    $LabAvanzado.Visibility = $(if ($script:avanzadoAbierto) { 'Visible' } else { 'Collapsed' })
    $LabVerAvanz.Text = $(if ($script:avanzadoAbierto) { 'Ajustes avanzados de la red ▾' } else { 'Ajustes avanzados de la red ▸' })
}
$LabVerAvanz.Add_MouseLeftButtonUp({ $script:avanzadoAbierto = -not $script:avanzadoAbierto; Poner-AvanzadoLab })

function Proponer-RedLab {
    # Valores de IP según la red elegida
    $o = $script:opcRedLab[[Math]::Max(0, $LabRed.SelectedIndex)]
    if ($o.Tipo -eq 'nat' -and $script:red) {
        $b = $script:red.Subred.Split('.')
        $LabIp.Text = "$($b[0]).$($b[1]).$($b[2]).50"; $LabPrefijo.Text = [string]$script:red.Prefijo
        $LabGw.Text = $script:red.Puerta; $LabDns.Text = $script:red.Puerta
        $LabRedNota.Text = 'Con Internet. DHCP de VMware desde .128.'
    } elseif ($o.Tipo -eq 'pvn') {
        $LabIp.Text = '192.168.100.10'; $LabPrefijo.Text = '24'; $LabGw.Text = ''; $LabDns.Text = ''
        $LabRedNota.Text = 'Red aislada: solo se ven entre ellas, sin Internet ni DHCP.'
        $LabFija.IsChecked = $true
    } else { $LabRedNota.Text = '' }
}

function Cargar-OpcionesRedLab($claveElegida) {
    $script:opcRedLab.Clear()
    foreach ($o in @(Opciones-Red)) { [void]$script:opcRedLab.Add($o) }
    $script:cargandoRedLab = $true
    $LabRed.Items.Clear()
    foreach ($o in $script:opcRedLab) { [void]$LabRed.Items.Add($o.Texto) }
    [void]$LabRed.Items.Add($textoNuevoSeg)
    $idx = 0
    for ($k = 0; $k -lt $script:opcRedLab.Count; $k++) { if ($script:opcRedLab[$k].Clave -eq $claveElegida) { $idx = $k } }
    $LabRed.SelectedIndex = $idx
    $script:anteriorRedLab = $idx
    $script:cargandoRedLab = $false
    Pintar-ChipsRedLab
}

function Cargar-BasesLab {
    $script:basesLab = @(Obtener-Bases)
    $antes = [string]$LabBase.SelectedItem
    $LabBase.Items.Clear()
    foreach ($b in $script:basesLab) { [void]$LabBase.Items.Add($b.Nombre) }
    if ($LabBase.Items.Count) { $LabBase.SelectedIndex = [Math]::Max(0, $LabBase.Items.IndexOf($antes)) }
}

function Cargar-PlantillasLab([string]$elegir) {
    $script:plantillasLab = @()
    # (en Windows PowerShell, ConvertFrom-Json devuelve la lista entera como un solo objeto: se separa)
    try { $datosPl = [IO.File]::ReadAllText($archivoPlantillasLab, [Text.Encoding]::UTF8) | ConvertFrom-Json; $script:plantillasLab = @($datosPl | ForEach-Object { $_ }) } catch {}
    $script:cargandoPlant = $true
    $LabPlantilla.Items.Clear()
    [void]$LabPlantilla.Items.Add('(ninguna)')
    foreach ($pl in $script:plantillasLab) { [void]$LabPlantilla.Items.Add([string]$pl.nombre) }
    $LabPlantilla.SelectedIndex = [Math]::Max(0, $LabPlantilla.Items.IndexOf($elegir))
    $script:cargandoPlant = $false
    $BtnLabBorrarPl.IsEnabled = $LabPlantilla.SelectedIndex -gt 0
    Pintar-ChipsLab
}

function Entrar-Lab {
    # Al entrar en la página: bases, redes y máquinas al día (lo que estés preparando se conserva)
    if (-not $script:red) { $script:red = Leer-RedNat }
    if (-not $script:red) { $script:red = @{ Subred = '192.168.1.0'; Prefijo = 24; Puerta = '192.168.1.1' } }
    Cargar-BasesLab
    if (-not $script:labIniciado) {
        Cargar-OpcionesRedLab 'nat'
        Cargar-PlantillasLab ''
        Proponer-RedLab
        $script:labIniciado = $true
    }
    Refrescar-Lab
    Pintar-ProgresoLab
    Entrar-MisLab
}

# ---------------------------------------------------------------- añadir, editar, quitar
$LabBase.Add_SelectionChanged({
    # RAM y CPUs propuestas según el sistema (un laboratorio suma mucha RAM)
    $b = Base-PorNombreLab ([string]$LabBase.SelectedItem)
    if (-not $b) { return }
    $LabRam.Text = $(if ($b.EsWindows -or $b.Nombre -match 'Desk|Lubuntu|Kali') { '4096' } else { '2048' })
    $LabCpu.Text = '2'
})
$BtnLabAnadir.Add_Click({
    $b = [string]$LabBase.SelectedItem
    if (-not $b) { Aviso 'No hay bases: créalas en «Crear base».'; return }
    $cant = Numero $LabCantidad.Text; $ram = Numero $LabRam.Text; $cpus = Numero $LabCpu.Text; $vram = Numero $LabVram.Text
    if ($cant -lt 1 -or $cant -gt 20) { Aviso 'La cantidad tiene que ser un número del 1 al 20.'; return }
    if ($ram -lt 512 -or $ram -gt 131072) { Aviso 'La RAM tiene que ser un número de MB entre 512 y 131072.'; return }
    if ($cpus -lt 1 -or $cpus -gt 64) { Aviso 'Las CPUs tienen que ser un número entre 1 y 64.'; return }
    if ($vram -lt 0 -or $vram -gt 8192) { Aviso 'El vídeo 3D tiene que ser un número de MB entre 0 y 8192 (0 = sin 3D).'; return }
    if (-not $LabNombre.Text.Trim()) { $LabNombre.Text = Nombre-LabLibre }
    for ($k = 0; $k -lt $cant; $k++) {
        [void]$script:filasLab.Add(@{ base = $b; nombre = (Nombre-MaquinaLab $b); ram = $ram; cpus = $cpus; vram = $vram })
    }
    $script:anadirAbierto = $false
    Refrescar-Lab
})

function Hacer-DcLab {
    $sel = @($LabLista.SelectedItems)
    if ($sel.Count -ne 1) { return }
    $fila = $sel[0].Datos
    if (-not (Puede-SerDc $fila)) { Aviso 'Solo un Windows Server puede ser controlador de dominio.'; return }
    $script:dcLab = $fila
    if (-not $LabConDominio.IsChecked) {
        if (-not $LabDominio.Text.Trim()) { $LabDominio.Text = 'empresa.local' }
        $LabConDominio.IsChecked = $true
    }
    Refrescar-Lab
}

function Quitar-Lab {
    foreach ($v in @($LabLista.SelectedItems)) { $script:filasLab.Remove($v.Datos) }
    Refrescar-Lab
}

$LabLista.Add_SelectionChanged({ Estado-BotonesLab })
$LabLista.Add_PreviewKeyDown({
    param($s, $a)
    if ($a.Key -eq [System.Windows.Input.Key]::Delete) { Quitar-Lab; $a.Handled = $true }
})
$BtnLabDc.Add_Click({ Hacer-DcLab })
$BtnLabQuitar.Add_Click({ Quitar-Lab })
$BtnLabVaciar.Add_Click({ $script:filasLab.Clear(); $script:dcLab = $null; Refrescar-Lab })

# ---------------------------------------------------------------- red y dominio
$LabRed.Add_SelectionChanged({
    if ($script:cargandoRedLab -or $LabRed.SelectedIndex -lt 0) { return }
    if ($LabRed.SelectedIndex -eq $script:opcRedLab.Count) {
        # «Nuevo segmento LAN…»
        $nombre = Pedir-Texto 'Nuevo segmento LAN' "Nombre del segmento (por ejemplo LAB-AD).`nLas máquinas del mismo segmento se ven entre ellas, sin Internet." 'LAB'
        $nombre = "$nombre".Trim()
        if (-not $nombre) { $LabRed.SelectedIndex = [int]$script:anteriorRedLab; return }
        $motivo = Validar-NombreSegmento $nombre
        if ($motivo) { Aviso $motivo; $LabRed.SelectedIndex = [int]$script:anteriorRedLab; return }
        if (@($script:opcRedLab | Where-Object { $_.Texto -eq "Segmento LAN: $nombre" }).Count) { Aviso "Ya existe el segmento «$nombre»."; $LabRed.SelectedIndex = [int]$script:anteriorRedLab; return }
        $id = Nuevo-Segmento $nombre
        Cargar-OpcionesRedLab "pvn:$id"
    }
    $script:anteriorRedLab = $LabRed.SelectedIndex
    Proponer-RedLab
    Refrescar-Lab
    Pintar-ChipsRedLab
})
foreach ($ctl in @($LabDhcp, $LabFija, $LabConDominio)) {
    $ctl.Add_Checked({ Refrescar-Lab })
    $ctl.Add_Unchecked({ Refrescar-Lab })
}
$LabIp.Add_TextChanged({ Refrescar-Lab })
$LabNombre.Add_LostFocus({
    # Si cambia el nombre del laboratorio, se renombran las máquinas que siguen el patrón LAB-XXX-n
    $lab = $LabNombre.Text.Trim()
    if (-not $lab) { return }
    foreach ($fila in $script:filasLab) {
        if ($fila.nombre -match '^[^-]+-([A-Z0-9]+)-(\d+)$' -and -not $fila.nombre.StartsWith("$lab-")) {
            $fila.nombre = "$lab-$($Matches[1])-$($Matches[2])"
        }
    }
    Refrescar-Lab
})
$LabDominio.Add_TextChanged({
    $nb = (($LabDominio.Text.Trim().Split('.')[0]) -replace '[^a-zA-Z0-9-]', '').ToUpper()
    if ($nb.Length -gt 15) { $nb = $nb.Substring(0, 15) }
    $LabNetbios.Text = $nb
})

# ---------------------------------------------------------------- plantillas
function Base-ParaTipoLab([string]$tipo) {
    # Primera base de este PC que encaja con el tipo (por orden de preferencia)
    $pref = switch ($tipo) {
        'servidor' { @('WinServer2022', 'WinServer2025', 'WinServer2019') }
        'clientewin' { @('Win11Pro', 'Win10Pro') }
        'linux' { @('Ubuntu2404', 'Ubuntu2204', 'Ubuntu2404Desk', 'Ubuntu2204Desk', 'Lubuntu2404', 'Ubuntu2604', 'Ubuntu2604Desk') }
        'kali' { @('Kali') }
        default { @() }
    }
    foreach ($nombreB in $pref) { if (Base-PorNombreLab $nombreB) { return $nombreB } }
    $x = $null
    switch ($tipo) {
        'servidor' { $x = $script:basesLab | Where-Object { $_.EsWindows -and $_.EsServidor } | Select-Object -First 1 }
        'clientewin' { $x = $script:basesLab | Where-Object { $_.EsWindows -and -not $_.EsServidor } | Select-Object -First 1 }
        'linux' { $x = $script:basesLab | Where-Object { -not $_.EsWindows -and $_.Nombre -notlike 'Kali*' } | Select-Object -First 1 }
        'kali' { $x = $script:basesLab | Where-Object { $_.Nombre -like 'Kali*' } | Select-Object -First 1 }
    }
    if ($x) { return [string]$x.Nombre }
    return ''
}
function Texto-TipoLab([string]$tipo) {
    switch ($tipo) { 'servidor' { 'un Windows Server' } 'clientewin' { 'un Windows 10 u 11' } 'linux' { 'un Ubuntu' } 'kali' { 'Kali' } default { $tipo } }
}

function Aplicar-PlantillaLab($pl) {
    # $pl tiene la forma de las plantillas guardadas (nombre, red, ip, maquinas, dominio...). Sirve para las de David y las de serie.
    $LabNombre.Text = Nombre-LabLibre
    $script:filasLab.Clear(); $script:dcLab = $null
    $faltanBases = @()
    foreach ($m in @($pl.maquinas)) {
        # Las de serie piden un tipo (servidor, cliente Windows, Linux, Kali) y se usa la base que haya en este PC
        $nb = $(if ($m.tipo) { Base-ParaTipoLab ([string]$m.tipo) } else { [string]$m.base })
        if (-not $nb -or -not (Base-PorNombreLab $nb)) { $faltanBases += $(if ($m.tipo) { Texto-TipoLab ([string]$m.tipo) } else { [string]$m.base }); continue }
        $fila = @{ base = $nb; nombre = (Nombre-MaquinaLab $nb); ram = [int]$m.ram; cpus = [int]$m.cpus
                   extras = @(Extras-Validos (Base-PorNombreLab $nb) @($m.extras))   # (ficha 20) solo los del catálogo de esa base
                   vram = $(if ($null -ne $m.vram) { [int]$m.vram } else { $vramDefLab }) }
        [void]$script:filasLab.Add($fila)
        if ($m.dc) { $script:dcLab = $fila }
    }
    Cargar-OpcionesRedLab ([string]$pl.red)
    if ($pl.ip) {
        $LabFija.IsChecked = ($pl.ip.modo -eq 'fija'); $LabDhcp.IsChecked = -not $LabFija.IsChecked
        if ([string]$pl.ip.desde) {
            $LabIp.Text = [string]$pl.ip.desde; $LabPrefijo.Text = [string]$pl.ip.prefix
            $LabGw.Text = [string]$pl.ip.gw; $LabDns.Text = (@($pl.ip.dns) -join ', ')
        } else { Proponer-RedLab }   # (plantillas importadas con DHCP: sin direcciones propias)
    } else {
        # (las de serie no traen IP: se propone la de la red elegida)
        Proponer-RedLab
        $LabFija.IsChecked = [bool]$pl.conDominio; $LabDhcp.IsChecked = -not $LabFija.IsChecked
    }
    $LabConDominio.IsChecked = [bool]$pl.conDominio; $LabDominio.Text = [string]$pl.dominio; $LabNetbios.Text = [string]$pl.netbios
    $LabDesechable.IsChecked = [bool]$pl.desechable; $LabPing.IsChecked = [bool]$pl.ping
    Refrescar-Lab
    if ($faltanBases.Count) {
        $lista = (@($faltanBases | Select-Object -Unique) -join ', ')
        Aviso "No se han añadido $(Plural $faltanBases.Count 'máquina' 'máquinas') porque en este PC no hay base de: $lista.`nPuedes crearla en «Crear base»."
    }
}
$LabPlantilla.Add_SelectionChanged({
    $BtnLabBorrarPl.IsEnabled = $LabPlantilla.SelectedIndex -gt 0
    if ($script:cargandoPlant -or $LabPlantilla.SelectedIndex -le 0) { return }
    Aplicar-PlantillaLab $script:plantillasLab[$LabPlantilla.SelectedIndex - 1]
    Pintar-ChipsLab
})

# ---- «Empezar desde»: En blanco / Active Directory / Solo Linux / las plantillas guardadas
$script:plantillasSerieLab = @(
    [pscustomobject]@{ clave = 'ad'; nombre = 'Active Directory'; red = 'nat'; ip = $null; conDominio = $true; dominio = 'empresa.local'; netbios = 'EMPRESA'; desechable = $true; ping = $true
        maquinas = @(
            [pscustomobject]@{ tipo = 'servidor'; ram = 4096; cpus = 2; vram = $null; dc = $true }
            [pscustomobject]@{ tipo = 'clientewin'; ram = 4096; cpus = 2; vram = $null; dc = $false }
            [pscustomobject]@{ tipo = 'clientewin'; ram = 4096; cpus = 2; vram = $null; dc = $false }) }
    [pscustomobject]@{ clave = 'linux'; nombre = 'Solo Linux'; red = 'nat'; ip = $null; conDominio = $false; dominio = ''; netbios = ''; desechable = $true; ping = $true
        maquinas = @(
            [pscustomobject]@{ tipo = 'linux'; ram = 2048; cpus = 2; vram = $null; dc = $false }
            [pscustomobject]@{ tipo = 'kali'; ram = 4096; cpus = 2; vram = $null; dc = $false }) }
)
$script:chipLab = 'blanco'
$script:alChipLab = { param($s, $a) Elegir-ChipLab ([string]$s.Tag) }

function Pintar-ChipsLab {
    $LabChips.Children.Clear()
    $claves = @(@{ c = 'blanco'; t = 'En blanco' }, @{ c = 'ad'; t = 'Active Directory' }, @{ c = 'linux'; t = 'Solo Linux' })
    # Con pocas plantillas guardadas, una chip por cada una; con más de 3 (se saturaría), un desplegable «Mis plantillas»
    $muchas = ($script:plantillasLab.Count -gt 3)
    $LabPlantilla.Visibility = $(if ($muchas) { 'Visible' } else { 'Collapsed' })
    if (-not $muchas) {
        for ($k = 0; $k -lt $script:plantillasLab.Count; $k++) { $claves += @{ c = "pl:$k"; t = [string]$script:plantillasLab[$k].nombre } }
    }
    $activa = $script:chipLab
    if ($LabPlantilla.SelectedIndex -gt 0) { $activa = "pl:$($LabPlantilla.SelectedIndex - 1)" }
    foreach ($ch in $claves) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $LabChips.FindResource('ChipLab')
        $rb.GroupName = 'LabChip'; $rb.Content = $ch.t; $rb.Tag = $ch.c
        $rb.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)
        $rb.IsChecked = ($ch.c -eq $activa)
        $rb.Add_Click($script:alChipLab)
        [void]$LabChips.Children.Add($rb)
    }
    try { Poner-MasPl } catch {}
}

function Elegir-ChipLab([string]$clave) {
    $script:chipLab = $clave
    if ($clave.StartsWith('pl:')) {
        $LabPlantilla.SelectedIndex = [int]$clave.Substring(3) + 1     # su evento aplica la plantilla
        return
    }
    $script:cargandoPlant = $true
    try { $LabPlantilla.SelectedIndex = 0 } finally { $script:cargandoPlant = $false }
    $BtnLabBorrarPl.IsEnabled = $false
    try { Poner-MasPl } catch {}
    if ($clave -eq 'blanco') {
        $LabNombre.Text = Nombre-LabLibre
        $script:filasLab.Clear(); $script:dcLab = $null
        $LabConDominio.IsChecked = $false; $LabDominio.Text = ''
        $LabDesechable.IsChecked = $true; $LabArrancar.IsChecked = $true
        Refrescar-Lab
        return
    }
    $pl = @($script:plantillasSerieLab | Where-Object { $_.clave -eq $clave }) | Select-Object -First 1
    if ($pl) { Aplicar-PlantillaLab $pl }
}

$BtnLabGuardarPl.Add_Click({
    if (-not $script:filasLab.Count) { Aviso 'Añade antes alguna máquina.'; return }
    $nombre = Pedir-Texto 'Guardar plantilla' 'Nombre de la plantilla:' 'Dominio con clientes'
    $nombre = "$nombre".Trim()
    if (-not $nombre) { return }
    $o = $script:opcRedLab[[Math]::Max(0, $LabRed.SelectedIndex)]
    $nueva = [ordered]@{
        nombre = $nombre; red = $o.Clave; desechable = [bool]$LabDesechable.IsChecked; ping = [bool]$LabPing.IsChecked
        ip = [ordered]@{ modo = $(if ($LabFija.IsChecked) { 'fija' } else { 'dhcp' }); desde = $LabIp.Text.Trim(); prefix = (Numero $LabPrefijo.Text 24); gw = $LabGw.Text.Trim(); dns = @($LabDns.Text -split '\s*,\s*' | Where-Object { $_ }) }
        conDominio = [bool]$LabConDominio.IsChecked; dominio = $LabDominio.Text.Trim(); netbios = $LabNetbios.Text.Trim()
        maquinas = @(Orden-Lab | ForEach-Object { [ordered]@{ base = $_.Fila.base; ram = $_.Fila.ram; cpus = $_.Fila.cpus; vram = $_.Fila.vram; dc = ($_.Papel -eq 'dc'); extras = @($_.Fila.extras | Where-Object { $_ }) } })
    }
    $todas = @($script:plantillasLab | Where-Object { $_.nombre -ne $nombre }) + @([pscustomobject]$nueva)
    [IO.File]::WriteAllText($archivoPlantillasLab, (ConvertTo-Json @($todas) -Depth 6), [Text.UTF8Encoding]::new($false))
    Cargar-PlantillasLab $nombre
    Mostrar-Toast "Plantilla «$nombre» guardada."
})
$BtnLabBorrarPl.Add_Click({
    if ($LabPlantilla.SelectedIndex -le 0) { return }
    $nombre = [string]$LabPlantilla.SelectedItem
    if (-not (Pregunta "¿Borrar la plantilla «$nombre»? (Las máquinas no se tocan.)" 'Borrar plantilla' 'Borrar' 'Cancelar' 'BotonRojo')) { return }
    $todas = @($script:plantillasLab | Where-Object { $_.nombre -ne $nombre })
    [IO.File]::WriteAllText($archivoPlantillasLab, (ConvertTo-Json @($todas) -Depth 6), [Text.UTF8Encoding]::new($false))
    Cargar-PlantillasLab ''
})

# ---------------------------------------------------------------- crear
function Crear-Laboratorio {
    $lab = $LabNombre.Text.Trim()
    if ($lab -notmatch '^[A-Za-z0-9]{1,8}$') { Aviso 'Nombre del laboratorio: letras y números, máximo 8 (por ejemplo LAB1).'; return }
    if (-not $script:filasLab.Count) { Aviso 'Añade al menos una máquina.'; return }
    foreach ($fila in $script:filasLab) {
        $motivo = Validar-NombreMaquina $fila.nombre
        if ($motivo) { Aviso "$($fila.nombre): $motivo"; return }
    }
    $o = $script:opcRedLab[[Math]::Max(0, $LabRed.SelectedIndex)]
    $ip = [ordered]@{ modo = 'dhcp'; desde = ''; prefix = 24; gw = ''; dns = @() }
    if ($LabFija.IsChecked) {
        $desde = $LabIp.Text.Trim()
        $pre = Numero $LabPrefijo.Text
        if (-not (Es-IPv4 $desde)) { Aviso 'La primera IP no es válida.'; return }
        if ([int]$desde.Split('.')[3] -lt 1) { Aviso 'La primera IP no puede acabar en .0 (es la dirección de la red).'; return }
        if ([int]$desde.Split('.')[3] + $script:filasLab.Count - 1 -gt 254) { Aviso "No caben $($script:filasLab.Count) IPs seguidas a partir de $desde."; return }
        if ($pre -lt 1 -or $pre -gt 32) { Aviso 'El prefijo tiene que ser un número del 1 al 32 (por ejemplo 24).'; return }
        # IP que ya usan otras máquinas tuyas (si están en la misma red, chocarían)
        $b4 = $desde.Split('.')
        $delLab = @(for ($k = 0; $k -lt $script:filasLab.Count; $k++) { "$($b4[0]).$($b4[1]).$($b4[2]).$([int]$b4[3] + $k)" })
        $ocupadas = @(@(Leer-Clones) | Where-Object { $_.IP -and $delLab -contains $_.IP } | ForEach-Object { "$($_.IP) ($($_.Nombre))" })
        if ($ocupadas.Count -and -not (Pregunta "Estas IP ya las tienen otras máquinas tuyas:`n  $($ocupadas -join "`n  ")`n`nSi están en la misma red habrá conflictos." 'IP repetidas' 'Crear igualmente')) { return }
        $gw = $LabGw.Text.Trim()
        if ($gw -and -not (Es-IPv4 $gw)) { Aviso 'La puerta de enlace no es válida (o déjala vacía).'; return }
        $dns = @($LabDns.Text -split '\s*,\s*' | Where-Object { $_ })
        if (@($dns | Where-Object { -not (Es-IPv4 $_) }).Count) { Aviso 'Algún DNS no es válido (sepáralos por comas).'; return }
        $ip = [ordered]@{ modo = 'fija'; desde = $desde; prefix = $pre; gw = $gw; dns = @($dns) }
    } elseif ($o.Tipo -eq 'pvn') {
        if (-not (Pregunta "En un segmento LAN no hay DHCP: sin IP fija, las máquinas no tendrán dirección (salvo que una haga de servidor DHCP)." 'Sin direcciones' 'Seguir igualmente')) { return }
    }
    $dominio = $null
    $orden = @(Orden-Lab)
    if ($LabConDominio.IsChecked) {
        $dom = $LabDominio.Text.Trim().ToLower(); $nb = $LabNetbios.Text.Trim().ToUpper()
        if (-not (Es-Dominio $dom)) { Aviso 'El nombre de dominio no es válido (ejemplo: empresa.local).'; return }
        if ($nb -notmatch '^[A-Z0-9-]{1,15}$') { Aviso 'El nombre NetBIOS no es válido (letras, números y guiones, máximo 15).'; return }
        if (-not @($orden | Where-Object { $_.Papel -eq 'dc' }).Count) { Aviso 'Para crear un dominio hace falta un Windows Server en el laboratorio.'; return }
        $dominio = [ordered]@{ dominio = $dom; netbios = $nb }
    }
    # Extras (ficha 20): solo los del catálogo de cada base; sin Internet, se avisa de los que no se podrán instalar
    $extrasDe = @{}; $sinRed = @()
    $hayNet = Red-ConInternetLab
    foreach ($fo in $orden) {
        $baseFo = Base-PorNombreLab $fo.Fila.base
        $val = @(Extras-Validos $baseFo @($fo.Fila.extras))
        if ($fo.Papel -eq 'dc') { $val = @($val | Where-Object { @('dns', 'adds') -notcontains $_ }) }
        $extrasDe[[string]$fo.Fila.nombre] = $val
        if (-not $hayNet -and $val.Count) {
            $conNet = @(Catalogo-Extras $baseFo | Where-Object { $_.Internet -and $val -contains $_.Id })
            if ($conNet.Count) { $sinRed += "$($fo.Fila.nombre): $((@($conNet | ForEach-Object { $_.Nombre }) -join ', '))" }
        }
    }
    if ($sinRed.Count -and -not (Pregunta "La red elegida no tiene Internet y estos extras lo necesitan para instalarse:`n  $($sinRed -join "`n  ")`n`nSaldrán con ✗ (el resto de la máquina se configura igual). Para instalarlos, elige NAT o puente." 'Extras sin Internet' 'Crear igualmente')) { return }
    $pedido = [ordered]@{
        nombre = $lab; desechable = [bool]$LabDesechable.IsChecked; arrancar = [bool]$LabArrancar.IsChecked; ping = [bool]$LabPing.IsChecked
        estadoInicial = [bool]($LabEstadoIni.IsChecked -and -not $LabDesechable.IsChecked)
        red = [ordered]@{ tipo = $o.Tipo; vnet = $o.Vnet; pvn = $o.Pvn; texto = $o.Texto }
        ip = $ip; dominio = $dominio
        maquinas = @($orden | ForEach-Object { [ordered]@{ base = $_.Fila.base; nombre = $_.Fila.nombre; ram = $_.Fila.ram; cpus = $_.Fila.cpus; vram = [int]$_.Fila.vram; papel = $_.Papel; extras = @($extrasDe[[string]$_.Fila.nombre]) } })
    }
    if (-not (Asegurar-PasswordVms)) { return }   # la contraseña se pide en una ventana, nunca en la consola
    Lanzar 'laboratorio.ps1' $pedido
    Mostrar-Toast "Creando el laboratorio «$lab» ($(Plural $script:filasLab.Count 'máquina' 'máquinas')): el progreso sale aquí arriba y en la consola."
    # Se pasa a «Mis laboratorios» con el nuevo elegido (sus máquinas salen «Configurándose» en cuanto existan)
    $script:labElegido = $lab; $script:labMaq = ''
    Poner-PestanaLab 'mis'
    Recargar-Luego 4000
    # Para el siguiente: nombre nuevo y lista vacía
    $script:filasLab.Clear(); $script:dcLab = $null
    $LabNombre.Text = $(if ($lab -match '^(.*?)(\d+)$') { $Matches[1] + ([int]$Matches[2] + 1) } else { '' })
    Refrescar-Lab
}
$BtnCrearLab.Add_Click({ Crear-Laboratorio })

# Estado inicial (ficha 28): no se ofrece en los desechables (se borran al apagarse)
function Poner-OpcionEstadoInicial {
    $esDesechable = [bool]$LabDesechable.IsChecked
    $LabEstadoIni.IsEnabled = -not $esDesechable
    $LabEstadoIniAyuda.Text = $(if ($esDesechable) { 'No se ofrece en un laboratorio desechable: se borra al apagarse.' } else { 'Permite volver a empezar la práctica con un clic. Tarda un par de minutos más y ocupa poco.' })
}
$LabDesechable.Add_Checked({ Poner-OpcionEstadoInicial })
$LabDesechable.Add_Unchecked({ Poner-OpcionEstadoInicial })
Poner-OpcionEstadoInicial

# ---------------------------------------------------------------- progreso de los laboratorios
# Una fila de cabecera por laboratorio (cuántas listas, media y contador desde la primera máquina) y
# debajo sus máquinas, igual que en «Nueva máquina». Se repinta cada segundo mientras se ve la página.
$script:filasProgLab = @{}

function Fila-ProgLab([string]$clave, [bool]$cabecera) {
    $fp = $script:filasProgLab[$clave]
    if ($fp) { return $fp }
    $raizFila = [Windows.Markup.XamlReader]::Parse($filaProgXaml)
    $fp = Elementos $raizFila $filaProgXaml
    $fp.Raiz = $raizFila
    if ($cabecera) { $raizFila.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'T_neutro') } else { $raizFila.Margin = New-Object System.Windows.Thickness(22, 0, 0, 8) }
    $raizFila.Opacity = 0
    Animar $raizFila $propOpacidad 1 300 0
    $script:filasProgLab[$clave] = $fp
    return $fp
}

function Poner-BarraProg($barra, [double]$pct, [string]$color) {
    $barra.Foreground = Pincel $color
    if ([Math]::Abs($barra.Value - $pct) -gt 0.5) {
        $an = New-Object System.Windows.Media.Animation.DoubleAnimation
        $an.To = $pct
        $an.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(200))
        $barra.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $an)
    }
    Brillo-Barra $barra $pct $color
}

function Pintar-ProgresoLab {
    $ahoraEp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $entradas = @((Leer-ProgresoVm).Values | Where-Object {
        $_.lab -and $_.enCurso -and (($finalesProg -notcontains [string]$_.estado) -or ($ahoraEp - [int64]$_.inicio) -lt 7200) })
    # el progreso ahora se ve en «Mis laboratorios» (mapa y lista); este bloque ya no se muestra
    $LabProgCaja.Visibility = 'Collapsed'
    # Un grupo por laboratorio; el más reciente arriba
    $grupos = @($entradas | Group-Object { "$($_.labid)|$($_.lab)" } | Sort-Object { $mx = [int64]0; foreach ($x in $_.Group) { if ([int64]$x.creada -gt $mx) { $mx = [int64]$x.creada } }; -$mx })
    $vistas = @{}
    $orden = 0
    foreach ($g in $grupos) {
        $maqs = @($g.Group | Sort-Object nombre)
        $infos = @($maqs | ForEach-Object { Info-Paso $_ })
        $listas = @($maqs | Where-Object { $finalesProg -contains [string]$_.estado }).Count
        $todas = $listas -eq $maqs.Count
        $hayMal = @($maqs | Where-Object { $finalesProg -contains [string]$_.estado -and [string]$_.estado -ne 'ok' }).Count -gt 0
        $suma = 0.0; foreach ($x in $infos) { $suma += [double]$x.Pct }
        $media = $suma / [Math]::Max(1, $infos.Count)
        # Contador del laboratorio: desde la primera máquina creada hasta ahora (o hasta la última lista)
        $desde = [int64]0; $ultimaLista = [int64]0
        foreach ($x in $maqs) {
            $c = [int64]$x.creada
            if ($c -gt 0 -and ($desde -eq 0 -or $c -lt $desde)) { $desde = $c }
            if ([int64]$x.inicio -gt $ultimaLista) { $ultimaLista = [int64]$x.inicio }
        }
        $hasta = if ($todas) { $ultimaLista } else { $ahoraEp }
        $kc = "cab:$($g.Name)"; $vistas[$kc] = $true
        $cab = Fila-ProgLab $kc $true
        $cab.ProgNombre.Text = "Laboratorio $($maqs[0].lab)"
        if ($todas) {
            $cab.ProgPaso.Text = $(if ($hayMal) { 'Terminado, con avisos' } else { 'Listo para usar' })
            $colorCab = if ($hayMal) { $Colores.Aviso } else { $Colores.Ok }
            $cab.ProgPaso.Foreground = Pincel $colorCab
            Poner-BarraProg $cab.ProgBarra 100 $colorCab
        } else {
            $cab.ProgPaso.Text = "$listas de $($maqs.Count) listas  ·  $([int]$media) %"
            $cab.ProgPaso.Foreground = Pincel $Colores.Suave
            Poner-BarraProg $cab.ProgBarra $media $Colores.Verde
        }
        $cab.ProgReloj.Text = $(if ($desde -gt 0) { Formato-Tiempo ($hasta - $desde) } else { '' })
        $cab.ProgReloj.Foreground = Pincel $(if ($todas) { $colorCab } else { '#12261A' })
        $cab.ProgRelojNota.Text = $(if ($desde -le 0) { '' } elseif ($todas) { 'tardó en total' } else { 'desde que empezó' })
        $raices = @($cab.Raiz)
        for ($k = 0; $k -lt $maqs.Count; $k++) {
            $e = $maqs[$k]; $i = $infos[$k]
            $kv = "vm:$($e.nombre)|$($e.creada)"; $vistas[$kv] = $true
            $fp = Fila-ProgLab $kv $false
            $final = $finalesProg -contains [string]$e.estado
            $total = Tiempo-Total $e
            $fp.ProgNombre.Text = [string]$e.nombre
            if ($final -and [string]$e.estado -eq 'ok') { $fp.ProgPaso.Text = 'Lista para usar' }
            elseif ($i.SinDatos) { $fp.ProgPaso.Text = 'Sin datos: ¿la base no tiene VMware Tools?' }
            else { $fp.ProgPaso.Text = $i.Largo + $(if ($i.Tiempo -and -not $final) { "  ·  este paso: $($i.Tiempo)" } else { '' }) }
            $fp.ProgPaso.Foreground = Pincel $(if ($final -or $i.SinDatos) { $i.Color } else { $Colores.Suave })
            $fp.ProgReloj.Text = $(if ($total -ge 0) { Formato-Tiempo $total } else { '' })
            $fp.ProgReloj.FontSize = 15
            $fp.ProgReloj.Foreground = Pincel $(if ($final) { $i.Color } else { '#12261A' })
            $fp.ProgRelojNota.Text = $(if ($total -lt 0) { '' } elseif ($final) { 'tardó' } else { 'desde que se creó' })
            Poner-BarraProg $fp.ProgBarra $i.Pct $i.Color
            $raices += $fp.Raiz
        }
        foreach ($r in $raices) {
            if ($LabProgLista.Children.IndexOf($r) -ne $orden) {
                if ($LabProgLista.Children.Contains($r)) { $LabProgLista.Children.Remove($r) }
                $LabProgLista.Children.Insert($orden, $r)
            }
            $orden++
        }
    }
    foreach ($k in @($script:filasProgLab.Keys)) {
        if (-not $vistas.ContainsKey($k)) { $LabProgLista.Children.Remove($script:filasProgLab[$k].Raiz); $script:filasProgLab.Remove($k) }
    }
}
