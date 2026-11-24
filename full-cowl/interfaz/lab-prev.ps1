#  Vista previa en vivo de «Crear laboratorio» (ficha 13, parte 2). Dibuja el MISMO mapa que «Mis laboratorios»
#  (lab-mapa.ps1) con lo que se está preparando, y trae el panel «Esta máquina» (memoria, procesadores y vídeo 3D
#  de la máquina elegida en el dibujo), que sustituye a la ventana de edición de antes.

$script:prevMaq = ''          # nombre de la máquina elegida en la vista previa
$script:prevModelo = $null
$script:prevFilas = @()
$script:prevCargando = $false
$script:prevSucio = $false

function Datos-PrevElegida {
    return @($script:filasLab | Where-Object { [string]$_.nombre -eq $script:prevMaq }) | Select-Object -First 1
}

function Pintar-PrevLab([object[]]$listaVistas, [object[]]$listaOrden) {
    # Se llama desde Refrescar-LabAhora cada vez que cambia algo del formulario
    if (-not $listaVistas -or -not $listaVistas.Count) {
        $LabPrevScroll.Visibility = 'Collapsed'; $LabPrevVacio.Visibility = 'Visible'
        Poner-Vacio $LabPrevVacio 'Ico_Laboratorio' 'Aún no hay nada que mostrar' 'Añade máquinas o elige una plantilla para ver cómo quedarán conectadas.' '' $null $false $false
        $LabPEsta.Visibility = 'Collapsed'; $BtnCrearLab.IsEnabled = $false; $LabPResumen.Text = ''
        $script:prevModelo = $null
        Parar-AnimMapa
        return
    }
    $LabPrevScroll.Visibility = 'Visible'; $LabPrevVacio.Visibility = 'Collapsed'
    $BtnCrearLab.IsEnabled = $true
    $red = $script:opcRedLab[[Math]::Max(0, $LabRed.SelectedIndex)]
    $conDom = [bool]$LabConDominio.IsChecked
    $dom = $(if ($conDom) { $LabDominio.Text.Trim() } else { '' })
    $arr = [bool]$LabArrancar.IsChecked
    $pf = New-Object System.Collections.ArrayList
    foreach ($v in $listaVistas) {
        $d = $v.Datos
        $papel = ''
        foreach ($oo in $listaOrden) { if ($oo.Fila -eq $d) { $papel = [string]$oo.Papel } }
        $ipv = $(if ([string]$v.Ip -match '^\d+\.\d+\.\d+\.\d+$') { [string]$v.Ip } else { '' })
        $bs = Base-PorNombreLab $d.base
        $datos = [pscustomobject]@{
            Tarjetas = @([pscustomobject]@{ Tipo = [string]$red.Tipo; Vnet = [string]$red.Vnet; Pvn = [string]$red.Pvn })
            IP = $ipv; Dominio = $(if ($papel -eq 'dc') { $dom } else { '' }); EsWindows = [bool]($bs -and $bs.EsWindows)
        }
        [void]$pf.Add([pscustomobject]@{
            Datos = $datos; Vmx = "prev:$($d.nombre)"; Nombre = [string]$d.nombre; Familia = $(if ($bs) { [string]$bs.Familia } else { '' })
            Encendida = $arr; Configurando = $false; Progreso = 0; EstadoTexto = ''
            IconoFondo = $v.IconoFondo; IconoSimbolo = $v.IconoSimbolo; IconoLogo = $v.IconoLogo; IconoGlifo = $v.IconoGlifo
            Papel = $papel; Base = [string]$d.base
        })
    }
    $script:prevFilas = $pf
    if (-not @($pf | Where-Object { $_.Nombre -eq $script:prevMaq }).Count) {
        $dcp = @($pf | Where-Object { $_.Papel -eq 'dc' }) | Select-Object -First 1
        $script:prevMaq = $(if ($dcp) { $dcp.Nombre } else { $pf[0].Nombre })
    }
    $script:prevModelo = Construir-ModeloLab $pf
    # Resumen: «3 máquinas · 12 GB de RAM · red aislada · dominio empresa.local · desechable»
    $gb = [Math]::Round((($script:filasLab | ForEach-Object { [double]$_.ram } | Measure-Object -Sum).Sum) / 1024, 1)
    $partes = @((Plural $pf.Count 'máquina' 'máquinas'), "$gb GB de RAM")
    if ($red -and $red.Texto) { $partes += "red $([string]$red.Texto)" }
    if ($conDom -and $dom) { $partes += "dominio $dom" }
    if ($LabDesechable.IsChecked) { $partes += 'desechable' }
    $LabPResumen.Text = ($partes -join ' · ')
    # El dibujo solo se rehace si la pestaña se ve (si no, al volver a «Crear»)
    if ($LabCrear.Visibility -ne 'Visible') { $script:prevSucio = $true; return }
    $script:prevSucio = $false
    Dibujar-MapaLab $LabPrevMapa $script:prevModelo @("prev:$($script:prevMaq)") 1.0 $script:alPulsarPrev
    Ajustar-EscalaCanvas $LabPrevScroll $LabPrevMapa 0.55
    Pintar-EstaMaquina
    Actualizar-AnimLab
}

