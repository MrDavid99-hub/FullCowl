param([string]$Pedido)   # lo crea la ventana (Mis máquinas > Red...): máquinas y tarjetas con su IP
# =====================================================================
#  Aplica IP fija o DHCP dentro de varias máquinas a la vez (VMware Tools)
# =====================================================================
. "$PSScriptRoot\comun.ps1"
if (-not $Pedido) { Salir-ConError "Ábrelo desde la ventana: Mis máquinas > Red..." }
$vmrun = Buscar-Vmrun
$P = Leer-Pedido $Pedido
$maquinas = @($P.maquinas)
Escribir-Titulo "Red del laboratorio: $($maquinas.Count) máquina(s)"
# Validar lo que se va a escribir dentro de las máquinas (configuración de red como root/SYSTEM)
$malos = @()
foreach ($m in $maquinas) {
    foreach ($t in @($m.tarjetas)) {
        $donde = "$($m.nombre), tarjeta $($t.mac)"
        if ([string]$t.mac -notmatch '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$') { $malos += "$($donde): MAC no válida"; continue }
        if (@('fija', 'dhcp', 'igual') -notcontains [string]$t.modo) { $malos += "$($donde): modo '$($t.modo)'" }
        if ([string]$t.nombre -match '[\x00-\x1F"\\=\[\]]' -or ([string]$t.nombre).Length -gt 60) { $malos += "$($donde): nombre de red '$($t.nombre)'" }
        if ($t.modo -eq 'fija') {
            $pre = 0
            if (-not (Es-IPv4 ([string]$t.ip))) { $malos += "$($donde): IP '$($t.ip)'" }
            if (-not [int]::TryParse([string]$t.prefix, [ref]$pre) -or $pre -lt 1 -or $pre -gt 32) { $malos += "$($donde): prefijo '$($t.prefix)'" }
            if ($t.gw -and -not (Es-IPv4 ([string]$t.gw))) { $malos += "$($donde): puerta '$($t.gw)'" }
            foreach ($dn in @($t.dns | Where-Object { $_ })) { if (-not (Es-IPv4 ([string]$dn))) { $malos += "$($donde): DNS '$dn'" } }
        }
    }
}
if ($malos.Count) { Salir-ConError "Datos de red no válidos:`n  $($malos -join "`n  ")" }

$pass = Obtener-Password

# --- Encender las que estén apagadas (todas a la vez, para no esperar una tras otra)
$encendidas = Maquinas-Encendidas $vmrun
foreach ($m in $maquinas) {
    if ($encendidas -notcontains ([string]$m.vmx).ToLower()) {
        Write-Host "Encendiendo $($m.nombre)..." -ForegroundColor Cyan
        Iniciar-Oculto $vmrun "-T ws start `"$($m.vmx)`" gui"
        Start-Sleep 3
    }
}

