# =====================================================================
#  Packer: dónde está y cómo se instala (ficha 33). Archivo independiente
#  (no necesita la configuración de Full Cowl) para que lo usen igual el
#  instalador, el asistente de primer arranque y crear-base.ps1.
#
#  Orden al instalar: (1) descarga directa del ZIP oficial de HashiCorp de la
#  versión fijada en recursos\versiones.json, comprobando su SHA-256, a
#  <carpeta del programa>\herramientas\packer\packer.exe (sin administrador ni
#  winget); (2) si falla, winget; (3) si falla, un mensaje con los pasos a mano.
# =====================================================================

$script:dirPackerFc = Split-Path $PSScriptRoot          # ...\full-cowl
$script:raizPackerFc = Split-Path $script:dirPackerFc   # carpeta del programa

function Carpeta-PackerPropio { return (Join-Path $script:raizPackerFc 'herramientas\packer') }

function Version-PackerFijada {
    try {
        $v = [string](([IO.File]::ReadAllText((Join-Path $script:dirPackerFc 'recursos\versiones.json')) | ConvertFrom-Json).packer)
        if ($v -match '^\d+\.\d+\.\d+$') { return $v }
    } catch {}
    return '1.16.2'
}

function Obtener-Packer {
    # Ruta de packer.exe: primero el propio de Full Cowl, después el del PATH. $null si no hay.
    $propio = Join-Path (Carpeta-PackerPropio) 'packer.exe'
    if (Test-Path -LiteralPath $propio) { return $propio }
    try {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    } catch {}
    $cmd = Get-Command packer.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return [string]$cmd.Source }
    return $null
}

function Origen-Packer {
    # Para Ajustes → Este PC: de dónde sale el Packer que se usa
    $r = Obtener-Packer
    if (-not $r) { return 'No instalado' }
    if ($r -like "$(Carpeta-PackerPropio)*") { return 'El de Full Cowl (herramientas\packer)' }
    return 'El del sistema (PATH)'
}

function Preparar-Red {
    # TLS 1.2 y las credenciales del proxy del sistema (redes de centro con filtro web)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch {}
}

function Instalar-Packer([switch]$SinWinget) {
    # Devuelve @{ Ok; Ruta; Via; Mensaje }. Nunca pide administrador.
    $ver = Version-PackerFijada
    $base = "https://releases.hashicorp.com/packer/$ver"
    $zipNombre = "packer_${ver}_windows_amd64.zip"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("FullCowl-packer-" + [guid]::NewGuid().ToString('N'))
    $fallo = ''
    try {
        Preparar-Red
        [void](New-Item -ItemType Directory -Path $tmp -Force)
        $zip = Join-Path $tmp $zipNombre
        $sumas = Join-Path $tmp 'SHA256SUMS'
        $wc = New-Object Net.WebClient
        $wc.DownloadFile("$base/packer_${ver}_SHA256SUMS", $sumas)
        $wc.DownloadFile("$base/$zipNombre", $zip)
        $linea = @(Get-Content -LiteralPath $sumas | Where-Object { $_ -match "\s$([regex]::Escape($zipNombre))$" }) | Select-Object -First 1
        if (-not $linea) { throw 'La lista de sumas de HashiCorp no trae el archivo de Windows.' }
        $esperada = ($linea -split '\s+')[0].ToLower()
        $real = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
        if ($esperada -ne $real) { throw 'El archivo descargado no coincide con su suma SHA-256 (puede estar dañado o manipulado): no se instala.' }
        $destino = Carpeta-PackerPropio
        [void](New-Item -ItemType Directory -Path $destino -Force)
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        Copy-Item -LiteralPath (Join-Path $tmp 'packer.exe') -Destination (Join-Path $destino 'packer.exe') -Force
        return @{ Ok = $true; Ruta = (Join-Path $destino 'packer.exe'); Via = 'descarga'; Mensaje = "Packer $ver instalado en herramientas\packer." }
    } catch {
        $fallo = $_.Exception.Message
    } finally {
        try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    if (-not $SinWinget) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($winget) {
            try {
                & $winget.Source install --id Hashicorp.Packer -e --source winget --accept-source-agreements --accept-package-agreements | Out-Null
                $r = Obtener-Packer
                if ($r) { return @{ Ok = $true; Ruta = $r; Via = 'winget'; Mensaje = 'Packer instalado con winget.' } }
            } catch {}
        }
    }
    return @{ Ok = $false; Ruta = $null; Via = ''
              Mensaje = "No he podido instalar Packer ($fallo). A mano: descarga $base/$zipNombre, ábrelo y copia packer.exe en «$(Carpeta-PackerPropio)»." }
}