function Pintar-EstaMaquina {
    $d = Datos-PrevElegida
    $pf = @($script:prevFilas | Where-Object { $_.Nombre -eq $script:prevMaq }) | Select-Object -First 1
    if (-not $d -or -not $pf) { $LabPEsta.Visibility = 'Collapsed'; return }
    $LabPEsta.Visibility = 'Visible'
    $script:prevCargando = $true
    try {
        $LabPSimbolo.Child = Pastilla-Sistema $pf 40
        $LabPNombre.Text = [string]$d.nombre
        $rol = $(if ($pf.Papel -eq 'dc') { 'Controlador de dominio' } elseif ($pf.Papel -eq 'miembro') { 'Cliente del dominio' } elseif ($pf.Papel -eq 'fuera') { 'Fuera del dominio' } else { '' })
        $maq = @($script:prevModelo.Maquinas | Where-Object { $_.Nombre -eq $pf.Nombre }) | Select-Object -First 1
        $LabPSub.Text = (@(@([string]$pf.Familia, $rol, $(if ($maq) { $maq.Ip } else { '' })) | Where-Object { $_ }) -join ' · ')
        $gbv = [double]$d.ram / 1024
        $LabPRam.Text = $(if ($gbv -eq [Math]::Floor($gbv)) { [string][int]$gbv } else { $gbv.ToString('0.#', [Globalization.CultureInfo]::InvariantCulture) })
        $LabPCpu.Text = [string]$d.cpus
        $LabPVram.Text = [string]$d.vram
        $LabPError.Visibility = 'Collapsed'
        $mismas = @($script:filasLab | Where-Object { $_.base -eq $d.base }).Count
        $BtnPAplicar.Content = "Aplicar a $(if ($mismas -eq 2) { 'la otra' } else { "las $mismas" }) $($d.base)"
        $BtnPAplicar.Visibility = $(if ($mismas -gt 1) { 'Visible' } else { 'Collapsed' })
        # Extras de esta máquina (ficha 20)
        $catP = @(Catalogo-Extras (Base-PorNombreLab $d.base))
        $LabPExtrasFila.Visibility = $(if ($catP.Count) { 'Visible' } else { 'Collapsed' })
        $nomP = @($catP | Where-Object { @($d.extras) -contains $_.Id } | ForEach-Object { [string]$_.Nombre })
        $LabPExtras.Text = 'Extras: ' + $(if (-not $nomP.Count) { 'ninguno' } elseif ($nomP.Count -le 3) { $nomP -join ', ' } else { (@($nomP | Select-Object -First 3) -join ', ') + " y $($nomP.Count - 3) más" })
        $LabPEsDc.Visibility = $(if (Puede-SerDc $d) { 'Visible' } else { 'Collapsed' })
        $LabPEsDc.IsChecked = [bool]($LabConDominio.IsChecked -and (Dc-Lab) -eq $d)
    } finally { $script:prevCargando = $false }
}

