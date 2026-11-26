# =====================================================================
#  Instalador de Full Cowl (ficha 33). Lo lanzan el comando de una línea
#  (instalar.ps1, tras descargar y comprobar el ZIP) y «Instalar Full Cowl.bat»
#  (desde un ZIP descargado a mano).
#
#  No pide administrador. Instala en %USERPROFILE%\Full Cowl (o la carpeta que
#  elijas); si ya hay una instalación, la actualiza/repara sin tocar los datos
#  de este PC (configuración, contraseña cifrada, estado, máquinas).
#  Volver a ejecutarlo siempre es seguro.
#
#  -Origen     carpeta con el programa descomprimido (por defecto, la de este ZIP)
#  -Carpeta    dónde instalar
#  -Si         no pregunta (acepta lo propuesto y abre Full Cowl al final)
#  -Silencioso no pregunta ni abre Full Cowl
# =====================================================================
param([string]$Origen, [string]$Carpeta, [switch]$Si, [switch]$Silencioso)

$ErrorActionPreference = 'Stop'
if ($Silencioso) { $Si = $true }
if (-not $Origen) { $Origen = Split-Path (Split-Path $PSScriptRoot) }
$Origen = (Resolve-Path -LiteralPath $Origen).Path.TrimEnd('\')
$registro = Join-Path ([IO.Path]::GetTempPath()) 'FullCowl-instalacion.log'
try { $Host.UI.RawUI.WindowTitle = 'Instalar Full Cowl' } catch {}

function Apuntar([string]$t) { try { Add-Content -LiteralPath $registro -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}" -f (Get-Date), $t) -Encoding UTF8 } catch {} }
function Decir([string]$t, [string]$color = 'Gray') { Write-Host $t -ForegroundColor $color; Apuntar $t }
function Paso([int]$n, [string]$t) { Write-Host ''; Decir "[$n de 5] $t" 'Cyan' }
function Preguntar([string]$t, [string]$porDefecto = 's') {
    if ($Si) { return $porDefecto }
    $r = Read-Host $t
    if (-not $r) { return $porDefecto }
    return $r.Trim().ToLower()
}
function Terminar-ConError([string]$que, [string]$hacer) {
    Write-Host ''
    Decir "No se ha podido terminar: $que" 'Red'
    if ($hacer) { Decir "Qué hacer: $hacer" 'Yellow' }
    Decir "El detalle está en $registro" 'DarkGray'
    if (-not $Silencioso) { [void](Read-Host 'Pulsa Enter para cerrar') }
    exit 1
}

Apuntar '==== Instalación de Full Cowl ===='
$version = ''
try { $version = ([IO.File]::ReadAllText((Join-Path $Origen 'VERSION'))).Trim() } catch {}

# ---------------------------------------------------------------- comprobaciones previas
if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10) {
    Terminar-ConError 'Full Cowl necesita Windows 10 u 11 de 64 bits.' ''
}
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Terminar-ConError "Hay que usar el PowerShell de Windows (5.1); este es el $($PSVersionTable.PSVersion)." 'Abre «Windows PowerShell» (no «PowerShell 7») y vuelve a pegar el comando.'
}
if (-not (Test-Path -LiteralPath (Join-Path $Origen 'full-cowl\abrir-nueva.ps1'))) {
    Terminar-ConError 'La carpeta descargada no tiene el programa completo.' 'Vuelve a descargarlo.'
}

# ---------------------------------------------------------------- resumen y destino
if (-not $Carpeta) { $Carpeta = Join-Path $env:USERPROFILE 'Full Cowl' }
Write-Host ''
Decir "Full Cowl $version" 'Green'
Decir "Voy a instalar Full Cowl en «$Carpeta», descargar Packer (unos 25 MB) en esa carpeta y crear accesos directos."
Decir 'No necesito permisos de administrador y no cambio nada fuera de esa carpeta, salvo los accesos directos.'
Decir 'Las máquinas, las bases y las ISO no van aquí: las eliges luego en el asistente de Full Cowl.' 'DarkGray'
if (-not $Si) {
    $otra = Read-Host 'Pulsa Enter para seguir, o escribe otra carpeta'
    if ($otra) { $Carpeta = $otra.Trim().Trim('"') }
}

