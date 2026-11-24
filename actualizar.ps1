# =====================================================================
#  Actualizar esta carpeta a la última versión de GitHub. Un solo sitio con la lógica; lo usan:
#    - Actualizar.bat                 (sin parámetros: con mensajes en la consola)
#    - Full Cowl, para buscar        (-Buscar: solo mira si hay algo nuevo; no cambia ningún archivo)
#    - Full Cowl, «Actualizar ahora» (-Interfaz -EsperarPid N: espera a que Full Cowl se cierre,
#                                     actualiza y vuelve a abrirlo)
#    - Al abrir Full Cowl con «actualizar solo» (-Automatico: actualiza antes de cargar la interfaz,
#                                     si no hay tareas en marcha, ni cambios a mano, ni versión mayor)
#  Lo propio de cada PC (config.local.json, password.sec, preferencias...) no se toca.
#  OJO: si se cambia a mano algún archivo del programa, ese cambio se pierde al actualizar.
#
#  Dos modos (ficha 33):
#    - Copia del repositorio (con carpeta .git, la de David): git fetch + reset, como siempre.
#    - Instalado por descarga (sin .git: comando de una línea o ZIP): lee VERSION del repositorio
#      público (raw.githubusercontent.com, sin gastar el límite de la API), descarga Full-Cowl.zip de la
#      última Release, comprueba su SHA-256 y copia solo los archivos de su MANIFIESTO.txt que cambian
#      (instalacion\programa.ps1). Lo que no está en el manifiesto (los datos del PC) no se toca.
#  Resultado de -Buscar: full-cowl\estado\actualizacion.json · Registro: full-cowl\estado\actualizar.log
# =====================================================================
param(
    [switch]$Buscar,
    [switch]$Interfaz,
    [switch]$Automatico,
    [int]$EsperarPid = 0
)
$ErrorActionPreference = 'Continue'
$raiz = $PSScriptRoot
$dirEstado = Join-Path $raiz 'full-cowl\estado'
$env:GIT_TERMINAL_PROMPT = '0'
$enConsola = -not ($Buscar -or $Interfaz -or $Automatico)
# Repositorio público (lo pone herramientas\preparar-publico.py en la copia pública; en la copia de trabajo no se usa)
$RepoPublico = 'MrDavid99-hub/FullCowl'
$modoDescarga = -not (Test-Path -LiteralPath (Join-Path $raiz '.git'))
$dominiosPermitidos = @('github.com', 'raw.githubusercontent.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com')