function Limites-Maquina {
    $maxGb = $(if ($ramPC) { [Math]::Floor($ramPC / 1GB) } else { 128 })
    return @{ MaxGb = [Math]::Max(1, $maxGb); MaxCpu = [Math]::Max(1, [Environment]::ProcessorCount); MaxVram = 8192 }
}

function Aplicar-EstaMaquina {
    # Lee los tres campos, los valida con los mismos límites que la creación y los guarda en la máquina elegida
    if ($script:prevCargando) { return }
    $d = Datos-PrevElegida
    if (-not $d) { return }
    $lim = Limites-Maquina
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $gb = 0.0; $cpu = 0; $vr = 0
    $errores = @()
    if (-not [double]::TryParse($LabPRam.Text.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, $ci, [ref]$gb) -or $gb -lt 1 -or $gb -gt $lim.MaxGb) { $errores += "Memoria: entre 1 y $($lim.MaxGb) GB (lo que deja la RAM de tu PC)." }
    if (-not [int]::TryParse($LabPCpu.Text.Trim(), [ref]$cpu) -or $cpu -lt 1 -or $cpu -gt $lim.MaxCpu) { $errores += "Procesadores: entre 1 y $($lim.MaxCpu)." }
    if (-not [int]::TryParse($LabPVram.Text.Trim(), [ref]$vr) -or $vr -lt 0 -or $vr -gt $lim.MaxVram) { $errores += "Vídeo 3D: entre 0 y $($lim.MaxVram) MB (0 = sin 3D)." }
    if ($errores.Count) {
        $LabPError.Text = ($errores -join ' '); $LabPError.Visibility = 'Visible'
        return
    }
    $LabPError.Visibility = 'Collapsed'
    $ramNueva = [int][Math]::Round($gb * 1024)
    if ([int]$d.ram -eq $ramNueva -and [int]$d.cpus -eq $cpu -and [int]$d.vram -eq $vr) { return }
    $d.ram = $ramNueva; $d.cpus = $cpu; $d.vram = $vr
    Refrescar-Lab
}

function Paso-EstaMaquina([string]$campo, [int]$signo) {
    # Botones − y +: memoria de 1 en 1 GB, procesadores de 1 en 1, vídeo de 64 en 64 MB
    $lim = Limites-Maquina
    $ci = [Globalization.CultureInfo]::InvariantCulture
    switch ($campo) {
        'ram'  { $x = 0.0; if (-not [double]::TryParse($LabPRam.Text.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, $ci, [ref]$x)) { $x = 1 }
                 $LabPRam.Text = [string][Math]::Min($lim.MaxGb, [Math]::Max(1, [Math]::Round($x) + $signo)) }
        'cpu'  { $x = 0; if (-not [int]::TryParse($LabPCpu.Text.Trim(), [ref]$x)) { $x = 1 }
                 $LabPCpu.Text = [string][Math]::Min($lim.MaxCpu, [Math]::Max(1, $x + $signo)) }
        'vram' { $x = 0; if (-not [int]::TryParse($LabPVram.Text.Trim(), [ref]$x)) { $x = 0 }
                 $LabPVram.Text = [string][Math]::Min($lim.MaxVram, [Math]::Max(0, $x + 64 * $signo)) }
    }
    Aplicar-EstaMaquina
}

function Elegir-PrevLab([string]$vmx) {
    if (-not $vmx.StartsWith('prev:')) { return }
    $script:prevMaq = $vmx.Substring(5)
    Marcar-CartaElegida @($vmx)
    Pintar-EstaMaquina
}
$script:alPulsarPrev = { param($s, $a) Elegir-PrevLab ([string]$s.Tag) }

