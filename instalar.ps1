# Full Cowl - instalador de una linea (ficha 33).
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/MrDavid99-hub/FullCowl/main/instalar.ps1 | iex"
# Este archivo va SOLO en ASCII, sin BOM y con finales LF: "irm | iex" se rompe con BOM o tildes en PowerShell 5.1.
# Solo hace lo imprescindible: descarga Full-Cowl.zip de la ultima Release, comprueba su SHA-256 y ejecuta
# full-cowl\instalacion\instalar-completo.ps1, que es el instalador de verdad (con mensajes en espanol).
$ErrorActionPreference = 'Stop'
$Repo = 'MrDavid99-hub/FullCowl'
$Permitidos = @('github.com', 'raw.githubusercontent.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com', 'releases.hashicorp.com')

function Fallo([string]$que, [string]$hacer) {
    Write-Host ''
    Write-Host "Full Cowl no se ha instalado: $que" -ForegroundColor Red
    if ($hacer) { Write-Host "Que hacer: $hacer" -ForegroundColor Yellow }
}

function Descargar([string]$url, [string]$destino) {
    # Solo dominios de la lista, tambien despues de las redirecciones de GitHub
    $u = [Uri]$url
    if ($u.Scheme -ne 'https' -or $Permitidos -notcontains $u.Host) { throw "Direccion no permitida: $($u.Host)" }
    $pet = [Net.HttpWebRequest]::Create($u)
    $pet.UserAgent = 'FullCowl-instalador'
    $pet.Proxy = [Net.WebRequest]::DefaultWebProxy
    $resp = $pet.GetResponse()
    try {
        $final = $resp.ResponseUri
        if ($final.Scheme -ne 'https' -or $Permitidos -notcontains $final.Host) { throw "Direccion no permitida tras redirigir: $($final.Host)" }
        $entrada = $resp.GetResponseStream()
        $salida = [IO.File]::Create($destino)
        try { $entrada.CopyTo($salida) } finally { $salida.Dispose(); $entrada.Dispose() }
    } finally { $resp.Close() }
}

function Instalar-FullCowl {
    if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        Fallo 'este instalador es el de la copia de trabajo (no lleva la direccion del repositorio publico).' 'Usa el comando del README del repositorio publico.'
        return
    }
    if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10) { Fallo 'hace falta Windows 10 u 11 de 64 bits.' ''; return }
    if ($PSVersionTable.PSVersion.Major -ne 5) { Fallo 'hay que usar Windows PowerShell 5.1.' 'Pega el comando tal cual (empieza por "powershell"), que ya llama al correcto.'; return }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch {}

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('FullCowl-instalar-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $tmp -Force)
        $zip = Join-Path $tmp 'Full-Cowl.zip'
        $sumas = Join-Path $tmp 'SHA256SUMS.txt'
        Write-Host 'Descargando Full Cowl de GitHub...' -ForegroundColor Cyan
        try {
            Descargar "https://github.com/$Repo/releases/latest/download/SHA256SUMS.txt" $sumas
            Descargar "https://github.com/$Repo/releases/latest/download/Full-Cowl.zip" $zip
        } catch {
            Fallo "no se ha podido descargar ($($_.Exception.Message))." 'Comprueba la conexion a Internet. En la red de un centro, el filtro web puede bloquear GitHub: prueba con otra red o descarga el ZIP desde la pagina de Releases.'
            return
        }
        $linea = @(Get-Content -LiteralPath $sumas | Where-Object { $_ -match '\sFull-Cowl\.zip$' }) | Select-Object -First 1
        $esperada = $(if ($linea) { ($linea -split '\s+')[0].ToLower() } else { '' })
        $real = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
        if (-not $esperada -or $esperada -ne $real) {
            Fallo 'el archivo descargado no coincide con su suma SHA-256 (danado o manipulado). No se ha instalado nada.' 'Vuelve a intentarlo dentro de un rato.'
            return
        }
        Write-Host 'Descarga comprobada (SHA-256 correcto).' -ForegroundColor Green
        $prog = Join-Path $tmp 'programa'
        Expand-Archive -LiteralPath $zip -DestinationPath $prog -Force
        $script = Join-Path $prog 'full-cowl\instalacion\instalar-completo.ps1'
        if (-not (Test-Path -LiteralPath $script)) { Fallo 'el ZIP no trae el instalador.' 'Descarga el ZIP a mano desde la pagina de Releases.'; return }
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $ps -NoProfile -ExecutionPolicy Bypass -File $script -Origen $prog
    } finally {
        try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

Instalar-FullCowl
