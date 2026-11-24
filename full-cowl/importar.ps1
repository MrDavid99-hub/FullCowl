param([string]$Pedido)   # lo crea la ventana (panel Importar)
# =====================================================================
#  Importa una máquina virtual completa e independiente a este PC:
#    · un .ova o .ovf (lo que saca «Exportar» de otro Full Cowl, o de VMware/VirtualBox)
#    · una carpeta con un .vmx
#    · un .zip o .7z que contenga esa carpeta
#  La máquina queda en la carpeta de máquinas, con el nombre elegido, marcada como «Importada».
#  No depende de ninguna base. Los clones ENLAZADOS no valen (dependen de su base): hay que
#  exportarlos antes desde su Full Cowl, que los saca completos.
# =====================================================================
. "$PSScriptRoot\comun.ps1"

# --- Progreso para la ventana: estado\importar.json (se cancela creando estado\importar.abortar)
$dirEstado = Join-Path $PSScriptRoot 'estado'
New-Item -ItemType Directory -Force -Path $dirEstado | Out-Null
$script:archivoEstado = Join-Path $dirEstado 'importar.json'
$script:archivoAbortar = Join-Path $dirEstado 'importar.abortar'
Remove-Item -LiteralPath $script:archivoAbortar -Force -ErrorAction SilentlyContinue
$ahora = (Get-Date).ToString('o')
$script:est = [ordered]@{
    sistema = 'importar'; nombre = ''; paso = 'Preparando'; pct = 2; hasta = 2
    inicio = $ahora; inicioFase = $ahora; esperadoSeg = 0
    estado = 'curso'; mensaje = ''; pid = $PID; actualizado = ''
}
Guardar-Estado

if (-not $Pedido) { Salir-ConError "Ábrelo desde la ventana: Importar." }
$P = Leer-Pedido $Pedido
$origen = [string]$P.origen
$nombre = ([string]$P.nombre).Trim()
$script:est.nombre = $nombre
Guardar-Estado

function Estado($paso, $pct, $hasta = $null, $esperado = 0) {
    # $hasta/$esperado: en fases sin mensajes, la ventana avanza la barra de $pct a $hasta en ~$esperado segundos
    $script:est.paso = $paso; $script:est.pct = $pct
    $script:est.hasta = if ($hasta) { $hasta } else { $pct }
    $script:est.esperadoSeg = $esperado
    $script:est.inicioFase = (Get-Date).ToString('o')
    Guardar-Estado
}

# Carpetas que ha creado esta importación (la de la máquina y, si hay que descomprimir, una temporal)
$script:creadas = @()

function Borrar-Creadas {
    # Solo borra carpetas que ha creado esta importación y que cuelgan directamente de la carpeta de máquinas
    $vms = [IO.Path]::GetFullPath($Config.CarpetaVMs).TrimEnd('\')
    foreach ($c in @($script:creadas)) {
        try { $full = [IO.Path]::GetFullPath($c).TrimEnd('\') } catch { continue }
        if ((Split-Path $full) -ne $vms) { continue }
        # VMware tarda unos segundos en soltar los archivos
        for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $full); $i++) {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $full) { Start-Sleep 2 }
        }
    }
}

function Matar-Hijos {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'conhost.exe' } |
        ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null }
}

function Cancelar-Importacion {
    Write-Host ""
    Write-Host "Cancelando la importación..." -ForegroundColor Yellow
    Matar-Hijos
    Borrar-Creadas
    Remove-Item -LiteralPath $script:archivoAbortar -Force -ErrorAction SilentlyContinue
    $script:est.estado = 'cancelada'
    $resto = @($script:creadas | Where-Object { Test-Path -LiteralPath $_ })
    $script:est.mensaje = $(if ($resto.Count) { "No se pudo borrar del todo: $($resto -join ', ')" } else { '' })
    Guardar-Estado
    if ($resto.Count) {
        Write-Host "Quedan restos en $($resto -join ', ') (bórralos a mano)." -ForegroundColor Yellow
        Read-Host "Pulsa Enter para cerrar"
    } else {
        Write-Host "Importación cancelada y borrada. Esta ventana se cierra sola."
        Start-Sleep 4
    }
    exit 2
}

