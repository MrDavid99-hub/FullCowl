# CD de configuración del clon (Windows). Lo ejecuta el agente de la base como SYSTEM
# en cada arranque hasta terminar. Cada paso se marca al completarse, así puede
# reiniciar entre medias (cambio de nombre, Active Directory...) y seguir donde iba.
# Registro: C:\ProgramData\VMTareas\config.log
$ErrorActionPreference = 'Continue'
$cd  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Get-Content (Join-Path $cd 'config.json') -Raw | ConvertFrom-Json
$dir = 'C:\ProgramData\VMTareas'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Start-Transcript -Path "$dir\config.log" -Append | Out-Null

function Hecho($paso)  { Test-Path "$dir\$($cfg.id).$paso" }
function Marcar($paso) { New-Item -ItemType File -Force -Path "$dir\$($cfg.id).$paso" | Out-Null }
function Salir { Stop-Transcript | Out-Null; exit 0 }
function Reiniciar($motivo) {
    Write-Host "Reiniciando: $motivo"
    Stop-Transcript | Out-Null
    Restart-Computer -Force
    exit 0
}

# ---------------------------------------------------------------- Progreso para Full Cowl
# Cada paso se publica en guestinfo.vmtareas.progreso (VMware Tools) y Full Cowl lo lee desde
# fuera con vmrun:  1|paso|total|segundos estimados|inicio (epoch UTC)|estado|clave
# estado: curso, ok, fallos, error. Las claves se traducen a texto en Full Cowl (sin tildes aquí).
$pasos = @('preparar')
if ($cfg.zona) { $pasos += 'zona' }
if ($cfg.hostname) { $pasos += 'nombre' }
if ($cfg.ip) { $pasos += 'red' }
if ($cfg.extras) { $pasos += 'extras' }
if ($cfg.ad -and $cfg.ad.modo -eq 'dc') { $pasos += 'dominio-crear', 'dominio-arrancar' }
elseif ($cfg.ad -and $cfg.ad.modo -eq 'unir') { $pasos += 'dominio-esperar', 'dominio-unir' }
$esperado = @{ zona = 5; nombre = 90; red = 20; extras = 180; 'dominio-crear' = 540; 'dominio-arrancar' = 90; 'dominio-esperar' = 600; 'dominio-unir' = 120 }
$rpcProg = 'C:\Program Files\VMware\VMware Tools\rpctool.exe'
function Progreso($clave, $estado = 'curso') {
    if (-not (Test-Path $rpcProg)) { return }
    $n = if ($clave -eq 'lista') { $pasos.Count } else { [Math]::Max(1, [array]::IndexOf($pasos, $clave) + 1) }
    $seg = if ($esperado.ContainsKey($clave)) { $esperado[$clave] } else { 0 }
    $ahora = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    try { & $rpcProg "info-set guestinfo.vmtareas.progreso 1|$n|$($pasos.Count)|$seg|$ahora|$estado|$clave" 2>$null | Out-Null } catch {}
}

$escritorio = 'C:\Users\Public\Desktop'
$aviso = Join-Path $escritorio 'CONFIGURANDO - NO APAGAR.txt'
if (Hecho 'fin') {
    # Ya configurada (arranques posteriores): avisar de que está lista
    Progreso 'lista' $(if (Test-Path "$dir\$($cfg.id).fallos") { 'fallos' } else { 'ok' })
    # (lo publicado por las VMware Tools se pierde al apagar: se repite el estado de los extras que quedó apuntado)
    try {
        $archivoExt = "$dir\$($cfg.id).extras-estado"
        if ((Test-Path $archivoExt) -and (Test-Path $rpcProg)) {
            $tExt = ([string](Get-Content $archivoExt -TotalCount 1)) -replace '[^a-z0-9=;]', ''
            if ($tExt.Length -gt 900) { $tExt = $tExt.Substring(0, 900) }
            if ($tExt) { & $rpcProg "info-set guestinfo.vmtareas.extras.estado $tExt" 2>$null | Out-Null }
        }
    } catch {}
    Salir
}
Set-Content -Path $aviso -Value "La VM se está configurando sola (puede reiniciarse varias veces).`r`nRegistro: $dir\config.log"

