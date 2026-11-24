# Se ejecuta DENTRO de una VM Windows (lo copia y lanza usuarios.ps1 desde el PC).
# Crea usuarios en Active Directory o locales. Datos: C:\Windows\Temp\vmt-usuarios.json
$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\vmt-usuarios.log'
$datos = 'C:\Windows\Temp\vmt-usuarios.json'
[IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
function L($t) { [IO.File]::AppendAllText($log, "$t`r`n", [Text.UTF8Encoding]::new($false)) }

$ok = 0; $mal = 0
try {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { throw 'el programa no tiene permisos de administrador dentro de la VM.' }
    $P = [IO.File]::ReadAllText($datos, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Remove-Item $datos -Force
    $cambiar = [bool]$P.cambiar

    if ($P.destino -eq 'ad') {
        Import-Module ActiveDirectory
        $dominio = Get-ADDomain
        $dn = $dominio.DistinguishedName
        function Asegurar-OU($nombre) {
            if (-not $nombre) { return $dn }
            $ruta = "OU=$nombre,$dn"
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ruta'" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $nombre -Path $dn -ProtectedFromAccidentalDeletion $false
                L "OU creada: $nombre"
            }
            return $ruta
        }
        $ouComun = Asegurar-OU $P.ou
        foreach ($u in $P.usuarios) {
            try {
                $sec = ConvertTo-SecureString ([string]$u.password) -AsPlainText -Force
                $nom = ("$($u.nombre) $($u.apellidos)").Trim(); if (-not $nom) { $nom = $u.usuario }
                $ruta = if ($u.ou) { Asegurar-OU $u.ou } else { $ouComun }
                if (Get-ADUser -Filter "SamAccountName -eq '$($u.usuario)'") {
                    Set-ADAccountPassword -Identity $u.usuario -Reset -NewPassword $sec
                    Enable-ADAccount -Identity $u.usuario
                    L "YA EXISTE  $($u.usuario) (contraseña actualizada)"
                } else {
                    $param = @{
                        Name = $nom; SamAccountName = $u.usuario; UserPrincipalName = "$($u.usuario)@$($dominio.DNSRoot)"
                        DisplayName = $nom; AccountPassword = $sec; Enabled = $true; Path = $ruta
                    }
                    if ($u.nombre) { $param.GivenName = $u.nombre }
                    if ($u.apellidos) { $param.Surname = $u.apellidos }
                    if ($cambiar) { $param.ChangePasswordAtLogon = $true } else { $param.PasswordNeverExpires = $true }
                    try { New-ADUser @param }
                    catch {
                        # Mismo nombre visible que otro usuario de la OU: se distingue con el login
                        if ($_.Exception.Message -match 'already in use|ya est') { $param.Name = "$nom ($($u.usuario))"; New-ADUser @param } else { throw }
                    }
                    L "CREADO     $($u.usuario)  ($nom)"
                }
                if ($u.grupo) {
                    if (-not (Get-ADGroup -Filter "Name -eq '$($u.grupo)'")) {
                        New-ADGroup -Name $u.grupo -GroupScope Global -GroupCategory Security -Path $ouComun
                        L "Grupo creado: $($u.grupo)"
                    }
                    Add-ADGroupMember -Identity $u.grupo -Members $u.usuario
                }
                $ok++
            } catch { L "FALLO      $($u.usuario): $($_.Exception.Message)"; $mal++ }
        }
    } else {
        $grupoUsuarios = Get-LocalGroup -SID 'S-1-5-32-545'   # "Usuarios" en cualquier idioma
        foreach ($u in $P.usuarios) {
            try {
                $sec = ConvertTo-SecureString ([string]$u.password) -AsPlainText -Force
                $nom = ("$($u.nombre) $($u.apellidos)").Trim()
                if (Get-LocalUser -Name $u.usuario -ErrorAction SilentlyContinue) {
                    Set-LocalUser -Name $u.usuario -Password $sec
                    Enable-LocalUser -Name $u.usuario
                    L "YA EXISTE  $($u.usuario) (contraseña actualizada)"
                } else {
                    $param = @{ Name = $u.usuario; Password = $sec; Description = 'Creado con VMTareas' }
                    if ($nom) { $param.FullName = $nom }
                    if (-not $cambiar) { $param.PasswordNeverExpires = $true }
                    New-LocalUser @param | Out-Null
                    Add-LocalGroupMember -Group $grupoUsuarios -Member $u.usuario -ErrorAction SilentlyContinue
                    L "CREADO     $($u.usuario)$(if ($nom) { "  ($nom)" })"
                }
                if ($cambiar) { & net.exe user $u.usuario /logonpasswordchg:yes | Out-Null }
                if ($u.grupo) {
                    if (-not (Get-LocalGroup -Name $u.grupo -ErrorAction SilentlyContinue)) {
                        New-LocalGroup -Name $u.grupo | Out-Null
                        L "Grupo creado: $($u.grupo)"
                    }
                    Add-LocalGroupMember -Group $u.grupo -Member $u.usuario -ErrorAction SilentlyContinue
                }
                $ok++
            } catch { L "FALLO      $($u.usuario): $($_.Exception.Message)"; $mal++ }
        }
    }
    L ''
    L "Correctos: $ok   Con fallos: $mal"
} catch {
    L "ERROR: $($_.Exception.Message)"
}