function Registro([string]$texto) {
    try {
        if (-not (Test-Path $dirEstado)) { [void](New-Item -ItemType Directory -Path $dirEstado) }
        Add-Content -LiteralPath (Join-Path $dirEstado 'actualizar.log') -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}" -f (Get-Date), $texto) -Encoding UTF8
    } catch {}
}
function Decir([string]$texto) { if ($enConsola) { Write-Host $texto } }
function Escribir-Json([string]$nombre, $objeto) {
    try {
        if (-not (Test-Path $dirEstado)) { [void](New-Item -ItemType Directory -Path $dirEstado) }
        [IO.File]::WriteAllText((Join-Path $dirEstado $nombre), ($objeto | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}

# Ejecuta git en la carpeta del repositorio, con tiempo máximo. Devuelve @{ Codigo; Salida }
function Git([string[]]$argumentos, [int]$msMaximo = 60000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo('git', ((@('-C', "`"$raiz`"") + $argumentos) -join ' '))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return @{ Codigo = -1; Salida = $_.Exception.Message } }
    $tarea = $p.StandardOutput.ReadToEndAsync(); $tareaErr = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($msMaximo)) { try { $p.Kill() } catch {}; return @{ Codigo = -2; Salida = 'Se agotó el tiempo de espera.' } }
    $p.WaitForExit()
    return @{ Codigo = $p.ExitCode; Salida = (($tarea.Result + "`n" + $tareaErr.Result).Trim()) }
}

function Hay-Git { return [bool](Get-Command git -ErrorAction SilentlyContinue) }

# ---------------------------------------------------------------- modo descarga (sin Git)
function Preparar-Red {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch {}
}
function Descargar([string]$url, [string]$destino, [int]$msMaximo = 120000) {
    # Solo https y dominios de la lista, también tras las redirecciones de GitHub
    $u = [Uri]$url
    if ($u.Scheme -ne 'https' -or $dominiosPermitidos -notcontains $u.Host) { throw "Dirección no permitida: $($u.Host)" }
    $pet = [Net.HttpWebRequest]::Create($u)
    $pet.UserAgent = 'FullCowl-actualizar'; $pet.Timeout = $msMaximo; $pet.ReadWriteTimeout = $msMaximo
    $pet.Proxy = [Net.WebRequest]::DefaultWebProxy
    $resp = $pet.GetResponse()
    try {
        if ($resp.ResponseUri.Scheme -ne 'https' -or $dominiosPermitidos -notcontains $resp.ResponseUri.Host) { throw "Dirección no permitida tras redirigir: $($resp.ResponseUri.Host)" }
        $entrada = $resp.GetResponseStream()
        if ($destino) {
            $salida = [IO.File]::Create($destino)
            try { $entrada.CopyTo($salida) } finally { $salida.Dispose(); $entrada.Dispose() }
            return $null
        }
        $lector = New-Object IO.StreamReader($entrada, [Text.Encoding]::UTF8)
        try { return $lector.ReadToEnd() } finally { $lector.Dispose() }
    } finally { $resp.Close() }
}
function Repo-Valido { return ($RepoPublico -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') }
function Version-Mayor([string]$a, [string]$b) {
    # $true si la versión $a es más nueva que $b (MAYOR.MENOR.PARCHE)
    try { return ([version]$a -gt [version]$b) } catch { return $false }
}
function Cambios-ALaManoDescarga {
    # Archivos del manifiesto que ya no coinciden con su suma (cambiados a mano)
    $man = Join-Path $raiz 'MANIFIESTO.txt'
    if (-not (Test-Path -LiteralPath $man)) { return 0 }
    $n = 0
    foreach ($l in [IO.File]::ReadAllLines($man)) {
        if ($l -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            $f = Join-Path $raiz ($Matches[2].Trim().Replace('/', '\'))
            if ((Test-Path -LiteralPath $f) -and ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() -ne $Matches[1].ToLower())) { $n++ }
        }
    }
    return $n
}
function Buscar-VersionDescarga($res) {
    if (-not (Repo-Valido)) { $res.sinConexion = $true; Registro 'Buscar: esta copia no lleva la dirección del repositorio público.'; return $res }
    Preparar-Red
    try { $nueva = ([string](Descargar "https://raw.githubusercontent.com/$RepoPublico/main/VERSION" $null 10000)).Trim() }
    catch { $res.sinConexion = $true; Registro "Buscar: no se pudo consultar GitHub ($($_.Exception.Message))"; return $res }
    $res.ok = $true
    if ($nueva -match '^\d+\.\d+\.\d+$' -and (Version-Mayor $nueva $res.actual)) {
        $res.hayNueva = $true; $res.nueva = $nueva
        try { $res.mayor = ([int]($nueva.Split('.')[0]) -gt [int]($res.actual.Split('.')[0])) } catch {}
        $res.cambiosLocales = Cambios-ALaManoDescarga
    }
    return $res
}
function Poner-AlDiaDescarga {
    # Devuelve $null si fue bien o el texto del problema. Nunca deja nada a medias sin avisar.
    if (-not (Repo-Valido)) { return 'Esta copia no lleva la dirección del repositorio público.' }
    Preparar-Red
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('FullCowl-actualizar-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $tmp -Force)
        $zip = Join-Path $tmp 'Full-Cowl.zip'; $sumas = Join-Path $tmp 'SHA256SUMS.txt'
        try {
            Descargar "https://github.com/$RepoPublico/releases/latest/download/SHA256SUMS.txt" $sumas
            Descargar "https://github.com/$RepoPublico/releases/latest/download/Full-Cowl.zip" $zip 600000
        } catch { return "No se pudo descargar de GitHub. Comprueba la conexión a Internet. ($($_.Exception.Message))" }
        $linea = @(Get-Content -LiteralPath $sumas | Where-Object { $_ -match '\sFull-Cowl\.zip$' }) | Select-Object -First 1
        $esperada = $(if ($linea) { ($linea -split '\s+')[0].ToLower() } else { '' })
        if (-not $esperada -or $esperada -ne (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()) {
            return 'La descarga no coincide con su suma SHA-256 (dañada o manipulada): no se ha cambiado nada.'
        }
        $prog = Join-Path $tmp 'programa'
        Expand-Archive -LiteralPath $zip -DestinationPath $prog -Force
        $copiar = Join-Path $prog 'full-cowl\instalacion\programa.ps1'
        if (-not (Test-Path -LiteralPath $copiar)) { return 'La descarga no trae el programa completo: no se ha cambiado nada.' }
        . $copiar
        try { $r = Copiar-Programa $prog $raiz }
        catch {
            # El motivo REAL va delante; la pista de «cierra Full Cowl» solo si de verdad parece un archivo en uso
            $motivo = [string]$_.Exception.Message
            $pista = $(if ($motivo -match 'otro proceso|being used|en uso|denegad|denied|Access') { ' Parece que algo está usando esos archivos: cierra Full Cowl y las consolas abiertas (y espera un minuto si OneDrive o el antivirus están mirando la carpeta) y repite.' } else { '' })
            return "No se pudo copiar la versión nueva: $motivo$pista"
        }
        Registro "Descarga: $($r.Copiados) archivos copiados, $($r.Borrados) quitados$(if ($r.Respetados.Count) { ", respetados (cambiados a mano): $($r.Respetados -join ', ')" })"
        return $null
    } finally {
        try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
function Version-Actual { try { return ([IO.File]::ReadAllText((Join-Path $raiz 'VERSION'))).Trim() } catch { return '' } }
function Cambios-ALaMano { if ($modoDescarga) { return (Cambios-ALaManoDescarga) }; $r = Git @('status', '--porcelain', '--untracked-files=no') 15000; if ($r.Codigo -ne 0) { return 0 }; return @($r.Salida -split "`n" | Where-Object { $_.Trim() }).Count }
function Hay-TareasEnMarcha {
    # Otros procesos de PowerShell de este repositorio (crear base, vigilante, importar...) que no sean la propia
    # ventana ni este script
    try {
        $mis = $PID
        foreach ($pr in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)) {
            if ($pr.ProcessId -eq $mis -or -not $pr.CommandLine) { continue }
            if ($pr.CommandLine -notlike "*$raiz*") { continue }
            if ($pr.CommandLine -match 'abrir-nueva|ventana-nueva|abrir-ventana|gui\.ps1|actualizar\.ps1') { continue }
            return $true
        }
    } catch {}
    return $false
}

function Ventanas-FullCowlAbiertas {
    # Procesos de la ventana de Full Cowl de ESTA carpeta (abrir-nueva / ventana-nueva); nunca este script
    $ids = @()
    try {
        foreach ($pr in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)) {
            if ($pr.ProcessId -eq $PID -or -not $pr.CommandLine) { continue }
            if ($pr.CommandLine -notlike "*$raiz*") { continue }
            if ($pr.CommandLine -match 'abrir-nueva|ventana-nueva') { $ids += [int]$pr.ProcessId }
        }
    } catch {}
    return $ids
}
function Cerrar-FullCowl {
    # Cierra la ventana (solo es la interfaz: las bases y las máquinas siguen). $true si ya no queda ninguna
    foreach ($id in @(Ventanas-FullCowlAbiertas)) { try { Stop-Process -Id $id -Force -ErrorAction Stop } catch {} }
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    while ($reloj.Elapsed.TotalSeconds -lt 10 -and @(Ventanas-FullCowlAbiertas).Count) { Start-Sleep -Milliseconds 400 }
    return (@(Ventanas-FullCowlAbiertas).Count -eq 0)
}

# ---------------------------------------------------------------- buscar (sin tocar nada)
function Buscar-Version {
    $res = [ordered]@{ ok = $false; sinGit = $false; sinConexion = $false; hayNueva = $false; actual = (Version-Actual); nueva = ''
                       cambios = @(); mayor = $false; cambiosLocales = 0; fecha = (Get-Date).ToString('dd/MM/yyyy HH:mm') }
    if ($modoDescarga) { return (Buscar-VersionDescarga $res) }
    if (-not (Hay-Git)) { $res.sinGit = $true; return $res }
    $f = Git @('fetch', 'origin', 'main') 10000
    if ($f.Codigo -ne 0) { $res.sinConexion = $true; Registro "Buscar: no se pudo consultar GitHub ($($f.Salida))"; return $res }
    $res.ok = $true
    $n = Git @('rev-list', 'HEAD..origin/main', '--count') 15000
    if ($n.Codigo -eq 0 -and [int]$n.Salida -gt 0) {
        $res.hayNueva = $true
        $v = Git @('show', 'origin/main:VERSION') 15000
        if ($v.Codigo -eq 0) { $res.nueva = $v.Salida.Trim() }
        $l = Git @('log', 'HEAD..origin/main', '--format=%s') 15000
        if ($l.Codigo -eq 0) { $res.cambios = @($l.Salida -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 5) }
        if ($res.actual -and $res.nueva) {
            try { $res.mayor = ([int]($res.nueva.Split('.')[0]) -gt [int]($res.actual.Split('.')[0])) } catch {}
        }
        $res.cambiosLocales = Cambios-ALaMano
    }
    return $res
}

# ---------------------------------------------------------------- poner al día (fetch + reset + accesos)
function Poner-AlDia {
    # Devuelve $null si fue bien o el texto del problema. Si el reset falla, lo reintenta una vez.
    if ($modoDescarga) { return (Poner-AlDiaDescarga) }
    if (-not (Hay-Git)) { return 'Git no está instalado.' }
    $f = Git @('fetch', 'origin', 'main') 60000
    if ($f.Codigo -ne 0) { return "No se pudo conectar con GitHub. Comprueba la conexión a Internet. ($($f.Salida))" }
    $r = Git @('reset', '--hard', 'origin/main') 60000
    if ($r.Codigo -ne 0) {
        Start-Sleep -Seconds 3
        $r = Git @('reset', '--hard', 'origin/main') 60000
        if ($r.Codigo -ne 0) { return "No se pudo actualizar (¿hay algún archivo en uso?). Cierra Full Cowl y las consolas abiertas y repite. ($($r.Salida))" }
    }
    return $null
}
function Accesos {
    try { & (Join-Path $raiz 'crear-accesos.ps1') | Out-Null } catch { Registro "Accesos: $($_.Exception.Message)" }
}
function Reabrir-FullCowl {
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $abrir = Join-Path $raiz 'full-cowl\abrir-nueva.ps1'
    $psi = New-Object System.Diagnostics.ProcessStartInfo($conhost, "--headless `"$ps`" -NoProfile -ExecutionPolicy Bypass -STA -File `"$abrir`"")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = (Join-Path $raiz 'full-cowl')
    try { [void][System.Diagnostics.Process]::Start($psi) } catch { Registro "No se pudo volver a abrir Full Cowl: $($_.Exception.Message)" }
}

# ================================================================ modos
if ($Buscar) {
    Escribir-Json 'actualizacion.json' (Buscar-Version)
    exit 0
}

if ($Automatico) {
    # Antes de cargar la interfaz: nunca con tareas en marcha, cambios a mano o versión mayor; con 10 s de margen
    $b = Buscar-Version
    if (-not $b.hayNueva) { exit 0 }
    if ($b.mayor) { Registro 'Automático: hay una versión mayor; no se actualiza sola.'; exit 0 }
    if ($b.cambiosLocales -gt 0) { Registro "Automático: $($b.cambiosLocales) archivos cambiados a mano; no se actualiza."; exit 0 }
    if (Hay-TareasEnMarcha) { Registro 'Automático: hay una tarea en marcha; no se actualiza.'; exit 0 }
    $antes = Version-Actual
    $fallo = Poner-AlDia
    if ($fallo) { Registro "Automático: $fallo"; exit 0 }
    Accesos
    Registro "Automático: actualizado de $antes a $(Version-Actual)"
    Escribir-Json 'actualizado.json' ([ordered]@{ de = $antes; a = (Version-Actual); cambios = @($b.cambios) })
    exit 0
}

if ($Interfaz) {
    # Desde «Actualizar ahora»: esperar a que Full Cowl se cierre del todo
    $antes = Version-Actual
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    if ($EsperarPid -gt 0) {
        while ((Get-Process -Id $EsperarPid -ErrorAction SilentlyContinue) -and $reloj.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 400 }
    }
    Start-Sleep -Milliseconds 600
    $cambios = @()
    try { $b = Buscar-Version; if ($b.hayNueva) { $cambios = @($b.cambios) } } catch {}
    $fallo = Poner-AlDia
    if ($fallo) {
        Registro "Fallo al actualizar desde Full Cowl: $fallo"
        Escribir-Json 'actualizar-error.json' ([ordered]@{ mensaje = $fallo; fecha = (Get-Date).ToString('dd/MM/yyyy HH:mm') })
    } else {
        Accesos
        Registro "Actualizado de $antes a $(Version-Actual)"
        Escribir-Json 'actualizado.json' ([ordered]@{ de = $antes; a = (Version-Actual); cambios = $cambios })
    }
    Reabrir-FullCowl      # siempre se vuelve a abrir (la nueva versión, o la de antes si algo falló)
    exit 0
}

# Sin parámetros (Actualizar.bat): con mensajes
if (-not $modoDescarga -and -not (Hay-Git)) {
    Write-Host 'Git no esta instalado. Instalalo con:'
    Write-Host '   winget install --id Git.Git -e --source winget'
    exit 1
}
# Si Full Cowl esta abierto (o se ha quedado colgado con un aviso), se cierra solo: antes habia que hacerlo a mano
$estabaAbierto = (@(Ventanas-FullCowlAbiertas).Count -gt 0)
if ($estabaAbierto) {
    Write-Host 'Full Cowl esta abierto: lo cierro para poder actualizar...'
    if (-not (Cerrar-FullCowl)) {
        Registro 'Actualizar.bat: no se pudo cerrar la ventana de Full Cowl.'
        Write-Host 'No he podido cerrar Full Cowl. Cierralo tu (tambien desde el Administrador de tareas) y repite.'
        exit 1
    }
}
if (Hay-TareasEnMarcha) { Write-Host 'AVISO: hay una tarea de Full Cowl en marcha (crear una base, por ejemplo). Si falla, esperate a que termine y repite.' }
Write-Host 'Buscando la ultima version...'
$fallo = Poner-AlDia
if ($fallo) {
    Registro "Actualizar.bat: $fallo"
    Write-Host ''; Write-Host $fallo
    if ($estabaAbierto) { Reabrir-FullCowl }
    exit 1
}
Write-Host ''
Write-Host 'Version instalada:'
if ($modoDescarga) { Write-Host "  $(Version-Actual)" }
else { $u = Git @('log', '-1', '"--format=  %cd  %s"', '--date=short') 15000; Write-Host $u.Salida }
Write-Host 'Actualizado.'
Write-Host 'Revisando los accesos directos...'
Accesos
Registro "Actualizar.bat: version $(Version-Actual)"
if ($estabaAbierto) { Write-Host 'Vuelvo a abrir Full Cowl...'; Reabrir-FullCowl }
exit 0