$esServidor = (Get-CimInstance Win32_OperatingSystem).ProductType -ne 1
$hechos = New-Object System.Collections.ArrayList
$fallos = New-Object System.Collections.ArrayList
$archivoFallos = "$dir\$($cfg.id).fallos"
if (Test-Path $archivoFallos) { foreach ($l in (Get-Content $archivoFallos)) { if ($l) { [void]$fallos.Add($l) } } }

# ---------------------------------------------------------------- 0. Contraseña de las cuentas
# Las bases nuevas se instalan con una contraseña aleatoria de un solo uso: la real llega en este CD
# y se pone aquí, antes de nada (y antes de que, en un controlador de dominio, las cuentas locales dejen de existir).
if ($cfg.password -and -not (Hecho 'clave')) {
    try {
        $segura = ConvertTo-SecureString $cfg.password -AsPlainText -Force
        $locales = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -eq $cfg.usuario -or $_.SID.Value -like '*-500' })
        foreach ($cuenta in $locales) {
            Set-LocalUser -Name $cuenta.Name -Password $segura -ErrorAction Stop
            Write-Host "Contrasena puesta a la cuenta $($cuenta.Name)"
        }
        if ($locales.Count) { Marcar 'clave' } else { Write-Host "ERROR contrasena: no encuentro la cuenta $($cfg.usuario)" }
    } catch { Write-Host "ERROR contrasena: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- 0b. Zona horaria (ficha 36)
# Solo llega si en Nueva maquina se eligio una zona distinta a la de la base. Sin reinicio.
# Se comprueba antes que Windows la conoce (tzutil /l); si no, se apunta el aviso y se sigue.
if ($cfg.zona -and -not (Hecho 'zona')) {
    Progreso 'zona'
    $zonaPedida = [string]$cfg.zona
    try {
        $conocidas = @(& tzutil /l 2>$null | ForEach-Object { ([string]$_).Trim() })
        if ($zonaPedida -match '^[A-Za-z0-9 ()+.,_-]{1,64}$' -and $conocidas -contains $zonaPedida) {
            & tzutil /s "$zonaPedida"
            Write-Host "Zona horaria: $zonaPedida"
        } else { Write-Host "AVISO zona horaria: Windows no conoce '$zonaPedida' (se deja la de la base)" }
    } catch { Write-Host "AVISO zona horaria: $($_.Exception.Message)" }
    Marcar 'zona'
}

# ---------------------------------------------------------------- 1. Nombre de equipo
if ($cfg.hostname -and -not (Hecho 'nombre')) {
    Progreso 'nombre'
    Marcar 'nombre'
    if ($env:COMPUTERNAME -ne $cfg.hostname) {
        Rename-Computer -NewName $cfg.hostname -Force
        Reiniciar "nuevo nombre $($cfg.hostname)"
    }
}

# ---------------------------------------------------------------- 2. Red
function Adaptador {
    for ($i = 0; $i -lt 60; $i++) {
        $a = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1
        if ($a) { return $a }
        Start-Sleep 2
    }
    return (Get-NetAdapter -Physical | Select-Object -First 1)
}
if ($cfg.ip -and -not (Hecho 'ip')) {
    Progreso 'red'
    try {
        $a = Adaptador
        Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Dhcp Disabled
        Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        # Puerta de enlace y DNS son opcionales (en un segmento LAN aislado no hay)
        $param = @{ InterfaceIndex = $a.ifIndex; IPAddress = $cfg.ip.addr; PrefixLength = $cfg.ip.prefix; ErrorAction = 'Stop' }
        if ($cfg.ip.gw) { $param.DefaultGateway = $cfg.ip.gw }
        New-NetIPAddress @param | Out-Null
        $dnsIp = @($cfg.ip.dns | Where-Object { $_ })
        if ($dnsIp.Count) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $dnsIp }
        # Redes sin puerta de enlace = "red no identificada": que cuenten como privadas
        try {
            $sig = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24'
            New-Item -Path $sig -Force | Out-Null
            New-ItemProperty -Path $sig -Name Category -Value 1 -PropertyType DWord -Force | Out-Null
        } catch {}
        Set-NetConnectionProfile -InterfaceIndex $a.ifIndex -NetworkCategory Private -ErrorAction SilentlyContinue
        Marcar 'ip'
        Write-Host "IP fija $($cfg.ip.addr)/$($cfg.ip.prefix) gw $($cfg.ip.gw) dns $($cfg.ip.dns -join ',')"
    } catch { Write-Host "ERROR IP: $_" }
}

