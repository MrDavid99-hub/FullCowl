param([string]$Pedido)   # lo crea la ventana: máquina, destino y lista de usuarios
# =====================================================================
#  Crea usuarios en masa dentro de una máquina (Active Directory, usuarios
#  locales de Windows o usuarios de Linux) usando las VMware Tools.
# =====================================================================
. "$PSScriptRoot\comun.ps1"
if (-not $Pedido) { Salir-ConError "Ábrelo desde la ventana: Mis máquinas > Usuarios..." }
$vmrun = Buscar-Vmrun
$P = Leer-Pedido $Pedido
$vmx = [string]$P.vmx
$usuarios = @($P.usuarios)
$esLinux = $P.destino -eq 'linux'

# --- 0. Validar los datos (vienen de un CSV: nada de comillas, comas o caracteres que se cuelen
#        en las órdenes de Active Directory o de Linux)
$malos = @()
$reUsu = if ($esLinux) { '^[A-Za-z_][A-Za-z0-9._-]{0,31}$' } else { '^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$' }
$reGrupo = if ($esLinux) { '^$|^[A-Za-z_][A-Za-z0-9._-]{0,31}$' } else { '^$|^[\p{L}\p{Nd}][\p{L}\p{Nd} ._-]{0,63}$' }
$reOu = '^$|^[\p{L}\p{Nd}][\p{L}\p{Nd} ._-]{0,63}$'
if ([string]$P.ou -notmatch $reOu) { $malos += "unidad organizativa '$($P.ou)'" }
foreach ($u in $usuarios) {
    $u.usuario = ([string]$u.usuario).Trim()
    if ($u.usuario -cnotmatch $reUsu) { $malos += "usuario '$($u.usuario)'"; continue }
    if ([string]$u.grupo -cnotmatch $reGrupo) { $malos += "grupo '$($u.grupo)' ($($u.usuario))" }
    if ([string]$u.ou -notmatch $reOu) { $malos += "unidad organizativa '$($u.ou)' ($($u.usuario))" }
    if (-not [string]$u.password -or [string]$u.password -match '[\x00-\x1F]') { $malos += "contraseña de '$($u.usuario)' (vacía o con tabuladores, saltos de línea u otros caracteres de control)" }
    foreach ($campo in 'nombre', 'apellidos') { $u.$campo = (([string]$u.$campo) -replace '[\x00-\x1F",;:=<>\\]', ' ').Trim() }
}
if ($malos.Count) {
    $ayuda = if ($esLinux) { "En Linux: usuarios y grupos con letras sin tildes, números, punto, guion y guion bajo (empezando por letra, máx. 32)." } else { "En Windows: usuarios con letras, números, punto, guion y guion bajo (máx. 20); grupos y OU con letras, números, espacios, punto, guion y guion bajo." }
    Salir-ConError "Hay datos no válidos en la lista:`n  $(($malos | Select-Object -First 15) -join "`n  ")`n`n$ayuda"
}

Escribir-Titulo "Crear $($usuarios.Count) usuarios en '$($P.nombre)'"
switch ($P.destino) {
    'ad'    { Write-Host "  Destino: Active Directory, dominio $($P.dominio)$(if ($P.ou) { ", unidad organizativa $($P.ou)" })" }
    'local' { Write-Host "  Destino: usuarios locales de Windows" }
    default { Write-Host "  Destino: usuarios de Linux" }
}
Write-Host ""

# --- 1. Encender la máquina si está apagada
if ((Maquinas-Encendidas $vmrun) -notcontains $vmx.ToLower()) {
    Write-Host "Encendiendo la máquina..." -ForegroundColor Cyan
    Iniciar-Oculto $vmrun "-T ws start `"$vmx`" gui"
}

# --- 2. Esperar a las VMware Tools (hasta 10 minutos)
Write-Host "Esperando a que el sistema arranque y respondan las VMware Tools..." -ForegroundColor Cyan
$listo = $false
for ($i = 0; $i -lt 120; $i++) {
    $t = (& $vmrun -T ws checkToolsState $vmx 2>$null | Select-Object -Last 1)
    if ("$t".Trim() -eq 'running') { $listo = $true; break }
    Start-Sleep 5
}
if (-not $listo) {
    $extra = if ($esLinux) { '' } else { "`nSi en VMware sale «Install VMware Tools», la base de Windows es anterior al 29/10/2026: rehazla (o instálalas a mano: menú VM > Install VMware Tools)." }
    Salir-ConError "Las VMware Tools no responden en la máquina.$extra"
}

# --- 3. Entrar con el usuario de las VMs
$pass = Obtener-Password
# (el de su base y, si no, el de Ajustes; se reintenta: recién encendida aún no acepta sesiones)
$usu = Entrar-Invitado $vmrun $vmx $esLinux $P.netbios $pass 12
if (-not $usu) { Salir-ConError "No se pudo entrar en la máquina con el usuario '$(Usuario-DeVm $vmx)'. ¿Ha terminado de arrancar?" }
function Vm { & $vmrun -T ws -gu $usu -gp $pass @args 2>&1 }