# ---------------------------------------------------------------- eventos
foreach ($pe in @($LabPRam, $LabPCpu, $LabPVram)) {
    $pe.Add_LostFocus({ Aplicar-EstaMaquina })
    $pe.Add_KeyDown({ param($s, $a) if ($a.Key -eq [System.Windows.Input.Key]::Return) { Aplicar-EstaMaquina; $a.Handled = $true } })
}
$BtnPRamMenos.Add_Click({ Paso-EstaMaquina 'ram' -1 })
$BtnPRamMas.Add_Click({ Paso-EstaMaquina 'ram' 1 })
$BtnPCpuMenos.Add_Click({ Paso-EstaMaquina 'cpu' -1 })
$BtnPCpuMas.Add_Click({ Paso-EstaMaquina 'cpu' 1 })
$BtnPVramMenos.Add_Click({ Paso-EstaMaquina 'vram' -1 })
$BtnPVramMas.Add_Click({ Paso-EstaMaquina 'vram' 1 })
$BtnPAplicar.Add_Click({
    $d = Datos-PrevElegida
    if (-not $d) { return }
    Aplicar-EstaMaquina
    foreach ($o in @($script:filasLab | Where-Object { $_.base -eq $d.base })) { $o.ram = $d.ram; $o.cpus = $d.cpus; $o.vram = $d.vram; $o.extras = @($d.extras | Where-Object { $_ }) }
    Refrescar-Lab
})
function Red-ConInternetLab {
    # NAT y puente tienen Internet; un segmento LAN (aislada) y «solo anfitrión», no
    try { $opRed = $script:opcRedLab[[Math]::Max(0, $LabRed.SelectedIndex)]; return (@('nat', 'bridged') -contains [string]$opRed.Tipo) } catch { return $true }
}
$BtnPExtras.Add_Click({
    $d = Datos-PrevElegida
    if (-not $d) { return }
    try {
        $baseP = Base-PorNombreLab $d.base
        $bloq = @{}
        if ($LabConDominio.IsChecked -and (Dc-Lab) -eq $d) { $bloq = @{ dns = 'Ya lo instala Active Directory'; adds = 'Ya lo instala Active Directory' } }
        $elegidos = Elegir-ExtrasDialogo $baseP @($d.extras | Where-Object { $_ }) (Red-ConInternetLab) $bloq ([string]$d.nombre)
        if ($null -eq $elegidos) { return }
        $d.extras = @($elegidos)
        Pintar-EstaMaquina
    } catch { Error-Amable 'No se ha podido abrir la lista de extras.' 'Prueba otra vez. Si se repite, copia el detalle al avisar del fallo.' ($_ | Out-String) }
})
# Elegir en la lista del formulario también elige en el dibujo
$LabLista.Add_SelectionChanged({
    $el = @($LabLista.SelectedItems)
    if ($el.Count -eq 1 -and -not $script:prevCargando) {
        $nm = [string]$el[0].Datos.nombre
        if ($nm -and $nm -ne $script:prevMaq -and $script:prevModelo) { Elegir-PrevLab "prev:$nm" }
    }
})
$LabPrevScroll.Add_SizeChanged({ Ajustar-EscalaCanvas $LabPrevScroll $LabPrevMapa 0.55 })
# «Es el controlador del dominio» (sustituye a «Hacer controlador» de la lista)
$LabPEsDc.Add_Click({
    $dd = Datos-PrevElegida
    if (-not $dd) { return }
    if ($LabPEsDc.IsChecked) {
        $script:dcLab = $dd
        if (-not $LabConDominio.IsChecked) {
            if (-not $LabDominio.Text.Trim()) { $LabDominio.Text = 'empresa.local' }
            $LabConDominio.IsChecked = $true
        }
    } elseif ($script:dcLab -eq $dd) { $script:dcLab = $null }
    Refrescar-Lab
})