# ---------------------------------------------------------------- 3. Extras (roles y características)
$script:reinicio = $false
function Rol([string[]]$nombres) {
    # Windows Server: roles y características
    $r = Install-WindowsFeature -Name $nombres -IncludeManagementTools -ErrorAction Stop
    if (-not $r.Success) { throw "no se pudo instalar $($nombres -join ', ')" }
    if ([string]$r.RestartNeeded -ne 'No') { $script:reinicio = $true }
}
function Opcional([string[]]$nombres) {
    # Windows 10/11: características opcionales
    $r = Enable-WindowsOptionalFeature -Online -All -NoRestart -FeatureName $nombres -ErrorAction Stop
    if ($r.RestartNeeded) { $script:reinicio = $true }
}
function Capacidad([string[]]$patrones) {
    # Capacidades "a petición" (se descargan de Windows Update: necesitan Internet)
    $caps = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object {
        $n = $_.Name; ($patrones | Where-Object { $n -like $_ }) -and $_.State -ne 'Installed' })
    foreach ($c in $caps) {
        Write-Host "  Añadiendo $($c.Name)..."
        $r = Add-WindowsCapability -Online -Name $c.Name -ErrorAction Stop
        if ($r.RestartNeeded) { $script:reinicio = $true }
    }
}

# Extras (ficha 20). CATÁLOGO CERRADO: cada identificador de config.json tiene que ser solo letras minúsculas y
# números, y se compara con la lista de abajo (switch): solo si coincide se ejecuta lo que está ESCRITO AQUÍ. El
# identificador nunca forma parte de una orden (nada de Invoke-Expression ni de montar órdenes con texto de fuera).
# Lo desconocido se anota y se ignora; un extra que falla no para a los demás.
$estadoExtras = [ordered]@{}
$archivoExtras = "$dir\$($cfg.id).extras-estado"
$registroExtras = "$dir\extras.log"
function Publicar-Extras {
    # guestinfo.vmtareas.extras.estado = iis=ok;dhcp=instalando  (lo lee Full Cowl desde fuera)
    $t = (@($estadoExtras.Keys | ForEach-Object { "$_=$($estadoExtras[$_])" }) -join ';')
    try { Set-Content -Path $archivoExtras -Value $t -Encoding ASCII } catch {}
    if (Test-Path $rpcProg) { try { & $rpcProg "info-set guestinfo.vmtareas.extras.estado $t" 2>$null | Out-Null } catch {} }
}
function Anotar-Extra([string]$linea) {
    try { Add-Content -Path $registroExtras -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $linea) -Encoding UTF8 } catch {}
}
if ($cfg.extras -and -not (Hecho 'extras')) {
    Progreso 'extras'
    $listaExtras = @()
    foreach ($x in @($cfg.extras)) {
        if ($x -isnot [string] -or $x -cnotmatch '^[a-z0-9]{1,24}$') { Write-Host 'Identificador de extra no válido: se ignora'; continue }
        if ($listaExtras -contains $x -or $listaExtras.Count -ge 30) { continue }
        $listaExtras += $x; $estadoExtras[$x] = 'espera'
    }
    Publicar-Extras
    foreach ($e in $listaExtras) {
        Write-Host "--- $e"
        $estadoExtras[$e] = 'instalando'; Publicar-Extras
        $conocido = $true
        try {
            switch -CaseSensitive ($e) {
                'ping' {
                    Get-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In*', 'CoreNet-Diag-ICMP4-EchoRequest-In*' -ErrorAction SilentlyContinue | Enable-NetFirewallRule
                }
                'rdp' {
                    Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
                    Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue | Enable-NetFirewallRule
                }
                'iis'        { if ($esServidor) { Rol 'Web-Server' } else { Opcional 'IIS-WebServerRole', 'IIS-WebServer', 'IIS-ManagementConsole' } }
                'ftp'        { if ($esServidor) { Rol 'Web-Server', 'Web-Ftp-Server' } else { Opcional 'IIS-WebServerRole', 'IIS-FTPServer', 'IIS-FTPSvc', 'IIS-ManagementConsole' } }
                'dhcp'       { Rol 'DHCP' }
                'adds'       { Rol 'AD-Domain-Services' }
                'dns'        { Rol 'DNS' }
                'fileserver' { Rol 'FS-FileServer', 'FS-Resource-Manager' }
                'print'      { Rol 'Print-Server' }
                'adcs'       { Rol 'ADCS-Cert-Authority' }   # solo el rol: la entidad de certificación se configura a mano
                'backup'     { Rol 'Windows-Server-Backup' }
                'wds'        { Rol 'WDS' }
                'hyperv'     { if ($esServidor) { Rol 'Hyper-V' } else { Opcional 'Microsoft-Hyper-V-All' } }
                'sandbox'    { Opcional 'Containers-DisposableClientVM' }
                'wsl'        { Opcional 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform' }
                'netfx3'     { if ($esServidor) { Rol 'NET-Framework-Core' } else { Opcional 'NetFx3' } }
                'telnet'     { if ($esServidor) { Rol 'Telnet-Client' } else { Opcional 'TelnetClient' } }
                'sshserver'  {
                    Capacidad 'OpenSSH.Server*'
                    Set-Service sshd -StartupType Automatic
                    Start-Service sshd -ErrorAction SilentlyContinue
                    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
                        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
                    }
                }
                'rsat'       { Capacidad 'Rsat.ActiveDirectory.DS-LDS.Tools*', 'Rsat.Dns.Tools*', 'Rsat.DHCP.Tools*', 'Rsat.GroupPolicy.Management.Tools*', 'Rsat.ServerManager.Tools*' }
                default      { $conocido = $false }
            }
            if ($conocido) { Write-Host "Extra '$e' aplicado"; $estadoExtras[$e] = 'ok'; Anotar-Extra "$e  instalado" }
            else { Write-Host "Extra desconocido (no está en el catálogo): $e"; $estadoExtras[$e] = 'desconocido'; Anotar-Extra "$e  no está en el catálogo: no se hace nada" }
        } catch {
            Write-Host "ERROR extra '$e': $_"; [void]$fallos.Add($e); Add-Content $archivoFallos $e
            $estadoExtras[$e] = 'fallo'; Anotar-Extra "$e  FALLO: $($_.Exception.Message)"
        }
        Publicar-Extras
    }
    Marcar 'extras'
    # Hyper-V, WSL, Sandbox... necesitan reiniciar antes de seguir
    if ($script:reinicio) { Reiniciar 'terminar de instalar roles y características' }
}

