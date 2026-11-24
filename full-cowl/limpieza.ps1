# =====================================================================
#  Limpiar espacio (ficha 30): qué ocupa cada base, máquina e instantánea, y borrado seguro.
#  Sin ventana: lo cargan la interfaz (interfaz\limpieza.ps1) y su hilo de trabajo.
#  Necesita comun.ps1 cargado antes.
#
#  REGLAS (no saltárselas al tocar este archivo):
#   1. Todo lo que se borra pasa por Borrar-ArchivoLimpieza o Borrar-CarpetaSinEnlaces, y las dos
#      comprueban antes Ruta-BorrableLimpieza: la ruta completa tiene que estar DENTRO de la carpeta de
#      máquinas, la de bases o las carpetas propias de Full Cowl (build, estado, output-*), sin «..»,
#      sin comodines y sin pasar por ningún enlace ni unión de directorios.
#   2. Nunca se sigue un enlace/unión al medir ni al borrar.
#   3. Cada borrado vuelve a comprobarlo TODO en el momento (no se fía de lo calculado minutos antes).
#   4. Máquinas y bases: «vmrun deleteVM» y después su carpeta; instantáneas: «vmrun deleteSnapshot».
#   5. Tamaños siempre en [double] o [long]; nunca [int].
# =====================================================================

$script:extVmware = '^\.(vmx|vmxf|vmsd|vmdk|nvram|vmem|vmss|vmsn|log|scoreboard|lck|iso|vmtm|dmp|hlog|mem|vmpl)$'

# ---------------------------------------------------------------- rutas
function Es-EnlaceRuta([string]$ruta) {
    # $true si es un enlace simbólico o una unión de directorios; $null si no se puede saber
    try { return [bool]([IO.File]::GetAttributes($ruta) -band [IO.FileAttributes]::ReparsePoint) } catch { return $null }
}