function Comprobar-Cancelar {
    if (Test-Path -LiteralPath $script:archivoAbortar) { Cancelar-Importacion }
}

function Fallar([string]$texto) {
    # Error: se limpia lo creado y se avisa
    Matar-Hijos
    Borrar-Creadas
    Salir-ConError $texto
}

Escribir-Titulo "Importar '$nombre'"

# --- Comprobaciones previas
if (-not $Config.CarpetaVMs) { Fallar "No hay carpeta de máquinas elegida: ábrela en Ajustes." }
if (-not $origen -or -not (Test-Path -LiteralPath $origen)) { Fallar "No encuentro lo que quieres importar:`n  $origen" }
$motivo = Validar-NombreMaquina $nombre
if ($motivo) { Fallar $motivo }
$destino = Join-Path $Config.CarpetaVMs $nombre
New-Item -ItemType Directory -Force -Path $Config.CarpetaVMs | Out-Null

$esCarpeta = Test-Path -LiteralPath $origen -PathType Container
$ext = $(if ($esCarpeta) { 'carpeta' } else { [IO.Path]::GetExtension($origen).TrimStart('.').ToLower() })
if (@('carpeta', 'ova', 'ovf', 'zip', '7z') -notcontains $ext) {
    Fallar "No sé importar archivos .$ext. Elige un .ova, un .ovf, un .zip, un .7z o una carpeta con un .vmx."
}
Write-Host "  Origen:  $origen  ($ext)"
Write-Host "  Destino: $destino"
Write-Host ""

# Tamaño del origen y espacio libre en el disco de destino
$tamOrigen = [double]0
if ($esCarpeta) { $tamOrigen = Tamano-Carpeta $origen }
elseif ($ext -eq 'ovf') { $tamOrigen = Tamano-Carpeta (Split-Path $origen) }
else { $tamOrigen = [double](Get-Item -LiteralPath $origen).Length }
$factor = $(switch ($ext) { 'carpeta' { 1.05 } 'ova' { 2 } 'ovf' { 1.5 } default { 3 } })
$libre = $null
try { $libre = [double](New-Object System.IO.DriveInfo([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Config.CarpetaVMs)))).AvailableFreeSpace } catch {}
if ($null -ne $libre -and $libre -lt ($tamOrigen * $factor)) {
    Fallar ("No hay espacio suficiente en el disco de las máquinas: hacen falta unos {0} y quedan {1}." -f (Formato-Tamano ($tamOrigen * $factor)), (Formato-Tamano $libre))
}

function Buscar-Vmx([string]$carpeta) {
    # El .vmx de una carpeta (o de una subcarpeta directa, por si el .zip trae una carpeta dentro)
    $v = @(Get-ChildItem -LiteralPath $carpeta -Filter *.vmx -File -ErrorAction SilentlyContinue)
    if (-not $v.Count) {
        foreach ($sub in @(Get-ChildItem -LiteralPath $carpeta -Directory -ErrorAction SilentlyContinue)) {
            $v = @(Get-ChildItem -LiteralPath $sub.FullName -Filter *.vmx -File -ErrorAction SilentlyContinue)
            if ($v.Count) { break }
        }
    }
    return $v
}

function Comprobar-NoEnlazada([string]$carpeta) {
    # Un clon enlazado necesita los discos de su base y fuera de su PC no funciona
    foreach ($d in @(Get-ChildItem -LiteralPath $carpeta -Filter *.vmdk -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 1MB })) {
        $padre = Leer-PadreVmdk $d.FullName
        if ($padre) {
            Fallar "Esta máquina es un clon ENLAZADO: su disco depende de otro ($padre) y fuera de su PC no funciona.`nExpórtala con «Exportar» en el Full Cowl donde está (saca clones completos) e importa el .ova."
        }
    }
}

function Comprobar-OrigenCarpeta([string]$carpeta) {
    if (Get-ChildItem -LiteralPath $carpeta -Filter '*.lck' -Force -ErrorAction SilentlyContinue) {
        Fallar "Esa máquina está abierta o encendida en VMware. Apágala (y ciérrala) y vuelve a importar."
    }
    if (Get-ChildItem -LiteralPath $carpeta -Filter *.vmss -File -ErrorAction SilentlyContinue) {
        Fallar "Esa máquina está suspendida. Enciéndela, apágala del todo y vuelve a importar."
    }
}

