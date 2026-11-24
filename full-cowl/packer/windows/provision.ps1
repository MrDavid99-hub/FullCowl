# Los mensajes van sin tildes: la consola de Packer las muestra mal.
# Se ejecuta dentro de la VM base (Packer, por WinRM) antes de generalizarla con sysprep.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "== VMware Tools =="
$vmtoolsd = 'C:\Program Files\VMware\VMware Tools\vmtoolsd.exe'
# Al instalarse, las Tools cambian el driver de red: se corta la conexion con Packer y Packer
# repite este paso. Si la instalacion anterior sigue en marcha, se espera a que acabe en vez de
# lanzar otra encima (antes salia "Instalando desde el CD" dos o tres veces).
for ($i = 0; $i -lt 120; $i++) {
    $enCurso = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(setup|setup64|msiexec)\.exe$' -and $_.CommandLine -match 'REBOOT=R|VMware Tools' })
    if (-not $enCurso) { break }
    if ($i -eq 0) { Write-Host "Ya hay una instalacion de VMware Tools en marcha: se espera a que termine..." }
    Start-Sleep 5
}
if (Test-Path $vmtoolsd) { Write-Host "VMware Tools ya instaladas." }
else {
    # 1) Desde el CD de VMware Tools que trae VMware Workstation (windows.iso), que crear-base.ps1
    #    conecta a la VM: no necesita Internet ni depende de la web de VMware/Broadcom
    $setup = $null
    for ($i = 0; $i -lt 15 -and -not $setup; $i++) {
        # El CD se llama "VMware Tools" (el de instalación de Windows también trae un setup.exe)
        foreach ($vol in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter })) {
            $esTools = $vol.FileSystemLabel -like 'VMware Tools*'
            foreach ($exe in 'setup64.exe', 'setup.exe') {
                $ruta = "$($vol.DriveLetter):\$exe"
                if (-not $setup -and (Test-Path $ruta) -and ($esTools -or $exe -eq 'setup64.exe')) { $setup = $ruta }
            }
        }
        if (-not $setup) { Start-Sleep 2 }
    }
    if ($setup) {
        Write-Host "Instalando desde el CD de VMware ($setup)..."
        $proc = Start-Process -FilePath $setup -ArgumentList '/S /v "/qn REBOOT=R ADDLOCAL=ALL"' -Wait -PassThru
        Write-Host "  Codigo de salida: $($proc.ExitCode) (0 o 3010 = bien)"
    } else {
        Write-Host "No encuentro el CD de VMware Tools: se intenta descargar."
    }
    # 2) Si no se pudo, descargarlas de la web de VMware
    if (-not (Test-Path $vmtoolsd)) {
        foreach ($base in 'https://packages.vmware.com/tools/releases/latest/windows/x64/',
                          'https://packages-prod.broadcom.com/tools/releases/latest/windows/x64/') {
            try {
                $html = (Invoke-WebRequest -Uri $base -UseBasicParsing -TimeoutSec 60).Content
                $exe = [regex]::Match($html, 'VMware-tools-[0-9][0-9\.\-]*-x86_64\.exe').Value
                if (-not $exe) { continue }
                $dest = "$env:TEMP\$exe"
                Invoke-WebRequest -Uri ($base + $exe) -OutFile $dest -UseBasicParsing -TimeoutSec 600
                Start-Process -FilePath $dest -ArgumentList '/S /v "/qn REBOOT=R ADDLOCAL=ALL"' -Wait
                break
            } catch {
                Write-Host "No se pudo descargar desde $base : $_"
            }
        }
    }
    if (Test-Path $vmtoolsd) { Write-Host "VMware Tools instaladas." }
    else { Write-Host "AVISO: VMware Tools no se ha instalado: Red, Usuarios, Archivos y el progreso de los laboratorios no funcionaran en sus copias." }
}

Write-Host "== Agente de primer arranque para los clones =="
# Cada clon lleva un CD con etiqueta VMTAREAS (lo crea nueva-maquina.ps1) con config.ps1:
# nombre de equipo, IP fija, roles, Active Directory... El agente lo ejecuta en cada
# arranque como SYSTEM; config.ps1 lleva la cuenta de lo que ya ha hecho.
$dir = 'C:\ProgramData\VMTareas'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
@'
$dir = 'C:\ProgramData\VMTareas'
# Espera a que termine la configuracion inicial de Windows (tras sysprep)
for ($i = 0; $i -lt 120; $i++) {
    $s = Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue
    if ($s.SystemSetupInProgress -eq 0 -and $s.OOBEInProgress -ne 1) { break }
    Start-Sleep 5
}
# Busca el CD de configuracion
$cd = $null
for ($i = 0; $i -lt 30 -and -not $cd; $i++) {
    $v = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'VMTAREAS' -and $_.DriveLetter } | Select-Object -First 1
    if ($v) { $cd = "$($v.DriveLetter):\" } else { Start-Sleep 2 }
}
if ($cd -and (Test-Path "$cd\config.ps1")) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$cd\config.ps1"
    exit 0
}
# Sin CD: nombre de equipo desde el .vmx (guestinfo.hostname), una sola vez
$rpc = 'C:\Program Files\VMware\VMware Tools\rpctool.exe'
if (-not (Test-Path $rpc)) { exit 0 }
$nombre = (& $rpc 'info-get guestinfo.hostname' 2>$null | Out-String).Trim()
$marca = "$dir\hostname.done"
if (-not $nombre) { exit 0 }
if ((Test-Path $marca) -and ((Get-Content $marca -Raw).Trim() -eq $nombre)) { exit 0 }
Set-Content -Path $marca -Value $nombre
if ($nombre -ne $env:COMPUTERNAME) { Rename-Computer -NewName $nombre -Force -Restart }
'@ | Set-Content -Path "$dir\agente.ps1" -Encoding UTF8
# Solo administradores y SYSTEM pueden leer la carpeta del agente
icacls $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

