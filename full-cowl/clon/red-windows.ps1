# Se ejecuta DENTRO de una VM Windows (lo copia y lanza red-ip.ps1 desde el PC).
# Pone IP fija o DHCP en cada tarjeta indicada (se reconocen por su MAC).
# Datos: C:\Windows\Temp\vmt-red.json
$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\vmt-red.log'
$datos = 'C:\Windows\Temp\vmt-red.json'
[IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
function L($t) { [IO.File]::AppendAllText($log, "$t`r`n", [Text.UTF8Encoding]::new($false)) }

try {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { throw 'el programa no tiene permisos de administrador dentro de la VM.' }
    $cfg = [IO.File]::ReadAllText($datos, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Remove-Item $datos -Force

    # Redes sin puerta de enlace (segmentos LAN) = "red no identificada": que cuenten como privadas
    try {
        $sig = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24'
        New-Item -Path $sig -Force | Out-Null
        New-ItemProperty -Path $sig -Name Category -Value 1 -PropertyType DWord -Force | Out-Null
    } catch {}

    foreach ($t in @($cfg.tarjetas)) {
        if ($t.modo -notin 'fija', 'dhcp') { continue }
        $macW = ([string]$t.mac -replace ':', '-').ToUpper()
        $a = $null
        for ($i = 0; $i -lt 30 -and -not $a; $i++) {
            $a = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.MacAddress -eq $macW } | Select-Object -First 1
            if (-not $a) { Start-Sleep 2 }
        }
        if (-not $a) { L "FALLO      tarjeta $($t.mac): Windows no la ve"; continue }
        try {
            # Nombre del adaptador = nombre de la red (más fácil de reconocer en ipconfig)
            if ($t.nombre -and $a.Name -ne $t.nombre) {
                $nuevo = [string]$t.nombre; $k = 2
                while (Get-NetAdapter -Name $nuevo -ErrorAction SilentlyContinue) { $nuevo = "$($t.nombre) $k"; $k++ }
                try { Rename-NetAdapter -Name $a.Name -NewName $nuevo -ErrorAction Stop } catch {}
            }
            $idx = $a.ifIndex
            Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            if ($t.modo -eq 'fija') {
                Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -Dhcp Disabled
                $param = @{ InterfaceIndex = $idx; IPAddress = $t.ip; PrefixLength = [int]$t.prefix; AddressFamily = 'IPv4' }
                if ($t.gw) { $param.DefaultGateway = $t.gw }
                New-NetIPAddress @param | Out-Null
                if (@($t.dns).Count -and $t.dns[0]) { Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($t.dns) }
                else { Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses }
                L "IP FIJA    $((Get-NetAdapter -InterfaceIndex $idx).Name): $($t.ip)/$($t.prefix)$(if ($t.gw) { "  puerta $($t.gw)" })$(if (@($t.dns).Count -and $t.dns[0]) { "  DNS $(@($t.dns) -join ',')" })"
            } else {
                Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -Dhcp Enabled
                Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses
                L "DHCP       $((Get-NetAdapter -InterfaceIndex $idx).Name)"
            }
            Set-NetConnectionProfile -InterfaceIndex $idx -NetworkCategory Private -ErrorAction SilentlyContinue
        } catch { L "FALLO      $($a.Name): $($_.Exception.Message)" }
    }

    if ($cfg.ping) {
        # Ping entre las máquinas del laboratorio (Windows lo bloquea por defecto)
        & netsh.exe advfirewall firewall delete rule name="Ping (Full Cowl)" | Out-Null
        & netsh.exe advfirewall firewall add rule name="Ping (Full Cowl)" protocol=icmpv4:8,any dir=in action=allow | Out-Null
        L 'PING       permitido'
    }
} catch {
    L "ERROR: $($_.Exception.Message)"
}
