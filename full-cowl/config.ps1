# =====================================================================
#  Configuración de Full Cowl
#
#  Aquí solo hay valores por defecto, iguales en todos los PC.
#  Lo propio de cada equipo (carpetas de ISOs y de máquinas, usuario de las
#  VMs...) se guarda en config.local.json: lo crea la ventana la primera vez
#  y se cambia con el botón "Ajustes". Ese archivo NO se sube a GitHub.
#  La contraseña de las VMs tampoco está aquí: va cifrada en password.sec.
# =====================================================================
$Config = @{
    # Carpetas (las rellena config.local.json)
    CarpetaISOs   = ''
    CarpetaVMs    = ''             # cada máquina nueva va en su subcarpeta
    CarpetaBases  = ''             # vacío = <CarpetaVMs>\_Bases

    # Usuario que se crea en todas las VMs (administrador / sudo)
    Usuario       = 'alumno'

    # Recursos por defecto
    RAM_MB        = 6144
    CPUs          = 4
    VRAM_MB       = 1024           # memoria gráfica con aceleración 3D (0 = sin aceleración 3D)
    DiscoWin_GB   = 60
    DiscoLinux_GB = 40

    # Windows
    ZonaHorariaWin = 'Romance Standard Time'       # Madrid

    # Las ISO se buscan solas en la carpeta de ISOs por su nombre (la más nueva
    # que encaje con cada sistema). Si quieres fijar una, pon en config.local.json
    # por ejemplo:  "ISO_Win11Pro": "Win11_23H2_Spanish_x64v2.iso"
}

# ---- Lo propio de este PC
$ConfigPorDefecto = $Config.Clone()
$ArchivoConfigLocal = Join-Path $PSScriptRoot 'config.local.json'
if (Test-Path $ArchivoConfigLocal) {
    try {
        $local = [IO.File]::ReadAllText($ArchivoConfigLocal, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($prop in $local.PSObject.Properties) { $Config[$prop.Name] = $prop.Value }
    } catch {}
}
# Valores que acaban dentro de archivos de configuración de las VMs (XML de Windows, scripts de
# Linux): si config.local.json trae algo raro, se usa el valor por defecto
if ([string]$Config.Usuario -cnotmatch '^[a-z_][a-z0-9_-]{0,19}$') { $Config.Usuario = $ConfigPorDefecto.Usuario }
if ([string]$Config.ZonaHorariaWin -notmatch '^[A-Za-z0-9 ()+.,_-]{1,64}$') { $Config.ZonaHorariaWin = $ConfigPorDefecto.ZonaHorariaWin }
& {   # (en un bloque aparte para no dejar variables sueltas en los scripts que cargan este archivo)
    foreach ($clave in 'RAM_MB', 'CPUs', 'VRAM_MB', 'DiscoWin_GB', 'DiscoLinux_GB') {
        $num = 0
        if (-not [int]::TryParse([string]$Config[$clave], [ref]$num) -or $num -lt 0 -or $num -gt 1048576) { $Config[$clave] = $ConfigPorDefecto[$clave] } else { $Config[$clave] = $num }
    }
}
if (-not $Config.CarpetaBases -and $Config.CarpetaVMs) { $Config.CarpetaBases = Join-Path $Config.CarpetaVMs '_Bases' }

function Config-Completa {
    return [bool]($Config.CarpetaISOs -and $Config.CarpetaVMs -and (Test-Path $Config.CarpetaISOs) -and (Test-Path $Config.CarpetaVMs))
}

function Guardar-ConfigLocal([hashtable]$valores) {
    # Mezcla los valores nuevos con lo que ya hubiera en config.local.json
    $datos = [ordered]@{}
    if (Test-Path $ArchivoConfigLocal) {
        try { foreach ($prop in ([IO.File]::ReadAllText($ArchivoConfigLocal, [Text.Encoding]::UTF8) | ConvertFrom-Json).PSObject.Properties) { $datos[$prop.Name] = $prop.Value } } catch {}
    }
    foreach ($k in $valores.Keys) { $datos[$k] = $valores[$k] }
    [IO.File]::WriteAllText($ArchivoConfigLocal, ($datos | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    foreach ($k in $valores.Keys) { $Config[$k] = $valores[$k] }
    if ($valores.ContainsKey('CarpetaVMs') -and -not $valores.ContainsKey('CarpetaBases')) { $Config.CarpetaBases = Join-Path $Config.CarpetaVMs '_Bases' }
}