$accion    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$dir\agente.ps1`""
$disparo   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$ajustes   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'VMTareas-Agente' -Action $accion -Trigger $disparo -Principal $principal -Settings $ajustes -Force | Out-Null
Unregister-ScheduledTask -TaskName 'VMTareas-Hostname' -Confirm:$false -ErrorAction SilentlyContinue
Get-ChildItem $dir -Exclude 'agente.ps1' | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

Write-Host "== Ajustes =="
# Server: que no se abra el Administrador del servidor al iniciar sesion
Get-ScheduledTask -TaskName 'ServerManager' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
# Sin hibernacion (ahorra espacio en disco)
powercfg /hibernate off
# Pantalla sin apagarse mientras trabajas
powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-ac 0

Write-Host "== Preparando sysprep =="
New-Item -ItemType Directory -Force -Path 'C:\Windows\Panther' | Out-Null
foreach ($u in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root 'sysprep-oobe.xml' })) {
    if (Test-Path $u) { Copy-Item $u 'C:\Windows\Panther\sysprep-oobe.xml' -Force; break }
}
if (-not (Test-Path 'C:\Windows\Panther\sysprep-oobe.xml')) {
    throw "No encuentro sysprep-oobe.xml en la disquetera ni en los CD"
}
# Windows 10/11: las apps instaladas solo para el usuario (no aprovisionadas) hacen fallar sysprep
if ((Get-CimInstance Win32_OperatingSystem).ProductType -eq 1) {
    $aprov = @(Get-AppxProvisionedPackage -Online | ForEach-Object DisplayName)
    Get-AppxPackage | Where-Object { -not $_.NonRemovable -and -not $_.IsFramework -and $aprov -notcontains $_.Name } |
        ForEach-Object { Write-Host "Quitando app de usuario: $($_.Name)"; Remove-AppxPackage $_.PackageFullName -ErrorAction SilentlyContinue }
}

# Tarea para lanzar sysprep al final (la ejecuta Packer con schtasks; ver windows.pkr.hcl).
# Antes de generalizar se cierra la administración remota que ha usado Packer: WinRM sin cifrar
# y con autenticación básica no debe quedarse abierto en las máquinas que salgan de esta base.
New-Item -ItemType Directory -Force -Path 'C:\Windows\Setup\Scripts' | Out-Null
@'
try {
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false -Force
} catch {}
& netsh.exe advfirewall firewall delete rule name="WinRM-Packer" | Out-Null
if ((Get-CimInstance Win32_OperatingSystem).ProductType -eq 1) {
    # Windows 10/11: sin administración remota (en Windows Server se deja la de serie, que va cifrada)
    try { Disable-PSRemoting -Force -WarningAction SilentlyContinue } catch {}
    Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    Set-Service -Name WinRM -StartupType Manual -ErrorAction SilentlyContinue
}
& C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /quiet /unattend:C:\Windows\Panther\sysprep-oobe.xml
'@ | Set-Content -Path 'C:\Windows\Setup\Scripts\antes-de-sysprep.ps1' -Encoding UTF8
$sp = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\antes-de-sysprep.ps1'
Register-ScheduledTask -TaskName 'VMTareas-Sysprep' -Action $sp -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest) -Force | Out-Null

# Borra la contraseña de los archivos de instalación en cuanto el clon termina de configurarse
New-Item -ItemType Directory -Force -Path 'C:\Windows\Setup\Scripts' | Out-Null
@"
@echo off
del /f /q C:\Windows\Panther\sysprep-oobe.xml >nul 2>&1
del /f /q C:\Windows\Panther\unattend.xml >nul 2>&1
del /f /q C:\Windows\System32\Sysprep\Panther\unattend.xml >nul 2>&1
del /f /q C:\Windows\Setup\Scripts\antes-de-sysprep.ps1 >nul 2>&1
schtasks /delete /tn VMTareas-Sysprep /f >nul 2>&1
del /f /q "%~f0"
"@ | Set-Content -Path 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -Encoding ASCII

# Quita el inicio de sesión automático y la contraseña que deja guardada
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $wl -Name AutoAdminLogon -Value '0' -ErrorAction SilentlyContinue
Remove-ItemProperty $wl -Name DefaultPassword -ErrorAction SilentlyContinue
Remove-ItemProperty $wl -Name AutoLogonCount -ErrorAction SilentlyContinue
Write-Host "Listo."
