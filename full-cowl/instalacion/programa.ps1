# =====================================================================
#  Copiar el programa de una carpeta a otra sin tocar los datos de cada PC
#  (ficha 33). Lo usan el instalador y la actualización «por descarga».
#
#  MANIFIESTO.txt (lo crea herramientas\crear-release.py en cada Release):
#  una línea por archivo del programa, «<sha256>  <ruta/relativa>».
#  Se copian los archivos del manifiesto nuevo que cambian y se borran los
#  que estaban en el anterior y ya no están. Lo que no está en el manifiesto
#  (los datos de cada PC) no se toca nunca.
# =====================================================================

$script:ArchivosProtegidos = @('config.local.json', 'password.sec', 'password.sec.antes', 'preferencias.json', 'segmentos.json', 'plantillas-laboratorio.json')
$script:CarpetasProtegidas = @('full-cowl/estado/', 'full-cowl/build/', 'full-cowl/packer_cache/', 'herramientas/packer/', '.git/')

function Es-Protegido([string]$rel) {
    $r = $rel.Replace('\', '/')
    if ($script:ArchivosProtegidos -contains (Split-Path $r -Leaf)) { return $true }
    if ($r -like '*.lnk' -or $r -like 'full-cowl/*.log') { return $true }
    foreach ($c in $script:CarpetasProtegidas) { if ($r.StartsWith($c, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

function Leer-Manifiesto([string]$ruta) {
    # Tabla ruta relativa (con /) → sha256 en minúsculas. Vacía si no existe.
    $t = @{}
    if (-not (Test-Path -LiteralPath $ruta)) { return $t }
    foreach ($l in [IO.File]::ReadAllLines($ruta)) {
        if ($l -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            $rel = $Matches[2].Trim().Replace('\', '/')
            # Nada de rutas que se salgan de la carpeta
            if ($rel -match '(^|/)\.\.(/|$)' -or $rel -match '^[A-Za-z]:' -or $rel.StartsWith('/')) { continue }
            $t[$rel] = $Matches[1].ToLower()
        }
    }
    return $t
}

function Hash-Archivo([string]$ruta) {
    try { return (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash.ToLower() } catch { return '' }
}

function Copiar-ConReintentos([string]$de, [string]$a) {
    # Windows, el antivirus o OneDrive pueden tener un archivo cogido unos segundos: se reintenta antes de rendirse,
    # y si no se puede, el error dice QUÉ archivo y el motivo de verdad (no solo «algo está en uso»)
    for ($i = 1; $i -le 6; $i++) {
        try { Copy-Item -LiteralPath $de -Destination $a -Force -ErrorAction Stop; return }
        catch {
            if ($i -eq 6) { throw "No se pudo escribir «${a}»: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 1500
        }
    }
}

function Copiar-Programa([string]$origen, [string]$destino) {
    # Devuelve @{ Copiados; Borrados; Respetados } (Respetados: archivos viejos cambiados a mano, que no se borran)
    $nuevo = Leer-Manifiesto (Join-Path $origen 'MANIFIESTO.txt')
    if ($nuevo.Count -eq 0) {
        # Sin manifiesto (por ejemplo, desde una copia del repositorio): todos los archivos de la carpeta
        $baseO = (Resolve-Path -LiteralPath $origen).Path.TrimEnd('\') + '\'
        foreach ($f in Get-ChildItem -LiteralPath $origen -Recurse -File -Force) {
            $rel = $f.FullName.Substring($baseO.Length).Replace('\', '/')
            if (-not (Es-Protegido $rel)) { $nuevo[$rel] = '' }
        }
    }
    $viejo = Leer-Manifiesto (Join-Path $destino 'MANIFIESTO.txt')
    $copiados = 0; $borrados = 0; $respetados = @()
    foreach ($rel in @($nuevo.Keys)) {
        if (Es-Protegido $rel) { continue }
        $de = Join-Path $origen ($rel.Replace('/', '\'))
        $a = Join-Path $destino ($rel.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $de)) { throw "Falta $rel en la descarga." }
        if ((Test-Path -LiteralPath $a) -and (Hash-Archivo $de) -eq (Hash-Archivo $a)) { continue }
        $dirA = Split-Path $a
        if (-not (Test-Path -LiteralPath $dirA)) { [void](New-Item -ItemType Directory -Path $dirA -Force) }
        Copiar-ConReintentos $de $a
        $copiados++
    }
    foreach ($rel in @($viejo.Keys)) {
        if ($nuevo.ContainsKey($rel) -or (Es-Protegido $rel)) { continue }
        $a = Join-Path $destino ($rel.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $a)) { continue }
        # Solo si sigue como lo dejó la versión anterior: si alguien lo cambió a mano, se respeta
        if ((Hash-Archivo $a) -eq $viejo[$rel]) {
            try { Remove-Item -LiteralPath $a -Force -ErrorAction Stop } catch { throw "No se pudo quitar «${a}»: $($_.Exception.Message)" }
            $borrados++
        } else { $respetados += $rel }
    }
    $man = Join-Path $origen 'MANIFIESTO.txt'
    if (Test-Path -LiteralPath $man) { Copiar-ConReintentos $man (Join-Path $destino 'MANIFIESTO.txt') }
    return @{ Copiados = $copiados; Borrados = $borrados; Respetados = $respetados }
}
