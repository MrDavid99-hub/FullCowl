param([string]$Pedido)   # lo crea la ventana (pestaña Laboratorio)
# =====================================================================
#  Crea un laboratorio entero de una vez: varias máquinas de las bases,
#  todas en la misma red, con IP seguidas y, si se pide, un dominio
#  (el primer Windows Server es el controlador y los demás Windows se unen).
#  Cada máquina se crea con nueva-maquina.ps1 y se configura sola al arrancar.
# =====================================================================
. "$PSScriptRoot\comun.ps1"
if (-not $Pedido) { Salir-ConError "Ábrelo desde la ventana: pestaña Laboratorio." }
$vmrun = Buscar-Vmrun
$P = Leer-Pedido $Pedido
$maqs = @($P.maquinas)
$labId = [guid]::NewGuid().ToString('N').Substring(0, 12)
$bases = @(Obtener-Bases)

Escribir-Titulo "Laboratorio '$($P.nombre)': $($maqs.Count) máquina(s)"
Write-Host "  Red: $($P.red.texto)"
if ($P.ip.modo -eq 'fija') { Write-Host "  IP fija desde $($P.ip.desde)/$($P.ip.prefix)$(if ($P.ip.gw) { "  puerta $($P.ip.gw)" })" } else { Write-Host '  IP: automática (DHCP)' }
if ($P.dominio) { Write-Host "  Dominio: $($P.dominio.dominio) ($($P.dominio.netbios))" }
if ($P.desechable) { Write-Host '  Desechable: se borra todo al apagar todas sus máquinas.' -ForegroundColor Yellow }
Write-Host ""

# --- IP de cada máquina (en el orden de la lista; el controlador va primero)
$ipDe = @{}
$ipDc = $null
if ($P.ip.modo -eq 'fija') {
    $b = ([string]$P.ip.desde).Split('.')
    for ($i = 0; $i -lt $maqs.Count; $i++) { $ipDe[$maqs[$i].nombre] = "$($b[0]).$($b[1]).$($b[2]).$([int]$b[3] + $i)" }
    $dc = $maqs | Where-Object { $_.papel -eq 'dc' } | Select-Object -First 1
    if ($dc) { $ipDc = $ipDe[$dc.nombre] }
}
$dnsComun = @($P.ip.dns | Where-Object { $_ })

# --- Crear cada máquina
$creadas = @(); $fallidas = @()
$n = 0
foreach ($m in $maqs) {
    $n++
    Write-Host ""
    Write-Host "[$n/$($maqs.Count)] $($m.nombre)  ($($m.base))" -ForegroundColor Cyan
    $base = $bases | Where-Object { $_.Nombre -eq $m.base } | Select-Object -First 1
    $ip = $null
    if ($ipDe.ContainsKey($m.nombre)) {
        # DNS: con dominio, todos al controlador (el controlador, a sí mismo y luego al de la red)
        if ($m.papel -eq 'dc') { $dns = @($ipDc) + @($dnsComun | Where-Object { $_ -ne $ipDc }) }
        elseif ($ipDc) { $dns = @($ipDc) }
        else { $dns = $dnsComun }
        $ip = [ordered]@{ addr = $ipDe[$m.nombre]; prefix = [int]$P.ip.prefix; gw = [string]$P.ip.gw; dns = @($dns) }
    }
    $ad = $null
    if ($P.dominio -and $m.papel -eq 'dc') { $ad = [ordered]@{ modo = 'dc'; dominio = $P.dominio.dominio; netbios = $P.dominio.netbios; dcip = $ipDc } }
    elseif ($P.dominio -and $m.papel -eq 'miembro' -and $ipDc) { $ad = [ordered]@{ modo = 'unir'; dominio = $P.dominio.dominio; netbios = $P.dominio.netbios; dcip = $ipDc } }
    # Extras de cada máquina (ficha 20): nueva-maquina.ps1 los comprueba contra el catálogo de su base
    $extras = @(); $paquetes = @()
    $pedidosM = @($m.extras | Where-Object { $_ } | ForEach-Object { [string]$_ })
    if ($base -and $base.EsWindows) { $extras = $pedidosM } else { $paquetes = $pedidosM }
    if ($base -and $base.EsWindows -and $P.ping -and $extras -notcontains 'ping') { $extras += 'ping' }   # que se vean con ping
    $pedidoM = [ordered]@{
        base = $m.base; nombre = $m.nombre; hostname = (Nombre-Equipo $m.nombre); tipo = 'linked'
        ram = [int]$m.ram; cpus = [int]$m.cpus; vram = [int]$m.vram
        ip = $ip; ad = $ad; extras = @($extras); actualizar = $false; paquetes = @($paquetes); arrancar = $false
        desechable = [bool]$P.desechable; lab = [string]$P.nombre; labid = $labId; red = $P.red
    }
    $archivo = Guardar-Pedido $pedidoM
    & (Join-Path $PSScriptRoot 'nueva-maquina.ps1') -Pedido $archivo -EnLote
    $vmx = Join-Path (Join-Path $Config.CarpetaVMs $m.nombre) "$($m.nombre).vmx"
    if (Test-Path -LiteralPath $vmx) { $creadas += [pscustomobject]@{ Nombre = $m.nombre; Vmx = $vmx; Papel = $m.papel; IP = $(if ($ip) { $ip.addr }) } }
    else { $fallidas += $m.nombre }
}