Paso 1 'Carpeta de destino'
try { $Carpeta = [IO.Path]::GetFullPath($Carpeta).TrimEnd('\') } catch { Terminar-ConError "La carpeta «$Carpeta» no es válida." 'Escribe una ruta completa, por ejemplo %USERPROFILE%\Full Cowl.' }
foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($pf -and $Carpeta.StartsWith($pf, [StringComparison]::OrdinalIgnoreCase)) {
        Terminar-ConError 'No se instala en «Archivos de programa» (pediría administrador).' 'Usa la carpeta propuesta u otra de tu usuario.'
    }
}
$avisos = @()
$od = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ }
if (@($od | Where-Object { $Carpeta.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -or $Carpeta -match '\\OneDrive') {
    $avisos += 'La carpeta está dentro de OneDrive: la sincronización puede bloquear archivos mientras Full Cowl trabaja.'
}
if ($Carpeta -match '[^\x20-\x7E]') { $avisos += 'La ruta tiene tildes u otros caracteres especiales: Packer y VMware a veces fallan con ellas.' }
foreach ($av in $avisos) { Decir "Aviso: $av" 'Yellow' }
if ($avisos.Count -and (Preguntar '¿Instalar ahí de todos modos? [S/n]') -like 'n*') { Terminar-ConError 'Cancelado.' 'Vuelve a ejecutarlo y escribe otra carpeta.' }
$yaInstalado = Test-Path -LiteralPath (Join-Path $Carpeta 'full-cowl\abrir-nueva.ps1')
if ($yaInstalado) { Decir 'Ya hay una instalación: se actualiza/repara sin tocar tus ajustes ni tus máquinas.' 'Green' }
Decir "Carpeta: $Carpeta"

Paso 2 'Copiar el programa'
if ($Origen -eq $Carpeta) {
    Decir 'El programa ya está en esa carpeta: no hay nada que copiar.'
} else {
    # Full Cowl abierto desde esa carpeta: hay que cerrarlo antes de sustituir sus archivos
    for ($intento = 1; ; $intento++) {
        $abiertos = @()
        try {
            $patron = [regex]::Escape((Join-Path $Carpeta 'full-cowl'))
            $abiertos = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object { $_.CommandLine -match $patron -and $_.CommandLine -match 'abrir-nueva|ventana-nueva' })
        } catch {}
        if (-not $abiertos.Count) { break }
        if ($Silencioso -or $intento -gt 3) { Terminar-ConError 'Full Cowl está abierto.' 'Ciérralo y vuelve a ejecutar el instalador.' }
        Decir 'Full Cowl está abierto: ciérralo para seguir.' 'Yellow'
        [void](Read-Host 'Cuando lo hayas cerrado, pulsa Enter')
    }
    try {
        if (-not (Test-Path -LiteralPath $Carpeta)) { [void](New-Item -ItemType Directory -Path $Carpeta -Force) }
        . (Join-Path $Origen 'full-cowl\instalacion\programa.ps1')
        $res = Copiar-Programa $Origen $Carpeta
        Decir "Archivos copiados: $($res.Copiados) · quitados (ya no hacen falta): $($res.Borrados)"
        if ($res.Respetados.Count) { Decir "Cambiados a mano, no se han borrado: $($res.Respetados -join ', ')" 'Yellow' }
    } catch {
        Apuntar $_.Exception.ToString()
        Terminar-ConError "al copiar los archivos ($($_.Exception.Message))." 'Comprueba que tienes espacio y que ningún programa (antivirus, OneDrive) tiene abiertos los archivos, y vuelve a ejecutarlo.'
    }
}
foreach ($d in @('full-cowl\estado')) { try { [void](New-Item -ItemType Directory -Path (Join-Path $Carpeta $d) -Force) } catch {} }

Paso 3 'VMware Workstation'
$vmrun = $null
foreach ($clave in 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation', 'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation') {
    try { $dirVm = (Get-ItemProperty -Path $clave -ErrorAction Stop).InstallPath; if ($dirVm -and (Test-Path (Join-Path $dirVm 'vmrun.exe'))) { $vmrun = Join-Path $dirVm 'vmrun.exe' } } catch {}
}
foreach ($c in 'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe', 'C:\Program Files\VMware\VMware Workstation\vmrun.exe') { if (-not $vmrun -and (Test-Path $c)) { $vmrun = $c } }
if ($vmrun) { Decir 'VMware Workstation: encontrado.' 'Green' }
else {
    Decir 'VMware Workstation Pro no está instalado. Full Cowl no puede instalarlo por ti (se descarga con una cuenta de Broadcom).' 'Yellow'
    Decir 'Descárgalo de https://www.vmware.com/products/desktop-hypervisor/workstation-and-fusion ; el asistente de Full Cowl lo volverá a mirar.' 'Yellow'
}

Paso 4 'Packer (el que crea las bases desde las ISO)'
try {
    . (Join-Path $Carpeta 'full-cowl\instalacion\packer.ps1')
    $pk = Obtener-Packer
    if ($pk) { Decir "Packer: ya está ($(Origen-Packer))." 'Green' }
    else {
        Decir "Descargando Packer $(Version-PackerFijada) de releases.hashicorp.com y comprobando su suma SHA-256…"
        $rp = Instalar-Packer
        if ($rp.Ok) { Decir $rp.Mensaje 'Green' } else { Decir $rp.Mensaje 'Yellow'; Decir 'Full Cowl funciona igual; el asistente te dejará instalarlo después.' 'Yellow' }
    }
} catch { Apuntar $_.Exception.ToString(); Decir "No he podido instalar Packer: $($_.Exception.Message). El asistente te dejará instalarlo después." 'Yellow' }

Paso 5 'Accesos directos'
try {
    $ws = New-Object -ComObject WScript.Shell
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $abrir = Join-Path $Carpeta 'full-cowl\abrir-nueva.ps1'
    foreach ($dirLnk in @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('Programs')) ''))) {
        if (-not $dirLnk -or -not (Test-Path -LiteralPath $dirLnk)) { continue }
        $acc = $ws.CreateShortcut((Join-Path $dirLnk 'Full Cowl.lnk'))
        $acc.TargetPath = $conhost
        # Consola clásica minimizada y sin -ExecutionPolicy Bypass (ver crear-accesos.ps1: Check Point lo tomaba por MuddyWater)
        $acc.Arguments = "`"$ps`" -NoProfile -STA -File `"$abrir`""
        $acc.WindowStyle = 7
        $acc.WorkingDirectory = Split-Path $abrir
        $acc.IconLocation = (Join-Path $Carpeta 'full-cowl\recursos\full-cowl-icono-4.ico') + ',0'
        $acc.Description = 'Full Cowl - máquinas virtuales de VMware'
        $acc.Save()
    }
    $ca = Join-Path $Carpeta 'crear-accesos.ps1'
    if (Test-Path -LiteralPath $ca) { & $ca | Out-Null }
    Decir 'Accesos directos «Full Cowl» en el escritorio y en el menú Inicio.' 'Green'
} catch { Apuntar $_.Exception.ToString(); Decir "No he podido crear los accesos directos: $($_.Exception.Message). Puedes abrir Full Cowl con «Abrir Full Cowl.bat» de la carpeta." 'Yellow' }

Write-Host ''
Decir $(if ($yaInstalado) { "Listo: Full Cowl $version ya estaba instalado y se ha actualizado." } else { "Listo: Full Cowl $version instalado." }) 'Green'
Decir 'Para quitarlo: «Desinstalar Full Cowl.bat» en su carpeta (no toca tus máquinas).' 'DarkGray'
if (-not $Silencioso) {
    if ((Preguntar '¿Abrir Full Cowl ahora? [S/n]') -notlike 'n*') {
        Start-Process -FilePath $conhost -ArgumentList "`"$ps`" -NoProfile -STA -File `"$abrir`"" -WorkingDirectory (Split-Path $abrir) -WindowStyle Minimized
    }
}
exit 0
