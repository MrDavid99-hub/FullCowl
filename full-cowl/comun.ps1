# Funciones compartidas por crear-base.ps1 y nueva-maquina.ps1
. "$PSScriptRoot\config.ps1"
# Carpeta de Full Cowl, guardada al cargar este archivo. Las funciones de aquí la usan en vez de
# $PSScriptRoot: llamadas desde un botón de la interfaz nueva, $PSScriptRoot puede no ser esta carpeta.
$dirComun = $PSScriptRoot
# Las consolas necesitan las carpetas de este PC (la ventana las pide la primera vez)
if (-not $EsVentana -and -not (Config-Completa)) {
    Write-Host ""
    Write-Host "Falta configurar las carpetas de este PC (ISOs y máquinas)." -ForegroundColor Red
    Write-Host "Abre 'Full Cowl.bat': la primera vez te las pide (luego, botón Ajustes)." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Pulsa Enter para cerrar"
    exit 1
}
try { $Host.UI.RawUI.WindowTitle = 'Full Cowl' } catch {}
. (Join-Path $PSScriptRoot 'instalacion\packer.ps1')   # Obtener-Packer / Instalar-Packer (ficha 33)
Add-Type -AssemblyName System.Security   # DPAPI para los pedidos temporales (Guardar-Pedido / Leer-Pedido)

function Escribir-Titulo($texto) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
}