# ---------------------------------------------------------------- 4. Active Directory
$cs = Get-CimInstance Win32_ComputerSystem
if ($cfg.ad -and $cfg.ad.modo -eq 'dc' -and -not (Hecho 'ad')) {
    $seguro = ConvertTo-SecureString $cfg.password -AsPlainText -Force
    if (-not (Hecho 'dc-promocion')) {
        Progreso 'dominio-crear'
        Write-Host "Instalando AD DS y creando el bosque $($cfg.ad.dominio)..."
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        Import-Module ADDSDeployment
        Marcar 'dc-promocion'
        try {
            # Si sale bien, Windows se reinicia solo al terminar
            $r = Install-ADDSForest -DomainName $cfg.ad.dominio -DomainNetbiosName $cfg.ad.netbios `
                    -InstallDns -SafeModeAdministratorPassword $seguro -Force -NoRebootOnCompletion:$false -ErrorAction Stop
            Write-Host "Resultado: $($r.Status) $($r.Message)"
            if ($r.Status -eq 'Success') { Salir }
        } catch { Write-Host "ERROR promoción: $_" }
        $cs = Get-CimInstance Win32_ComputerSystem
    }
    if ($cs.DomainRole -ge 4) {
        Progreso 'dominio-arrancar'
        # Ya es controlador: reenviar al DNS de VMware para tener Internet
        if ($cfg.ip.gw) {
            for ($i = 0; $i -lt 30; $i++) {
                try { Add-DnsServerForwarder -IPAddress $cfg.ip.gw -ErrorAction Stop; break } catch { Start-Sleep 10 }
            }
        }
        Marcar 'ad'
        [void]$hechos.Add("Controlador de dominio de $($cfg.ad.dominio) (NetBIOS $($cfg.ad.netbios))")
    } else {
        Write-Host "ERROR: la promoción a controlador de dominio no se completó."
        Marcar 'ad'
        [void]$fallos.Add('Active Directory (crear dominio)'); Add-Content $archivoFallos 'Active Directory (crear dominio)'
    }
}
elseif ($cfg.ad -and $cfg.ad.modo -eq 'unir' -and -not (Hecho 'ad')) {
    if ($cs.PartOfDomain -and $cs.Domain -eq $cfg.ad.dominio) {
        Marcar 'ad'
        [void]$hechos.Add("Unido al dominio $($cfg.ad.dominio)")
    } else {
        $a = Adaptador
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @($cfg.ad.dcip)
        $nbAd = if ($cfg.ad.netbios) { [string]$cfg.ad.netbios } else { $cfg.ad.dominio.Split('.')[0].ToUpper() }
        $pw = ConvertTo-SecureString $cfg.password -AsPlainText -Force
        # Cuentas con las que unirse, por orden: el usuario de las VMs (en los dominios que crea Full Cowl
        # existe y tiene siempre la contraseña buena) y el administrador integrado, que se llama
        # distinto según el idioma de Windows (Administrador en español)
        $cuentas = @(@([string]$cfg.usuario, 'Administrador', 'Administrator') | Where-Object { $_ } | Select-Object -Unique)
        $unido = $false
        $intentando = $false
        Progreso 'dominio-esperar'
        # Espera hasta 30 min a que el controlador responda (puede estar arrancando)
        for ($i = 0; $i -lt 60 -and -not $unido; $i++) {
            if (Resolve-DnsName $cfg.ad.dominio -Server $cfg.ad.dcip -ErrorAction SilentlyContinue) {
                if (-not $intentando) { Progreso 'dominio-unir'; $intentando = $true }
                foreach ($cu in $cuentas) {
                    try {
                        Add-Computer -DomainName $cfg.ad.dominio -Credential (New-Object PSCredential("$nbAd\$cu", $pw)) -Force -ErrorAction Stop
                        $unido = $true
                        Write-Host "Unido a $($cfg.ad.dominio) con la cuenta $nbAd\$cu"
                        break
                    } catch { Write-Host "Intento de unión con $nbAd\$cu fallido: $($_.Exception.Message)" }
                }
            }
            if (-not $unido) { Start-Sleep 30 }
        }
        if ($unido) {
            Marcar 'ad'
            Reiniciar "unido a $($cfg.ad.dominio)"
        } else {
            Write-Host "ERROR: no se pudo unir al dominio $($cfg.ad.dominio). Se reintentará en el próximo arranque."
            Progreso 'dominio-unir' 'error'
            [void]$fallos.Add("Unir a $($cfg.ad.dominio) (se reintenta al reiniciar)")
        }
    }
}

# ---------------------------------------------------------------- 5. Resumen
$pendiente = $fallos | Where-Object { $_ -match 'reintenta' }
if (-not $pendiente) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
    $lineas = @("Configuración automática del clon - $(Get-Date -Format 'yyyy-MM-dd HH:mm')", '',
                "Equipo: $env:COMPUTERNAME", "IP: $ip")
    if ($cfg.extras) { $lineas += "Extras: $($cfg.extras -join ', ')" }
    foreach ($h in $hechos) { $lineas += $h }
    if ($cfg.ad -and $cfg.ad.modo -eq 'dc') {
        # Nombre real del administrador del dominio (SID ...-500): depende del idioma de Windows
        $adm = if ((Get-UICulture).Name -like 'es-*') { 'Administrador' } else { 'Administrator' }
        try {
            $sidEq = (New-Object Security.Principal.NTAccount("$($cfg.ad.netbios)\$env:COMPUTERNAME`$")).Translate([Security.Principal.SecurityIdentifier])
            $sidAdm = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::AccountAdministratorSid, $sidEq.AccountDomainSid)
            $adm = $sidAdm.Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
        } catch {}
        $lineas += '', "Inicia sesión como $($cfg.ad.netbios)\$($cfg.usuario) o $($cfg.ad.netbios)\$adm"
    }
    if ($cfg.ad -and $cfg.ad.modo -eq 'unir') { $lineas += '', "Cuentas del dominio: $($cfg.ad.netbios)\usuario   |   Cuenta local: .\$($cfg.usuario)" }
    if ($fallos.Count) { $lineas += '', "Con errores: $($fallos -join ', ')", "Revisa $dir\config.log" }
    Set-Content -Path (Join-Path $escritorio 'Configuración de la VM.txt') -Value $lineas
    Remove-Item $aviso -ErrorAction SilentlyContinue
    Marcar 'fin'
    Progreso 'lista' $(if ($fallos.Count) { 'fallos' } else { 'ok' })
}
Salir