$utf8 = [Text.UTF8Encoding]::new($false)
$resumen = @()
foreach ($m in $maquinas) {
    $vmx = [string]$m.vmx
    $esLinux = -not [bool]$m.eswindows
    Write-Host ""
    Write-Host "== $($m.nombre) ==" -ForegroundColor Cyan
    Write-Host "  Esperando a que arranque y respondan las VMware Tools..."
    if (-not (Esperar-Tools $vmrun $vmx 600)) {
        Write-Host "  FALLO: las VMware Tools no responden (si es Windows, su base puede ser anterior al 29/10/2026: rehazla o instálalas con menú VM > Install VMware Tools)." -ForegroundColor Red
        $resumen += "$($m.nombre): sin VMware Tools"; continue
    }
    $usu = Entrar-Invitado $vmrun $vmx $esLinux $m.netbios $pass 12
    if (-not $usu) {
        Write-Host "  FALLO: no se pudo entrar con el usuario '$(Usuario-DeVm $vmx)'." -ForegroundColor Red
        $resumen += "$($m.nombre): no se pudo entrar"; continue
    }
    $tmp = Join-Path $env:TEMP ("vmtareas-red-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $logLocal = Join-Path $tmp 'resultado.log'
    try {
        if ($esLinux) {
            # Carpeta privada del usuario de la VM (no /tmp, que pueden leer todos)
            $dirVm = Carpeta-PrivadaLinux $vmrun $vmx $usu $pass
            $lineas = foreach ($t in @($m.tarjetas)) {
                $ipp = if ($t.modo -eq 'fija') { "$($t.ip)/$($t.prefix)" } else { '' }
                # (separados por 0x1F, no por tabuladores: ver clon\red-linux.sh)
                (([string]$t.mac).ToLower(), $t.modo, $ipp, [string]$t.gw, (@($t.dns) -join ','), [string]$t.nombre) -join [char]0x1F
            }
            [IO.File]::WriteAllText((Join-Path $tmp 'r.tsv'), (($lineas -join "`n") + "`n"), $utf8)
            [IO.File]::WriteAllText((Join-Path $tmp 'p'), "$pass`n", $utf8)
            $sh = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'clon\red-linux.sh')) -replace "`r`n", "`n"
            [IO.File]::WriteAllText((Join-Path $tmp 'r.sh'), $sh, $utf8)
            $run = "#!/bin/bash`nD='$dirVm'`nchmod 700 `"`$D`"`nsudo -S -p '' bash `"`$D/r.sh`" `"`$D`" < `"`$D/p`" > `"`$D/resultado.log`" 2>&1`nrm -f `"`$D/p`" `"`$D/r.sh`" `"`$D/run.sh`" `"`$D/r.tsv`"`n"
            [IO.File]::WriteAllText((Join-Path $tmp 'run.sh'), $run, $utf8)
            try {
                foreach ($f in 'r.tsv', 'p', 'r.sh', 'run.sh') {
                    $o = & $vmrun -T ws -gu $usu -gp $pass copyFileFromHostToGuest $vmx (Join-Path $tmp $f) "$dirVm/$f" 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar a la máquina: $o" }
                }
                Remove-Item (Join-Path $tmp 'p') -Force
                $fallo = Ejecutar-EnInvitado $vmrun $vmx $usu $pass '/bin/bash' "$dirVm/run.sh" "$dirVm/resultado.log" $logLocal
                if ($fallo) { throw $fallo }
            } finally {
                & $vmrun -T ws -gu $usu -gp $pass deleteDirectoryInGuest $vmx $dirVm 2>&1 | Out-Null
            }
        } else {
            $datos = [ordered]@{ ping = [bool]$P.ping; tarjetas = @($m.tarjetas) }
            [IO.File]::WriteAllText((Join-Path $tmp 'r.json'), ($datos | ConvertTo-Json -Depth 5), $utf8)
            foreach ($par in @(@((Join-Path $tmp 'r.json'), 'C:\Windows\Temp\vmt-red.json'), @((Join-Path $PSScriptRoot 'clon\red-windows.ps1'), 'C:\Windows\Temp\vmt-red.ps1'))) {
                $o = & $vmrun -T ws -gu $usu -gp $pass copyFileFromHostToGuest $vmx $par[0] $par[1] 2>&1
                if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar a la máquina: $o" }
            }
            try {
                $fallo = Ejecutar-EnInvitado $vmrun $vmx $usu $pass 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' '-NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\vmt-red.ps1' 'C:\Windows\Temp\vmt-red.log' $logLocal
            } finally {
                foreach ($f in 'C:\Windows\Temp\vmt-red.log', 'C:\Windows\Temp\vmt-red.ps1', 'C:\Windows\Temp\vmt-red.json') {
                    & $vmrun -T ws -gu $usu -gp $pass deleteFileInGuest $vmx $f 2>&1 | Out-Null
                }
            }
            if ($fallo) { throw $fallo }
        }
        if (-not (Test-Path $logLocal)) { throw "La máquina no devolvió el resultado. $o" }
        $fallos = 0
        foreach ($l in [IO.File]::ReadAllLines($logLocal, [Text.Encoding]::UTF8)) {
            if (-not $l.Trim()) { continue }
            $color = if ($l -match '^(FALLO|ERROR)') { $fallos++; 'Red' } else { 'Green' }
            Write-Host "  $l" -ForegroundColor $color
        }
        $resumen += "$($m.nombre): $(if ($fallos) { 'con fallos' } else { 'correcto' })"
    } catch {
        Write-Host "  FALLO: $_" -ForegroundColor Red
        $resumen += "$($m.nombre): $_"
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Escribir-Titulo "Resumen"
$resumen | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Read-Host "Pulsa Enter para cerrar"