function Guardar-Estado {
    # Archivo de progreso que lee la ventana. Solo si el script lo ha activado.
    if (-not $script:est -or -not $script:archivoEstado) { return }
    $script:est.actualizado = (Get-Date).ToString('o')
    $tmp = "$($script:archivoEstado).tmp"
    try {
        [IO.File]::WriteAllText($tmp, ($script:est | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        Move-Item $tmp $script:archivoEstado -Force
    } catch {}
}

function Salir-ConError($texto) {
    if ($script:est) { $script:est.estado = 'error'; $script:est.mensaje = [string]$texto; Guardar-Estado }
    Write-Host ""
    Write-Host "ERROR: $texto" -ForegroundColor Red
    Write-Host ""
    Read-Host "Pulsa Enter para cerrar"
    exit 1
}

function Buscar-Vmrun([switch]$Silencioso) {
    $candidatos = @()
    foreach ($clave in 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation',
                       'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation') {
        try {
            $dir = (Get-ItemProperty -Path $clave -ErrorAction Stop).InstallPath
            if ($dir) { $candidatos += (Join-Path $dir 'vmrun.exe') }
        } catch {}
    }
    $candidatos += 'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe',
                   'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
    foreach ($ctl in $candidatos) { if (Test-Path $ctl) { return $ctl } }
    if ($Silencioso) { return $null }
    Salir-ConError "No encuentro vmrun.exe. ¿Está instalado VMware Workstation Pro?"
}

function Refrescar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Leer-Vmx($ruta) {
    # VMware tiene el .vmx abierto mientras enciende o apaga la máquina: se lee compartiéndolo y, si
    # aun así está bloqueado, se reintenta un momento (antes podía fallar toda la lista de máquinas)
    for ($intentoVmx = 1; ; $intentoVmx++) {
        try {
            $flujo = [System.IO.FileStream]::new($ruta, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $lector = [System.IO.StreamReader]::new($flujo, [System.Text.UTF8Encoding]::new($false))
                $lineasVmx = [System.Collections.Generic.List[string]]::new()
                while ($null -ne ($lineaVmx = $lector.ReadLine())) { $lineasVmx.Add($lineaVmx) }
                return [string[]]$lineasVmx.ToArray()
            } finally { $flujo.Dispose() }
        } catch {
            # Solo se reintenta si es un bloqueo del archivo (el error puede venir envuelto)
            $exVmx = $_.Exception
            while ($exVmx.InnerException -and -not ($exVmx -is [System.IO.IOException])) { $exVmx = $exVmx.InnerException }
            if (-not ($exVmx -is [System.IO.IOException]) -or $exVmx -is [System.IO.FileNotFoundException] -or $intentoVmx -ge 6) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Guardar-Vmx($ruta, $lineas) {
    [System.IO.File]::WriteAllLines($ruta, [string[]]$lineas, [System.Text.UTF8Encoding]::new($false))
}

function Fijar-ValoresVmx($ruta, [hashtable]$valores) {
    $lineas = Leer-Vmx $ruta
    $claves = $valores.Keys | ForEach-Object { $_.ToLower() }
    $lineas = $lineas | Where-Object {
        $k = ($_ -split '=', 2)[0].Trim().ToLower()
        -not ($claves -contains $k)
    }
    foreach ($k in $valores.Keys) {
        $v = ([string]$valores[$k]) -replace '["\r\n]', ''
        $lineas += "$k = `"$v`""
    }
    Guardar-Vmx $ruta $lineas
}

function Crear-Iso {
    # Crea una ISO (ISO9660 + Joliet) con el contenido de una carpeta, usando el
    # motor de grabación integrado en Windows (IMAPI2). No necesita programas extra.
    param([string]$Carpeta, [string]$Destino, [string]$Etiqueta)
    if (-not ('IsoEscritor' -as [type])) {
        $cp = New-Object CodeDom.Compiler.CompilerParameters
        $cp.CompilerOptions = '/unsafe'
        Add-Type -CompilerParameters $cp -TypeDefinition @'
public class IsoEscritor {
    public unsafe static void Guardar(string ruta, object flujo, int bloque, int bloques) {
        int leidos = 0;
        byte[] buf = new byte[bloque];
        var ptr = (System.IntPtr)(&leidos);
        var salida = System.IO.File.Create(ruta);
        var entrada = flujo as System.Runtime.InteropServices.ComTypes.IStream;
        while (bloques-- > 0) { entrada.Read(buf, bloque, ptr); salida.Write(buf, 0, leidos); }
        salida.Flush(); salida.Close();
    }
}
'@
    }
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3      # ISO9660 + Joliet
    $fsi.VolumeName = $Etiqueta
    $fsi.Root.AddTree($Carpeta, $false)
    $img = $fsi.CreateResultImage()
    [IsoEscritor]::Guardar($Destino, $img.ImageStream, $img.BlockSize, $img.TotalBlocks)
}

function Obtener-Password([switch]$SinPreguntar) {
    # Devuelve la contraseña de las VMs. Se guarda cifrada con DPAPI de Windows.
    # -SinPreguntar (para la ventana): devuelve $null si no está guardada.
    $archivo = Join-Path $dirComun 'password.sec'
    if (Test-Path $archivo) {
        try {
            # (sin el salto de línea del final: con él, ConvertTo-SecureString falla con «La cadena de
            # entrada no tiene el formato correcto» y la contraseña se volvía a pedir cada vez)
            $seguro = ([IO.File]::ReadAllText($archivo)).Trim() | ConvertTo-SecureString
            return [Net.NetworkCredential]::new('', $seguro).Password
        } catch {
            if ($SinPreguntar) { $script:motivoPassword = "No se pudo descifrar $archivo ($($_.Exception.Message)). Solo la puede leer el usuario de Windows que la guardó, en este PC."; return $null }
            Write-Host "No se pudo leer password.sec; vuelve a introducirla." -ForegroundColor Yellow
        }
    }
    if ($SinPreguntar) { $script:motivoPassword = "No existe $archivo."; return $null }
    Write-Host ""
    Write-Host "Contraseña para el usuario '$($Config.Usuario)' de las VMs (no se mostrará)." -ForegroundColor Cyan
    do {
        $a = Read-Host "Contraseña" -AsSecureString
        $b = Read-Host "Repítela" -AsSecureString
        $pa = [Net.NetworkCredential]::new('', $a).Password
        $pb = [Net.NetworkCredential]::new('', $b).Password
        if (-not $pa) { Write-Host "  No puede estar vacía." -ForegroundColor Yellow }
        elseif ($pa -ne $pb) { Write-Host "  No coinciden." -ForegroundColor Yellow }
        elseif ($pa.Contains("'")) { Write-Host "  No puede contener comillas simples (')." -ForegroundColor Yellow; $pa = '' }
    } until ($pa -and $pa -eq $pb)
    $a | ConvertFrom-SecureString | Set-Content $archivo
    Write-Host "  Guardada cifrada en password.sec" -ForegroundColor Green
    return $pa
}

function Nueva-PasswordTemporal {
    # Contraseña aleatoria de un solo uso para INSTALAR una base (la ve el instalador y Packer, y nadie
    # más). La de verdad la pone cada máquina en su primer arranque, desde su CD de configuración.
    # Solo letras y números sin parecidos (vale en XML, JSON y shell sin escapar) y con mayúsculas,
    # minúsculas y números, así que cumple la complejidad de Windows Server.
    $mayus = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; $minus = 'abcdefghijkmnpqrstuvwxyz'; $nums = '23456789'
    $todos = $mayus + $minus + $nums
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $indice = { param($n) $b = New-Object byte[] 4; $rng.GetBytes($b); [int]([BitConverter]::ToUInt32($b, 0) % [uint32]$n) }
        $lista = New-Object 'System.Collections.Generic.List[char]'
        $lista.Add($mayus[(& $indice $mayus.Length)]); $lista.Add($minus[(& $indice $minus.Length)]); $lista.Add($nums[(& $indice $nums.Length)])
        while ($lista.Count -lt 24) { $lista.Add($todos[(& $indice $todos.Length)]) }
        for ($i = $lista.Count - 1; $i -gt 0; $i--) {   # mezclar para que no tengan un orden fijo
            $j = & $indice ($i + 1)
            $tmp = $lista[$i]; $lista[$i] = $lista[$j]; $lista[$j] = $tmp
        }
        return (-join $lista)
    } finally { $rng.Dispose() }
}

function Ip-PcVmnet8 {
    # IP del PC dentro de la red NAT de VMware (VMnet8): desde ahí el instalador de Kali descarga su configuración
    $red = Leer-RedNat
    if (-not $red) { return $null }
    $partes = $red.Subred.Split('.')
    $ip = "$($partes[0]).$($partes[1]).$($partes[2]).1"
    # Mejor la IP real del adaptador VMnet8 del PC (el servidor de Packer solo escuchará ahí)
    $ipAdaptador = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.InterfaceAlias -like '*VMnet8*' } | Select-Object -First 1).IPAddress
    if ($ipAdaptador) { $ip = $ipAdaptador }
    return $ip
}

function Linea-ArranqueKali {
    # La línea que se escribe a mano en el prompt «boot:» del instalador de Kali (o $null si no hay VMnet8).
    # Es una línea ENTERA (no se añade a la de «Install»): la de Kali lleva su propio preseed/file y con él el
    # instalador ignora nuestro url= (comprobado en el registro del instalador el 05/11/2026).
    $ip = Ip-PcVmnet8
    if (-not $ip) { return $null }
    return "/install.amd/vmlinuz auto=true priority=critical url=http://$($ip):8820/k.cfg initrd=/install.amd/initrd.gz"
}

function Linea-ArranqueDebian {
    # Igual que la de Kali, para el instalador «netinst» de Debian (lee d.cfg del servidor de Packer)
    $ip = Ip-PcVmnet8
    if (-not $ip) { return $null }
    return "/install.amd/vmlinuz auto=true priority=critical url=http://$($ip):8820/d.cfg initrd=/install.amd/initrd.gz"
}

# ---------------------------------------------------------------- datos de la aplicación (ficha 37, «Acerca de»)
# Un solo sitio para cada texto: la ventana «Acerca de», y más adelante el README y NOTICE.md (ficha 32).
function Autor-FullCowl { return 'David Cabello Grimaldi' }
function Url-RepoPublico {
    # Dirección del repositorio PÚBLICO (ficha 32). Mientras esté vacía (el de hoy es privado) no sale ningún
    # enlace a GitHub. Nunca poner aquí el repositorio privado. Solo https://github.com/…
    $u = 'https://github.com/MrDavid99-hub/FullCowl'
    if ($u -match '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { return $u }
    return ''
}
function Aviso-Marcas {
    # Aviso de marcas (el mismo de la ficha 32, A.3). Texto pendiente de revisar por David: no es asesoramiento legal.
    return 'Windows, Ubuntu, Kali, Debian, Rocky, Arch, Proxmox, pfSense y VMware son marcas de sus propietarios. Sus logos solo sirven para reconocer cada sistema; Full Cowl es independiente y no está respaldado por ellos.'
}

# ---------------------------------------------------------------- idioma, teclado y zona horaria (ficha 36)
# Listas CERRADAS: lo que acaba dentro del XML de Windows y de los scripts de Linux sale solo de aquí (nunca texto libre).
# Las zonas se comprobaron con la tabla de Unicode (CLDR windowsZones) y la base de zonas IANA el 16/11/2026.
function Obtener-Idiomas {
    @(
        [pscustomobject]@{ Clave = 'es'; Nombre = 'Español'; Corto = 'ES'; Win = 'es-ES'; Locale = 'es_ES.UTF-8'; Language = 'es'; Pais = 'ES'; Teclado = 'es' }
        [pscustomobject]@{ Clave = 'en'; Nombre = 'Inglés (EE. UU.)'; Corto = 'EN'; Win = 'en-US'; Locale = 'en_US.UTF-8'; Language = 'en'; Pais = 'US'; Teclado = 'us' }
    )
}
function Obtener-Teclados {
    @(
        [pscustomobject]@{ Clave = 'es'; Nombre = 'Español'; Win = '040a:0000040a'; Linux = 'es' }
        [pscustomobject]@{ Clave = 'us'; Nombre = 'Inglés (EE. UU.)'; Win = '0409:00000409'; Linux = 'us' }
    )
}
function Obtener-Zonas {
    @(
        [pscustomobject]@{ Clave = 'Madrid';      Nombre = 'Madrid, Barcelona (península y Baleares)'; Corto = 'Madrid';       Win = 'Romance Standard Time';          Iana = 'Europe/Madrid' }
        [pscustomobject]@{ Clave = 'Canarias';    Nombre = 'Islas Canarias';                           Corto = 'Canarias';     Win = 'GMT Standard Time';              Iana = 'Atlantic/Canary' }
        [pscustomobject]@{ Clave = 'Londres';     Nombre = 'Londres';                                  Corto = 'Londres';      Win = 'GMT Standard Time';              Iana = 'Europe/London' }
        [pscustomobject]@{ Clave = 'Lisboa';      Nombre = 'Lisboa';                                   Corto = 'Lisboa';       Win = 'GMT Standard Time';              Iana = 'Europe/Lisbon' }
        [pscustomobject]@{ Clave = 'Paris';       Nombre = 'París, Bruselas';                          Corto = 'París';        Win = 'Romance Standard Time';          Iana = 'Europe/Paris' }
        [pscustomobject]@{ Clave = 'Berlin';      Nombre = 'Berlín, Roma, Ámsterdam';                  Corto = 'Berlín';       Win = 'W. Europe Standard Time';        Iana = 'Europe/Berlin' }
        [pscustomobject]@{ Clave = 'UTC';         Nombre = 'UTC (hora universal)';                     Corto = 'UTC';          Win = 'UTC';                            Iana = 'UTC' }
        [pscustomobject]@{ Clave = 'NuevaYork';   Nombre = 'Nueva York';                               Corto = 'Nueva York';   Win = 'Eastern Standard Time';          Iana = 'America/New_York' }
        [pscustomobject]@{ Clave = 'Chicago';     Nombre = 'Chicago';                                  Corto = 'Chicago';      Win = 'Central Standard Time';          Iana = 'America/Chicago' }
        [pscustomobject]@{ Clave = 'Denver';      Nombre = 'Denver';                                   Corto = 'Denver';       Win = 'Mountain Standard Time';         Iana = 'America/Denver' }
        [pscustomobject]@{ Clave = 'LosAngeles';  Nombre = 'Los Ángeles';                              Corto = 'Los Ángeles';  Win = 'Pacific Standard Time';          Iana = 'America/Los_Angeles' }
        [pscustomobject]@{ Clave = 'Mexico';      Nombre = 'Ciudad de México';                         Corto = 'México';       Win = 'Central Standard Time (Mexico)'; Iana = 'America/Mexico_City' }
        [pscustomobject]@{ Clave = 'Bogota';      Nombre = 'Bogotá, Lima, Quito';                      Corto = 'Bogotá';       Win = 'SA Pacific Standard Time';       Iana = 'America/Bogota' }
        [pscustomobject]@{ Clave = 'Santiago';    Nombre = 'Santiago de Chile';                        Corto = 'Santiago';     Win = 'Pacific SA Standard Time';       Iana = 'America/Santiago' }
        [pscustomobject]@{ Clave = 'BuenosAires'; Nombre = 'Buenos Aires';                             Corto = 'Buenos Aires'; Win = 'Argentina Standard Time';        Iana = 'America/Argentina/Buenos_Aires' }
        [pscustomobject]@{ Clave = 'Caracas';     Nombre = 'Caracas';                                  Corto = 'Caracas';      Win = 'Venezuela Standard Time';        Iana = 'America/Caracas' }
    )
}
function Zona-PorDefecto {
    # La de config (ZonaHorariaWin, por defecto Madrid): la que tienen las bases hechas antes de la ficha 36
    $z = @(Obtener-Zonas | Where-Object { $_.Win -eq [string]$Config.ZonaHorariaWin }) | Select-Object -First 1
    if ($z) { return [string]$z.Clave } else { return 'Madrid' }
}
function Zona-DelPc {
    # La zona de este PC si está en la lista (si varias filas comparten id de Windows, la primera); si no, Madrid
    $id = ''
    try { $id = [string][TimeZoneInfo]::Local.Id } catch {}
    $z = @(Obtener-Zonas | Where-Object { $_.Win -eq $id }) | Select-Object -First 1
    if ($z) { return [string]$z.Clave } else { return 'Madrid' }
}
function Resolver-Idioma([string]$clave) {
    $r = @(Obtener-Idiomas | Where-Object { $_.Clave -eq $clave }) | Select-Object -First 1
    if ($r) { return $r } else { return (Obtener-Idiomas)[0] }
}
function Resolver-Teclado([string]$clave) {
    $r = @(Obtener-Teclados | Where-Object { $_.Clave -eq $clave }) | Select-Object -First 1
    if ($r) { return $r } else { return (Obtener-Teclados)[0] }
}
function Resolver-Zona([string]$clave) {
    $r = @(Obtener-Zonas | Where-Object { $_.Clave -eq $clave }) | Select-Object -First 1
    if ($r) { return $r }
    return (@(Obtener-Zonas | Where-Object { $_.Clave -eq (Zona-PorDefecto) }) | Select-Object -First 1)
}
function Texto-IdiomaZona([string]$idioma, [string]$zona) {
    # Etiqueta pequeña «ES · Madrid» de las bases y las máquinas
    return "$((Resolver-Idioma $idioma).Corto) · $((Resolver-Zona $zona).Corto)"
}

function Recomendado-Sistema($sx) {
    # RAM (MB), procesadores y disco (GB) que conviene para instalar cada sistema. Es lo que sale por defecto en «Crear base»
    # (si no has guardado otra cosa para ese sistema) y lo que enseña la nota «Recomendado». Sin dato: lo de Ajustes.
    $clave = [string]$sx.Clave
    # (cada línea lleva «break»: sin él, «Ubuntu2404Desk» encajaría en dos y saldría una lista)
    $r = switch -Regex ($clave) {
        '^WinServer'            { @{ Ram = 4096; Cpus = 2; Disco = 60 }; break }
        '^Win11'                { @{ Ram = 4096; Cpus = 2; Disco = 64 }; break }
        '^Win10'                { @{ Ram = 4096; Cpus = 2; Disco = 60 }; break }
        '^Lubuntu'              { @{ Ram = 2048; Cpus = 2; Disco = 25 }; break }
        '^Kali'                 { @{ Ram = 4096; Cpus = 2; Disco = 40 }; break }
        '^ParrotHome$'          { @{ Ram = 4096; Cpus = 2; Disco = 30 }; break }
        '^Parrot$'              { @{ Ram = 4096; Cpus = 2; Disco = 40 }; break }
        'Desk$'                 { @{ Ram = 4096; Cpus = 2; Disco = 30 }; break }
        '^(Ubuntu|Debian|Rocky|Alma)' { @{ Ram = 2048; Cpus = 2; Disco = 20 }; break }
        '^Arch$'                { @{ Ram = 2048; Cpus = 2; Disco = 20 }; break }
        '^(OPNsense|pfSense)$'  { @{ Ram = 2048; Cpus = 2; Disco = 16 }; break }
        '^Proxmox$'             { @{ Ram = 8192; Cpus = 4; Disco = 64 }; break }
        '^FreeBSD$'             { @{ Ram = 2048; Cpus = 2; Disco = 20 }; break }
        default                 { $null; break }
    }
    if ($r) { return [pscustomobject]$r }
    $disco = $(if ([string]$sx.Tipo -eq 'windows') { $Config.DiscoWin_GB } else { $Config.DiscoLinux_GB })
    return [pscustomobject]@{ Ram = [int]$Config.RAM_MB; Cpus = [int]$Config.CPUs; Disco = [int]$disco }
}

function Receta-Manual($sx, [string]$idioma = 'es', [string]$teclado = 'es', [string]$zona = '') {
    # Pasos que se enseñan al hacer una base de instalación manual guiada (consola de Crear base y notas de la ventana).
    # Ficha 36: el idioma y el teclado que se dicen son los elegidos en la ventana (si no, español)
    $nomIdi = ([string](Resolver-Idioma $idioma).Nombre).ToLower()
    $nomTec = ([string](Resolver-Teclado $teclado).Nombre).ToLower()
    $nomTec = $nomTec -replace 'ee\. uu\.', 'EE. UU.'; $nomIdi = $nomIdi -replace 'ee\. uu\.', 'EE. UU.'
    $pasos = @()
    switch -Wildcard ([string]$sx.Clave) {
        'OPNsense' { $pasos += 'Esta base lleva 2 tarjetas de red: la 1ª es la WAN (NAT) y la 2ª la LAN (solo-anfitrión).'
                     $pasos += 'En el arranque, entra al instalador con el usuario «installer» (la contraseña de ese inicio la enseña OPNsense en pantalla / su documentación).'
                     $pasos += "Elige teclado $nomTec, disco entero, y al terminar pon la contraseña de root que quieras. Interfaz web después: https://<IP de la LAN>." }
        'pfSense'  { $pasos += 'Esta base lleva 2 tarjetas de red: la 1ª es la WAN (NAT) y la 2ª la LAN (solo-anfitrión).'
                     $pasos += "Acepta, elige «Install», teclado $nomTec y disco entero (las opciones por defecto valen)."
                     $pasos += 'Al asignar interfaces: WAN = la primera (vmx0) y LAN = la segunda (vmx1). Interfaz web después: https://<IP de la LAN>.' }
        'Proxmox'  { $pasos += 'La VM lleva la virtualización anidada activada (hace falta para crear máquinas dentro de Proxmox). Con 8 GB de RAM hay sitio para probar alguna máquina dentro.'
                     $pasos += 'Usa el instalador gráfico. En «Management Network» pon los datos de red de esta máquina (en Crear base salen listos para copiar). El nombre tiene que ser COMPLETO, con punto, por ejemplo  pve.lab.local.'
                     $pasos += 'La contraseña de root la pones tú en el instalador: Full Cowl no la guarda ni la cambia.'
                     $pasos += 'Al terminar, entra desde el navegador del PC a https://<IP que pusiste>:8006 con el usuario root (el aviso del certificado es normal: acéptalo).' }
        'Parrot*'  { $pasos += 'Arranca en modo «Live» (la primera opción del menú) y, ya en el escritorio, abre «Install Parrot».'
                     $pasos += "Elige idioma $nomIdi, teclado $nomTec y el disco entero (las opciones por defecto valen)."
                     $pasos += "Crea el usuario con el nombre «$($Config.Usuario)», el mismo que usa Full Cowl (la contraseña, la que tú quieras: Full Cowl no la guarda ni la cambia en estas bases)."
                     $pasos += "Al terminar y reiniciar, abre una terminal dentro de la máquina y escribe:  sudo apt install -y open-vm-tools-desktop openssh-server  y después  sudo systemctl enable --now ssh" }
        default    { $pasos += 'Instala el sistema como harías en un ordenador normal, con el disco entero.' }
    }
    $pasos += "Si el instalador te pregunta idioma, teclado o zona horaria, elige: idioma $nomIdi, teclado $nomTec y zona «$((Resolver-Zona $zona).Nombre)»."
    if ([string]$sx.Clave -notlike 'Parrot*') { $pasos += "Crea un usuario con el nombre «$($Config.Usuario)» si el sistema lo permite (la contraseña, la que tú quieras: Full Cowl no la guarda ni la cambia en estas bases)." }
    if ([string]$sx.Clave -notlike 'Parrot*') { $pasos += 'Si existen, instala las VMware Tools / open-vm-tools de ese sistema.' }
    $pasos += 'Cuando acabes, apaga el sistema desde dentro. O pulsa «Ya he terminado» en la ventana de Full Cowl: apaga la máquina con cuidado (y a la fuerza si no responde).'
    return $pasos
}

function Datos-RedProxmox {
    # Lo que pide el instalador de Proxmox en «Management Network», para la red NAT de VMware (VMnet8).
    # IP sugerida .120: fuera del reparto automático de VMware (empieza en .128) y lejos de los laboratorios (empiezan en .50).
    # Solo vale para redes /24 (lo normal en VMnet8); si no se puede leer la red, devuelve $null y la nota sale sin datos.
    $red = $null
    try { $red = Leer-RedNat } catch {}
    if (-not $red -or -not $red.Subred -or [int]$red.Prefijo -ne 24) { return $null }
    $b = ([string]$red.Subred).Split('.')
    if ($b.Count -ne 4) { return $null }
    $ip = "$($b[0]).$($b[1]).$($b[2]).120"
    return [pscustomobject]@{ Ip = $ip; Cidr = "$ip/24"; Puerta = [string]$red.Puerta; Dns = [string]$red.Puerta }
}

function Info-Arranque([string]$tipo) {
    # Qué hay que escribir a mano al arrancar el instalador de cada sistema (no hay VNC para que Packer lo escriba).
    #   Modo 'completa' = el prompt «boot:» (tecla ESC) y se escribe una línea ENTERA (Kali, Debian)
    #   Modo 'anadir'   = se pulsa Tab y se AÑADE un texto al final de la línea que sale (Rocky/Alma, Arch)
    # Devuelve $null si ese sistema no necesita nada a mano o si no hay VMnet8.
    $ip = Ip-PcVmnet8
    if (-not $ip) { return $null }
    switch ($tipo) {
        'kali'   { return @{ Modo = 'completa'; Texto = (Linea-ArranqueKali); Nombre = 'Kali' } }
        'debian' { return @{ Modo = 'completa'; Texto = (Linea-ArranqueDebian); Nombre = 'Debian' } }
        'rhel'   { return @{ Modo = 'anadir'; Texto = "inst.ks=http://$($ip):8820/ks.cfg"; Nombre = 'Rocky/Alma' } }
        'arch'   { return @{ Modo = 'anadir'; Texto = "script=http://$($ip):8820/arch.sh"; Nombre = 'Arch' } }
    }
    return $null
}

function Linea-KaliTeclado([string]$linea) {
    # Lo que hay que pulsar en un teclado ESPAÑOL para que el menú de arranque (teclado inglés) reciba la línea:
    # = es la tecla ¡ · : es Mayús+ñ (se escribe Ñ) · / es la tecla - (a la derecha del punto). Vale para cualquier texto.
    return $linea.Replace('=', '¡').Replace(':', 'Ñ').Replace('/', '-')
}

function Usuario-DeVm($vmx) {
    # Usuario con el que se creó la base de esta máquina. Desde el 30/10/2026 Full Cowl lo apunta en el
    # .vmx de cada base y de cada máquina (guestinfo.vmtareas.usuario): así, cambiar el usuario en
    # Ajustes solo afecta a las bases nuevas. Sin marca (bases anteriores), el de Ajustes.
    $u = [string](Leer-ValorVmx $vmx 'guestinfo.vmtareas.usuario')
    if (-not $u) {
        $nb = [string](Leer-ValorVmx $vmx 'guestinfo.vmtareas.base')
        if ($nb -and $Config.CarpetaBases) {
            $vb = Get-ChildItem -LiteralPath (Join-Path $Config.CarpetaBases $nb) -Filter *.vmx -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($vb) { $u = [string](Leer-ValorVmx $vb.FullName 'guestinfo.vmtareas.usuario') }
        }
    }
    if ($u -cmatch '^[a-z_][a-z0-9_-]{0,19}$') { return $u }
    return [string]$Config.Usuario
}

function Marcar-UsuarioBases([string]$usuario) {
    # Antes de cambiar el usuario en Ajustes: las bases sin marca se hicieron con el usuario de antes.
    # Se apunta en su .vmx (solo si están apagadas y cerradas: las bases no se arrancan).
    if ($usuario -cnotmatch '^[a-z_][a-z0-9_-]{0,19}$' -or -not $Config.CarpetaBases -or -not (Test-Path -LiteralPath $Config.CarpetaBases)) { return }
    foreach ($d in @(Get-ChildItem -LiteralPath $Config.CarpetaBases -Directory -ErrorAction SilentlyContinue)) {
        $v = Get-ChildItem -LiteralPath $d.FullName -Filter *.vmx -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $v -or (Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.usuario')) { continue }
        if (Get-ChildItem -LiteralPath $d.FullName -Filter '*.lck' -ErrorAction SilentlyContinue) { continue }
        try { Fijar-ValoresVmx $v.FullName @{ 'guestinfo.vmtareas.usuario' = $usuario } } catch {}
    }
}

function Leer-ValorVmx($ruta, $clave) {
    foreach ($l in (Leer-Vmx $ruta)) {
        if ($l -match ('^\s*' + [regex]::Escape($clave) + '\s*=\s*"(.*)"')) { return $Matches[1] }
    }
    return $null
}

# =====================================================================
#  Etiquetas y nota de cada máquina (ficha 18)
#  Se guardan en el .vmx: guestinfo.vmtareas.etiquetas (lista con comas) y guestinfo.vmtareas.nota (una línea; los saltos
#  de línea se guardan como \n). Las copias NO las heredan de la base.
# =====================================================================
$script:EtqMaxPorMaquina = 8
$script:EtqMaxLetras = 24
$script:NotaMaxLetras = 500

function Limpiar-Etiqueta([string]$textoEtq) {
    # Una etiqueta limpia: sin comillas, comas ni saltos de línea y con los espacios justos
    $limpiaEtq = ([string]$textoEtq) -replace '[\r\n\t",|]', ' ' -replace '\s+', ' '
    return $limpiaEtq.Trim()
}

function Normalizar-Etiquetas($listaEtq) {
    # Quita vacías y repetidas (sin mirar mayúsculas), recorta a 24 letras y deja como mucho 8
    $vistasEtq = @{}
    $salidaEtq = @()
    foreach ($elemEtq in @($listaEtq)) {
        foreach ($parteEtq in ([string]$elemEtq -split ',')) {
            $unaEtq = Limpiar-Etiqueta $parteEtq
            if (-not $unaEtq) { continue }
            if ($unaEtq.Length -gt $script:EtqMaxLetras) { $unaEtq = $unaEtq.Substring(0, $script:EtqMaxLetras).Trim() }
            $claveEtq = $unaEtq.ToLowerInvariant()
            if ($vistasEtq.ContainsKey($claveEtq)) { continue }
            if ($salidaEtq.Count -ge $script:EtqMaxPorMaquina) { break }
            $vistasEtq[$claveEtq] = $true
            $salidaEtq += $unaEtq
        }
    }
    return $salidaEtq
}

function Codificar-TextoVmx([string]$textoVmx) {
    # Texto seguro para una línea del .vmx: sin comillas ni saltos reales. «\» se duplica, el salto es «\n» y «|» sigue
    # la costumbre de VMware (|7C), así que no se rompe aunque VMware reescriba el archivo
    $t = ([string]$textoVmx) -replace '"', "'"
    $t = $t -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    $t = $t.Replace("`t", ' ').Replace('\', '\\').Replace("`r`n", '\n').Replace("`n", '\n').Replace("`r", '\n').Replace('|', '|7C')
    return $t
}

function Decodificar-TextoVmx([string]$textoVmx) {
    # Lo contrario de Codificar-TextoVmx (entiende también los |22, |0A... que escribe VMware)
    return [regex]::Replace([string]$textoVmx, '\\(\\|n)|\|([0-9A-Fa-f]{2})', [System.Text.RegularExpressions.MatchEvaluator]{
        param($coincide)
        if ($coincide.Groups[2].Success) { return [string][char][Convert]::ToInt32($coincide.Groups[2].Value, 16) }
        if ($coincide.Groups[1].Value -eq 'n') { return "`n" }
        return '\'
    })
}

function Leer-EtiquetasNota($rutaVmx) {
    # Etiquetas guardadas y nota de una máquina (en una sola lectura del .vmx)
    $etqCrudo = ''; $notaCruda = ''
    try {
        foreach ($lineaEn in (Leer-Vmx $rutaVmx)) {
            if ($lineaEn -match '^\s*guestinfo\.vmtareas\.etiquetas\s*=\s*"(.*)"') { $etqCrudo = $Matches[1] }
            elseif ($lineaEn -match '^\s*guestinfo\.vmtareas\.nota\s*=\s*"(.*)"') { $notaCruda = $Matches[1] }
        }
    } catch {}
    return [pscustomobject]@{
        Etiquetas = @(Normalizar-Etiquetas (Decodificar-TextoVmx $etqCrudo))
        Nota      = (Decodificar-TextoVmx $notaCruda)
    }
}

function Quitar-ValoresVmx($rutaVmx, [string[]]$clavesQuitar) {
    # Borra esas claves del .vmx (si están)
    $minusQuitar = @($clavesQuitar | ForEach-Object { $_.ToLower() })
    $lineasQuedan = @(Leer-Vmx $rutaVmx | Where-Object { $minusQuitar -notcontains (($_ -split '=', 2)[0].Trim().ToLower()) })
    Guardar-Vmx $rutaVmx $lineasQuedan
}

function Guardar-EtiquetasNota($rutaVmx, $etiquetasNuevas, $notaNueva) {
    # $null = no tocar esa parte. Lo vacío quita la clave del .vmx (queda limpio)
    $ponerEtq = @{}; $quitarEtq = @()
    if ($null -ne $etiquetasNuevas) {
        $unidas = (@(Normalizar-Etiquetas $etiquetasNuevas)) -join ','
        if ($unidas) { $ponerEtq['guestinfo.vmtareas.etiquetas'] = Codificar-TextoVmx $unidas } else { $quitarEtq += 'guestinfo.vmtareas.etiquetas' }
    }
    if ($null -ne $notaNueva) {
        $notaTxt = ([string]$notaNueva).Replace("`r`n", "`n")
        if ($notaTxt.Length -gt $script:NotaMaxLetras) { $notaTxt = $notaTxt.Substring(0, $script:NotaMaxLetras) }
        if ($notaTxt.Trim()) { $ponerEtq['guestinfo.vmtareas.nota'] = Codificar-TextoVmx $notaTxt } else { $quitarEtq += 'guestinfo.vmtareas.nota' }
    }
    if ($quitarEtq.Count) { Quitar-ValoresVmx $rutaVmx $quitarEtq }
    if ($ponerEtq.Count) { Fijar-ValoresVmx $rutaVmx $ponerEtq }
}

function Etiqueta-DeLab([string]$nombreLab) {
    # La etiqueta fija de las máquinas de un laboratorio («Lab LAB1»). No se guarda: se calcula al leer
    if ($nombreLab) { return "Lab $nombreLab" }
    return ''
}

function Leer-RedNat {
    # Red NAT de VMware (VMnet8): subred, prefijo y puerta de enlace
    $red = $null
    try {
        $t = Get-Content (Join-Path $env:ProgramData 'VMware\vmnetdhcp.conf') -Raw -ErrorAction Stop
        $m = [regex]::Match($t, '(?s)segment 8\b.*?subnet\s+([\d\.]+)\s+netmask\s+([\d\.]+)\s*\{(.*?)\}')
        if ($m.Success) {
            $bits = ($m.Groups[2].Value.Split('.') | ForEach-Object { [Convert]::ToString([int]$_, 2) }) -join ''
            $gw = [regex]::Match($m.Groups[3].Value, 'option routers\s+([\d\.]+)').Groups[1].Value
            $red = @{ Subred = $m.Groups[1].Value; Prefijo = ($bits -replace '0', '').Length; Puerta = $gw }
        }
    } catch {}
    if (-not $red) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -like '*VMnet8*' } | Select-Object -First 1)
        if ($ip) {
            $b = $ip.IPAddress.Split('.')
            $red = @{ Subred = "$($b[0]).$($b[1]).$($b[2]).0"; Prefijo = $ip.PrefixLength; Puerta = "$($b[0]).$($b[1]).$($b[2]).2" }
        }
    }
    if ($red -and -not $red.Puerta) {
        $b = $red.Subred.Split('.'); $red.Puerta = "$($b[0]).$($b[1]).$($b[2]).2"
    }
    return $red
}

function Leer-InventarioVmware {
    # Máquinas que hay en la biblioteca de VMware Workstation de este PC (.vmx que existen)
    $f = Join-Path $env:APPDATA 'VMware\inventory.vmls'
    if (-not (Test-Path $f)) { return @() }
    $r = @()
    foreach ($l in [IO.File]::ReadAllLines($f)) {
        if ($l -match '^\s*vmlist\d+\.config\s*=\s*"(.+\.vmx)"') {
            $ruta = $Matches[1]
            if (Test-Path -LiteralPath $ruta) { $r += $ruta }
        }
    }
    return @($r | Select-Object -Unique)
}

function Leer-Clones {
    # Máquinas de la carpeta de VMs (una por subcarpeta) y, además, las de la biblioteca
    # de VMware que estén en otras carpetas (Externa = no las creó Full Cowl)
    $r = @(); $vistos = @{}
    if ($Config.CarpetaVMs -and (Test-Path $Config.CarpetaVMs)) {
        foreach ($d in @(Get-ChildItem $Config.CarpetaVMs -Directory -ErrorAction SilentlyContinue | Where-Object { -not $_.Name.StartsWith('_') })) {
            $v = Get-ChildItem -LiteralPath $d.FullName -Filter *.vmx -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $v) { continue }
            $vistos[$v.FullName.ToLower()] = $true
            $r += [pscustomobject]@{
                Nombre  = $d.Name
                Carpeta = $d.FullName
                Vmx     = $v.FullName
                IP      = Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.ip'
                Dominio = Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.dominio'
                Netbios = Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.netbios'
                Externa = $false
            }
        }
    }
    $prefBases = if ($Config.CarpetaBases) { ($Config.CarpetaBases.TrimEnd('\') + '\').ToLower() } else { $null }
    foreach ($vmx in @(Leer-InventarioVmware)) {
        $k = $vmx.ToLower()
        if ($vistos[$k]) { continue }
        if ($prefBases -and $k.StartsWith($prefBases)) { continue }   # las bases no se tocan
        $vistos[$k] = $true
        $nombre = Leer-ValorVmx $vmx 'displayName'
        if (-not $nombre) { $nombre = [IO.Path]::GetFileNameWithoutExtension($vmx) }
        $r += [pscustomobject]@{
            Nombre  = $nombre
            Carpeta = Split-Path $vmx
            Vmx     = $vmx
            IP      = Leer-ValorVmx $vmx 'guestinfo.vmtareas.ip'
            Dominio = Leer-ValorVmx $vmx 'guestinfo.vmtareas.dominio'
            Netbios = Leer-ValorVmx $vmx 'guestinfo.vmtareas.netbios'
            Externa = $true
        }
    }
    return $r
}

function Familia-GuestOS($vmx) {
    # Sistema de una máquina que no viene de una base de Full Cowl
    $g = "$(Leer-ValorVmx $vmx 'guestOS')".ToLower()
    if ($g -like '*srv*' -or $g -like '*server*') { return 'Windows Server' }
    if ($g -like 'windows*') { return 'Windows' }
    if ($g -like 'ubuntu*') { return 'Ubuntu' }
    if ($g -like 'debian*') { return 'Debian/Kali' }
    if ($g -like '*linux*' -or $g -like 'other*') { return 'Linux' }
    return $g
}

function Preguntar($texto, $defecto) {
    $r = (Read-Host "$texto [$defecto]").Trim()
    if ($r) { return $r } else { return $defecto }
}

function Preguntar-SiNo($texto, [bool]$defecto = $false) {
    $suf = if ($defecto) { '(S/n)' } else { '(s/N)' }
    $r = (Read-Host "$texto $suf").Trim()
    if (-not $r) { return $defecto }
    return ($r -match '^[sSyY]')
}

function Elegir-Varios($opciones) {
    # $opciones: lista de @{ Clave; Texto }. Devuelve las claves elegidas.
    for ($i = 0; $i -lt $opciones.Count; $i++) { Write-Host ("  {0,2}) {1}" -f ($i + 1), $opciones[$i].Texto) }
    $r = Read-Host "Números separados por espacios (Enter = ninguno)"
    $elegidas = @()
    foreach ($n in [regex]::Matches($r, '\d+')) {
        $k = [int]$n.Value
        if ($k -ge 1 -and $k -le $opciones.Count) { $elegidas += $opciones[$k - 1].Clave }
    }
    return @($elegidas | Select-Object -Unique)
}

# (\z y no $: «$» también acepta un salto de línea al final; [0-9] y no \d: \d acepta dígitos de otros alfabetos)
function Es-IPv4($t) { return ([string]$t -match '^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\z') -and ((([string]$t).Split('.') | Where-Object { [int]$_ -gt 255 }).Count -eq 0) }
function Usuario-SeguroEnOrden([string]$u) {
    # $true si ese nombre de usuario se puede poner en una línea de órdenes (ssh, cmdkey…): letras, números, punto, guion y
    # guion bajo, sin empezar por guion (se leería como una opción). El usuario sale del .vmx, que puede ser de otra persona.
    return ($u -cmatch '^[A-Za-z0-9_][A-Za-z0-9._-]{0,31}\z')
}

# =====================================================================
#  Datos compartidos por la consola y la ventana
# =====================================================================
function Obtener-Sistemas {
    # Catálogo de sistemas. Campos (ficha 17): Familia (windows, ubuntu, debian, rhel, bsd, otro), Estado (Estable, Nuevo = recién
    # añadido y sin probar a fondo, Manual), Gestor (paquetes de los extras de la ficha 20: apt, dnf, pacman, windows, ninguno) y
    # Conexion (acción rápida de la ficha 19: rdp, ssh, ninguna). Para las tarjetas de «Crear base»: Linea (una tarjeta por línea,
    # p. ej. «Ubuntu»), Version y Edicion (chips dentro de la tarjeta) y Web (dónde conseguir la ISO oficial; no se descarga nada). OJO: la Clave de un sistema que ya existe no se cambia nunca,
    # porque los laboratorios compartidos (.fclab, ficha 21) se refieren a las bases por su Clave.
    @(
        @{ Clave = 'WinServer2025';  Nombre = 'Windows Server 2025 (escritorio)';     Tipo = 'windows'; ISO = $Config.ISO_WinServer2025; Patron = '(server.*2025|2025.*server)'; GuestOS = 'windows2019srvnext-64'; Familia = 'windows'; Estado = 'Nuevo';  Gestor = 'windows'; Conexion = 'rdp'; Linea = 'Windows Server'; Version = '2025'; Edicion = ''; Web = 'https://www.microsoft.com/evalcenter/' }
        @{ Clave = 'WinServer2022';  Nombre = 'Windows Server 2022 (escritorio)';     Tipo = 'windows'; ISO = $Config.ISO_WinServer2022; Patron = '(server.*2022|2022.*server)'; GuestOS = 'windows2019srvnext-64'; Familia = 'windows'; Estado = 'Estable'; Gestor = 'windows'; Conexion = 'rdp'; Linea = 'Windows Server'; Version = '2022'; Edicion = ''; Web = 'https://www.microsoft.com/evalcenter/' }
        @{ Clave = 'WinServer2019';  Nombre = 'Windows Server 2019 (escritorio)';     Tipo = 'windows'; ISO = $Config.ISO_WinServer2019; Patron = '(server.*2019|2019.*server)'; GuestOS = 'windows2019srv-64'; Familia = 'windows'; Estado = 'Estable'; Gestor = 'windows'; Conexion = 'rdp'; Linea = 'Windows Server'; Version = '2019'; Edicion = ''; Web = 'https://www.microsoft.com/evalcenter/' }
        @{ Clave = 'Win10Pro';       Nombre = 'Windows 10 Pro';                       Tipo = 'windows'; ISO = $Config.ISO_Win10Pro;      Patron = '(win(dows)?[ _-]?10)';       GuestOS = 'windows9-64'; Familia = 'windows'; Estado = 'Estable'; Gestor = 'ninguno'; Conexion = 'rdp'; Linea = 'Windows'; Version = '10 Pro'; Edicion = ''; Web = 'https://www.microsoft.com/software-download/windows10' }
        @{ Clave = 'Win11Pro';       Nombre = 'Windows 11 Pro';                       Tipo = 'windows'; ISO = $Config.ISO_Win11Pro;      Patron = '(win(dows)?[ _-]?11)';       GuestOS = 'windows9-64'; Win11 = $true; Familia = 'windows'; Estado = 'Estable'; Gestor = 'ninguno'; Conexion = 'rdp'; Linea = 'Windows'; Version = '11 Pro'; Edicion = ''; Web = 'https://www.microsoft.com/software-download/windows11' }
        @{ Clave = 'Ubuntu2604';     Nombre = 'Ubuntu 26.04 Server (sin escritorio)'; Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2604;    Patron = '^ubuntu-26\.04.*server';     Desktop = $false; Familia = 'ubuntu'; Estado = 'Nuevo';  Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Ubuntu'; Version = '26.04'; Edicion = 'Server'; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Ubuntu2604Desk'; Nombre = 'Ubuntu 26.04 con escritorio';          Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2604;    Patron = '^ubuntu-26\.04.*server';     Desktop = $true;  Familia = 'ubuntu'; Estado = 'Nuevo';  Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Ubuntu'; Version = '26.04'; Edicion = 'Con escritorio'; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Ubuntu2404';     Nombre = 'Ubuntu 24.04 Server (sin escritorio)'; Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2404;    Patron = '^ubuntu-24\.04.*server';     Desktop = $false; Familia = 'ubuntu'; Estado = 'Estable'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Ubuntu'; Version = '24.04'; Edicion = 'Server'; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Ubuntu2404Desk'; Nombre = 'Ubuntu 24.04 con escritorio';          Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2404;    Patron = '^ubuntu-24\.04.*server';     Desktop = $true;  Familia = 'ubuntu'; Estado = 'Estable'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Ubuntu'; Version = '24.04'; Edicion = 'Con escritorio'; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Lubuntu2404';    Nombre = 'Lubuntu 24.04 (escritorio ligero)';    Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2404;    Patron = '^ubuntu-24\.04.*server';     Desktop = $true; Escritorio = 'lubuntu-desktop'; Familia = 'ubuntu'; Estado = 'Estable'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Lubuntu'; Version = '24.04'; Edicion = ''; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Ubuntu2204';     Nombre = 'Ubuntu 22.04 Server (sin escritorio)'; Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2204;    Patron = '^ubuntu-22\.04.*server';     Desktop = $false; Antiguo = $true; Familia = 'ubuntu'; Estado = 'Estable'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Ubuntu'; Version = '22.04'; Edicion = 'Server'; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Ubuntu2204Desk'; Nombre = 'Ubuntu 22.04 con escritorio';          Tipo = 'ubuntu';  ISO = $Config.ISO_Ubuntu2204;    Patron = '^ubuntu-22\.04.*server';     Desktop = $true;  Antiguo = $true; Familia = 'ubuntu'; Estado = 'Estable'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Ubuntu'; Version = '22.04'; Edicion = 'Con escritorio'; Web = 'https://ubuntu.com/download/server' }
        @{ Clave = 'Kali';           Nombre = 'Kali Linux (escribes una línea al arrancar)'; Tipo = 'kali'; ISO = $Config.ISO_Kali;     Patron = '^kali-linux.*installer.*\.iso$'; GuestOS = 'debian12-64'; Familia = 'debian'; Estado = 'Estable'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Kali Linux'; Version = ''; Edicion = ''; Web = 'https://www.kali.org/get-kali/#kali-installer-images' }
        @{ Clave = 'Parrot'; Nombre = 'Parrot Security (instalación manual)'; Tipo = 'manual'; ISO = $Config.ISO_Parrot; Patron = '^Parrot-security-.*_amd64\.iso$'; GuestOS = 'debian12-64'; Familia = 'debian'; Estado = 'Nuevo'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Parrot'; Version = ''; Edicion = 'Security'; Web = 'https://parrotsec.org/download/' }
        @{ Clave = 'ParrotHome'; Nombre = 'Parrot Home (instalación manual)'; Tipo = 'manual'; ISO = $Config.ISO_ParrotHome; Patron = '^Parrot-home-.*_amd64\.iso$'; GuestOS = 'debian12-64'; Familia = 'debian'; Estado = 'Nuevo'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Parrot'; Version = ''; Edicion = 'Home'; Web = 'https://parrotsec.org/download/' }
        @{ Clave = 'Debian13'; Nombre = 'Debian 13 (sin escritorio)'; Tipo = 'debian'; ISO = $Config.ISO_Debian13; Patron = '^debian-13.*netinst.*\.iso$'; GuestOS = 'debian12-64'; Familia = 'debian'; Estado = 'Nuevo'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Debian'; Version = '13'; Edicion = 'Server'; Web = 'https://www.debian.org/distrib/netinst' }
        @{ Clave = 'Debian13Desk'; Nombre = 'Debian 13 con escritorio Xfce'; Tipo = 'debian'; ISO = $Config.ISO_Debian13Desk; Patron = '^debian-13.*netinst.*\.iso$'; GuestOS = 'debian12-64'; Desktop = $true; Familia = 'debian'; Estado = 'Nuevo'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Debian'; Version = '13'; Edicion = 'Con escritorio'; Web = 'https://www.debian.org/distrib/netinst' }
        @{ Clave = 'Debian12'; Nombre = 'Debian 12 (sin escritorio)'; Tipo = 'debian'; ISO = $Config.ISO_Debian12; Patron = '^debian-12.*netinst.*\.iso$'; GuestOS = 'debian12-64'; Familia = 'debian'; Estado = 'Nuevo'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Debian'; Version = '12'; Edicion = 'Server'; Web = 'https://www.debian.org/distrib/netinst' }
        @{ Clave = 'Debian12Desk'; Nombre = 'Debian 12 con escritorio Xfce'; Tipo = 'debian'; ISO = $Config.ISO_Debian12Desk; Patron = '^debian-12.*netinst.*\.iso$'; GuestOS = 'debian12-64'; Desktop = $true; Familia = 'debian'; Estado = 'Nuevo'; Gestor = 'apt'; Conexion = 'ssh'; Linea = 'Debian'; Version = '12'; Edicion = 'Con escritorio'; Web = 'https://www.debian.org/distrib/netinst' }
        @{ Clave = 'Rocky9'; Nombre = 'Rocky Linux 9 (sin escritorio)'; Tipo = 'rhel'; ISO = $Config.ISO_Rocky9; Patron = '^Rocky-9.*dvd.*\.iso$'; GuestOS = 'rhel9-64'; Familia = 'rhel'; Estado = 'Nuevo'; Gestor = 'dnf'; Conexion = 'ssh'; Linea = 'Rocky Linux'; Version = '9'; Edicion = 'Server'; Web = 'https://rockylinux.org/download' }
        @{ Clave = 'Rocky9Desk'; Nombre = 'Rocky Linux 9 con escritorio GNOME'; Tipo = 'rhel'; ISO = $Config.ISO_Rocky9Desk; Patron = '^Rocky-9.*dvd.*\.iso$'; GuestOS = 'rhel9-64'; Desktop = $true; Familia = 'rhel'; Estado = 'Nuevo'; Gestor = 'dnf'; Conexion = 'ssh'; Linea = 'Rocky Linux'; Version = '9'; Edicion = 'Con escritorio'; Web = 'https://rockylinux.org/download' }
        @{ Clave = 'Alma9'; Nombre = 'AlmaLinux 9 (sin escritorio)'; Tipo = 'rhel'; ISO = $Config.ISO_Alma9; Patron = '^AlmaLinux-9.*dvd.*\.iso$'; GuestOS = 'rhel9-64'; Familia = 'rhel'; Estado = 'Nuevo'; Gestor = 'dnf'; Conexion = 'ssh'; Linea = 'AlmaLinux'; Version = '9'; Edicion = 'Server'; Web = 'https://almalinux.org/get-almalinux/' }
        @{ Clave = 'Alma9Desk'; Nombre = 'AlmaLinux 9 con escritorio GNOME'; Tipo = 'rhel'; ISO = $Config.ISO_Alma9Desk; Patron = '^AlmaLinux-9.*dvd.*\.iso$'; GuestOS = 'rhel9-64'; Desktop = $true; Familia = 'rhel'; Estado = 'Nuevo'; Gestor = 'dnf'; Conexion = 'ssh'; Linea = 'AlmaLinux'; Version = '9'; Edicion = 'Con escritorio'; Web = 'https://almalinux.org/get-almalinux/' }
        @{ Clave = 'Arch'; Nombre = 'Arch Linux (mínimo)'; Tipo = 'arch'; ISO = $Config.ISO_Arch; Patron = '^archlinux-.*x86_64\.iso$'; GuestOS = 'other5xlinux-64'; Familia = 'otro'; Estado = 'Nuevo'; Gestor = 'pacman'; Conexion = 'ssh'; Linea = 'Arch Linux'; Version = ''; Edicion = 'Mínimo'; Web = 'https://archlinux.org/download/' }
        @{ Clave = 'ArchDesk'; Nombre = 'Arch Linux con escritorio Xfce'; Tipo = 'arch'; ISO = $Config.ISO_ArchDesk; Patron = '^archlinux-.*x86_64\.iso$'; GuestOS = 'other5xlinux-64'; Desktop = $true; Familia = 'otro'; Estado = 'Nuevo'; Gestor = 'pacman'; Conexion = 'ssh'; Linea = 'Arch Linux'; Version = ''; Edicion = 'Con escritorio'; Web = 'https://archlinux.org/download/' }
        @{ Clave = 'OPNsense'; Nombre = 'OPNsense (cortafuegos)'; Tipo = 'manual'; ISO = $Config.ISO_OPNsense; Patron = '^OPNsense-.*dvd.*\.iso$'; GuestOS = 'freebsd12-64'; Nics = 2; Familia = 'bsd'; Estado = 'Manual'; Gestor = 'ninguno'; Conexion = 'ninguna'; Linea = 'Cortafuegos'; Version = ''; Edicion = 'OPNsense'; Web = 'https://opnsense.org/download/' }
        @{ Clave = 'pfSense'; Nombre = 'pfSense CE (cortafuegos)'; Tipo = 'manual'; ISO = $Config.ISO_pfSense; Patron = '^pfSense-CE-.*\.iso$'; GuestOS = 'freebsd12-64'; Nics = 2; Familia = 'bsd'; Estado = 'Manual'; Gestor = 'ninguno'; Conexion = 'ninguna'; Linea = 'Cortafuegos'; Version = ''; Edicion = 'pfSense'; Web = 'https://www.pfsense.org/download/' }
        @{ Clave = 'Proxmox'; Nombre = 'Proxmox VE'; Tipo = 'manual'; ISO = $Config.ISO_Proxmox; Patron = '^proxmox-ve.*\.iso$'; GuestOS = 'debian12-64'; Anidada = $true; Familia = 'debian'; Estado = 'Manual'; Gestor = 'ninguno'; Conexion = 'ninguna'; Linea = 'Proxmox VE'; Version = ''; Edicion = 'Virtualización'; Web = 'https://www.proxmox.com/en/downloads' }
        @{ Clave = 'FreeBSD'; Nombre = 'FreeBSD'; Tipo = 'manual'; ISO = $Config.ISO_FreeBSD; Patron = '^FreeBSD-.*(disc1|dvd1).*\.iso$'; GuestOS = 'freebsd12-64'; Familia = 'bsd'; Estado = 'Manual'; Gestor = 'ninguno'; Conexion = 'ninguna'; Linea = 'FreeBSD'; Version = ''; Edicion = 'Server'; Web = 'https://www.freebsd.org/where/' }
        @{ Clave = 'Otro'; Nombre = 'Otro sistema (instalación manual)'; Tipo = 'manual'; ISO = $Config.ISO_Otro; Patron = '\.iso$'; GuestOS = 'other5xlinux-64'; Familia = 'otro'; Estado = 'Manual'; Gestor = 'ninguno'; Conexion = 'ninguna'; Linea = 'Otro sistema'; Version = ''; Edicion = 'Cualquier ISO'; Web = '' }
    )
}

function Buscar-IsosSistema($sistema) {
    # ISO de la carpeta que encajan con el sistema; la preferida de config.ps1 primero
    if (-not $Config.CarpetaISOs) { return @() }
    $ctl = @(Get-ChildItem -LiteralPath $Config.CarpetaISOs -Filter *.iso -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match $sistema.Patron } | Sort-Object LastWriteTime -Descending)
    $pref = @($ctl | Where-Object { $_.Name -eq $sistema.ISO })
    return @($pref + @($ctl | Where-Object { $_.Name -ne $sistema.ISO }))
}

function Buscar-IsoTools([string]$nombre) {
    # CD de VMware Tools para instalarlas en una base: windows.iso (Windows) o linux.iso (Linux antiguos).
    # Primero el que trae VMware Workstation (su carpeta solo la puede cambiar un administrador);
    # si no está, el de la carpeta de ISOs de este PC (por si se descargó aparte).
    $sitios = @()
    $vmrunTools = Buscar-Vmrun -Silencioso
    if ($vmrunTools) { $sitios += (Split-Path $vmrunTools) }
    if ($Config.CarpetaISOs) { $sitios += $Config.CarpetaISOs }
    foreach ($dir in $sitios) {
        $ruta = Join-Path $dir $nombre
        if (Test-Path -LiteralPath $ruta) { return $ruta }
    }
    return $null
}

function Obtener-Bases {
    # (la primera vez en un PC la carpeta aún no está elegida: sin bases, y sin pasar una ruta vacía a Test-Path)
    if (-not $Config.CarpetaBases -or -not (Test-Path -LiteralPath $Config.CarpetaBases)) { return @() }
    @(Get-ChildItem $Config.CarpetaBases -Directory | ForEach-Object {
        $v = Get-ChildItem $_.FullName -Filter *.vmx | Select-Object -First 1
        if ($v) {
            [pscustomobject]@{
                Nombre     = $_.Name
                Vmx        = $v.FullName
                EsWindows  = (Leer-ValorVmx $v.FullName 'guestOS') -like 'windows*'
                EsServidor = $_.Name -like '*Server*'
                ConAgente  = [int](Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.agente') -ge 2
                # Desde la 2.0 las bases se instalan con una contraseña temporal y cada máquina recibe la real en su CD
                ClaveTemporal = [int](Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.agente') -ge 3
                Familia    = Familia-Sistema $_.Name
                Usuario    = Usuario-DeVm $v.FullName
                # Base de «instalación manual guiada» (fase 3 de la ficha 17): sin agente ni personalización automática
                Manual     = ((Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.manual') -eq 'TRUE')
                # Ficha 36: idioma, teclado y zona con que se instaló (bases de antes: español, español y la zona de config)
                Idioma     = [string](Resolver-Idioma ([string](Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.idioma'))).Clave
                Teclado    = [string](Resolver-Teclado ([string](Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.teclado'))).Clave
                Zona       = [string](Resolver-Zona ([string](Leer-ValorVmx $v.FullName 'guestinfo.vmtareas.zona'))).Clave
            }
        }
    })
}

function Familia-Sistema($nombre) {
    # Nombre corto del sistema a partir del nombre de la base
    if ($nombre -like 'Kali*') { return 'Kali Linux' }
    if ($nombre -like 'Parrot*') { return 'Parrot' }
    if ($nombre -like 'Debian*') { return 'Debian' }
    if ($nombre -like 'Rocky*') { return 'Rocky Linux' }
    if ($nombre -like 'Alma*') { return 'AlmaLinux' }
    if ($nombre -like 'Arch*') { return 'Arch Linux' }
    if ($nombre -like 'OPNsense*' -or $nombre -like 'pfSense*') { return 'Cortafuegos' }
    if ($nombre -like 'Proxmox*') { return 'Proxmox VE' }
    if ($nombre -like 'FreeBSD*') { return 'FreeBSD' }
    if ($nombre -eq 'Otro') { return 'Otro sistema' }
    if ($nombre -like 'Lubuntu*') { return 'Lubuntu' }
    if ($nombre -like 'Ubuntu*') { return 'Ubuntu' }
    if ($nombre -like '*Server*') { return 'Windows Server' }
    if ($nombre -like 'Win*') { return 'Windows' }
    return $nombre
}

# =====================================================================
#  Gestor de máquinas y limpieza (ventana, pestaña "Mis máquinas")
# =====================================================================
function Formato-Tamano([double]$b) {
    if ($b -ge 1GB) { return '{0:N1} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    return '{0:N0} KB' -f ($b / 1KB)
}

function Tamano-Carpeta($ruta) {
    $t = [double]0
    Get-ChildItem -LiteralPath $ruta -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $t += $_.Length }
    return $t
}

function Tamano-Maquina($vmx, $carpeta) {
    # Lo que ocupa una máquina. Si tiene su propia carpeta, la carpeta entera; si su .vmx está suelto
    # en una carpeta compartida (por ejemplo directamente en la carpeta de máquinas, junto a otras),
    # solo sus archivos: los que empiezan por su nombre (Nombre.vmx, Nombre-s001.vmdk, Nombre.nvram…)
    if (Carpeta-BorrableSegura $carpeta) { return Tamano-Carpeta $carpeta }
    $base = [IO.Path]::GetFileNameWithoutExtension($vmx)
    $t = [double]0
    Get-ChildItem -LiteralPath $carpeta -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $t += $_.Length }
    return $t
}

function Leer-PadreVmdk($vmdk) {
    # parentFileNameHint del descriptor del disco (va en texto al principio del archivo)
    try {
        $fs = [IO.File]::Open($vmdk, 'Open', 'Read', 'ReadWrite')
        try {
            $buf = New-Object byte[] 65536
            $n = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Close() }
        $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
        if ($txt -match 'parentFileNameHint\s*=\s*"([^"]+)"') { return $Matches[1] }
        return ''
    } catch { return $null }   # bloqueado o ilegible
}

function Base-DeMaquina($vmx) {
    # Devuelve @{ Base; Enlazada } siguiendo la cadena de discos hasta salir de la carpeta del clon
    # Rota = el disco del que depende ya no existe (su base se borró)
    $r = @{ Base = Leer-ValorVmx $vmx 'guestinfo.vmtareas.base'; Enlazada = $null; Rota = $false }
    $copia = Leer-ValorVmx $vmx 'guestinfo.vmtareas.copia'
    if ($copia) { $r.Enlazada = ($copia -eq 'linked') }
    if ($r.Base -and $copia) { return $r }
    $carpeta = Split-Path $vmx
    $disco = $null
    foreach ($l in (Leer-Vmx $vmx)) {
        if ($l -match '^\s*(scsi|sata|nvme|ide)\d+:\d+\.fileName\s*=\s*"(.+\.vmdk)"') { $disco = $Matches[2]; break }
    }
    for ($i = 0; $disco -and $i -lt 12; $i++) {
        if (-not [IO.Path]::IsPathRooted($disco)) { $disco = Join-Path $carpeta $disco }
        if (-not (Test-Path -LiteralPath $disco)) {
            if ($i -gt 0) { $r.Enlazada = $true; $r.Rota = $true; if (-not $r.Base) { $r.Base = Split-Path (Split-Path $disco) -Leaf } }
            break
        }
        if ((Split-Path $disco) -ne $carpeta) {
            $r.Enlazada = $true
            if (-not $r.Base) { $r.Base = Split-Path (Split-Path $disco) -Leaf }
            break
        }
        $padre = Leer-PadreVmdk $disco
        if ($null -eq $padre) { break }               # no se pudo leer (encendida)
        if (-not $padre) { if ($null -eq $r.Enlazada) { $r.Enlazada = $false }; break }
        $disco = $padre
    }
    return $r
}

# =====================================================================
#  vmrun con límite de tiempo (ficha 34)
# =====================================================================
#  VMware a veces se queda pensando y vmrun no vuelve. Todo lo que no sea una consola que David está mirando
#  llama a vmrun por aquí: se espera N segundos y, si no acaba, se mata SOLO ese vmrun (nunca nada de VMware).
#  Un tiempo agotado no es un «no»: quien llama debe mirar .Agotado antes que .Codigo.
#  El registro (estado\vmrun.log) apunta solo la operación, el código y los segundos: NUNCA los argumentos
#  (pueden llevar la contraseña de las máquinas con -gp).
$script:LimitesVmrun = @{
    'list' = 15; 'checkToolsState' = 15; 'readVariable' = 15; 'getGuestIPAddress' = 15
    'directoryExistsInGuest' = 15; 'fileExistsInGuest' = 15
    'listSnapshots' = 30; 'listDirectoryInGuest' = 30; 'listProcessesInGuest' = 30
    'stop soft' = 120; 'stop hard' = 60; 'stop' = 120
    'start' = 300; 'deleteVM' = 300
    'snapshot' = 600; 'revertToSnapshot' = 600; 'deleteSnapshot' = 600    # borrar una instantánea grande junta discos: tarda
    'copyFileFromHostToGuest' = 120; 'copyFileFromGuestToHost' = 120
    'otra' = 120
}
function Citar-Argumento([string]$texto) {
    # Un argumento tal como lo espera un programa de Windows: entre comillas si lleva espacios o comillas, con las
    # comillas de dentro escapadas y las barras finales dobladas (si no, «C:\carpeta\» se comería la comilla de cierre)
    if ($texto -ne '' -and $texto -notmatch '[\s"]') { return $texto }
    $barra = [string][char]92; $comilla = [string][char]34
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($comilla)
    $barras = 0
    foreach ($letra in $texto.ToCharArray()) {
        if ([int]$letra -eq 92) { $barras++; continue }
        if ([int]$letra -eq 34) { [void]$sb.Append($barra * ($barras * 2 + 1)); [void]$sb.Append($comilla) }
        else { [void]$sb.Append($barra * $barras); [void]$sb.Append($letra) }
        $barras = 0
    }
    [void]$sb.Append($barra * ($barras * 2)); [void]$sb.Append($comilla)
    return $sb.ToString()
}
function Operacion-Vmrun($argumentos) {
    # Nombre de la operación (para el límite y el registro). Solo nombres conocidos: cualquier otra cosa es «otra»,
    # así nunca se apunta un argumento por error
    $lista = @($argumentos | ForEach-Object { [string]$_ })
    $conValor = @('-T', '-h', '-P', '-u', '-p', '-vp', '-gu', '-gp')
    $i = 0
    while ($i -lt $lista.Count) {
        $actual = $lista[$i]
        if ($conValor -ccontains $actual) { $i += 2; continue }
        if ($script:LimitesVmrun.ContainsKey($actual)) {
            if ($actual -ceq 'stop') {
                $modo = [string]$lista[$lista.Count - 1]
                if ($modo -ceq 'soft' -or $modo -ceq 'hard') { return "stop $modo" }
            }
            return $actual
        }
        return 'otra'
    }
    return 'otra'
}
function Limite-Vmrun([string]$operacion) {
    if ($script:LimitesVmrun.ContainsKey($operacion)) { return [int]$script:LimitesVmrun[$operacion] }
    return [int]$script:LimitesVmrun['otra']
}
function Limite-CopiaVmrun([double]$bytes) {
    # Copiar archivos: 2 min + 1 s por cada 10 MB, 30 min como mucho
    return [int][Math]::Min(1800.0, 120.0 + [Math]::Ceiling([Math]::Max([double]0, $bytes) / 10MB))
}
function Apuntar-Vmrun([string]$operacion, [string]$resultado, [double]$segundos) {
    try {
        $dirReg = Join-Path $dirComun 'estado'
        if (-not (Test-Path -LiteralPath $dirReg)) { New-Item -ItemType Directory -Path $dirReg -Force | Out-Null }
        $archReg = Join-Path $dirReg 'vmrun.log'
        try { if ((Test-Path -LiteralPath $archReg) -and ([double](Get-Item -LiteralPath $archReg).Length -gt 512KB)) { Remove-Item -LiteralPath $archReg -Force } } catch {}
        Add-Content -LiteralPath $archReg -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}: {2} ({3:0.0} s)" -f (Get-Date), $operacion, $resultado, $segundos) -Encoding UTF8
    } catch {}
}
function Matar-ProcesoPropio([int]$idProceso) {
    # Mata el proceso que lanzamos y sus hijos, PERO nunca nada de VMware: si vmrun hubiera arrancado la ventana
    # de VMware o una máquina (vmware.exe, vmware-vmx.exe...), eso se deja vivo. Por eso no se usa «taskkill /T» a ciegas.
    $victimas = New-Object System.Collections.ArrayList
    try {
        $todos = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction Stop)
        $cola = New-Object System.Collections.Queue
        $cola.Enqueue($idProceso)
        $vistosProc = @{}
        while ($cola.Count) {
            $padre = [int]$cola.Dequeue()
            if ($vistosProc[$padre]) { continue }
            $vistosProc[$padre] = $true
            foreach ($hijo in @($todos | Where-Object { [int]$_.ParentProcessId -eq $padre })) {
                if ([string]$hijo.Name -match '^(vmware|vmplayer|vmnat|vmnet|mkssandbox)') { continue }   # nada de VMware, ni lo que cuelgue de ello
                [void]$victimas.Add([int]$hijo.ProcessId)
                $cola.Enqueue([int]$hijo.ProcessId)
            }
        }
    } catch {}
    foreach ($idVictima in @($idProceso) + @($victimas)) {
        try { $procVictima = [System.Diagnostics.Process]::GetProcessById($idVictima); $procVictima.Kill(); $procVictima.Dispose() } catch {}
    }
}
function Vmrun-ConLimite([string]$vmrun, $argumentos, [int]$segundos = 0, [scriptblock]$Mientras = $null) {
    # Ejecuta vmrun (o cualquier programa de consola) sin ventana y con límite de tiempo.
    # Devuelve: Codigo (-1 si no terminó o no arrancó), Salida, Error, Lineas (la salida por líneas), Agotado,
    # Operacion, Limite y Segundos. $Mientras se llama cada poco durante la espera (la ventana lo usa para seguir pintándose).
    $operacion = Operacion-Vmrun $argumentos
    if ($segundos -le 0) { $segundos = Limite-Vmrun $operacion }
    $res = [pscustomobject]@{ Codigo = -1; Salida = ''; Error = ''; Lineas = @(); Agotado = $false; Operacion = $operacion; Limite = $segundos; Segundos = [double]0 }
    if (-not $vmrun) { $res.Error = 'No encuentro VMware Workstation (vmrun).'; return $res }
    $proc = $null
    $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $vmrun
        $psi.Arguments = (@($argumentos | ForEach-Object { Citar-Argumento ([string]$_) }) -join ' ')
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $tareaSal = $proc.StandardOutput.ReadToEndAsync()
        $tareaErr = $proc.StandardError.ReadToEndAsync()
        $limiteMs = [double]$segundos * 1000
        while (-not $proc.WaitForExit(50)) {
            if ($cronometro.Elapsed.TotalMilliseconds -ge $limiteMs) { $res.Agotado = $true; break }
            if ($Mientras) { try { & $Mientras } catch {} }
        }
        if ($res.Agotado) {
            Matar-ProcesoPropio $proc.Id
            try { [void]$proc.WaitForExit(5000) } catch {}
        } else {
            $res.Codigo = [int]$proc.ExitCode
        }
        try { if ($tareaSal.Wait(3000)) { $res.Salida = [string]$tareaSal.Result } } catch {}
        try { if ($tareaErr.Wait(3000)) { $res.Error = [string]$tareaErr.Result } } catch {}
        $res.Lineas = @($res.Salida -split "`r?`n")
    } catch {
        $res.Error = [string]$_.Exception.Message
    } finally {
        if ($proc) { try { $proc.Dispose() } catch {} }
    }
    $cronometro.Stop()
    $res.Segundos = [Math]::Round($cronometro.Elapsed.TotalSeconds, 1)
    # Al registro, solo lo raro: sin respuesta, no arrancó, o tardó más de 5 s. Nunca los argumentos.
    if ($res.Agotado) { Apuntar-Vmrun $operacion "SIN RESPUESTA en $segundos s (se cerró el vmrun lanzado)" $res.Segundos }
    elseif ($res.Codigo -eq -1) { Apuntar-Vmrun $operacion 'no se pudo ejecutar' $res.Segundos }
    elseif ($res.Segundos -ge 5) { Apuntar-Vmrun $operacion "código $($res.Codigo)" $res.Segundos }
    return $res
}
function Texto-VmrunAgotado($resultado, [switch]$Larga) {
    # El aviso en llano de «VMware no ha contestado». Sin argumentos de vmrun (podrían llevar la contraseña).
    $texto = "VMware no ha contestado en $([int]$resultado.Limite) segundos. Puede que siga trabajando: espera un poco y vuelve a mirar. Si se repite, cierra VMware y ábrelo de nuevo."
    if ($Larga) { $texto += ' La operación puede haber terminado igualmente.' }
    return $texto
}

function Leer-Encendidas($vmrun) {
    # Qué máquinas están encendidas, DICIENDO SI SE SABE. Regla de oro: «VMware no contesta» nunca significa «apagada».
    # Devuelve @{ Sabido; Lista }: con Sabido = $false no se sabe nada y quien vaya a borrar, apagar o guardar algo
    # debe saltarse esa vuelta. (No se devuelve $null porque en PowerShell una lista vacía también llega como $null.)
    if (-not $vmrun) { return [pscustomobject]@{ Sabido = $true; Lista = @() } }    # sin VMware no hay nada encendido
    $r = Vmrun-ConLimite $vmrun @('-T', 'ws', 'list')
    if ($r.Agotado -or $r.Codigo -ne 0) { return [pscustomobject]@{ Sabido = $false; Lista = @() } }
    $lista = @($r.Lineas | Select-Object -Skip 1 | ForEach-Object { ([string]$_).Trim().ToLower() } | Where-Object { $_ })
    $script:ultimasEncendidas = $lista
    return [pscustomobject]@{ Sabido = $true; Lista = $lista }
}
function Maquinas-Encendidas($vmrun) {
    # Solo para ENSEÑAR el estado (listas, tarjetas). Si VMware no contesta, devuelve lo último que se supo
    # (no «todas apagadas»). Para decidir si se borra o se apaga algo, usar Leer-Encendidas y mirar .Sabido.
    $e = Leer-Encendidas $vmrun
    if ($e.Sabido) { return @($e.Lista) }
    if ($script:ultimasEncendidas) { return @($script:ultimasEncendidas) }
    return @()
}

function Nombres-LabGuardados {
    # labid -> nombre del laboratorio, según lo que apuntó el vigilante en estado\progreso.json.
    # Sirve para recuperar el nombre de laboratorios cuyas máquinas perdieron la marca «lab» (las conservadas
    # con versiones anteriores a 11/11/2026 se la quitaban y desaparecían de «Mis laboratorios»)
    $r = @{}
    try {
        $j = [IO.File]::ReadAllText((Join-Path $dirComun 'estado\progreso.json')) | ConvertFrom-Json
        foreach ($p in $j.maquinas.PSObject.Properties) {
            if ($p.Value.labid -and $p.Value.lab) { $r[[string]$p.Value.labid] = [string]$p.Value.lab }
        }
    } catch {}
    return $r
}

function Leer-Maquinas([switch]$ConTamano) {
    # Máquinas de la carpeta de VMs con su estado, base y tamaño
    $vmrun = Buscar-Vmrun -Silencioso
    $encendidas = Maquinas-Encendidas $vmrun
    $bases = @(Obtener-Bases | ForEach-Object Nombre)
    $segs = Leer-Segmentos
    $nombresLab = $null
    foreach ($ctl in @(Leer-Clones)) {
        $marcaLab = [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.lab')
        if (-not $marcaLab) {
            # Sin marca de laboratorio pero con identificador: era de un laboratorio y la perdió al conservarla
            $idLabMaq = [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.labid')
            if ($idLabMaq) {
                if ($null -eq $nombresLab) { $nombresLab = Nombres-LabGuardados }
                $marcaLab = $(if ($nombresLab[$idLabMaq]) { [string]$nombresLab[$idLabMaq] } else { 'Laboratorio ' + $idLabMaq.Substring(0, [Math]::Min(6, $idLabMaq.Length)) })
            }
        }
        $tarjetas = @(Leer-Tarjetas $ctl.Vmx)
        $b = Base-DeMaquina $ctl.Vmx
        $enc = $encendidas -contains $ctl.Vmx.ToLower()
        $susp = (-not $enc) -and [bool](Get-ChildItem -LiteralPath $ctl.Carpeta -Filter *.vmss -ErrorAction SilentlyContinue)
        $estadoVm = if ($enc) { 'Encendida' } elseif ($susp) { 'Suspendida' } else { 'Apagada' }
        # Clon hecho con Full Cowl: lleva sus marcas en el .vmx (las versiones antiguas solo «agente»,
        # sin «base» ni «copia»: entonces enlazada o completa se mira por sus discos). Las demás, sin marcar.
        $copiaFc = [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.copia')
        $baseFc = [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.base')
        $importada = [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.importada')
        $esFc = [bool]($copiaFc -or $baseFc -or $importada -or (Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.agente'))
        $enlazada = $(if ($copiaFc) { $copiaFc -eq 'linked' } else { $b.Enlazada })
        # «Sin base» solo para clones enlazados de Full Cowl cuya base ya no existe (un clon enlazado
        # hecho a mano en VMware depende de otra máquina normal, no de una base)
        if ($esFc -and $enlazada -and ($b.Rota -or ($baseFc -and $bases -notcontains $baseFc))) { $estadoVm = 'Sin base' }
        $desech = $(if ((Leer-Conservar) -contains $ctl.Vmx) { '' } else { [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.desechable') })
        $etqNota = Leer-EtiquetasNota $ctl.Vmx
        $tipoTxt = if (-not $esFc) { '' } elseif ($desech) { 'Desechable' } elseif ($importada) { 'Importada' } elseif ($enlazada) { 'Clon enlazado' } elseif ($null -eq $enlazada) { 'Clon' } else { 'Clon completo' }
        [pscustomobject]@{
            Nombre     = $ctl.Nombre
            Carpeta    = $ctl.Carpeta
            Vmx        = $ctl.Vmx
            IP         = $ctl.IP
            Dominio    = $ctl.Dominio
            Netbios    = $ctl.Netbios
            Base       = $(if ($ctl.Externa -and -not $b.Base) { '(biblioteca)' } else { $b.Base })
            Familia    = $(if ($b.Base -and -not $ctl.Externa) { Familia-Sistema $b.Base } else { Familia-GuestOS $ctl.Vmx })
            Externa    = [bool]$ctl.Externa
            Desechable = $desech
            Lab        = $marcaLab
            EsWindows  = (Leer-ValorVmx $ctl.Vmx 'guestOS') -like 'windows*'
            Manual     = ((Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.manual') -eq 'TRUE')
            Copia      = $(if ($null -eq $b.Enlazada) { '?' } elseif ($b.Enlazada) { 'Enlazada' } else { 'Completa' })
            Tarjetas   = $tarjetas
            Red        = (@($tarjetas | ForEach-Object { Texto-Tarjeta $_ $segs }) -join ' + ')
            Estado     = $estadoVm
            Encendida  = $enc
            Tamano     = $(if ($ConTamano) { Tamano-Maquina $ctl.Vmx $ctl.Carpeta } else { 0 })
            Modificada = (Get-Item -LiteralPath $ctl.Carpeta).LastWriteTime
            Tipo       = $tipoTxt
            EsBase     = $false
            Etiquetas  = @($etqNota.Etiquetas)
            Nota       = [string]$etqNota.Nota
            Web        = ([string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.web') -eq '1')   # tiene Apache, Nginx o IIS: «Abrir en el navegador» (ficha 19)
            Extras     = [string](Leer-ValorVmx $ctl.Vmx 'guestinfo.vmtareas.extras')          # extras pedidos al crearla (ficha 20), separados por comas
        }
    }
    # Las bases también salen en la lista (marcadas como «Base»), pero protegidas: no se arrancan
    # ni se tocan desde aquí, porque sus clones enlazados dependen de ellas
    foreach ($bs in @(Obtener-Bases)) {
        $carpetaB = Split-Path $bs.Vmx
        $encB = $encendidas -contains $bs.Vmx.ToLower()
        $tarjetasB = @(Leer-Tarjetas $bs.Vmx)
        $etqNotaB = Leer-EtiquetasNota $bs.Vmx
        [pscustomobject]@{
            Nombre = $bs.Nombre; Carpeta = $carpetaB; Vmx = $bs.Vmx; IP = ''; Dominio = ''; Netbios = ''
            Base = ''; Familia = $bs.Familia; Externa = $false; Desechable = ''; Lab = ''; EsWindows = $bs.EsWindows
            Copia = 'Completa'; Tarjetas = $tarjetasB; Red = (@($tarjetasB | ForEach-Object { Texto-Tarjeta $_ $segs }) -join ' + ')
            Estado = $(if ($encB) { 'Encendida' } else { 'Apagada' }); Encendida = $encB
            Tamano = $(if ($ConTamano) { Tamano-Carpeta $carpetaB } else { 0 })
            Modificada = (Get-Item -LiteralPath $carpetaB).LastWriteTime
            Tipo = 'Base'; EsBase = $true
            Etiquetas = @($etqNotaB.Etiquetas); Nota = [string]$etqNotaB.Nota; Web = $false; Extras = ''
        }
    }
}

# =====================================================================
#  Máquinas desechables (se borran solas al apagarse)
# =====================================================================
function Iniciar-Oculto([string]$programa, [string]$argumentos, [switch]$Esperar) {
    # Arranca un programa de consola SIN ninguna ventana. Con Start-Process -WindowStyle Hidden no
    # basta: si Windows Terminal es la consola predeterminada (Windows 11), la ventana sale igual.
    $psi = New-Object System.Diagnostics.ProcessStartInfo($programa, $argumentos)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $dirComun
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($Esperar -and $proc) { $proc.WaitForExit() }
}

function Abrir-EscritorioRemoto($vmx, [string]$ip, [string]$netbios) {
    # Escritorio remoto con el usuario de la máquina ya puesto: «.\usuario» (cuenta local de la máquina,
    # sin depender de su nombre de equipo) o «DOMINIO\usuario» si está en un dominio. Se abre con un
    # .rdp que lleva el usuario (sin contraseña). La contraseña se deja un minuto en el Administrador de
    # credenciales para entrar sin escribirla; si Windows no deja usarla (Credential Guard, normal en
    # Windows 11), basta escribir la contraseña de las máquinas en la ventana que sale.
    # La IP, el usuario y el NetBIOS salen del .vmx (que puede ser de otra persona) y acaban en líneas de órdenes:
    # solo se aceptan con su forma exacta. La contraseña no se pasa a cmdkey si lleva comillas (no se puede entrecomillar bien).
    if (-not (Es-IPv4 $ip)) { return }
    $usu = [string](Usuario-DeVm $vmx)
    if (-not (Usuario-SeguroEnOrden $usu)) { $usu = '' }
    if ($netbios -cnotmatch '^[A-Za-z0-9-]{1,15}\z') { $netbios = '' }
    $usuario = if ($netbios) { "$netbios\$usu" } else { ".\$usu" }
    $pass = Obtener-Password -SinPreguntar
    if (-not $usu -or ($pass -and $pass.Contains('"'))) { $pass = $null }
    if ($pass) { Iniciar-Oculto 'cmdkey.exe' "/generic:TERMSRV/$ip /user:`"$usuario`" /pass:`"$pass`"" -Esperar }
    $dirRdp = Join-Path ([IO.Path]::GetTempPath()) 'FullCowl'
    if (-not (Test-Path $dirRdp)) { [void](New-Item -ItemType Directory -Path $dirRdp) }
    $rdp = Join-Path $dirRdp ("{0}.rdp" -f ($ip -replace '[^0-9.]', ''))
    $lineas = @("full address:s:$ip", "username:s:$usuario", 'prompt for credentials:i:0', 'authentication level:i:2',
                'enablecredsspsupport:i:1', 'screen mode id:i:1', 'smart sizing:i:1', 'dynamic resolution:i:1')
    [IO.File]::WriteAllLines($rdp, $lineas)
    Start-Process mstsc.exe -ArgumentList "`"$rdp`""
    # Al minuto se quitan la contraseña guardada y el .rdp (ya no hacen falta: la sesión está abierta)
    $limpiar = "Start-Sleep 60; cmdkey.exe /delete:TERMSRV/$ip | Out-Null; Remove-Item -LiteralPath '$rdp' -Force -ErrorAction SilentlyContinue"
    Iniciar-Oculto 'powershell.exe' "-NoProfile -Command `"$limpiar`""
}

function Iniciar-Vigilante {
    # Proceso oculto que borra las desechables al apagarse; si ya está en marcha, el nuevo se cierra solo
    $v = Join-Path $dirComun 'vigilante.ps1'
    if (Test-Path $v) { Iniciar-Oculto 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$v`"" }
}

function Archivo-Conservar { return (Join-Path $dirComun 'estado\conservar.json') }

function Leer-Conservar {
    # .vmx de desechables que se han marcado para conservar mientras estaban encendidas
    # Ojo: en PowerShell 5.1 una lista vacía ([]) se lee como UN elemento vacío; por eso se recorre a mano y se descartan los vacíos
    try {
        $texto = [IO.File]::ReadAllText((Archivo-Conservar))
        if (-not $texto.Trim()) { return @() }
        $r = @()
        foreach ($grupo in @(ConvertFrom-Json $texto)) { foreach ($v in @($grupo)) { if ($v) { $r += [string]$v } } }
        return @($r)
    } catch { return @() }
}

function Guardar-Conservar($lista) {
    New-Item -ItemType Directory -Force -Path (Split-Path (Archivo-Conservar)) | Out-Null
    $unicos = @($lista | Where-Object { $_ } | Select-Object -Unique)
    $texto = if ($unicos.Count) { ConvertTo-Json $unicos } else { '[]' }
    [IO.File]::WriteAllText((Archivo-Conservar), $texto, [Text.UTF8Encoding]::new($false))
}

function Conservar-Maquina($vmx, [bool]$encendida) {
    # Deja de ser desechable. Apagada: se quita la marca del .vmx. Encendida: lo hará el vigilante al apagarse.
    # Solo se quita «desechable»: la marca del laboratorio (lab) se queda, así la máquina sigue en «Mis laboratorios»
    if ($encendida) { Guardar-Conservar (@(Leer-Conservar) + $vmx) }
    else {
        Guardar-Vmx $vmx @(Leer-Vmx $vmx | Where-Object { $_ -notmatch '^\s*guestinfo\.vmtareas\.desechable\s*=' })
    }
}

function Buscar-Restos {
    # Archivos que se pueden borrar sin perder nada: registros viejos, cachés de VMware
    # de máquinas apagadas, temporales de los scripts. Devuelve lista de FileInfo.
    $vmrun = Buscar-Vmrun -Silencioso
    $estadoEnc = Leer-Encendidas $vmrun
    $encendidas = @($estadoEnc.Lista)
    $r = @()
    $carpetas = @(Leer-Clones | ForEach-Object Carpeta)
    if ($Config.CarpetaBases -and (Test-Path -LiteralPath $Config.CarpetaBases)) { $carpetas += @(Get-ChildItem $Config.CarpetaBases -Directory | ForEach-Object FullName) }
    if (-not $estadoEnc.Sabido) { $carpetas = @() }    # VMware no contesta: no se sabe cuáles están apagadas, no se toca ninguna
    foreach ($d in $carpetas) {
        $vmx = Get-ChildItem -LiteralPath $d -Filter *.vmx -ErrorAction SilentlyContinue | Select-Object -First 1
        $abierta = ($vmx -and ($encendidas -contains $vmx.FullName.ToLower())) -or
                   [bool](Get-ChildItem -LiteralPath $d -Filter *.lck -ErrorAction SilentlyContinue)
        if ($abierta) { continue }
        $r += @(Get-ChildItem -LiteralPath $d -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^vmware-\d+\.log$|\.dmp$|^vmware-vmx.*\.log$|^mksSandbox.*\.log$' })
        $cache = Join-Path $d 'caches'
        if (Test-Path -LiteralPath $cache) { $r += @(Get-ChildItem -LiteralPath $cache -Recurse -File -Force -ErrorAction SilentlyContinue) }
    }
    $s = $dirComun
    if (Test-Path (Join-Path $s 'build')) {
        $enCurso = @(Get-ChildItem (Join-Path $s 'estado') -Filter *.json -ErrorAction SilentlyContinue | Where-Object {
            try { (([IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json).estado -eq 'curso') } catch { $false } })
        if (-not $enCurso.Count) { $r += @(Get-ChildItem (Join-Path $s 'build') -Recurse -File -Force -ErrorAction SilentlyContinue) }
    }
    # Registros y progresos viejos (no los del vigilante de desechables, que se necesitan)
    $r += @(Get-ChildItem (Join-Path $s 'estado') -File -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-2) -and @('desechables.json', 'conservar.json', 'tiempos.csv') -notcontains $_.Name })
    $r += @(Get-ChildItem $env:TEMP -Filter 'vmtareas-*' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) })
    return @($r)
}

# =====================================================================
#  Redes: tarjetas de las VMs, segmentos LAN y redes VMnet
# =====================================================================
function Archivo-PrefsVmware { return (Join-Path $env:APPDATA 'VMware\preferences.ini') }
function Archivo-SegmentosPropios { return (Join-Path $dirComun 'segmentos.json') }

function Leer-Segmentos {
    # Segmentos LAN: pvnID -> nombre (los de VMware y los creados con Full Cowl)
    $r = [ordered]@{}
    $f = Archivo-PrefsVmware
    if (Test-Path $f) {
        $nombres = @{}; $ids = @{}
        foreach ($x in [IO.File]::ReadAllLines($f)) {
            if ($x -match '^\s*pref\.namedPVNs(\d+)\.name\s*=\s*"(.*)"') { $nombres[$Matches[1]] = $Matches[2] }
            elseif ($x -match '^\s*pref\.namedPVNs(\d+)\.pvnID\s*=\s*"(.*)"') { $ids[$Matches[1]] = $Matches[2] }
        }
        foreach ($k in $ids.Keys) { if ($nombres[$k]) { $r[$ids[$k]] = $nombres[$k] } }
    }
    $propio = Archivo-SegmentosPropios
    if (Test-Path $propio) {
        try {
            foreach ($prop in ([IO.File]::ReadAllText($propio) | ConvertFrom-Json).PSObject.Properties) {
                if (-not $r.Contains($prop.Name)) { $r[$prop.Name] = [string]$prop.Value }
            }
        } catch {}
    }
    return $r
}

function Nuevo-Segmento([string]$nombre) {
    # Crea un segmento LAN: lo recuerda Full Cowl y se añade a la lista de VMware
    $motivo = Validar-NombreSegmento $nombre
    if ($motivo) { throw $motivo }
    $bytes = New-Object byte[] 16
    (New-Object Random).NextBytes($bytes)
    $bytes[0] = 0x52
    $h = @($bytes | ForEach-Object { $_.ToString('x2') })
    $id = ($h[0..7] -join ' ') + '-' + ($h[8..15] -join ' ')
    # Full Cowl
    $propio = Archivo-SegmentosPropios
    $datos = [ordered]@{}
    if (Test-Path $propio) { try { foreach ($prop in ([IO.File]::ReadAllText($propio) | ConvertFrom-Json).PSObject.Properties) { $datos[$prop.Name] = $prop.Value } } catch {} }
    $datos[$id] = $nombre
    [IO.File]::WriteAllText($propio, ($datos | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    # VMware (preferences.ini): para que el segmento salga con su nombre en Workstation
    try {
        $f = Archivo-PrefsVmware
        $lineas = if (Test-Path $f) { @([IO.File]::ReadAllLines($f)) } else { @('.encoding = "UTF-8"') }
        $n = 0
        foreach ($x in $lineas) { if ($x -match '^\s*pref\.namedPVNs\.count\s*=\s*"(\d+)"') { $n = [int]$Matches[1] } }
        $lineas = @($lineas | Where-Object { $_ -notmatch '^\s*pref\.namedPVNs\.count\s*=' })
        $lineas += "pref.namedPVNs.count = `"$($n + 1)`""
        $lineas += "pref.namedPVNs$n.name = `"$nombre`""
        $lineas += "pref.namedPVNs$n.pvnID = `"$id`""
        New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
        [IO.File]::WriteAllLines($f, [string[]]$lineas, [Text.UTF8Encoding]::new($false))
    } catch {}
    return $id
}

function Leer-VMnets {
    # Redes virtuales de VMware (Editor de red virtual): número, tipo y subred
    $r = @()
    foreach ($base in 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMnetLib\VMnetConfig', 'HKLM:\SOFTWARE\VMware, Inc.\VMnetLib\VMnetConfig') {
        if (-not (Test-Path $base)) { continue }
        foreach ($k in @(Get-ChildItem $base -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -notmatch '^vmnet(\d+)$') { continue }
            $num = [int]$Matches[1]
            $v = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            $r += [pscustomobject]@{
                Numero = $num; Nombre = "VMnet$num"
                Nat = [bool]($v.UseNAT -eq 1); Dhcp = [bool]($v.UseDHCP -eq 1)
                Subred = [string]$v.IPSubnetAddress
            }
        }
        if ($r.Count) { break }
    }
    if (-not @($r | Where-Object Numero -eq 8).Count) { $r += [pscustomobject]@{ Numero = 8; Nombre = 'VMnet8'; Nat = $true; Dhcp = $true; Subred = '' } }
    if (-not @($r | Where-Object Numero -eq 1).Count) { $r += [pscustomobject]@{ Numero = 1; Nombre = 'VMnet1'; Nat = $false; Dhcp = $true; Subred = '' } }
    return @($r | Sort-Object Numero)
}

function Opciones-Red {
    # Lo que se puede elegir para una tarjeta: @{ Clave; Texto; Tipo; Vnet; Pvn }
    $o = @(
        [pscustomobject]@{ Clave = 'nat';      Texto = 'NAT (con Internet)';      Tipo = 'nat';      Vnet = ''; Pvn = '' }
        [pscustomobject]@{ Clave = 'bridged';  Texto = 'Puente (red de tu casa)'; Tipo = 'bridged';  Vnet = ''; Pvn = '' }
        [pscustomobject]@{ Clave = 'hostonly'; Texto = 'Solo anfitrión (VMnet1)'; Tipo = 'hostonly'; Vnet = ''; Pvn = '' }
    )
    foreach ($n in @(Leer-VMnets | Where-Object { $_.Numero -notin 0, 1, 8 })) {
        $t = if ($n.Nat) { 'NAT' } else { 'solo anfitrión' }
        $o += [pscustomobject]@{ Clave = "vmnet$($n.Numero)"; Texto = "$($n.Nombre) ($t$(if ($n.Subred) { ", $($n.Subred)" }))"; Tipo = 'custom'; Vnet = $n.Nombre; Pvn = '' }
    }
    $segs = Leer-Segmentos
    foreach ($id in $segs.Keys) {
        $o += [pscustomobject]@{ Clave = "pvn:$id"; Texto = "Segmento LAN: $($segs[$id])"; Tipo = 'pvn'; Vnet = ''; Pvn = $id }
    }
    return $o
}

function Leer-Tarjetas($vmx) {
    # Tarjetas de red presentes en el .vmx, en orden
    $v = @{}
    foreach ($l in (Leer-Vmx $vmx)) {
        if ($l -match '^\s*ethernet(\d+)\.(\w+)\s*=\s*"(.*)"') { $v["$($Matches[1]).$($Matches[2].ToLower())"] = $Matches[3] }
    }
    $r = @()
    for ($i = 0; $i -lt 10; $i++) {
        if ($v["$i.present"] -ne 'TRUE') { continue }
        $tipo = if ($v["$i.connectiontype"]) { $v["$i.connectiontype"].ToLower() } else { 'bridged' }
        $estatica = ($v["$i.addresstype"] -eq 'static')
        $r += [pscustomobject]@{
            Indice = $i; Tipo = $tipo; Vnet = [string]$v["$i.vnet"]; Pvn = [string]$v["$i.pvnid"]
            Modelo = [string]$v["$i.virtualdev"]
            Mac = $(if ($estatica) { [string]$v["$i.address"] } else { [string]$v["$i.generatedaddress"] })
            MacFija = $estatica
        }
    }
    return $r
}

function Texto-Tarjeta($t, $segs) {
    switch ($t.Tipo) {
        'nat'      { return 'NAT' }
        'bridged'  { return 'Puente' }
        'hostonly' { return 'Solo anfitrión' }
        'custom'   { return $(if ($t.Vnet) { $t.Vnet } else { 'Personalizada' }) }
        'pvn'      { return $(if ($segs -and $segs.Contains($t.Pvn)) { $segs[$t.Pvn] } else { 'Segmento LAN' }) }
        default    { return $t.Tipo }
    }
}

function Clave-Tarjeta($t) {
    switch ($t.Tipo) {
        'custom' { return $t.Vnet.ToLower() }
        'pvn'    { return "pvn:$($t.Pvn)" }
        default  { return $t.Tipo }
    }
}

function Nueva-Mac {
    # Rango que VMware reserva para MAC fijas: 00:50:56:00:00:00 - 00:50:56:3F:FF:FF
    $b = New-Object byte[] 3
    (New-Object Random).NextBytes($b)
    $b[0] = $b[0] -band 0x3F
    return ('00:50:56:{0:x2}:{1:x2}:{2:x2}' -f $b[0], $b[1], $b[2])
}

function Guardar-Tarjetas($vmx, $tarjetas) {
    # $tarjetas: lista de @{ Tipo; Vnet; Pvn; Modelo; Mac; MacFija } en orden (ethernet0, 1, ...).
    # Se conservan del .vmx las demás claves de cada tarjeta (ranura PCI, MAC generada...).
    $n = @($tarjetas).Count
    $propias = 'present|virtualdev|connectiontype|vnet|pvnid|startconnected|displayname'
    $lineas = @(Leer-Vmx $vmx | Where-Object {
        if ($_ -match '^\s*ethernet(\d+)\.(\w+)\s*=') {
            $i = [int]$Matches[1]; $k = $Matches[2].ToLower()
            if ($i -ge $n) { return $false }
            if ($k -match "^($propias)$") { return $false }
            if ($tarjetas[$i].MacFija -and $k -match '^(addresstype|address|generatedaddress|generatedaddressoffset)$') { return $false }
        }
        return $true
    })
    for ($i = 0; $i -lt $n; $i++) {
        $t = $tarjetas[$i]
        $lineas += "ethernet$i.present = `"TRUE`""
        $lineas += "ethernet$i.virtualDev = `"$($t.Modelo)`""
        $lineas += "ethernet$i.connectionType = `"$($t.Tipo)`""
        $lineas += "ethernet$i.startConnected = `"TRUE`""
        if ($t.Tipo -eq 'custom') { $lineas += "ethernet$i.vnet = `"$($t.Vnet)`"" }
        if ($t.Tipo -eq 'pvn') { $lineas += "ethernet$i.pvnID = `"$($t.Pvn)`"" }
        if ($t.MacFija) {
            $lineas += "ethernet$i.addressType = `"static`""
            $lineas += "ethernet$i.address = `"$($t.Mac)`""
        }
    }
    Guardar-Vmx $vmx $lineas
}

# =====================================================================
#  Trabajar dentro de una VM encendida (VMware Tools)
# =====================================================================
function Tools-Listas($vmrun, $vmx, [scriptblock]$Mientras = $null) {
    $r = Vmrun-ConLimite $vmrun @('-T', 'ws', 'checkToolsState', $vmx) 0 $Mientras
    if ($r.Agotado) { return $false }
    return ((([string]$r.Salida).Trim() -split "`r?`n" | Select-Object -Last 1) -eq 'running')
}

function Esperar-Tools($vmrun, $vmx, [int]$segundos = 600) {
    for ($i = 0; $i -lt [Math]::Ceiling($segundos / 5); $i++) {
        if (Tools-Listas $vmrun $vmx) { return $true }
        Start-Sleep 5
    }
    return $false
}

function Entrar-Invitado($vmrun, $vmx, [bool]$esLinux, $netbios, $pass, [int]$intentos = 1) {
    # Devuelve el usuario con el que se puede entrar (david o DOMINIO\david), o $null.
    # Primero el de la base de la máquina; luego el de Ajustes, por si no coinciden.
    $usuarios = @(@((Usuario-DeVm $vmx), [string]$Config.Usuario) | Where-Object { $_ } | Select-Object -Unique)
    $candidatos = @($usuarios)
    if ($netbios) { $candidatos += @($usuarios | ForEach-Object { "$netbios\$_" }) }
    $prueba = if ($esLinux) { '/etc/passwd' } else { 'C:\Windows\explorer.exe' }
    for ($k = 0; $k -lt $intentos; $k++) {
        foreach ($cand in $candidatos) {
            # con límite de tiempo (ficha 34); la contraseña va en los argumentos y Vmrun-ConLimite nunca los apunta
            $rEntrar = Vmrun-ConLimite $vmrun @('-T', 'ws', '-gu', $cand, '-gp', $pass, 'fileExistsInGuest', $vmx, $prueba)
            if ($rEntrar.Agotado) { return $null }      # VMware no contesta: no tiene sentido probar los demás usuarios
            if ($rEntrar.Codigo -eq 0) { return $cand }
        }
        if ($k -lt $intentos - 1) { Start-Sleep 10 }
    }
    return $null
}

function Usuario-ConSesion($vmrun, $vmx, $usu, $pass) {
    # Windows: quién tiene el escritorio abierto en la máquina (dueño de explorer.exe), o $null. Puede no ser el
    # usuario con el que entra vmrun; y los archivos hay que dejarlos en el escritorio de quien lo está viendo.
    try {
        foreach ($l in @((Vmrun-ConLimite $vmrun @('-T', 'ws', '-gu', $usu, '-gp', $pass, 'listProcessesInGuest', $vmx)).Lineas)) {
            if ("$l" -match 'owner=([^,]+),\s*cmd=.*explorer\.exe') { return (($Matches[1].Trim()) -split '\\')[-1] }
        }
    } catch {}
    return $null
}

function Lista-ExtrasWindows([bool]$esServidor) {
    # Clave -> la aplica clon\config-windows.ps1 en el primer arranque
    $l = @(
        @{ Clave = 'ping';      Texto = 'Permitir ping (ICMP)' }
        @{ Clave = 'rdp';       Texto = 'Escritorio remoto (RDP)' }
        @{ Clave = 'sshserver'; Texto = 'Servidor OpenSSH (*)' }
        @{ Clave = 'iis';       Texto = 'IIS (servidor web)' }
        @{ Clave = 'ftp';       Texto = 'Servidor FTP (IIS)' }
        @{ Clave = 'telnet';    Texto = 'Cliente Telnet' }
        @{ Clave = 'netfx3';    Texto = '.NET Framework 3.5 (*)' }
        @{ Clave = 'hyperv';    Texto = 'Hyper-V (anidada)' }
    )
    if ($esServidor) {
        $l += @(
            @{ Clave = 'adds';       Texto = 'Rol AD DS (sin crear dominio)' }
            @{ Clave = 'dns';        Texto = 'Servidor DNS' }
            @{ Clave = 'dhcp';       Texto = 'Servidor DHCP (sin configurar)' }
            @{ Clave = 'fileserver'; Texto = 'Servidor de archivos + FSRM' }
            @{ Clave = 'print';      Texto = 'Servidor de impresión' }
            @{ Clave = 'adcs';       Texto = 'Servicios de certificados (AD CS, sin configurar)' }
            @{ Clave = 'backup';     Texto = 'Copias de seguridad de Windows Server' }
            @{ Clave = 'wds';        Texto = 'WDS (servicios de implementación)' }
        )
    } else {
        $l += @(
            @{ Clave = 'sandbox'; Texto = 'Windows Sandbox (anidada)' }
            @{ Clave = 'wsl';     Texto = 'WSL - Linux en Windows (anidada)' }
            @{ Clave = 'rsat';    Texto = 'RSAT: administrar AD, DNS, DHCP (*)' }
        )
    }
    return $l
}

function Lista-SoftwareUbuntu {
    @(
        @{ Clave = 'actualizar';   Texto = 'Actualizar el sistema (apt upgrade)' }
        @{ Clave = 'herramientas'; Texto = 'Herramientas: net-tools, curl, vim...' }
        @{ Clave = 'apache';       Texto = 'Apache' }
        @{ Clave = 'php';          Texto = 'PHP para Apache' }
        @{ Clave = 'mariadb';      Texto = 'MariaDB (MySQL)' }
        @{ Clave = 'postgresql';   Texto = 'PostgreSQL' }
        @{ Clave = 'nginx';        Texto = 'Nginx (choca con Apache: 80)' }
        @{ Clave = 'proftpd';      Texto = 'ProFTPD' }
        @{ Clave = 'vsftpd';       Texto = 'vsftpd (choca con ProFTPD: 21)' }
        @{ Clave = 'samba';        Texto = 'Samba (compartir con Windows)' }
        @{ Clave = 'bind9';        Texto = 'Bind9 (servidor DNS)' }
        @{ Clave = 'dhcp';         Texto = 'Servidor DHCP (isc-dhcp-server)' }
        @{ Clave = 'nfs';          Texto = 'Servidor NFS' }
        @{ Clave = 'squid';        Texto = 'Squid (proxy)' }
        @{ Clave = 'ldap';         Texto = 'OpenLDAP (slapd + utilidades)' }
        @{ Clave = 'cockpit';      Texto = 'Cockpit (administración web, :9090)' }
        @{ Clave = 'fail2ban';     Texto = 'Fail2ban' }
        @{ Clave = 'wireshark';    Texto = 'Wireshark / tshark' }
        @{ Clave = 'docker';       Texto = 'Docker' }
        @{ Clave = 'git';          Texto = 'Git' }
    )
}

# ---------------------------------------------------------------- Extras (ficha 20): datos para la interfaz
# El catálogo que MANDA es el del agente que corre dentro de la máquina (clon\config.sh y clon\config-windows.ps1):
# aquí solo está lo que se enseña (categoría, descripción, minutos, si necesita Internet) y en qué sistemas se ofrece.
# Añadir un extra = una línea aquí + su línea en Lista-ExtrasWindows / Lista-SoftwareUbuntu + su línea en el agente.
#   S = sistemas: apt (Ubuntu, Debian, Kali), dnf (Rocky, Alma), pacman (Arch), winsrv (Windows Server), wincli (Windows 10/11)
$InfoExtras = @{
    # --- Linux
    'lin:herramientas' = @{ Cat = 'Herramientas'; Min = 1; S = 'apt dnf pacman'; Desc = 'net-tools, curl, wget, vim, tree y git.' }
    'lin:apache'     = @{ Cat = 'Web'; Min = 1; S = 'apt dnf pacman'; Desc = 'Servidor web Apache (puerto 80).' }
    'lin:nginx'      = @{ Cat = 'Web'; Min = 1; S = 'apt dnf pacman'; Desc = 'Servidor web Nginx (puerto 80; choca con Apache).' }
    'lin:php'        = @{ Cat = 'Web'; Min = 1; S = 'apt dnf'; Desc = 'PHP para el servidor web (con Apache, como módulo).' }
    'lin:mariadb'    = @{ Cat = 'Bases de datos'; Min = 2; S = 'apt dnf pacman'; Desc = 'MariaDB (MySQL). Sin contraseña: se entra con «sudo mariadb».' }
    'lin:postgresql' = @{ Cat = 'Bases de datos'; Min = 2; S = 'apt dnf'; Desc = 'PostgreSQL. Sin contraseña: se entra con «sudo -u postgres psql».' }
    'lin:bind9'      = @{ Cat = 'Red'; Min = 1; S = 'apt dnf'; Desc = 'Servidor DNS (BIND).' }
    'lin:dhcp'       = @{ Cat = 'Red'; Min = 1; S = 'apt dnf'; Desc = 'Servidor DHCP, sin configurar (no arranca hasta que lo configures).' }
    'lin:vsftpd'     = @{ Cat = 'Red'; Min = 1; S = 'apt dnf pacman'; Desc = 'Servidor FTP vsftpd (puerto 21).' }
    'lin:proftpd'    = @{ Cat = 'Red'; Min = 1; S = 'apt'; Desc = 'Servidor FTP ProFTPD (puerto 21; choca con vsftpd).' }
    'lin:squid'      = @{ Cat = 'Red'; Min = 1; S = 'apt dnf'; Desc = 'Proxy Squid (puerto 3128).' }
    'lin:ldap'       = @{ Cat = 'Red'; Min = 1; S = 'apt'; Desc = 'OpenLDAP (slapd) y sus utilidades.' }
    'lin:samba'      = @{ Cat = 'Archivos'; Min = 1; S = 'apt dnf pacman'; Desc = 'Carpetas compartidas con Windows.' }
    'lin:nfs'        = @{ Cat = 'Archivos'; Min = 1; S = 'apt dnf'; Desc = 'Servidor NFS (carpetas compartidas entre Linux).' }
    'lin:git'        = @{ Cat = 'Herramientas'; Min = 1; S = 'apt dnf pacman'; Desc = 'Control de versiones Git.' }
    'lin:docker'     = @{ Cat = 'Herramientas'; Min = 3; S = 'apt pacman'; Desc = 'Docker (tu usuario queda en el grupo docker).' }
    'lin:fail2ban'   = @{ Cat = 'Herramientas'; Min = 1; S = 'apt pacman'; Desc = 'Bloquea las IP que fallan muchas veces la contraseña.' }
    'lin:cockpit'    = @{ Cat = 'Herramientas'; Min = 2; S = 'apt dnf pacman'; Desc = 'Administración por web en https://IP:9090.' }
    'lin:wireshark'  = @{ Cat = 'Herramientas'; Min = 2; S = 'apt'; Desc = 'Wireshark (con escritorio) o tshark (sin él).' }
    # --- Windows
    'win:ping'       = @{ Cat = 'Red'; Min = 0; S = 'winsrv wincli'; Local = $true; Desc = 'Deja que otras máquinas le hagan ping.' }
    'win:rdp'        = @{ Cat = 'Red'; Min = 0; S = 'winsrv wincli'; Local = $true; Desc = 'Activa el Escritorio remoto.' }
    'win:sshserver'  = @{ Cat = 'Red'; Min = 3; S = 'winsrv wincli'; Desc = 'Servidor OpenSSH (se descarga de Windows Update).' }
    'win:dns'        = @{ Cat = 'Red'; Min = 2; S = 'winsrv'; Local = $true; Desc = 'Rol Servidor DNS.' }
    'win:dhcp'       = @{ Cat = 'Red'; Min = 2; S = 'winsrv'; Local = $true; Desc = 'Rol Servidor DHCP, sin configurar.' }
    'win:telnet'     = @{ Cat = 'Red'; Min = 1; S = 'winsrv wincli'; Local = $true; Desc = 'Cliente Telnet.' }
    'win:iis'        = @{ Cat = 'Web'; Min = 3; S = 'winsrv wincli'; Local = $true; Desc = 'Servidor web IIS (puerto 80).' }
    'win:ftp'        = @{ Cat = 'Web'; Min = 3; S = 'winsrv wincli'; Local = $true; Desc = 'Servidor FTP de IIS.' }
    'win:fileserver' = @{ Cat = 'Archivos'; Min = 2; S = 'winsrv'; Local = $true; Desc = 'Servidor de archivos y cuotas (FSRM).' }
    'win:print'      = @{ Cat = 'Archivos'; Min = 2; S = 'winsrv'; Local = $true; Desc = 'Rol Servidor de impresión.' }
    'win:backup'     = @{ Cat = 'Archivos'; Min = 2; S = 'winsrv'; Local = $true; Desc = 'Copias de seguridad de Windows Server.' }
    'win:adds'       = @{ Cat = 'Seguridad'; Min = 3; S = 'winsrv'; Local = $true; Desc = 'Rol de Active Directory, sin crear el dominio.' }
    'win:adcs'       = @{ Cat = 'Seguridad'; Min = 3; S = 'winsrv'; Local = $true; Desc = 'Servicios de certificados (AD CS). Solo el rol: la entidad se configura a mano.' }
    'win:wds'        = @{ Cat = 'Herramientas'; Min = 2; S = 'winsrv'; Local = $true; Desc = 'Servicios de implementación (WDS).' }
    'win:netfx3'     = @{ Cat = 'Herramientas'; Min = 4; S = 'winsrv wincli'; Desc = '.NET Framework 3.5 (se descarga de Windows Update).' }
    'win:hyperv'     = @{ Cat = 'Virtualización'; Min = 4; S = 'winsrv wincli'; Local = $true; Desc = 'Hyper-V dentro de la máquina (8 GB de RAM o más).' }
    'win:sandbox'    = @{ Cat = 'Virtualización'; Min = 3; S = 'wincli'; Local = $true; Desc = 'Windows Sandbox (8 GB de RAM o más).' }
    'win:wsl'        = @{ Cat = 'Virtualización'; Min = 3; S = 'wincli'; Local = $true; Desc = 'Linux dentro de Windows (WSL).' }
    'win:rsat'       = @{ Cat = 'Herramientas'; Min = 5; S = 'wincli'; Desc = 'Herramientas para administrar AD, DNS y DHCP (de Windows Update).' }
}
$CategoriasExtras = @('Web', 'Bases de datos', 'Red', 'Archivos', 'Seguridad', 'Herramientas', 'Virtualización')

function Gestor-DeBase($base) {
    # apt, dnf, pacman, winsrv, wincli o ninguno (cortafuegos, manuales, bases sin agente)
    if (-not $base -or -not $base.ConAgente -or $base.Manual) { return 'ninguno' }
    if ($base.EsWindows) { if ($base.EsServidor) { return 'winsrv' } else { return 'wincli' } }
    $g = ''
    try { $g = [string](@(Obtener-Sistemas | Where-Object { $_.Clave -eq [string]$base.Nombre }) | Select-Object -First 1).Gestor } catch {}
    if (@('apt', 'dnf', 'pacman') -contains $g) { return $g }
    if ([string]$base.Nombre -match '^(Rocky|Alma)') { return 'dnf' }
    if ([string]$base.Nombre -match '^Arch') { return 'pacman' }
    return 'apt'
}

function Catalogo-Extras($base) {
    # Los extras que se pueden ofrecer para esa base, con sus datos para la interfaz:
    #   Id, Nombre, Cat, Desc, Min (minutos aprox.), Internet (necesita Internet para instalarse)
    $g = Gestor-DeBase $base
    if ($g -eq 'ninguno') { return @() }
    $win = ($g -like 'win*')
    $lista = $(if ($win) { @(Lista-ExtrasWindows ($g -eq 'winsrv')) } else { @(Lista-SoftwareUbuntu | Where-Object { $_.Clave -ne 'actualizar' }) })
    $r = @()
    foreach ($o in $lista) {
        $info = $InfoExtras[$(if ($win) { 'win:' } else { 'lin:' }) + [string]$o.Clave]
        if (-not $info) { continue }
        if (@(([string]$info.S) -split ' ') -notcontains $g) { continue }
        $r += [pscustomobject]@{
            Id = [string]$o.Clave; Nombre = (([string]$o.Texto) -replace '\s*\(\*\)\s*$', '' -replace '\s*\((anidada|choca[^)]*|sin configurar|sin crear dominio|MySQL)\)', '')
            Cat = [string]$info.Cat; Desc = [string]$info.Desc; Min = [int]$info.Min; Internet = (-not $info.Local)
        }
    }
    return $r
}

function Extras-Validos($base, $ids) {
    # De una lista que puede venir de fuera (pedido, plantilla, .fclab), solo los identificadores que están en el
    # catálogo de esa base. Lo demás se descarta en silencio. (El agente de la máquina lo vuelve a comprobar.)
    $cat = @(Catalogo-Extras $base | ForEach-Object { $_.Id })
    $r = @()
    foreach ($x in @($ids)) {
        $t = [string]$x
        if ($t -cmatch '^[a-z0-9]{1,24}$' -and $cat -contains $t -and $r -notcontains $t) { $r += $t }
    }
    return $r
}

function Leer-EstadoExtras([string]$texto) {
    # «apache=ok;mariadb=instalando» (lo que publica la máquina desde dentro) -> lista ordenada de @{ Id; Estado }.
    # Viene de dentro de una máquina: solo se acepta lo que tiene exactamente esa forma.
    $r = @()
    if (-not $texto -or $texto.Length -gt 1000) { return $r }
    foreach ($par in ($texto -split ';')) {
        if ($par -cmatch '^([a-z0-9]{1,24})=(espera|instalando|ok|fallo|desconocido)$') { $r += [pscustomobject]@{ Id = $Matches[1]; Estado = $Matches[2] } }
    }
    return $r
}

function Nombre-Extra([string]$id) {
    foreach ($o in @(@(Lista-SoftwareUbuntu) + @(Lista-ExtrasWindows $true) + @(Lista-ExtrasWindows $false))) {
        if ([string]$o.Clave -eq $id) { return (([string]$o.Texto) -replace '\s*\([^)]*\)\s*$', '') }
    }
    return $id
}

# Extras que necesitan virtualización anidada en la VM (VT-x/AMD-V dentro de la VM)
$ExtrasAnidados = @('hyperv', 'sandbox', 'wsl')

function Nombre-Equipo($nombre) {
    # Nombre de equipo válido (letras, números y guiones; máx. 15) a partir del nombre de la VM
    $h = ($nombre -replace '[^A-Za-z0-9-]', '-' -replace '-{2,}', '-').Trim('-')
    if ($h.Length -gt 15) { $h = $h.Substring(0, 15).Trim('-') }
    if (-not $h) { $h = 'equipo' }
    return $h
}

function Validar-NombreMaquina($nombre) {
    # Devuelve $null si es válido, o el motivo. Lista blanca: el nombre acaba en rutas, en el .vmx
    # y en la línea de órdenes de vmrun.
    if (-not $nombre) { return 'Escribe un nombre para la máquina.' }
    if ($nombre.Length -gt 60) { return 'El nombre es demasiado largo (máximo 60 caracteres).' }
    if ($nombre -notmatch '^[\p{L}\p{Nd}][\p{L}\p{Nd} ._()-]*$') { return 'Usa letras, números, espacios y . _ - ( ), empezando por letra o número.' }
    if ($nombre -match '[ .]$') { return 'El nombre no puede acabar en espacio ni en punto.' }
    if ($nombre -match '^(CON|PRN|AUX|NUL|COM\d|LPT\d)(\..*)?$') { return 'Ese nombre lo reserva Windows.' }
    if (Test-Path -LiteralPath (Join-Path $Config.CarpetaVMs $nombre)) { return "Ya existe la carpeta '$nombre'." }
    return $null
}

function Validar-NombreSegmento($nombre) {
    # Nombre de un segmento LAN (va a preferences.ini de VMware y a la configuración de red de Linux)
    if (-not $nombre) { return 'Escribe un nombre para el segmento.' }
    if ($nombre.Length -gt 40 -or $nombre -notmatch '^[\p{L}\p{Nd}][\p{L}\p{Nd} ._()-]*$') {
        return 'Nombre de segmento no válido: letras, números, espacios y . _ - ( ) (máximo 40).'
    }
    return $null
}

function Carpeta-BorrableSegura([string]$carpeta) {
    # $true si se puede borrar ENTERA la carpeta de una máquina sin llevarse nada más:
    # una subcarpeta directa de la carpeta de máquinas, o una carpeta con solo archivos de VMware.
    try { $full = [IO.Path]::GetFullPath($carpeta).TrimEnd('\') } catch { return $false }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $false }
    if ([IO.Path]::GetPathRoot($full).TrimEnd('\') -eq $full) { return $false }          # una unidad entera
    $norm = { param($r) if ($r) { try { [IO.Path]::GetFullPath([string]$r).TrimEnd('\').ToLower() } catch { $null } } }
    $protegidas = @($Config.CarpetaVMs, $Config.CarpetaBases, $Config.CarpetaISOs, $env:USERPROFILE, $env:SystemRoot,
                    $env:ProgramFiles, ${env:ProgramFiles(x86)}, $dirComun, (Split-Path $dirComun),
                    [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments')) | ForEach-Object { & $norm $_ }
    $bajo = $full.ToLower()
    if ($protegidas -contains $bajo) { return $false }
    $bases = & $norm $Config.CarpetaBases
    if ($bases -and $bajo.StartsWith($bases + '\')) { return $false }                      # las bases nunca
    if (@(Get-ChildItem -LiteralPath $full -Filter *.vmx -ErrorAction SilentlyContinue).Count -gt 1) { return $false }
    $vms = & $norm $Config.CarpetaVMs
    if ($vms -and (Split-Path $bajo) -eq $vms -and -not (Split-Path $bajo -Leaf).StartsWith('_')) { return $true }
    # Fuera de la carpeta de máquinas: solo si lo único que hay son archivos de VMware
    $ajenos = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -notmatch '^\.(vmx|vmxf|vmsd|vmdk|nvram|vmem|vmss|vmsn|log|scoreboard|lck|iso|vmtm|dmp|hlog|mem|vmpl)$' -and
        $_.DirectoryName -notmatch '\\caches(\\|$)|\.lck(\\|$)' })
    return ($ajenos.Count -eq 0)
}

function Limpiar-CdClave($c, [switch]$Forzar) {
    # Quita el CD de configuración que lleva la contraseña (máquinas con dominio) cuando la máquina
    # está apagada y ya ha funcionado un rato desde que se creó (su configuración ha terminado).
    # Con -Forzar no espera esos 30 minutos (lo usa Exportar cuando la persona confirma que ya terminó).
    $isoCd = Join-Path $c.Carpeta 'vmtareas.iso'
    if (-not (Test-Path -LiteralPath $isoCd) -or (Leer-ValorVmx $c.Vmx 'guestinfo.vmtareas.cdclave') -ne '1') { return }
    if (Get-ChildItem -LiteralPath $c.Carpeta -Filter '*.lck' -ErrorAction SilentlyContinue) { return }   # encendida o abierta
    $log = Get-Item -LiteralPath (Join-Path $c.Carpeta 'vmware.log') -ErrorAction SilentlyContinue
    if ($Forzar -or ($log -and $log.LastWriteTime -gt (Get-Item -LiteralPath $isoCd).LastWriteTime.AddMinutes(30))) {
        Fijar-ValoresVmx $c.Vmx @{ 'sata0:2.present' = 'FALSE'; 'guestinfo.vmtareas.cdclave' = '0' }
        Remove-Item -LiteralPath $isoCd -Force -ErrorAction SilentlyContinue
    }
}

function Apuntar-Invitado([string]$texto) {
    # Registro de lo que pasa al ejecutar cosas dentro de las máquinas (estado\invitado.log). Sin contraseñas.
    try {
        $dir = Join-Path $dirComun 'estado'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        Add-Content -LiteralPath (Join-Path $dir 'invitado.log') -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}" -f (Get-Date), $texto) -Encoding UTF8
    } catch {}
}

function Ejecutar-EnInvitado($vmrun, $vmx, $usu, $pass, [string]$programa, [string]$argumentos, [string]$logInvitado, [string]$logLocal, [int]$intentos = 6) {
    # Ejecuta un programa dentro de la máquina y se trae su registro. Si el programa ni siquiera llega
    # a arrancar (la máquina acaba de encenderse), lo reintenta cada 15 s. Devuelve '' si fue bien o
    # el motivo del fallo: lo que dijo vmrun y lo que escribió el programa en pantalla.
    $nombreVm = [IO.Path]::GetFileNameWithoutExtension($vmx)
    $esWin = $programa -match '^[A-Za-z]:\\'
    # En Windows se lanza a través de cmd para guardar lo que salga en pantalla (errores incluidos)
    # en C:\Users\Public, donde cualquier usuario puede escribir
    $pantallaVm = $null; $prog = $programa; $args2 = $argumentos
    if ($esWin) {
        $pantallaVm = 'C:\Users\Public\vmt-salida-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt'
        $prog = 'C:\Windows\System32\cmd.exe'
        $args2 = "/c $programa $argumentos > $pantallaVm 2>&1"
    }
    $pantallaLocal = "$logLocal.pantalla.txt"
    $motivo = ''
    try {
        for ($k = 1; $k -le $intentos; $k++) {
            $salida = (& $vmrun -T ws -gu $usu -gp $pass runProgramInGuest $vmx $prog $args2 2>&1 | Out-String).Trim()
            $codigo = $LASTEXITCODE
            $copia = (& $vmrun -T ws -gu $usu -gp $pass copyFileFromGuestToHost $vmx $logInvitado $logLocal 2>&1 | Out-String).Trim()
            if (Test-Path -LiteralPath $logLocal) {
                Apuntar-Invitado "$($nombreVm): $programa $argumentos -> bien (intento $k, código $codigo)"
                return ''
            }
            # Lo que el programa escribió en pantalla (el error de verdad, si arrancó)
            $pantalla = ''
            if ($pantallaVm) {
                Remove-Item -LiteralPath $pantallaLocal -Force -ErrorAction SilentlyContinue
                & $vmrun -T ws -gu $usu -gp $pass copyFileFromGuestToHost $vmx $pantallaVm $pantallaLocal 2>&1 | Out-Null
                if (Test-Path -LiteralPath $pantallaLocal) {
                    $pantalla = (([IO.File]::ReadAllText($pantallaLocal, [Text.Encoding]::GetEncoding(850))) -replace '\s+', ' ').Trim()
                    if ($pantalla.Length -gt 900) { $pantalla = $pantalla.Substring(0, 900) + '…' }
                }
            }
            $motivo = "vmrun dijo: $(if ($salida) { $salida } else { '(nada)' }) (código $codigo). Al traer el resultado: $copia" +
                      $(if ($pantalla) { " En pantalla dentro de la máquina: $pantalla" } elseif ($pantallaVm) { ' (No escribió nada en pantalla.)' } else { '' })
            Apuntar-Invitado "$nombreVm como $($usu): $programa $argumentos -> sin resultado (intento $k). $motivo"
            # Si el programa llegó a ejecutarse y terminó con error, repetir no sirve de nada
            if ($salida -match 'exit code' -or $pantalla) { break }
            if ($k -lt $intentos) {
                Write-Host "  La máquina aún no deja ejecutar programas; se reintenta en 15 s ($k de $($intentos - 1))..." -ForegroundColor Yellow
                Start-Sleep 15
            }
        }
    } finally {
        if ($pantallaVm) { & $vmrun -T ws -gu $usu -gp $pass deleteFileInGuest $vmx $pantallaVm 2>&1 | Out-Null }
        Remove-Item -LiteralPath $pantallaLocal -Force -ErrorAction SilentlyContinue
    }
    return "La máquina no devolvió el resultado. $motivo (Queda apuntado en full-cowl\estado\invitado.log.)"
}

function Carpeta-PrivadaLinux($vmrun, $vmx, $usu, $pass) {
    # Carpeta temporal dentro de la casa del usuario de la VM (no en /tmp, que pueden leer todos)
    $dir = "/home/$(($usu -split '\\')[-1])/.fullcowl-" + [guid]::NewGuid().ToString('N').Substring(0, 12)
    & $vmrun -T ws -gu $usu -gp $pass createDirectoryInGuest $vmx $dir 2>&1 | Out-Null
    & $vmrun -T ws -gu $usu -gp $pass directoryExistsInGuest $vmx $dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "No se pudo crear una carpeta temporal en la máquina ($dir)." }
    return $dir
}

function Es-Dominio($t) { return ([string]$t -match '^[a-z0-9-]+(\.[a-z0-9-]+)+\z') }

function Proponer-IP($red, $usadas, [int]$desde) {
    $b = $red.Subred.Split('.')
    for ($n = $desde; $n -lt 128; $n++) {
        $ip = "$($b[0]).$($b[1]).$($b[2]).$n"
        if (@($usadas) -notcontains $ip) { return $ip }
    }
    return "$($b[0]).$($b[1]).$($b[2]).$desde"
}

function Guardar-Pedido($pedido) {
    # Pedido de la ventana para un script (puede llevar contraseñas de usuarios nuevos): archivo
    # temporal cifrado con DPAPI, que solo puede leer este usuario de Windows. Devuelve la ruta.
    $archivo = Join-Path $env:TEMP ("vmtareas-pedido-" + [guid]::NewGuid().ToString('N') + '.json')
    $bytes = [Text.Encoding]::UTF8.GetBytes(($pedido | ConvertTo-Json -Depth 6))
    $cifrado = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    [IO.File]::WriteAllText($archivo, 'DPAPI:' + [Convert]::ToBase64String($cifrado), [Text.Encoding]::ASCII)
    return $archivo
}

function Leer-Pedido($ruta) {
    # Lee un pedido de la ventana (cifrado o JSON normal) y lo borra
    try {
        $txt = [IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8)
        if ($txt.StartsWith('DPAPI:')) {
            $bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($txt.Substring(6)), $null, 'CurrentUser')
            $txt = [Text.Encoding]::UTF8.GetString($bytes)
        }
        return ($txt | ConvertFrom-Json)
    } finally { Remove-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue }
}

# =====================================================================
#  Aviso de Windows con el icono de Full Cowl (lo usan el vigilante y lab-estado.ps1)
# =====================================================================
function Aviso-Windows($texto) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ico = Join-Path $dirComun 'recursos\full-cowl-icono-4.ico'
        $ni.Icon = if (Test-Path $ico) { New-Object System.Drawing.Icon($ico) } else { [System.Drawing.SystemIcons]::Information }
        $ni.Visible = $true
        $ni.ShowBalloonTip(8000, 'Full Cowl', $texto, 'Info')
        Start-Sleep 9
        $ni.Dispose()
    } catch {}
}

# =====================================================================
#  Estado inicial del laboratorio (ficha 28)
#  Cada máquina de un laboratorio guarda una instantánea «inicio-lab» (distinta de «base», la de la base, y de
#  «inicio», la de recién creada sin configurar) con el laboratorio ya creado y configurado. Para saber si la
#  tiene se lee el .vmsd (sin lanzar vmrun, que tarda). Las operaciones largas (guardar, volver, quitar) las hace
#  lab-estado.ps1 sin ventana y deja su progreso en estado\lab\<laboratorio>.json, que lee la ventana.
# =====================================================================
function Nombre-EstadoInicial { return 'inicio-lab' }

function Leer-Instantaneas([string]$vmx) {
    # Instantáneas de una máquina según su .vmsd: @{ Nombre; Fecha } (Fecha puede ser $null)
    $res = @()
    $vmsd = [IO.Path]::ChangeExtension($vmx, 'vmsd')
    if (-not $vmx -or -not (Test-Path -LiteralPath $vmsd)) { return $res }
    $lineasSnap = @()
    try {
        $fs = New-Object IO.FileStream($vmsd, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $lineasSnap = @($sr.ReadToEnd() -split "`r?`n") } finally { $fs.Dispose() }
    } catch { return $res }
    $porNum = @{}
    foreach ($ls in $lineasSnap) {
        if ($ls -match '^\s*snapshot(\d+)\.(displayName|createTimeHigh|createTimeLow)\s*=\s*"(.*)"\s*$') {
            if (-not $porNum.ContainsKey($Matches[1])) { $porNum[$Matches[1]] = @{} }
            $porNum[$Matches[1]][$Matches[2]] = $Matches[3]
        }
    }
    foreach ($num in @($porNum.Keys | Sort-Object { [int]$_ })) {
        $dato = $porNum[$num]
        if (-not $dato.displayName) { continue }
        $fechaSnap = $null
        try {
            if ($dato.createTimeHigh -and $dato.createTimeLow) {
                # Microsegundos desde 1970 en dos mitades de 32 bits (la baja puede venir con signo); en [long]
                $alto = [long]$dato.createTimeHigh; $bajo = [long]$dato.createTimeLow
                if ($bajo -lt 0) { $bajo += [long]4294967296 }
                $seg = [long][Math]::Floor(([double]$alto * 4294967296.0 + [double]$bajo) / 1000000.0)
                $f = [DateTimeOffset]::FromUnixTimeSeconds($seg).LocalDateTime
                if ($f.Year -ge 2000 -and $f -lt (Get-Date).AddDays(2)) { $fechaSnap = $f }
            }
        } catch {}
        $res += [pscustomobject]@{ Nombre = (([string]$dato.displayName) -replace '\\(["\\])', '$1'); Fecha = $fechaSnap }
    }
    return $res
}

function Tiene-EstadoInicial([string]$vmx) {
    return [bool](@(Leer-Instantaneas $vmx | Where-Object { $_.Nombre -ceq (Nombre-EstadoInicial) }).Count)
}

function Fecha-EstadoInicial([string]$vmx) {
    # Cuándo se guardó el estado inicial de esa máquina ($null si no lo tiene). La ficha del laboratorio la usa
    $snap = @(Leer-Instantaneas $vmx | Where-Object { $_.Nombre -ceq (Nombre-EstadoInicial) }) | Select-Object -First 1
    if ($snap) { return $snap.Fecha }
    return $null
}

function Archivo-InicioPendiente { return (Join-Path $dirComun 'estado\inicio-lab-pendiente.txt') }

function Pedir-EstadoInicial([string]$labId, [string]$lab) {
    # laboratorio.ps1 lo apunta al crear el laboratorio; el vigilante lo hace cuando todas sus máquinas terminan
    # (una línea por laboratorio: identificador|nombre). No va en el .vmx porque las máquinas están encendidas
    if (-not $labId) { return }
    $dirEst = Join-Path $dirComun 'estado'
    if (-not (Test-Path -LiteralPath $dirEst)) { New-Item -ItemType Directory -Path $dirEst -Force | Out-Null }
    [IO.File]::AppendAllText((Archivo-InicioPendiente), "$labId|$lab`r`n", [Text.UTF8Encoding]::new($false))
}

function Leer-IniciosPendientes {
    $r = @{}
    try {
        foreach ($lp in [IO.File]::ReadAllLines((Archivo-InicioPendiente), [Text.Encoding]::UTF8)) {
            $partes = $lp.Trim().TrimStart([char]0xFEFF).Split('|', 2)
            if ($partes[0]) { $r[$partes[0]] = $(if ($partes.Count -gt 1) { $partes[1].Trim() } else { '' }) }
        }
    } catch {}
    return $r
}

function Quitar-InicioPendiente([string]$labId) {
    $f = Archivo-InicioPendiente
    try {
        $quedan = @([IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8) | ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } |
            Where-Object { $_ -and -not $_.StartsWith("$labId|") })
        if ($quedan.Count) { [IO.File]::WriteAllLines($f, [string[]]$quedan, [Text.UTF8Encoding]::new($false)) }
        else { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Carpeta-OperacionesLab { return (Join-Path $dirComun 'estado\lab') }
function Archivo-OperacionLab([string]$lab) { return (Join-Path (Carpeta-OperacionesLab) (([string]$lab -replace '[^A-Za-z0-9_-]', '_') + '.json')) }

function Leer-OperacionLab([string]$lab) {
    # Última operación (guardar, volver o quitar el estado inicial) de ese laboratorio, o $null.
    # Si dice «curso» pero su proceso ya no existe, se da por interrumpida
    $f = Archivo-OperacionLab $lab
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { $op = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
    if (-not $op -or -not $op.estado -or -not $op.lab) { return $null }
    if ([string]$op.estado -eq 'curso') {
        $edad = (Get-Date) - (Get-Item -LiteralPath $f).LastWriteTime
        $muerto = $false
        if ([int]$op.pid -gt 0) { $muerto = -not (Get-Process -Id ([int]$op.pid) -ErrorAction SilentlyContinue) }
        else { $muerto = ($edad.TotalSeconds -gt 90) }   # no llegó a arrancar
        if ($muerto -or $edad.TotalHours -gt 12) { $op.estado = 'error'; $op.mensaje = 'Se interrumpió antes de terminar.' }
    }
    return $op
}

function Leer-OperacionesLab {
    $res = @()
    $dirOp = Carpeta-OperacionesLab
    if (-not (Test-Path -LiteralPath $dirOp)) { return $res }
    foreach ($fi in @(Get-ChildItem -LiteralPath $dirOp -Filter *.json -ErrorAction SilentlyContinue)) {
        try { $op = [IO.File]::ReadAllText($fi.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
        if (-not $op -or -not $op.lab) { continue }
        $res += (Leer-OperacionLab ([string]$op.lab))
    }
    return @($res | Where-Object { $_ })
}

function Lanzar-OperacionLab([string]$accion, [string]$lab, [string[]]$vmxLista, [string[]]$opciones = @()) {
    # Arranca lab-estado.ps1 sin ventana. Antes deja escrito el estado «curso» para que la ventana lo vea ya
    # y no se lance dos veces. $accion: guardar, volver o quitar. $opciones: ApagarAntes, Encender, Parcial, Aviso
    # El nombre del laboratorio sale del .vmx y va entre comillas a una línea de órdenes: sin comillas ni caracteres de control
    $lab = (([string]$lab) -replace '["\x00-\x1F]', '').Trim()
    if ($accion -notin @('guardar', 'volver', 'quitar')) { return }
    $dirOp = Carpeta-OperacionesLab
    if (-not (Test-Path -LiteralPath $dirOp)) { New-Item -ItemType Directory -Path $dirOp -Force | Out-Null }
    $ahoraIso = (Get-Date).ToString('o')
    $ini = [ordered]@{ accion = $accion; lab = $lab; estado = 'curso'; paso = 'Preparando…'; actual = 0; total = @($vmxLista).Count; pct = 0
                       inicio = $ahoraIso; actualizado = $ahoraIso; pid = 0; mensaje = ''; resultado = @() }
    [IO.File]::WriteAllText((Archivo-OperacionLab $lab), ($ini | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $script = Join-Path $dirComun 'lab-estado.ps1'
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Accion $accion -Lab `"$lab`" -Vmx `"$(@($vmxLista) -join '|')`""
    foreach ($o in @($opciones)) { if ($o) { $argumentos += " -$o" } }
    Iniciar-Oculto 'powershell.exe' $argumentos
}