# --- 4. Pasar los datos y el script, y ejecutarlo
$tmp = Join-Path $env:TEMP ("vmtareas-usu-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$logLocal = Join-Path $tmp 'resultado.log'
try {
    Write-Host "Creando usuarios dentro de la máquina..." -ForegroundColor Cyan
    if ($esLinux) {
        # Todo va a una carpeta privada del usuario de la VM (no a /tmp, que pueden leer todos)
        $dirVm = Carpeta-PrivadaLinux $vmrun $vmx $usu $pass
        $lineas = foreach ($u in $usuarios) {
            $nom = ("$($u.nombre) $($u.apellidos)").Trim() -replace '[\t:,]', ' '
            ($u.usuario, $nom, $u.password, $u.grupo) -join [char]0x1F   # (no tabuladores: ver usuarios-linux.sh)
        }
        [IO.File]::WriteAllText((Join-Path $tmp 'u.tsv'), (($lineas -join "`n") + "`n"), $utf8)
        [IO.File]::WriteAllText((Join-Path $tmp 'p'), "$pass`n", $utf8)
        [IO.File]::WriteAllText((Join-Path $tmp 'c'), $(if ($P.cambiar) { '1' } else { '0' }), $utf8)
        $sh = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'clon\usuarios-linux.sh')) -replace "`r`n", "`n"
        [IO.File]::WriteAllText((Join-Path $tmp 'u.sh'), $sh, $utf8)
        $run = "#!/bin/bash`nD='$dirVm'`nchmod 700 `"`$D`"`nsudo -S -p '' bash `"`$D/u.sh`" `"`$D`" < `"`$D/p`" > `"`$D/resultado.log`" 2>&1`nrm -f `"`$D/p`" `"`$D/u.sh`" `"`$D/run.sh`" `"`$D/u.tsv`" `"`$D/c`"`n"
        [IO.File]::WriteAllText((Join-Path $tmp 'run.sh'), $run, $utf8)
        try {
            foreach ($f in 'u.tsv', 'p', 'c', 'u.sh', 'run.sh') {
                $o = Vm copyFileFromHostToGuest $vmx (Join-Path $tmp $f) "$dirVm/$f"
                if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar a la máquina: $o" }
            }
            Remove-Item (Join-Path $tmp 'p') -Force
            $fallo = Ejecutar-EnInvitado $vmrun $vmx $usu $pass '/bin/bash' "$dirVm/run.sh" "$dirVm/resultado.log" $logLocal
            if ($fallo) { throw $fallo }
        } finally {
            Vm deleteDirectoryInGuest $vmx $dirVm | Out-Null   # con lo que quede dentro (también la contraseña si algo falló)
        }
    } else {
        $datos = [ordered]@{ destino = $P.destino; ou = $P.ou; cambiar = [bool]$P.cambiar; usuarios = $usuarios }
        [IO.File]::WriteAllText((Join-Path $tmp 'u.json'), ($datos | ConvertTo-Json -Depth 5), $utf8)
        foreach ($par in @(@('u.json', 'C:\Windows\Temp\vmt-usuarios.json'),
                           @((Join-Path $PSScriptRoot 'clon\usuarios-windows.ps1'), 'C:\Windows\Temp\vmt-usuarios.ps1'))) {
            $origen = if ([IO.Path]::IsPathRooted($par[0])) { $par[0] } else { Join-Path $tmp $par[0] }
            $o = Vm copyFileFromHostToGuest $vmx $origen $par[1]
            if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar a la máquina: $o" }
        }
        try {
            $fallo = Ejecutar-EnInvitado $vmrun $vmx $usu $pass 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' '-NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\vmt-usuarios.ps1' 'C:\Windows\Temp\vmt-usuarios.log' $logLocal
        } finally {
            foreach ($f in 'C:\Windows\Temp\vmt-usuarios.log', 'C:\Windows\Temp\vmt-usuarios.ps1', 'C:\Windows\Temp\vmt-usuarios.json') {
                Vm deleteFileInGuest $vmx $f | Out-Null
            }
        }
        if ($fallo) { throw $fallo }
    }
    Write-Host ""
    foreach ($l in [IO.File]::ReadAllLines($logLocal, [Text.Encoding]::UTF8)) {
        $color = if ($l -match '^(FALLO|ERROR)') { 'Red' } elseif ($l -match '^YA EXISTE') { 'Yellow' } elseif ($l -match '^CREADO') { 'Green' } else { 'Gray' }
        Write-Host $l -ForegroundColor $color
    }
} catch {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Salir-ConError "$_"
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Read-Host "Pulsa Enter para cerrar"