# --- Arrancar (el controlador primero)
if ($P.arrancar -and $creadas.Count) {
    Write-Host ""
    Write-Host "Arrancando..." -ForegroundColor Cyan
    foreach ($c in @($creadas | Sort-Object { if ($_.Papel -eq 'dc') { 0 } else { 1 } })) {
        Iniciar-Oculto $vmrun "-T ws start `"$($c.Vmx)`" gui"
        Start-Sleep 4
    }
}
# Estado inicial (ficha 28): lo guarda el vigilante cuando todas las máquinas terminan de configurarse
$pideInicio = [bool]($P.estadoInicial -and -not $P.desechable -and $creadas.Count)
if ($pideInicio) { Pedir-EstadoInicial $labId ([string]$P.nombre) }
if ($creadas.Count) { Iniciar-Vigilante }   # progreso, aviso al terminar y borrado de las desechables

# --- Resumen
Escribir-Titulo "Laboratorio '$($P.nombre)' creado"
foreach ($c in $creadas) {
    $papel = switch ($c.Papel) { 'dc' { "  controlador de $($P.dominio.dominio)" } 'miembro' { "  se une a $($P.dominio.dominio)" } default { '' } }
    Write-Host ("  {0,-28} {1,-16}{2}" -f $c.Nombre, $c.IP, $papel)
}
if ($fallidas.Count) { Write-Host "  No se crearon: $($fallidas -join ', ')" -ForegroundColor Red }
Write-Host ""
if ($P.dominio) {
    Write-Host "  El controlador tarda unos 10-15 minutos en crear el dominio; los demás Windows" -ForegroundColor Cyan
    Write-Host "  esperan solos (hasta 30 min) y se unen en cuanto responde." -ForegroundColor Cyan
}
Write-Host "  Progreso: Full Cowl > Laboratorio > Ver progreso. Cuando estén todas, sale un aviso de Windows." -ForegroundColor Cyan
if ($pideInicio) {
    Write-Host "  Al terminar, Full Cowl guardará el estado inicial del laboratorio (las máquinas se apagan y se" -ForegroundColor Cyan
    Write-Host "  vuelven a encender un momento) para poder repetir la práctica con un clic." -ForegroundColor Cyan
}
if ($P.desechable) {
    Write-Host "  Cuando apagues TODAS las máquinas del laboratorio, se borrarán solas (sale un aviso)." -ForegroundColor Yellow
    Write-Host "  Para quedarte con alguna: Mis máquinas > elígela > Conservar." -ForegroundColor Yellow
}
Write-Host ""
Read-Host "Pulsa Enter para cerrar"