function Ruta-DentroDe([string]$ruta, [string]$raiz) {
    # $true solo si $ruta existe y está ESTRICTAMENTE dentro de $raiz, sin trucos:
    # nada de «..», comodines, prefijos de dispositivo, flujos alternativos (:) ni enlaces por el camino.
    if (-not $ruta -or -not $raiz) { return $false }
    if ($ruta -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    if ($ruta.IndexOfAny([char[]]@('*', '?', '<', '>', '|', '"')) -ge 0) { return $false }
    if ($ruta.StartsWith('\\?\') -or $ruta.StartsWith('\\.\')) { return $false }
    try {
        $lzC = [IO.Path]::GetFullPath($ruta).TrimEnd('\')
        $lzR = [IO.Path]::GetFullPath($raiz).TrimEnd('\')
    } catch { return $false }
    if ($lzR.Length -lt 2 -or $lzC.Length -le ($lzR.Length + 1)) { return $false }
    if (-not $lzC.StartsWith($lzR + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($lzC.Length -gt 2 -and $lzC.Substring(2).Contains(':')) { return $false }
    # Ningún tramo entre la raíz y el destino (incluido el destino) puede ser un enlace o una unión
    $lzAct = $lzR
    foreach ($lzTramo in $lzC.Substring($lzR.Length + 1).Split('\')) {
        if (-not $lzTramo) { return $false }
        $lzAct = $lzAct + '\' + $lzTramo
        $lzEnl = Es-EnlaceRuta $lzAct
        if ($null -eq $lzEnl -or $lzEnl) { return $false }      # no existe, no se puede leer o es un enlace
    }
    return $true
}

function Raices-Limpieza {
    # Carpetas dentro de las que se permite borrar. Patron = cómo tiene que llamarse el primer tramo.
    $lzRaices = @()
    if ($Config.CarpetaVMs) { $lzRaices += @{ Raiz = [string]$Config.CarpetaVMs; Patron = '' } }
    if ($Config.CarpetaBases) { $lzRaices += @{ Raiz = [string]$Config.CarpetaBases; Patron = '' } }
    $lzRaices += @{ Raiz = (Join-Path $dirComun 'build'); Patron = '' }
    $lzRaices += @{ Raiz = (Join-Path $dirComun 'estado'); Patron = '' }
    $lzRaices += @{ Raiz = [string]$dirComun; Patron = '^output-' }
    return $lzRaices
}

function Ruta-BorrableLimpieza([string]$ruta) {
    foreach ($lzRz in @(Raices-Limpieza)) {
        if (-not (Ruta-DentroDe $ruta $lzRz.Raiz)) { continue }
        if ($lzRz.Patron) {
            $lzResto = [IO.Path]::GetFullPath($ruta).TrimEnd('\').Substring([IO.Path]::GetFullPath($lzRz.Raiz).TrimEnd('\').Length + 1)
            if (($lzResto.Split('\')[0]) -notmatch $lzRz.Patron) { continue }
        }
        return $true
    }
    return $false
}

function Misma-Ruta([string]$a, [string]$b) {
    try { return [string]::Equals([IO.Path]::GetFullPath($a).TrimEnd('\'), [IO.Path]::GetFullPath($b).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) } catch { return $false }
}

function Es-HijaDirecta([string]$carpeta, [string]$raiz) {
    # $carpeta es una subcarpeta directa de $raiz (un solo nivel)
    if (-not $carpeta -or -not $raiz) { return $false }
    try { $lzPadre = Split-Path ([IO.Path]::GetFullPath($carpeta).TrimEnd('\')) } catch { return $false }
    return (Misma-Ruta $lzPadre $raiz)
}

function Carpeta-MaquinasFiable {
    # $false si la carpeta de máquinas es un sitio donde hay más cosas que máquinas (una unidad entera, la
    # carpeta del usuario, Windows, la del propio Full Cowl...). Entonces NO se ofrecen «carpetas sin .vmx».
    try { $lzV = [IO.Path]::GetFullPath([string]$Config.CarpetaVMs).TrimEnd('\') } catch { return $false }
    if (-not $lzV -or $lzV.Length -le 3) { return $false }
    if ([IO.Path]::GetPathRoot($lzV).TrimEnd('\') -eq $lzV) { return $false }
    $lzSensibles = @($env:USERPROFILE, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA,
                     (Split-Path $dirComun), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'))
    foreach ($lzS in $lzSensibles) {
        if (-not $lzS) { continue }
        try { $lzSf = [IO.Path]::GetFullPath($lzS).TrimEnd('\') } catch { continue }
        # La carpeta de máquinas no puede SER ni CONTENER una carpeta sensible
        if ([string]::Equals($lzSf, $lzV, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        if ($lzSf.StartsWith($lzV + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    foreach ($lzS in @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($lzS -and $lzV.StartsWith(([IO.Path]::GetFullPath($lzS).TrimEnd('\')) + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

function Es-CarpetaReservada([string]$ruta) {
    # $true si $ruta ES o CONTIENE una carpeta que Full Cowl necesita (bases, ISO, el propio programa, fichas)
    try { $lzRr = [IO.Path]::GetFullPath($ruta).TrimEnd('\') } catch { return $true }
    foreach ($lzNec in @($Config.CarpetaBases, $Config.CarpetaISOs, $Config.CarpetaFichas, $dirComun, (Split-Path $dirComun))) {
        if (-not $lzNec) { continue }
        try { $lzNf = [IO.Path]::GetFullPath([string]$lzNec).TrimEnd('\') } catch { continue }
        if ([string]::Equals($lzNf, $lzRr, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($lzNf.StartsWith($lzRr + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- medir (sin seguir enlaces)
function Medir-Carpeta([string]$carpeta) {
    # @{ Bytes [double]; Archivos [long]; Enlaces [bool]; Ajenos [long]; Vmx [long]; Vmdk [long]; Lck [bool] }
    $lzRes = @{ Bytes = [double]0; Archivos = [long]0; Enlaces = $false; Ajenos = [long]0; Vmx = [long]0; Vmdk = [long]0; Lck = $false }
    $lzPila = New-Object System.Collections.Generic.Stack[string]
    $lzPila.Push($carpeta)
    while ($lzPila.Count) {
        $lzDir = $lzPila.Pop()
        try {
            foreach ($lzEnt in (New-Object IO.DirectoryInfo($lzDir)).EnumerateFileSystemInfos()) {
                if ($lzEnt.Attributes -band [IO.FileAttributes]::ReparsePoint) { $lzRes.Enlaces = $true; continue }
                if ($lzEnt -is [IO.DirectoryInfo]) {
                    if ($lzEnt.Name -like '*.lck') { $lzRes.Lck = $true }
                    $lzPila.Push($lzEnt.FullName)
                    continue
                }
                $lzRes.Archivos++
                $lzRes.Bytes += [double]$lzEnt.Length
                $lzExt = $lzEnt.Extension.ToLower()
                if ($lzExt -eq '.vmx') { $lzRes.Vmx++ } elseif ($lzExt -eq '.vmdk') { $lzRes.Vmdk++ } elseif ($lzExt -eq '.lck') { $lzRes.Lck = $true }
                if ($lzExt -notmatch $script:extVmware -and $lzEnt.Name -ine 'vmtareas.iso') { $lzRes.Ajenos++ }
            }
        } catch {}
    }
    return $lzRes
}

function Peso-Instantaneas([string]$carpeta) {
    # Lo que pesan (aprox.) los archivos de instantáneas: discos -0000NN.vmdk, .vmsn y .vmem de instantánea
    $lzT = [double]0
    try {
        foreach ($lzF in (New-Object IO.DirectoryInfo($carpeta)).EnumerateFiles()) {
            if ($lzF.Name -match '-\d{6}(-s\d{3})?\.vmdk$|\.vmsn$|-Snapshot\d+\.vmem$') { $lzT += [double]$lzF.Length }
        }
    } catch {}
    return $lzT
}

# ---------------------------------------------------------------- instantáneas y dependencias
function Leer-InstantaneasDetalle([string]$vmx) {
    # Como Leer-Instantaneas, pero dice además si alguna máquina enlazada depende de cada una:
    # @{ Nombre; Clones [int]; RutasClones [string[]] }
    # Devuelve @{ Leido [bool]; Lista } (Leido = $false: el archivo existe pero no se pudo leer → «no se sabe»)
    $lzRes = @()
    $lzVmsd = [IO.Path]::ChangeExtension($vmx, 'vmsd')
    if (-not $vmx -or -not (Test-Path -LiteralPath $lzVmsd)) { return @{ Leido = $true; Lista = @() } }
    $lzLineas = @()
    try {
        $lzFs = New-Object IO.FileStream($lzVmsd, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $lzSr = New-Object IO.StreamReader($lzFs, [Text.Encoding]::UTF8); $lzLineas = @($lzSr.ReadToEnd() -split "`r?`n") } finally { $lzFs.Dispose() }
    } catch { return @{ Leido = $false; Lista = @() } }
    $lzPorNum = @{}
    foreach ($lzL in $lzLineas) {
        if ($lzL -match '^\s*snapshot(\d+)\.(displayName|numClones|clone\d+)\s*=\s*"(.*)"\s*$') {
            if (-not $lzPorNum.ContainsKey($Matches[1])) { $lzPorNum[$Matches[1]] = @{ Nombre = ''; Clones = 0; Rutas = @() } }
            $lzD = $lzPorNum[$Matches[1]]
            if ($Matches[2] -eq 'displayName') { $lzD.Nombre = ($Matches[3] -replace '\\(["\\])', '$1') }
            elseif ($Matches[2] -eq 'numClones') { $lzN = 0; [void][int]::TryParse($Matches[3], [ref]$lzN); if ($lzN -gt $lzD.Clones) { $lzD.Clones = $lzN } }
            else { $lzD.Rutas += $Matches[3]; if ($lzD.Clones -lt 1) { $lzD.Clones = 1 } }
        }
    }
    foreach ($lzNum in @($lzPorNum.Keys | Sort-Object { [int]$_ })) {
        $lzD = $lzPorNum[$lzNum]
        if ($lzD.Nombre) { $lzRes += [pscustomobject]@{ Nombre = [string]$lzD.Nombre; Clones = [int]$lzD.Clones; RutasClones = @($lzD.Rutas) } }
    }
    return @{ Leido = $true; Lista = @($lzRes) }
}

function Padres-DeMaquina([string]$carpeta) {
    # Carpetas AJENAS de las que dependen los discos de esta máquina (por parentFileNameHint).
    # @{ Carpetas [string[]] (rutas completas); Ilegibles [int] (discos que no se pudieron leer) }
    $lzRes = @{ Carpetas = @(); Ilegibles = 0 }
    try { $lzPropia = [IO.Path]::GetFullPath($carpeta).TrimEnd('\') } catch { $lzRes.Ilegibles = 1; return $lzRes }
    $lzDiscos = @()
    try { $lzDiscos = @((New-Object IO.DirectoryInfo($lzPropia)).EnumerateFiles('*.vmdk')) } catch { $lzRes.Ilegibles = 1; return $lzRes }
    foreach ($lzDk in $lzDiscos) {
        if ($lzDk.Name -match '-(s|f)\d{3}\.vmdk$|-flat\.vmdk$|-delta\.vmdk$|-ctk\.vmdk$') { continue }   # trozos de datos: no llevan descriptor
        $lzHint = Leer-PadreVmdk $lzDk.FullName
        if ($null -eq $lzHint) { $lzRes.Ilegibles++; continue }
        if (-not $lzHint) { continue }
        try {
            $lzRuta = $(if ([IO.Path]::IsPathRooted($lzHint)) { $lzHint } else { Join-Path $lzPropia $lzHint })
            $lzDirPadre = Split-Path ([IO.Path]::GetFullPath($lzRuta))
            if (-not (Misma-Ruta $lzDirPadre $lzPropia)) { $lzRes.Carpetas += $lzDirPadre.TrimEnd('\') }
        } catch { $lzRes.Ilegibles++ }
    }
    $lzRes.Carpetas = @($lzRes.Carpetas | Select-Object -Unique)
    return $lzRes
}

function Mapa-Dependencias {
    # Una fila por máquina conocida (las de la carpeta de máquinas, las de la biblioteca de VMware y las bases):
    # @{ Nombre; Vmx; Carpeta; EsBase; Externa; Padres [string[]]; Ilegibles; MarcaBase; MarcaCopia }
    $lzFilas = @()
    foreach ($lzC in @(Leer-Clones)) {
        $lzP = Padres-DeMaquina $lzC.Carpeta
        $lzFilas += @{ Nombre = [string]$lzC.Nombre; Vmx = [string]$lzC.Vmx; Carpeta = [string]$lzC.Carpeta; EsBase = $false; Externa = [bool]$lzC.Externa
                       Padres = @($lzP.Carpetas); Ilegibles = [int]$lzP.Ilegibles
                       MarcaBase = [string](Leer-ValorVmx $lzC.Vmx 'guestinfo.vmtareas.base'); MarcaCopia = [string](Leer-ValorVmx $lzC.Vmx 'guestinfo.vmtareas.copia') }
    }
    foreach ($lzB in @(Obtener-Bases)) {
        $lzCarp = Split-Path $lzB.Vmx
        $lzP = Padres-DeMaquina $lzCarp
        $lzFilas += @{ Nombre = [string]$lzB.Nombre; Vmx = [string]$lzB.Vmx; Carpeta = [string]$lzCarp; EsBase = $true; Externa = $false
                       Padres = @($lzP.Carpetas); Ilegibles = [int]$lzP.Ilegibles; MarcaBase = ''; MarcaCopia = '' }
    }
    return $lzFilas
}

function Dependientes-De([string]$carpeta, [string]$vmx, [bool]$esBase, $mapa) {
    # Quién depende de la máquina/base de $carpeta. @{ Nombres [string[]]; Dudosas [string[]] }
    #  - por los discos: algún disco suyo tiene el padre dentro de $carpeta
    #  - por la marca de Full Cowl (solo bases): guestinfo.vmtareas.base = nombre de la base y copia distinta de «full»
    #  - por el .vmsd de la propia máquina: lista de clones enlazados que siguen existiendo
    #  Dudosas: máquinas cuyos discos no se pudieron leer (encendidas/en uso) y que no tienen marca que lo aclare
    $lzNombres = @(); $lzDudosas = @()
    try { $lzCf = [IO.Path]::GetFullPath($carpeta).TrimEnd('\') } catch { return @{ Nombres = @(); Dudosas = @('(ruta ilegible)') } }
    $lzNombreBase = Split-Path $lzCf -Leaf
    foreach ($lzM in @($mapa)) {
        if (Misma-Ruta $lzM.Carpeta $lzCf) { continue }
        $lzDepende = $false
        foreach ($lzPd in @($lzM.Padres)) {
            if ((Misma-Ruta $lzPd $lzCf) -or ([string]$lzPd).StartsWith($lzCf + '\', [StringComparison]::OrdinalIgnoreCase)) { $lzDepende = $true; break }
        }
        if (-not $lzDepende -and $esBase -and $lzM.MarcaBase -and ($lzM.MarcaBase -ieq $lzNombreBase) -and ($lzM.MarcaCopia -ine 'full')) { $lzDepende = $true }
        if ($lzDepende) { $lzNombres += [string]$lzM.Nombre; continue }
        if ($lzM.Ilegibles -gt 0 -and -not ($lzM.MarcaBase -and $lzM.MarcaCopia)) { $lzDudosas += [string]$lzM.Nombre }
    }
    $lzSnaps = Leer-InstantaneasDetalle $vmx
    if (-not $lzSnaps.Leido) { $lzDudosas += '(no se pudo leer su lista de instantáneas)' }
    else {
        foreach ($lzSn in @($lzSnaps.Lista)) {
            foreach ($lzRc in @($lzSn.RutasClones)) {
                if (-not $lzRc) { continue }
                try {
                    $lzRcFull = $(if ([IO.Path]::IsPathRooted($lzRc)) { $lzRc } else { Join-Path $lzCf $lzRc })
                    if ((Test-Path -LiteralPath $lzRcFull) -and -not (Misma-Ruta (Split-Path $lzRcFull) $lzCf)) {
                        $lzNom = Split-Path (Split-Path $lzRcFull) -Leaf
                        if ($lzNombres -notcontains $lzNom) { $lzNombres += $lzNom }
                    }
                } catch {}
            }
        }
    }
    return @{ Nombres = @($lzNombres | Select-Object -Unique); Dudosas = @($lzDudosas | Select-Object -Unique) }
}

function Hay-CreacionEnCurso {
    # Alguna base se está creando ahora (Packer trabajando en build\ y en la carpeta de bases)
    try {
        foreach ($lzJ in @(Get-ChildItem -LiteralPath (Join-Path $dirComun 'estado') -Filter *.json -File -ErrorAction SilentlyContinue)) {
            try { if (([IO.File]::ReadAllText($lzJ.FullName) | ConvertFrom-Json).estado -eq 'curso') { return $true } } catch {}
        }
    } catch {}
    return $false
}

function Maquina-EnUso([string]$vmx, $encendidas) {
    # Encendida (según vmrun) o con candados de VMware en su carpeta (abierta, encendida o a medio usar)
    if ($vmx -and (@($encendidas) -contains $vmx.ToLower())) { return $true }
    try {
        foreach ($lzE in (New-Object IO.DirectoryInfo((Split-Path $vmx))).EnumerateFileSystemInfos('*.lck')) { return $true }
    } catch { return $true }
    return $false
}

function Instantaneas-Borrables($snaps, [bool]$esBase) {
    # Nombres que se pueden borrar: nunca «base», nunca el estado inicial del laboratorio, nunca las que tienen
    # máquinas enlazadas colgando, nunca las de una base, ni nombres repetidos o con comillas (no se podrían indicar bien)
    if ($esBase -or $null -eq $snaps -or -not @($snaps).Count) { return @() }
    $lzOk = @()
    $lzProt = @('base', (Nombre-EstadoInicial))
    $lzGrupos = @($snaps | Group-Object Nombre)
    foreach ($lzG in $lzGrupos) {
        if ($lzG.Count -ne 1) { continue }
        $lzS = $lzG.Group[0]
        if ($lzProt -contains ([string]$lzS.Nombre).ToLower()) { continue }
        if ($lzS.Clones -gt 0) { continue }
        if (([string]$lzS.Nombre) -match '["`\r\n]' -or -not ([string]$lzS.Nombre).Trim()) { continue }
        $lzOk += [string]$lzS.Nombre
    }
    return $lzOk
}

# ---------------------------------------------------------------- análisis (lo llama el hilo de trabajo)
function Nuevo-ElementoLimpieza([string]$tipo, [string]$id, [string]$nombre) {
    return @{ Tipo = $tipo; Id = $id; Nombre = $nombre; Sub = ''; Tamano = [double]0; Aprox = $false; Bloqueo = ''; Necesaria = $false
              Lab = ''; Estado = ''; Etiqueta = ''; Fecha = $null; Vmx = ''; Carpeta = ''; Ruta = ''; Clase = ''; Snaps = @(); Rutas = @()
              Dependientes = @(); AutoMarcar = $false; EnRestos = $false; Familia = ''; Base = '' }
}

function Analizar-Espacio($progreso) {
    # Rellena $progreso (tabla sincronizada): Fase, Total, Hecho, Elementos (lista), Disco, Fin, Error
    $progreso.Fase = 'Mirando las máquinas…'
    $lzVmrun = Buscar-Vmrun -Silencioso
    $lzEnc = @(Maquinas-Encendidas $lzVmrun)
    $lzMaqs = @(Leer-Maquinas)
    $lzMapa = @(Mapa-Dependencias)
    $lzCreando = Hay-CreacionEnCurso
    $lzFiable = Carpeta-MaquinasFiable
    $lzPropias = @($lzMaqs | Where-Object { -not $_.Externa })
    $lzHuerfanas = @()
    foreach ($lzRaizH in @($Config.CarpetaVMs, $Config.CarpetaBases)) {
        if (-not $lzRaizH -or -not (Test-Path -LiteralPath $lzRaizH)) { continue }
        foreach ($lzDh in @(Get-ChildItem -LiteralPath $lzRaizH -Directory -Force -ErrorAction SilentlyContinue)) {
            if ((Misma-Ruta $lzRaizH $Config.CarpetaVMs) -and $lzDh.Name.StartsWith('_')) { continue }
            if (@($lzPropias | Where-Object { Misma-Ruta $_.Carpeta $lzDh.FullName }).Count) { continue }
            if (Es-CarpetaReservada $lzDh.FullName) { continue }
            $lzHuerfanas += $lzDh
        }
    }
    $progreso.Total = $lzPropias.Count + $lzHuerfanas.Count + 2
    $progreso.Hecho = 0

    # Discos y carpetas a los que apunta cualquier máquina conocida: una carpeta así nunca es un resto
    $lzEnUso = @()
    foreach ($lzMp in $lzMapa) { $lzEnUso += @($lzMp.Padres) }
    $lzVmxSueltos = @()
    if ($Config.CarpetaVMs -and (Test-Path -LiteralPath $Config.CarpetaVMs)) { $lzVmxSueltos = @(Get-ChildItem -LiteralPath $Config.CarpetaVMs -Filter *.vmx -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    foreach ($lzVx in (@($lzMapa | ForEach-Object { $_.Vmx }) + $lzVmxSueltos)) {
        try {
            foreach ($lzLn in @(Leer-Vmx $lzVx)) {
                if ($lzLn -match '^\s*[A-Za-z]+\d+:\d+\.fileName\s*=\s*"(.+)"') {
                    $lzArch = $Matches[1]
                    if (-not [IO.Path]::IsPathRooted($lzArch)) { $lzArch = Join-Path (Split-Path $lzVx) $lzArch }
                    try { $lzEnUso += (Split-Path ([IO.Path]::GetFullPath($lzArch))).TrimEnd('\') } catch {}
                }
            }
        } catch {}
    }
    $lzEnUso = @($lzEnUso | Where-Object { $_ } | Select-Object -Unique)

    $lzTotBases = [double]0; $lzTotMaq = [double]0; $lzTotSnap = [double]0
    foreach ($lzM in $lzPropias) {
        $progreso.Fase = "Midiendo $($lzM.Nombre)…"
        $lzEsBase = [bool]$lzM.EsBase
        $lzMed = Medir-Carpeta $lzM.Carpeta
        $lzTam = $(if ($lzEsBase -or (Carpeta-BorrableSegura $lzM.Carpeta)) { [double]$lzMed.Bytes } else { [double](Tamano-Maquina $lzM.Vmx $lzM.Carpeta) })
        $lzUso = Maquina-EnUso $lzM.Vmx $lzEnc
        $lzDep = Dependientes-De $lzM.Carpeta $lzM.Vmx $lzEsBase $lzMapa
        $lzEl = Nuevo-ElementoLimpieza $(if ($lzEsBase) { 'base' } else { 'maquina' }) ($(if ($lzEsBase) { 'b|' } else { 'm|' }) + $lzM.Vmx.ToLower()) ([string]$lzM.Nombre)
        $lzEl.Tamano = $lzTam; $lzEl.Vmx = [string]$lzM.Vmx; $lzEl.Carpeta = [string]$lzM.Carpeta; $lzEl.Fecha = $lzM.Modificada
        $lzEl.Familia = [string]$lzM.Familia; $lzEl.Lab = [string]$lzM.Lab; $lzEl.Base = [string]$lzM.Base
        $lzEl.Estado = $(if ($lzUso) { $(if ($lzEnc -contains $lzM.Vmx.ToLower()) { 'Encendida' } else { 'En uso' }) } else { [string]$lzM.Estado })
        $lzEl.Dependientes = @($lzDep.Nombres)
        if ($lzEsBase) {
            $lzTotBases += $lzTam
            $lzEl.Sub = $(if ($lzDep.Nombres.Count) { "$($lzDep.Nombres.Count) $(if ($lzDep.Nombres.Count -eq 1) { 'máquina depende' } else { 'máquinas dependen' }) de ella" } else { 'Ninguna máquina depende de ella' })
            if ($lzDep.Nombres.Count) { $lzEl.Bloqueo = "Primero borra o convierte en completas estas $($lzDep.Nombres.Count) máquinas: $($lzDep.Nombres -join ', ')" }
            elseif ($lzDep.Dudosas.Count) { $lzEl.Bloqueo = "No he podido comprobar si dependen de ella: $($lzDep.Dudosas -join ', '). Apágalas y pulsa «Volver a calcular»." }
            elseif ($lzUso) { $lzEl.Bloqueo = 'Está abierta o encendida en VMware. Ciérrala primero.' }
            elseif ($lzCreando) { $lzEl.Bloqueo = 'Se está creando una base ahora mismo. Espera a que termine.' }
            elseif (-not (Es-HijaDirecta $lzM.Carpeta $Config.CarpetaBases)) { $lzEl.Bloqueo = 'No está en la carpeta de bases.' }
            elseif ($lzMed.Enlaces) { $lzEl.Bloqueo = 'Su carpeta contiene un enlace a otra carpeta. Bórrala a mano si de verdad quieres.' }
        } else {
            $lzTotMaq += $lzTam
            $lzEl.Etiqueta = $(if ($lzM.Desechable) { 'Desechable' } elseif ($lzM.Tipo -eq 'Importada') { 'Importada' } elseif ($lzM.Tipo) { 'FC' } else { '' })
            $lzEl.Sub = $(if ($lzM.Base) { "Base: $($lzM.Base)" } else { 'Sin base de Full Cowl' })
            if ($lzUso) { $lzEl.Bloqueo = $(if ($lzEl.Estado -eq 'Encendida') { 'Apágala primero.' } else { 'Está abierta en VMware o en uso. Ciérrala primero.' }) }
            elseif ($lzDep.Nombres.Count) { $lzEl.Bloqueo = "Otras máquinas enlazadas dependen de ella: $($lzDep.Nombres -join ', ')" }
            elseif (-not (Es-HijaDirecta $lzM.Carpeta $Config.CarpetaVMs)) { $lzEl.Bloqueo = 'No está en una carpeta propia dentro de la carpeta de máquinas.' }
            elseif (-not (Carpeta-BorrableSegura $lzM.Carpeta)) { $lzEl.Bloqueo = 'Su carpeta tiene más de una máquina u otros archivos. Bórrala desde Mis máquinas.' }
            elseif ($lzMed.Enlaces) { $lzEl.Bloqueo = 'Su carpeta contiene un enlace a otra carpeta. Bórrala a mano si de verdad quieres.' }
            elseif (-not $lzFiable -and $lzMed.Ajenos -gt 0) { $lzEl.Bloqueo = 'Su carpeta tiene archivos que no son de VMware y la carpeta de máquinas no es solo de máquinas. Bórrala a mano.' }
            # Desechable apagada que nadie ha borrado: también sale en Restos
            if ($lzM.Desechable -and -not $lzEl.Bloqueo) { $lzEl.EnRestos = $true; $lzEl.AutoMarcar = $true; $lzEl.Clase = 'desechable' }
        }
        [void]$progreso.Elementos.Add($lzEl)

        # Instantáneas de esta máquina
        $lzSnapsLeidas = Leer-InstantaneasDetalle $lzM.Vmx
        $lzSnaps = @($lzSnapsLeidas.Lista)
        if ($lzSnapsLeidas.Leido -and $lzSnaps.Count) {
            $lzPeso = Peso-Instantaneas $lzM.Carpeta
            $lzTotSnap += $lzPeso
            $lzBorr = @(Instantaneas-Borrables $lzSnaps $lzEsBase)
            $lzNec = @($lzSnaps | Where-Object { $lzBorr -notcontains [string]$_.Nombre } | ForEach-Object {
                $(if ([string]$_.Nombre -ceq (Nombre-EstadoInicial)) { 'Estado inicial del laboratorio' } else { [string]$_.Nombre }) })
            $lzSn = Nuevo-ElementoLimpieza 'instantanea' ('s|' + $lzM.Vmx.ToLower()) ([string]$lzM.Nombre)
            $lzSn.Vmx = [string]$lzM.Vmx; $lzSn.Carpeta = [string]$lzM.Carpeta; $lzSn.Tamano = $lzPeso; $lzSn.Aprox = $true; $lzSn.Lab = [string]$lzM.Lab
            $lzSn.Snaps = @($lzBorr); $lzSn.Familia = [string]$lzM.Familia
            $lzPartes = @()
            if ($lzBorr.Count) { $lzPartes += "Se pueden borrar: $($lzBorr -join ', ')" }
            if ($lzNec.Count) { $lzPartes += "Necesarias (no se tocan): $($lzNec -join ', ')" }
            $lzSn.Sub = $lzPartes -join ' · '
            if (-not $lzBorr.Count) { $lzSn.Necesaria = $true; $lzSn.Bloqueo = $(if ($lzEsBase) { 'La instantánea «base» es de la que salen las máquinas enlazadas: no se borra nunca.' } else { 'Solo tiene instantáneas necesarias. El estado inicial se quita desde Laboratorio → ··· → Quitar el estado inicial.' }) }
            elseif ($lzUso) { $lzSn.Bloqueo = 'Apaga la máquina (y cierra su pestaña en VMware) para borrar sus instantáneas.' }
            elseif (-not $lzVmrun) { $lzSn.Bloqueo = 'No encuentro VMware (vmrun) para borrar instantáneas.' }
            [void]$progreso.Elementos.Add($lzSn)
        }
        $progreso.Hecho = [int]$progreso.Hecho + 1
    }

    # ---- Restos
    # (1) Carpetas sin ningún .vmx dentro de la carpeta de máquinas o de la de bases
    foreach ($lzDh in $lzHuerfanas) {
        $progreso.Fase = "Mirando $($lzDh.Name)…"
        $progreso.Hecho = [int]$progreso.Hecho + 1
        if ($lzDh.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }       # un enlace: ni se mira
        $lzMed = Medir-Carpeta $lzDh.FullName
        if ($lzMed.Vmx -gt 0) { continue }                                              # tiene un .vmx en algún nivel: no es un resto
        $lzEnBases = Es-HijaDirecta $lzDh.FullName $Config.CarpetaBases
        $lzR = Nuevo-ElementoLimpieza 'resto' ('r|carpeta|' + $lzDh.FullName.ToLower()) $lzDh.Name
        $lzR.Clase = 'carpeta'; $lzR.Ruta = $lzDh.FullName; $lzR.Tamano = [double]$lzMed.Bytes; $lzR.Fecha = $lzDh.LastWriteTime; $lzR.EnRestos = $true
        $lzR.Sub = $(if ($lzMed.Archivos -eq 0) { 'Carpeta vacía' } else { "Carpeta sin máquina dentro ($($lzMed.Archivos) archivos)" }) + $(if ($lzEnBases) { ' · en la carpeta de bases' } else { '' })
        $lzReferida = @($lzEnUso | Where-Object { (Misma-Ruta $_ $lzDh.FullName) -or ([string]$_).StartsWith($lzDh.FullName.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }).Count
        if (-not $lzFiable) { $lzR.Bloqueo = 'La carpeta de máquinas es una carpeta con más cosas (una unidad entera o una carpeta personal): aquí no se borran carpetas sueltas.' }
        elseif ($lzReferida) { $lzR.Bloqueo = 'Alguna máquina usa un disco o un CD que está aquí.' }
        elseif ($lzMed.Enlaces) { $lzR.Bloqueo = 'Contiene un enlace a otra carpeta.' }
        elseif ($lzMed.Lck) { $lzR.Bloqueo = 'VMware la tiene en uso (hay candados .lck).' }
        elseif ($lzMed.Ajenos -gt 0) { $lzR.Bloqueo = "Tiene $($lzMed.Ajenos) archivos que no son de VMware: revísala a mano." }
        elseif ($lzEnBases -and $lzCreando) { $lzR.Bloqueo = 'Se está creando una base ahora mismo.' }
        elseif ($lzMed.Vmdk -gt 0) { $lzR.Sub += ' · contiene discos virtuales'; $lzR.AutoMarcar = $false }
        else { $lzR.AutoMarcar = $true }
        [void]$progreso.Elementos.Add($lzR)
    }
    # (2) Restos de crear bases: build\<Clave> y output-*
    $progreso.Fase = 'Buscando restos…'
    $lzDirsBuild = @()
    $lzBuild = Join-Path $dirComun 'build'
    if (Test-Path -LiteralPath $lzBuild) { $lzDirsBuild += @(Get-ChildItem -LiteralPath $lzBuild -Directory -Force -ErrorAction SilentlyContinue) }
    $lzDirsBuild += @(Get-ChildItem -LiteralPath $dirComun -Directory -Filter 'output-*' -Force -ErrorAction SilentlyContinue)
    foreach ($lzDb in $lzDirsBuild) {
        if ($lzDb.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $lzMed = Medir-Carpeta $lzDb.FullName
        $lzR = Nuevo-ElementoLimpieza 'resto' ('r|build|' + $lzDb.FullName.ToLower()) $lzDb.Name
        $lzR.Clase = 'build'; $lzR.Ruta = $lzDb.FullName; $lzR.Tamano = [double]$lzMed.Bytes; $lzR.Fecha = $lzDb.LastWriteTime; $lzR.EnRestos = $true
        $lzR.Sub = 'Restos de crear una base'
        if ($lzCreando) { $lzR.Bloqueo = 'Se está creando una base ahora mismo.' }
        elseif ($lzMed.Enlaces) { $lzR.Bloqueo = 'Contiene un enlace a otra carpeta.' }
        else { $lzR.AutoMarcar = $true }
        [void]$progreso.Elementos.Add($lzR)
    }
    # (3) CD de configuración (vmtareas.iso) de máquinas que ya terminaron de configurarse
    $lzProg = $null
    try { $lzProg = ([IO.File]::ReadAllText((Join-Path $dirComun 'estado\progreso.json')) | ConvertFrom-Json).maquinas } catch {}
    foreach ($lzM in @($lzPropias | Where-Object { -not $_.EsBase })) {
        $lzIso = Join-Path $lzM.Carpeta 'vmtareas.iso'
        if (-not (Test-Path -LiteralPath $lzIso -PathType Leaf)) { continue }
        if (Maquina-EnUso $lzM.Vmx $lzEnc) { continue }
        if (-not (Cd-YaUsado $lzM.Vmx $lzIso $lzProg)) { continue }
        $lzR = Nuevo-ElementoLimpieza 'resto' ('r|cd|' + $lzIso.ToLower()) "CD de configuración de $($lzM.Nombre)"
        $lzR.Clase = 'cd'; $lzR.Ruta = $lzIso; $lzR.Vmx = [string]$lzM.Vmx; $lzR.Carpeta = [string]$lzM.Carpeta; $lzR.EnRestos = $true; $lzR.AutoMarcar = $true
        try { $lzFi = New-Object IO.FileInfo($lzIso); $lzR.Tamano = [double]$lzFi.Length; $lzR.Fecha = $lzFi.LastWriteTime } catch {}
        $lzR.Sub = 'La máquina ya está configurada: el CD no hace falta'
        [void]$progreso.Elementos.Add($lzR)
    }
    # (4) Registros y candados de hace más de 30 días (solo dentro de las carpetas de Full Cowl)
    $lzViejos = @(Buscar-ViejosLimpieza $lzPropias $lzEnc)
    if ($lzViejos.Count) {
        $lzR = Nuevo-ElementoLimpieza 'resto' 'r|viejos' 'Registros y candados antiguos'
        $lzR.Clase = 'viejos'; $lzR.EnRestos = $true; $lzR.AutoMarcar = $true
        $lzR.Rutas = @($lzViejos | ForEach-Object { $_.Ruta })
        $lzR.Tamano = [double](($lzViejos | Measure-Object Bytes -Sum).Sum)
        $lzR.Sub = "$($lzViejos.Count) archivos de hace más de 30 días (registros de VMware y de Full Cowl, candados que se quedaron)"
        [void]$progreso.Elementos.Add($lzR)
    }
    $progreso.Hecho = [int]$progreso.Hecho + 1

    # ---- Disco e ISO
    $progreso.Fase = 'Leyendo el disco…'
    $lzDisco = @{ Unidad = ''; Total = [double]0; Libre = [double]0; Bases = $lzTotBases; Maquinas = $lzTotMaq; Instantaneas = $lzTotSnap; Isos = [double]0; Fiable = [bool]$lzFiable; SinVmrun = (-not $lzVmrun) }
    try {
        $lzRaizD = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath([string]$Config.CarpetaVMs))
        $lzUni = New-Object IO.DriveInfo($lzRaizD)
        $lzDisco.Unidad = $lzRaizD.TrimEnd('\'); $lzDisco.Total = [double]$lzUni.TotalSize; $lzDisco.Libre = [double]$lzUni.AvailableFreeSpace
    } catch {}
    try {
        if ($Config.CarpetaISOs -and (Test-Path -LiteralPath $Config.CarpetaISOs)) {
            foreach ($lzI in (New-Object IO.DirectoryInfo([string]$Config.CarpetaISOs)).EnumerateFiles('*.iso')) { $lzDisco.Isos += [double]$lzI.Length }
        }
    } catch {}
    $progreso.Disco = $lzDisco
    $progreso.Hecho = [int]$progreso.Total
    $progreso.Fase = ''
}

function Cd-YaUsado([string]$vmx, [string]$iso, $progresoMaquinas) {
    # $true si la máquina ya terminó de configurarse: lo dice el vigilante (estado\progreso.json), o el CD tiene
    # más de 30 días y la máquina ha arrancado después de crearse
    try {
        if ($progresoMaquinas) {
            $lzP = $progresoMaquinas.PSObject.Properties[$vmx.ToLower()]
            if ($lzP -and [string]$lzP.Value.estado -eq 'ok') { return $true }
            if ($lzP) { return $false }                               # sigue configurándose o terminó con fallos: se deja
        }
        $lzIsoF = New-Object IO.FileInfo($iso)
        $lzLog = Join-Path (Split-Path $vmx) 'vmware.log'
        if ($lzIsoF.LastWriteTime -lt (Get-Date).AddDays(-30) -and (Test-Path -LiteralPath $lzLog) -and
            (New-Object IO.FileInfo($lzLog)).LastWriteTime -gt $lzIsoF.LastWriteTime.AddMinutes(30)) { return $true }
    } catch {}
    return $false
}

function Es-ViejoLimpieza($info, [string]$clase) {
    # Reglas de «registro o candado antiguo». $clase: 'maquina' (carpeta de una máquina o base apagada) o 'estado'
    if ($null -eq $info) { return $false }
    if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if ($info.LastWriteTime -gt (Get-Date).AddDays(-30)) { return $false }
    if ($clase -eq 'estado') { return (($info -is [IO.FileInfo]) -and $info.Name -match '\.log$') }
    if ($info -is [IO.FileInfo]) { return ($info.Name -match '^vmware-\d+\.log$|^vmware-vmx.*\.log$|^mksSandbox.*\.log$|\.dmp$|\.lck$') }
    return ($info.Name -match '\.lck$')
}

function Buscar-ViejosLimpieza($maquinas, $encendidas) {
    # @{ Ruta; Bytes; Clase } de registros (.log, .dmp) y candados (.lck) de más de 30 días
    $lzRes = @()
    foreach ($lzM in @($maquinas)) {
        if (@($encendidas) -contains ([string]$lzM.Vmx).ToLower()) { continue }
        try {
            $lzInfos = @((New-Object IO.DirectoryInfo([string]$lzM.Carpeta)).EnumerateFileSystemInfos())
            # Un candado reciente = la máquina está en uso: no se toca nada suyo
            if (@($lzInfos | Where-Object { $_.Name -like '*.lck' -and $_.LastWriteTime -gt (Get-Date).AddDays(-30) }).Count) { continue }
            foreach ($lzI in $lzInfos) {
                if (-not (Es-ViejoLimpieza $lzI 'maquina')) { continue }
                $lzB = [double]0
                if ($lzI -is [IO.FileInfo]) { $lzB = [double]$lzI.Length } else { $lzB = [double](Medir-Carpeta $lzI.FullName).Bytes }
                $lzRes += @{ Ruta = $lzI.FullName; Bytes = $lzB; Clase = 'maquina' }
            }
        } catch {}
    }
    try {
        $lzEst = Join-Path $dirComun 'estado'
        if (Test-Path -LiteralPath $lzEst) {
            foreach ($lzI in (New-Object IO.DirectoryInfo($lzEst)).EnumerateFiles('*.log')) {
                if (Es-ViejoLimpieza $lzI 'estado') { $lzRes += @{ Ruta = $lzI.FullName; Bytes = [double]$lzI.Length; Clase = 'estado' } }
            }
        }
    } catch {}
    return $lzRes
}

# ---------------------------------------------------------------- borrado (único sitio que borra)
function Borrar-ArchivoLimpieza([string]$ruta) {
    # Borra UN archivo si está dentro de lo permitido. Devuelve '' o el motivo por el que no se pudo
    if (-not (Ruta-BorrableLimpieza $ruta)) { return 'La ruta no está dentro de las carpetas de Full Cowl.' }
    try {
        $lzAt = [IO.File]::GetAttributes($ruta)
        if ($lzAt -band [IO.FileAttributes]::Directory) { return 'No es un archivo.' }
        if ($lzAt -band [IO.FileAttributes]::ReadOnly) { [IO.File]::SetAttributes($ruta, [IO.FileAttributes]::Normal) }
        [IO.File]::Delete($ruta)
        return ''
    } catch { return [string]$_.Exception.Message }
}

function Borrar-CarpetaSinEnlaces([string]$carpeta) {
    # Borra una carpeta entera SIN seguir enlaces. Si dentro hay algún enlace o unión, no borra nada.
    # Devuelve '' o el motivo.
    if (-not (Ruta-BorrableLimpieza $carpeta)) { return 'La ruta no está dentro de las carpetas de Full Cowl.' }
    try {
        $lzRaizB = [IO.Path]::GetFullPath($carpeta).TrimEnd('\')
        if (-not ([IO.File]::GetAttributes($lzRaizB) -band [IO.FileAttributes]::Directory)) { return 'No es una carpeta.' }
    } catch { return 'Ruta no válida.' }
    # 1) Recorrido previo: lista de carpetas (de fuera adentro) y comprobación de enlaces
    $lzDirs = New-Object System.Collections.Generic.List[string]
    $lzPila = New-Object System.Collections.Generic.Stack[string]
    $lzPila.Push($lzRaizB)
    try {
        while ($lzPila.Count) {
            $lzD = $lzPila.Pop()
            $lzDirs.Add($lzD)
            foreach ($lzE in (New-Object IO.DirectoryInfo($lzD)).EnumerateFileSystemInfos()) {
                if ($lzE.Attributes -band [IO.FileAttributes]::ReparsePoint) { return "Contiene un enlace a otra carpeta ($($lzE.Name)): no se borra." }
                if ($lzE -is [IO.DirectoryInfo]) { $lzPila.Push($lzE.FullName) }
            }
        }
    } catch { return [string]$_.Exception.Message }
    # 2) Borrado, de dentro afuera. Cada carpeta se borra vacía (sin «recursivo»): si entre tanto apareciera
    #    un enlace, Delete solo quitaría el enlace, nunca lo de detrás.
    $lzFallo = ''
    for ($lzI = $lzDirs.Count - 1; $lzI -ge 0; $lzI--) {
        $lzD = $lzDirs[$lzI]
        try {
            if (-not ($lzD -eq $lzRaizB -or $lzD.StartsWith($lzRaizB + '\', [StringComparison]::OrdinalIgnoreCase))) { return 'Ruta inesperada: se para.' }
            foreach ($lzF in (New-Object IO.DirectoryInfo($lzD)).EnumerateFiles()) {
                if ($lzF.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 'Apareció un enlace: se para.' }
                try {
                    if ($lzF.Attributes -band [IO.FileAttributes]::ReadOnly) { $lzF.Attributes = [IO.FileAttributes]::Normal }
                    $lzF.Delete()
                } catch { if (-not $lzFallo) { $lzFallo = "$($lzF.Name): $($_.Exception.Message)" } }
            }
            [IO.Directory]::Delete($lzD, $false)
        } catch { if (-not $lzFallo) { $lzFallo = [string]$_.Exception.Message } }
    }
    if (Test-Path -LiteralPath $lzRaizB) { return $(if ($lzFallo) { $lzFallo } else { 'No se pudo borrar del todo (¿abierta en VMware?).' }) }
    return ''
}

function Borrar-CarpetaConReintentos([string]$carpeta) {
    $lzMotivo = ''
    for ($lzI = 0; $lzI -lt 5; $lzI++) {
        if (-not (Test-Path -LiteralPath $carpeta)) { return '' }
        $lzMotivo = Borrar-CarpetaSinEnlaces $carpeta
        if (-not $lzMotivo) { return '' }
        if ($lzMotivo -match 'enlace|no está dentro|Ruta') { return $lzMotivo }     # no es cuestión de esperar
        Start-Sleep -Milliseconds 900
    }
    return $lzMotivo
}

function Borrar-ElementoLimpieza($el) {
    # Borra un elemento del análisis volviendo a comprobarlo todo AHORA. Devuelve @{ Ok; Motivo; Liberado [double] }
    $lzRes = @{ Ok = $false; Motivo = ''; Liberado = [double]0 }
    $lzVmrun = Buscar-Vmrun -Silencioso
    # Regla de oro (ficha 34): si VMware no contesta no se sabe qué está encendido, y entonces NO se borra nada
    $lzEstadoEnc = Leer-Encendidas $lzVmrun
    if (-not $lzEstadoEnc.Sabido) { $lzRes.Motivo = 'VMware no contesta y no se puede saber si hay máquinas encendidas. No se ha borrado: espera un poco y vuelve a intentarlo.'; return $lzRes }
    $lzEnc = @($lzEstadoEnc.Lista)
    try {
        switch ([string]$el.Tipo) {
            'maquina' {
                $lzVmx = [string]$el.Vmx; $lzCarp = Split-Path $lzVmx
                if (-not (Test-Path -LiteralPath $lzVmx)) { $lzRes.Motivo = 'Ya no existe.'; break }
                $lzClon = @(Leer-Clones | Where-Object { -not $_.Externa -and (Misma-Ruta $_.Vmx $lzVmx) }) | Select-Object -First 1
                if (-not $lzClon) { $lzRes.Motivo = 'Ya no es una máquina de la carpeta de máquinas.'; break }
                if (-not (Es-HijaDirecta $lzCarp $Config.CarpetaVMs) -or (Split-Path $lzCarp -Leaf).StartsWith('_')) { $lzRes.Motivo = 'No está en una carpeta propia de la carpeta de máquinas.'; break }
                if ($Config.CarpetaBases -and ((Misma-Ruta $lzCarp $Config.CarpetaBases) -or (Ruta-DentroDe $lzCarp $Config.CarpetaBases))) { $lzRes.Motivo = 'Es una base.'; break }
                if (-not (Ruta-BorrableLimpieza $lzCarp)) { $lzRes.Motivo = 'La carpeta no está dentro de la carpeta de máquinas (o pasa por un enlace).'; break }
                if (-not (Carpeta-BorrableSegura $lzCarp)) { $lzRes.Motivo = 'La carpeta tiene más de una máquina u otros archivos.'; break }
                if (Maquina-EnUso $lzVmx $lzEnc) { $lzRes.Motivo = 'Está encendida o abierta en VMware.'; break }
                if (-not (Carpeta-MaquinasFiable) -and (Medir-Carpeta $lzCarp).Ajenos -gt 0) { $lzRes.Motivo = 'La carpeta tiene archivos que no son de VMware.'; break }
                $lzDep = Dependientes-De $lzCarp $lzVmx $false @(Mapa-Dependencias)
                if ($lzDep.Nombres.Count) { $lzRes.Motivo = "Dependen de ella: $($lzDep.Nombres -join ', ')"; break }
                $lzAntes = [double](Medir-Carpeta $lzCarp).Bytes
                if ($lzVmrun) {
                    $lzBv = Vmrun-ConLimite $lzVmrun @('-T', 'ws', 'deleteVM', $lzVmx)
                    # sin respuesta: no se borra la carpeta a mano por debajo de VMware; se deja y se dice
                    if ($lzBv.Agotado) { $lzRes.Motivo = (Texto-VmrunAgotado $lzBv -Larga); break }
                }
                $lzMot = Borrar-CarpetaConReintentos $lzCarp
                if ($lzMot) { $lzRes.Motivo = $lzMot; break }
                $lzRes.Ok = $true; $lzRes.Liberado = $lzAntes
            }
            'base' {
                $lzVmx = [string]$el.Vmx; $lzCarp = Split-Path $lzVmx
                if (-not (Test-Path -LiteralPath $lzVmx)) { $lzRes.Motivo = 'Ya no existe.'; break }
                if (-not $Config.CarpetaBases -or -not (Es-HijaDirecta $lzCarp $Config.CarpetaBases)) { $lzRes.Motivo = 'No está en la carpeta de bases.'; break }
                if (-not (Ruta-BorrableLimpieza $lzCarp)) { $lzRes.Motivo = 'La carpeta no está dentro de la carpeta de bases (o pasa por un enlace).'; break }
                if (Hay-CreacionEnCurso) { $lzRes.Motivo = 'Se está creando una base ahora mismo.'; break }
                if (Maquina-EnUso $lzVmx $lzEnc) { $lzRes.Motivo = 'Está encendida o abierta en VMware.'; break }
                $lzDep = Dependientes-De $lzCarp $lzVmx $true @(Mapa-Dependencias)
                if ($lzDep.Nombres.Count) { $lzRes.Motivo = "Dependen de ella: $($lzDep.Nombres -join ', ')"; break }
                if ($lzDep.Dudosas.Count) { $lzRes.Motivo = "No se pudo comprobar si dependen de ella: $($lzDep.Dudosas -join ', ')"; break }
                $lzAntes = [double](Medir-Carpeta $lzCarp).Bytes
                if ($lzVmrun) {
                    $lzBv = Vmrun-ConLimite $lzVmrun @('-T', 'ws', 'deleteVM', $lzVmx)
                    # sin respuesta: no se borra la carpeta a mano por debajo de VMware; se deja y se dice
                    if ($lzBv.Agotado) { $lzRes.Motivo = (Texto-VmrunAgotado $lzBv -Larga); break }
                }
                $lzMot = Borrar-CarpetaConReintentos $lzCarp
                if ($lzMot) { $lzRes.Motivo = $lzMot; break }
                $lzRes.Ok = $true; $lzRes.Liberado = $lzAntes
            }
            'instantanea' {
                $lzVmx = [string]$el.Vmx; $lzCarp = Split-Path $lzVmx
                if (-not $lzVmrun) { $lzRes.Motivo = 'No encuentro VMware (vmrun).'; break }
                if (-not (Test-Path -LiteralPath $lzVmx)) { $lzRes.Motivo = 'La máquina ya no existe.'; break }
                $lzClon = @(Leer-Clones | Where-Object { -not $_.Externa -and (Misma-Ruta $_.Vmx $lzVmx) }) | Select-Object -First 1
                if (-not $lzClon) { $lzRes.Motivo = 'No es una máquina de la carpeta de máquinas.'; break }
                if ($Config.CarpetaBases -and (Ruta-DentroDe $lzVmx $Config.CarpetaBases)) { $lzRes.Motivo = 'Es una base: sus instantáneas no se tocan.'; break }
                if (Maquina-EnUso $lzVmx $lzEnc) { $lzRes.Motivo = 'La máquina está encendida o abierta en VMware.'; break }
                $lzAhora = Leer-InstantaneasDetalle $lzVmx
                if (-not $lzAhora.Leido) { $lzRes.Motivo = 'No se pudo leer la lista de instantáneas.'; break }
                $lzBorr = @(Instantaneas-Borrables @($lzAhora.Lista) $false)
                $lzPedidas = @($el.Snaps | Where-Object { $lzBorr -ccontains [string]$_ })
                if (-not $lzPedidas.Count) { $lzRes.Motivo = 'Ya no tiene instantáneas que se puedan borrar.'; break }
                $lzAntes = [double](Medir-Carpeta $lzCarp).Bytes
                $lzMal = @()
                $lzSinResp = $null
                foreach ($lzNs in $lzPedidas) {
                    $lzBs = Vmrun-ConLimite $lzVmrun @('-T', 'ws', 'deleteSnapshot', $lzVmx, $lzNs)
                    if ($lzBs.Agotado) { $lzSinResp = $lzBs; break }     # no se sigue con las demás de esta máquina
                    if ($lzBs.Codigo -ne 0) { $lzMal += $lzNs }
                }
                $lzRes.Liberado = [Math]::Max([double]0, $lzAntes - [double](Medir-Carpeta $lzCarp).Bytes)
                if ($lzSinResp) { $lzRes.Motivo = (Texto-VmrunAgotado $lzSinResp -Larga); break }
                if ($lzMal.Count) { $lzRes.Motivo = "VMware no pudo borrar: $($lzMal -join ', ')"; break }
                $lzRes.Ok = $true
            }
            'resto' {
                switch ([string]$el.Clase) {
                    'carpeta' {
                        $lzRuta = [string]$el.Ruta
                        if (-not (Test-Path -LiteralPath $lzRuta -PathType Container)) { $lzRes.Motivo = 'Ya no existe.'; break }
                        if (-not (Carpeta-MaquinasFiable)) { $lzRes.Motivo = 'La carpeta de máquinas no es solo de máquinas.'; break }
                        if (Es-CarpetaReservada $lzRuta) { $lzRes.Motivo = 'Es una carpeta que Full Cowl necesita.'; break }
                        $lzEnVms = (Es-HijaDirecta $lzRuta $Config.CarpetaVMs) -and -not (Split-Path $lzRuta -Leaf).StartsWith('_')
                        $lzEnBases = [bool]$Config.CarpetaBases -and (Es-HijaDirecta $lzRuta $Config.CarpetaBases)
                        if (-not ($lzEnVms -or $lzEnBases)) { $lzRes.Motivo = 'No es una subcarpeta directa de la carpeta de máquinas ni de la de bases.'; break }
                        if ($lzEnBases -and (Hay-CreacionEnCurso)) { $lzRes.Motivo = 'Se está creando una base ahora mismo.'; break }
                        $lzMed = Medir-Carpeta $lzRuta
                        if ($lzMed.Vmx -gt 0) { $lzRes.Motivo = 'Ahora tiene una máquina dentro (.vmx).'; break }
                        if ($lzMed.Enlaces) { $lzRes.Motivo = 'Contiene un enlace a otra carpeta.'; break }
                        if ($lzMed.Lck) { $lzRes.Motivo = 'VMware la tiene en uso.'; break }
                        if ($lzMed.Ajenos -gt 0) { $lzRes.Motivo = 'Tiene archivos que no son de VMware.'; break }
                        foreach ($lzMp in @(Mapa-Dependencias)) {
                            foreach ($lzPd in @($lzMp.Padres)) {
                                if ((Misma-Ruta $lzPd $lzRuta) -or ([string]$lzPd).StartsWith(([IO.Path]::GetFullPath($lzRuta).TrimEnd('\')) + '\', [StringComparison]::OrdinalIgnoreCase)) { $lzRes.Motivo = "La máquina $($lzMp.Nombre) usa un disco de esta carpeta."; break }
                            }
                            if ($lzRes.Motivo) { break }
                        }
                        if ($lzRes.Motivo) { break }
                        $lzMot = Borrar-CarpetaConReintentos $lzRuta
                        if ($lzMot) { $lzRes.Motivo = $lzMot; break }
                        $lzRes.Ok = $true; $lzRes.Liberado = [double]$lzMed.Bytes
                    }
                    'build' {
                        $lzRuta = [string]$el.Ruta
                        if (-not (Test-Path -LiteralPath $lzRuta -PathType Container)) { $lzRes.Motivo = 'Ya no existe.'; break }
                        $lzEsBuild = (Es-HijaDirecta $lzRuta (Join-Path $dirComun 'build')) -or ((Es-HijaDirecta $lzRuta $dirComun) -and ((Split-Path $lzRuta -Leaf) -like 'output-*'))
                        if (-not $lzEsBuild) { $lzRes.Motivo = 'No es una carpeta de restos de Full Cowl.'; break }
                        if (Hay-CreacionEnCurso) { $lzRes.Motivo = 'Se está creando una base ahora mismo.'; break }
                        $lzMed = Medir-Carpeta $lzRuta
                        $lzMot = Borrar-CarpetaConReintentos $lzRuta
                        if ($lzMot) { $lzRes.Motivo = $lzMot; break }
                        $lzRes.Ok = $true; $lzRes.Liberado = [double]$lzMed.Bytes
                    }
                    'cd' {
                        $lzVmx = [string]$el.Vmx; $lzIso = Join-Path (Split-Path $lzVmx) 'vmtareas.iso'
                        if (-not (Misma-Ruta $lzIso ([string]$el.Ruta)) -or -not (Test-Path -LiteralPath $lzIso -PathType Leaf)) { $lzRes.Motivo = 'Ya no existe.'; break }
                        if (-not (Es-HijaDirecta (Split-Path $lzVmx) $Config.CarpetaVMs)) { $lzRes.Motivo = 'No es una máquina de la carpeta de máquinas.'; break }
                        if (Maquina-EnUso $lzVmx $lzEnc) { $lzRes.Motivo = 'La máquina está encendida o abierta en VMware.'; break }
                        $lzProg = $null
                        try { $lzProg = ([IO.File]::ReadAllText((Join-Path $dirComun 'estado\progreso.json')) | ConvertFrom-Json).maquinas } catch {}
                        if (-not (Cd-YaUsado $lzVmx $lzIso $lzProg)) { $lzRes.Motivo = 'La máquina aún no ha terminado de configurarse.'; break }
                        $lzTamIso = [double](New-Object IO.FileInfo($lzIso)).Length
                        # Primero se desconecta el CD del .vmx (si no, VMware preguntaría por él al arrancar)
                        if ([string](Leer-ValorVmx $lzVmx 'sata0:2.fileName') -ieq 'vmtareas.iso') { Fijar-ValoresVmx $lzVmx @{ 'sata0:2.present' = 'FALSE'; 'guestinfo.vmtareas.cdclave' = '0' } }
                        $lzMot = Borrar-ArchivoLimpieza $lzIso
                        if ($lzMot) { $lzRes.Motivo = $lzMot; break }
                        $lzRes.Ok = $true; $lzRes.Liberado = $lzTamIso
                    }
                    'viejos' {
                        $lzHechos = 0; $lzPrimero = ''
                        $lzCarpetasOk = @(Leer-Clones | Where-Object { -not $_.Externa } | ForEach-Object { $_.Carpeta }) + @(Obtener-Bases | ForEach-Object { Split-Path $_.Vmx })
                        foreach ($lzRuta in @($el.Rutas)) {
                            try {
                                $lzRuta = [string]$lzRuta
                                if (-not (Test-Path -LiteralPath $lzRuta)) { continue }
                                $lzPadre = Split-Path $lzRuta
                                $lzEsDir = [bool]([IO.File]::GetAttributes($lzRuta) -band [IO.FileAttributes]::Directory)
                                $lzInfo = $(if ($lzEsDir) { New-Object IO.DirectoryInfo($lzRuta) } else { New-Object IO.FileInfo($lzRuta) })
                                if (Misma-Ruta $lzPadre (Join-Path $dirComun 'estado')) { $lzClase = 'estado' }
                                elseif (@($lzCarpetasOk | Where-Object { Misma-Ruta $_ $lzPadre }).Count) {
                                    $lzClase = 'maquina'
                                    $lzVmxDe = @(Get-ChildItem -LiteralPath $lzPadre -Filter *.vmx -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                                    if ($lzVmxDe.Count -and ($lzEnc -contains $lzVmxDe[0].FullName.ToLower())) { continue }
                                } else { continue }
                                if (-not (Es-ViejoLimpieza $lzInfo $lzClase)) { continue }
                                $lzB = $(if ($lzEsDir) { [double](Medir-Carpeta $lzRuta).Bytes } else { [double]$lzInfo.Length })
                                $lzMot = $(if ($lzEsDir) { Borrar-CarpetaSinEnlaces $lzRuta } else { Borrar-ArchivoLimpieza $lzRuta })
                                if ($lzMot) { if (-not $lzPrimero) { $lzPrimero = $lzMot } } else { $lzHechos++; $lzRes.Liberado += $lzB }
                            } catch { if (-not $lzPrimero) { $lzPrimero = [string]$_.Exception.Message } }
                        }
                        $lzRes.Ok = ($lzHechos -gt 0 -or -not $lzPrimero)
                        if (-not $lzRes.Ok) { $lzRes.Motivo = $lzPrimero }
                    }
                    default { $lzRes.Motivo = 'Tipo de resto desconocido.' }
                }
            }
            default { $lzRes.Motivo = 'Tipo desconocido.' }
        }
    } catch { $lzRes.Ok = $false; $lzRes.Motivo = [string]$_.Exception.Message }
    return $lzRes
}

function Borrar-ElementosLimpieza($elementos, $progreso) {
    # Lo llama el hilo de trabajo. Orden: restos, instantáneas, máquinas y, al final, bases
    # (así una base cuyas máquinas se borran en la misma tanda se comprueba cuando ya no están).
    $lzOrden = @{ resto = 0; instantanea = 1; maquina = 2; base = 3 }
    $lzLista = @($elementos | Sort-Object { $lzOrden[[string]$_.Tipo] })
    $progreso.Total = $lzLista.Count; $progreso.Hecho = 0
    foreach ($lzEl in $lzLista) {
        $progreso.Fase = "Borrando $([string]$lzEl.Nombre)…"
        $lzR = Borrar-ElementoLimpieza $lzEl
        [void]$progreso.Resultados.Add(@{ Id = [string]$lzEl.Id; Nombre = [string]$lzEl.Nombre; Tipo = [string]$lzEl.Tipo; Ok = [bool]$lzR.Ok; Motivo = [string]$lzR.Motivo; Liberado = [double]$lzR.Liberado })
        $progreso.Hecho = [int]$progreso.Hecho + 1
    }
    $progreso.Fase = ''
}