$vmx = $null

# =====================================================================
#  Traer la máquina a la carpeta de máquinas
# =====================================================================
if ($ext -eq 'carpeta') {
    $encontrados = @(Buscar-Vmx $origen)
    if (-not $encontrados.Count) { Fallar "En esa carpeta no hay ningún archivo .vmx." }
    $origenMaq = $encontrados[0].DirectoryName
    if (@(Get-ChildItem -LiteralPath $origenMaq -Filter *.vmx -File).Count -gt 1) {
        Fallar "En esa carpeta hay más de un .vmx: elige la carpeta de una sola máquina."
    }
    Comprobar-OrigenCarpeta $origenMaq
    Comprobar-NoEnlazada $origenMaq

    Estado 'Copiando la máquina' 5
    Write-Host "Copiando... (puede tardar según el tamaño del disco)" -ForegroundColor Cyan
    $script:creadas += $destino
    New-Item -ItemType Directory -Path $destino | Out-Null
    $archivos = @(Get-ChildItem -LiteralPath $origenMaq -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\caches(\\|$)|\.lck(\\|$)' -and $_.Name -notmatch '^vmware.*\.log$|\.scoreboard$'
    })
    $total = [double](($archivos | Measure-Object Length -Sum).Sum)
    if ($total -le 0) { $total = 1 }
    $hecho = [double]0
    $raizOrigen = $origenMaq.TrimEnd('\') + '\'
    $ultimoGuardado = Get-Date
    $buffer = New-Object byte[] (4MB)
    foreach ($a in $archivos) {
        Comprobar-Cancelar
        $rel = $a.FullName.Substring($raizOrigen.Length)
        $dest = Join-Path $destino $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        $entrada = [IO.File]::Open($a.FullName, 'Open', 'Read', 'ReadWrite')
        try {
            $salidaF = [IO.File]::Open($dest, 'Create', 'Write', 'None')
            try {
                while (($n = $entrada.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $salidaF.Write($buffer, 0, $n)
                    $hecho += $n
                    if (((Get-Date) - $ultimoGuardado).TotalSeconds -ge 1) {
                        Comprobar-Cancelar
                        Estado 'Copiando la máquina' ([int](5 + 85 * $hecho / $total))
                        $ultimoGuardado = Get-Date
                    }
                }
            } finally { $salidaF.Dispose() }
        } finally { $entrada.Dispose() }
    }
    $vmx = (Get-ChildItem -LiteralPath $destino -Filter *.vmx -File | Select-Object -First 1).FullName
}
elseif ($ext -eq 'zip' -or $ext -eq '7z') {
    $tmp = Join-Path $Config.CarpetaVMs ('_Importando-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $script:creadas += $tmp
    New-Item -ItemType Directory -Path $tmp | Out-Null
    if ($ext -eq 'zip') {
        Estado 'Descomprimiendo' 5
        Write-Host "Descomprimiendo el .zip..." -ForegroundColor Cyan
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $tmpCompleto = [IO.Path]::GetFullPath($tmp).TrimEnd('\') + '\'
        $zip = [IO.Compression.ZipFile]::OpenRead($origen)
        try {
            $totalZ = [double](($zip.Entries | Measure-Object Length -Sum).Sum)
            if ($totalZ -le 0) { $totalZ = 1 }
            # Un .zip pequeño puede anunciar un contenido enorme: se mira lo que ocupará descomprimido antes de empezar
            if ($null -ne $libre -and $totalZ -gt $libre) {
                Fallar ("El .zip ocupa {0} al descomprimirlo y en el disco de las máquinas quedan {1}." -f (Formato-Tamano $totalZ), (Formato-Tamano $libre))
            }
            $hechoZ = [double]0
            $ultimoGuardado = Get-Date
            foreach ($e in $zip.Entries) {
                Comprobar-Cancelar
                $dest = [IO.Path]::GetFullPath((Join-Path $tmp $e.FullName))
                # Que ninguna entrada pueda salirse de la carpeta temporal (rutas con «..»)
                if (-not $dest.StartsWith($tmpCompleto, [StringComparison]::OrdinalIgnoreCase)) { Fallar "El .zip trae una ruta no permitida ($($e.FullName)). No se importa." }
                if ($e.FullName.EndsWith('/') -or $e.FullName.EndsWith('\')) {
                    New-Item -ItemType Directory -Force -Path $dest | Out-Null
                } else {
                    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                    $hechoZ += $e.Length
                    if (((Get-Date) - $ultimoGuardado).TotalSeconds -ge 1) {
                        Estado 'Descomprimiendo' ([int](5 + 55 * $hechoZ / $totalZ))
                        $ultimoGuardado = Get-Date
                    }
                }
            }
        } finally { $zip.Dispose() }
    } else {
        $sevenZ = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
        if (-not $sevenZ) { $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue; if ($cmd) { $sevenZ = $cmd.Source } }
        if (-not $sevenZ) { Fallar "Para abrir un .7z hace falta 7-Zip (gratis, 7-zip.org). Instálalo, o descomprime el archivo tú y elige la carpeta." }
        $seg = [Math]::Max(60, [int]($tamOrigen / 40MB))
        Estado 'Descomprimiendo (tiempo estimado)' 5 60 $seg
        Write-Host "Descomprimiendo el .7z..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath $sevenZ -ArgumentList "x -y `"-o$tmp`" `"$origen`"" -WindowStyle Hidden -PassThru
        while (-not $proc.WaitForExit(1000)) { Comprobar-Cancelar }
        if ($proc.ExitCode -ne 0) { Fallar "7-Zip no pudo abrir el archivo (código $($proc.ExitCode))." }
    }
    Estado 'Colocando la máquina' 62
    $encontrados = @(Buscar-Vmx $tmp)
    if (-not $encontrados.Count) { Fallar "Dentro del archivo no hay ningún .vmx." }
    $carpetaVmx = $encontrados[0].DirectoryName
    if (@(Get-ChildItem -LiteralPath $carpetaVmx -Filter *.vmx -File).Count -gt 1) { Fallar "Dentro del archivo hay más de un .vmx: se importa de una en una." }
    # La carpeta con el .vmx pasa a ser la máquina (mismo disco: se mueve al instante)
    if ($carpetaVmx.TrimEnd('\') -eq $tmp.TrimEnd('\')) {
        Rename-Item -LiteralPath $tmp -NewName $nombre
        $script:creadas = @($destino)
    } else {
        Move-Item -LiteralPath $carpetaVmx -Destination $destino
        $script:creadas = @($tmp, $destino)
    }
    Comprobar-OrigenCarpeta $destino
    Comprobar-NoEnlazada $destino
    $vmx = (Get-ChildItem -LiteralPath $destino -Filter *.vmx -File | Select-Object -First 1).FullName
}
else {
    # .ova / .ovf con OVF Tool (viene con VMware Workstation)
    $vmrun = Buscar-Vmrun
    $ovf = Join-Path (Split-Path $vmrun) 'OVFTool\ovftool.exe'
    if (-not (Test-Path -LiteralPath $ovf)) { Fallar "No encuentro OVF Tool (viene con VMware Workstation):`n  $ovf" }
    $script:creadas += $destino
    $ultimasLineas = New-Object System.Collections.Generic.List[string]

    function Importar-ConOvfTool([string[]]$opciones) {
        # Devuelve el código de salida de OVF Tool; la barra avanza con su «Disk progress»
        $ultimasLineas.Clear()
        & $ovf @opciones "--name=$nombre" $origen $Config.CarpetaVMs 2>&1 | ForEach-Object {
            $linea = ([string]$_).Trim()
            if ($linea) {
                if ($ultimasLineas.Count -ge 12) { $ultimasLineas.RemoveAt(0) }
                $ultimasLineas.Add($linea)
            }
            if ($linea -match 'Disk progress:\s*(\d+)%') {
                Estado 'Importando el disco' ([int](8 + 82 * [int]$Matches[1] / 100))
                Write-Host "`r  Disco: $($Matches[1]) %   " -NoNewline
            }
            Comprobar-Cancelar
        }
        Write-Host ""
        return $LASTEXITCODE
    }

    Estado 'Importando con OVF Tool' 8 90 ([Math]::Max(120, [int]($tamOrigen / 30MB)))
    Write-Host "Importando... (puede tardar varios minutos según el tamaño del disco)" -ForegroundColor Cyan
    # Primero conservando las marcas de Full Cowl (extraConfig); si esta versión de OVF Tool no lo admite, sin ellas
    $codigo = Importar-ConOvfTool @('--acceptAllEulas', '--allowExtraConfig', '--lax')
    if ($codigo -ne 0) {
        Write-Host "  Reintentando sin conservar las marcas de Full Cowl..." -ForegroundColor Yellow
        Borrar-Creadas
        $codigo = Importar-ConOvfTool @('--acceptAllEulas', '--lax')
    }
    $vmxHallado = Get-ChildItem -LiteralPath $destino -Filter *.vmx -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($codigo -ne 0 -or -not $vmxHallado) {
        Fallar ("OVF Tool no pudo importar el archivo.`n" + (($ultimasLineas | Select-Object -Last 6) -join "`n"))
    }
    $vmx = $vmxHallado.FullName
}

# =====================================================================
#  Dejarla lista para este PC
# =====================================================================
Estado 'Ajustando la máquina' 92
Write-Host "Ajustando la máquina para este PC..." -ForegroundColor Cyan
$avisos = New-Object System.Collections.Generic.List[string]
try {
    # 1) CD de configuración con contraseña de otro Full Cowl: no debe quedarse en esta máquina
    $isoCd = Join-Path (Split-Path $vmx) 'vmtareas.iso'
    if (Test-Path -LiteralPath $isoCd) {
        Fijar-ValoresVmx $vmx @{ 'sata0:2.present' = 'FALSE'; 'guestinfo.vmtareas.cdclave' = '0' }
        Remove-Item -LiteralPath $isoCd -Force -ErrorAction SilentlyContinue
        $avisos.Add('Traía el CD de configuración de su Full Cowl de origen y se ha quitado. Si aquel Full Cowl no había terminado de configurarla, puede que le falte algo (ponerle IP o dominio).')
    }

    # 1b) Lo que una máquina hecha en otro PC no debe traer puesto: carpetas compartidas con ESTE PC y puertos serie o
    #     paralelo (pueden leer o escribir archivos del PC). Se quitan del .vmx; se pueden volver a poner en VMware.
    $patronAjeno = '^\s*(sharedFolder[0-9]*\.|serial[0-9]+\.|parallel[0-9]+\.)'
    $lineasAj = @(Leer-Vmx $vmx)
    if (@($lineasAj | Where-Object { $_ -match $patronAjeno }).Count) {
        Guardar-Vmx $vmx @($lineasAj | Where-Object { $_ -notmatch $patronAjeno })
        $avisos.Add('Traía carpetas compartidas con el PC o puertos serie/paralelo y se han quitado por seguridad. Si los necesitas, vuelve a ponerlos en los ajustes de la máquina en VMware.')
    }

    # 2) MAC nuevas (VMware las genera) para que no choquen con la máquina original si la tienes aquí también
    $lineas = @(Leer-Vmx $vmx)
    $conMac = $lineas | Where-Object { $_ -match '^\s*ethernet\d+\.(address|generatedAddress|generatedAddressOffset)\s*=' }
    if ($conMac) {
        $lineas = @($lineas | Where-Object { $_ -notmatch '^\s*ethernet\d+\.(address|generatedAddress|generatedAddressOffset)\s*=' })
        Guardar-Vmx $vmx $lineas
        $tipos = @{}
        foreach ($l in $lineas) { if ($l -match '^\s*(ethernet\d+)\.present\s*=\s*"TRUE"') { $tipos["$($Matches[1]).addressType"] = 'generated' } }
        if ($tipos.Count) { Fijar-ValoresVmx $vmx $tipos }
    }

    # 3) Nombre, identidad nueva y marca de importada
    $marca = "{0}|{1}|{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $ext, ((Split-Path $origen -Leaf) -replace '[|"]', '')
    $valores = @{
        displayName                   = $nombre
        'uuid.action'                 = 'create'
        'guestinfo.vmtareas.importada' = $marca
    }
    $usuarioPedido = [string]$P.usuario
    if ($usuarioPedido -cmatch '^[a-z_][a-z0-9_-]{0,19}$' -and -not (Leer-ValorVmx $vmx 'guestinfo.vmtareas.usuario')) {
        $valores['guestinfo.vmtareas.usuario'] = $usuarioPedido
    }
    Fijar-ValoresVmx $vmx $valores

    # 3b) Versión de hardware: si la máquina viene de un VMware más nuevo que el de este PC, no arranca
    #     («hardware version that is not supported»). Se baja a la que admite este VMware.
    try {
        $vmwareExe = Join-Path (Split-Path (Buscar-Vmrun -Silencioso)) 'vmware.exe'
        $verVm = [int](Get-Item -LiteralPath $vmwareExe).VersionInfo.FileMajorPart
        $maxHw = if ($verVm -ge 25) { 22 } elseif ($verVm -ge 17) { 20 } elseif ($verVm -eq 16) { 19 } elseif ($verVm -eq 15) { 16 } else { 14 }
        $hwActual = [int](([string](Leer-ValorVmx $vmx 'virtualHW.version')) -replace '[^\d]', '0')
        if ($hwActual -gt $maxHw -and $maxHw -ge 14) {
            Fijar-ValoresVmx $vmx @{ 'virtualHW.version' = [string]$maxHw }
            $avisos.Add("Venía de un VMware más nuevo (hardware $hwActual): se ha bajado a $maxHw para que arranque en este PC.")
        }
    } catch {}

    # 4) Cosas que pueden dar problemas y conviene decir
    $ipFija = [string](Leer-ValorVmx $vmx 'guestinfo.vmtareas.ip')
    if ($ipFija) {
        $otra = @(Leer-Clones | Where-Object { $_.IP -eq $ipFija -and $_.Vmx -ne $vmx })
        if ($otra.Count) {
            $avisos.Add("Trae la IP fija $ipFija y ya la usa «$($otra[0].Nombre)». Cámbiala en Mis máquinas > Red antes de encender las dos.")
        } else {
            $avisos.Add("Trae la IP fija $ipFija. Si este PC usa otra red, cámbiala en Mis máquinas > Red.")
        }
    }
    if (-not (Leer-ValorVmx $vmx 'guestinfo.vmtareas.agente')) {
        $avisos.Add('No trae el agente de Full Cowl: no tendrá IP, usuarios ni dominio desde Full Cowl hasta que se le instale. Encenderla y apagarla sí funciona.')
    }
    if (-not [bool]$P.mismaClave) {
        $avisos.Add('Dices que su contraseña no es la de este PC: Full Cowl no podrá entrar en ella (Usuarios, Red, Archivos) mientras no coincidan. Entra a mano y cámbiala a la de Full Cowl, o cambia la de Full Cowl (cambiar-password.bat).')
    }
    try {
        $segs = Leer-Segmentos
        $tarjetas = @(Leer-Tarjetas $vmx)
        if ($tarjetas.Count) {
            $avisos.Add('Red de la máquina: ' + ((@($tarjetas | ForEach-Object { Texto-Tarjeta $_ $segs }) -join ' + ')) + '. Comprueba en Mis máquinas > Red que esa red existe en este PC.')
        }
    } catch {}
} catch {
    Fallar "La máquina se copió pero no se pudo ajustar: $_"
}

# =====================================================================
$script:est.estado = 'ok'
$script:est.pct = 100; $script:est.paso = 'Importada'; $script:est.hasta = 100
$script:est.mensaje = (@($avisos) -join ' ')
Guardar-Estado
Escribir-Titulo "Importada"
Write-Host "  $nombre  ($(Formato-Tamano (Tamano-Carpeta $destino)))"
Write-Host "  $vmx"
Write-Host ""
foreach ($av in $avisos) { Write-Host "  · $av" -ForegroundColor Yellow }
Write-Host ""
Write-Host "  Ya sale en «Mis máquinas», marcada como Importada (Full Cowl le ha puesto identidad nueva: VMware no preguntará si la copiaste)."
Write-Host ""
Read-Host "Pulsa Enter para cerrar"
