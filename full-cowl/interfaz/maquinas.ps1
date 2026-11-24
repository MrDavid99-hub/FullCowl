# =====================================================================
#  Interfaz nueva: página «Mis máquinas»
#  Antes era una pestaña de la ventana de siempre (gui.ps1, quitada en la 2.0), con las
#  mismas funciones de comun.ps1. Lo carga ventana-nueva.ps1 después de
#  crear la página, así que sus elementos ya son variables ($Lista...).
# =====================================================================

$script:vmrun = Buscar-Vmrun -Silencioso
$script:maquinas = @()          # lo que devuelve Leer-Maquinas
$script:filas = $null           # filas de la lista (FullCowlWpf.Maquina)
$script:vista = $null
$script:filtro = 'FiltroTodas'
$script:cargado = $false
$script:cargando = $false
$script:restos = @()
$script:acciones = @($AccEncender, $AccApagar, $AccAbrir, $AccCarpeta, $AccSnap, $AccRed, $AccConectar, $AccArchivos, $AccUsuarios, $AccExportar, $AccConservar, $AccBorrar)

# ---------------------------------------------------------------- progreso de la configuración
# Lo escribe vigilante.ps1 en estado\progreso.json con lo que publica cada máquina desde dentro
$archivoProgresoMaq = Join-Path $dirFc 'estado\progreso.json'
$finalesProg = @('ok', 'fallos', 'error')
$textoPaso = @{
    preparar = 'Preparando el sistema'; zona = 'Poniendo la zona horaria'; nombre = 'Cambiando el nombre'; red = 'Configurando la red'
    extras = 'Instalando roles y extras'; 'dominio-crear' = 'Creando el dominio'
    'dominio-arrancar' = 'Arrancando el controlador'; 'dominio-esperar' = 'Esperando al controlador'
    'dominio-unir' = 'Uniéndose al dominio'; actualizar = 'Actualizando el sistema'
    paquetes = 'Instalando servicios'; lista = 'Lista'
}
$script:progCache = @{}
$script:progFecha = [datetime]::MinValue

function Leer-ProgresoVm {
    # vmx (en minúsculas) -> paso de su configuración. Solo se vuelve a leer si el archivo cambió.
    try {
        $fi = Get-Item -LiteralPath $archivoProgresoMaq -ErrorAction Stop
        if ($fi.LastWriteTime -ne $script:progFecha) {
            $h = @{}
            $j = [IO.File]::ReadAllText($fi.FullName) | ConvertFrom-Json
            foreach ($prop in $j.maquinas.PSObject.Properties) { $h[$prop.Name] = $prop.Value }
            $script:progCache = $h
            $script:progFecha = $fi.LastWriteTime
        }
    } catch { $script:progCache = @{}; $script:progFecha = [datetime]::MinValue }
    return $script:progCache
}

function Info-Paso($e) {
    # Textos, porcentaje y color de un paso (el avance dentro del paso se estima por el tiempo)
    $ahoraEp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lleva = [Math]::Max([double]0, [double]($ahoraEp - [int64]$e.inicio))
    $esp = [double]$e.esperado
    $tot = [int]$e.total; $num = [int]$e.paso
    $txt = if ($textoPaso.ContainsKey([string]$e.clave)) { $textoPaso[[string]$e.clave] } else { [string]$e.clave }
    $dentro = if ($esp -gt 0) { [Math]::Min(0.95, $lleva / $esp) } else { 0.5 }
    $r = [ordered]@{ Pct = 0; Corto = ''; Largo = ''; Tiempo = ''; Color = $Colores.Verde; Final = $false; SinDatos = $false }
    switch ([string]$e.estado) {
        'ok'     { $r.Pct = 100; $r.Corto = 'Lista'; $r.Largo = 'Lista para trabajar'; $r.Color = $Colores.Ok; $r.Final = $true }
        'fallos' { $r.Pct = 100; $r.Corto = 'Lista, con avisos'; $r.Largo = "Lista, con avisos (mira 'Configuración de la VM')"; $r.Color = $Colores.Aviso; $r.Final = $true }
        'error'  { $r.Pct = 100; $r.Corto = 'Error al configurar'; $r.Largo = "Falló: $($txt.ToLower()) (se reintenta al reiniciar)"; $r.Color = $Colores.Error; $r.Final = $true }
        default {
            if ($tot -le 0 -and $lleva -gt 900) {
                $r.Corto = ''; $r.Largo = 'Sin datos: ¿la base no tiene VMware Tools?'; $r.Color = $Colores.Suave; $r.SinDatos = $true
            } elseif ($tot -le 0) {
                $r.Pct = 10 * $dentro; $r.Corto = 'Preparando…'; $r.Largo = $txt
            } else {
                $r.Pct = 100 * (($num - 1) + $dentro) / $tot; $r.Corto = "Configurando $num/$tot"; $r.Largo = "Paso $num de $($tot): $txt"
            }
            if (-not $r.SinDatos) {
                $r.Tiempo = "$([int][Math]::Floor($lleva / 60)) min"
                if ($esp -ge 120) { $r.Tiempo += " de ~$([int][Math]::Ceiling($esp / 60))" }
            }
        }
    }
    $r.Pct = [Math]::Min(100, [Math]::Max(0, $r.Pct))
    return [pscustomobject]$r
}

function Entrada-Progreso($m) {
    # Lo que ha publicado la máquina sobre su configuración (o $null)
    return (Leer-ProgresoVm)[([string]$m.Vmx).ToLower()]
}

function Tiempo-Total($e) {
    # Desde que se creó la máquina hasta ahora o, si ya terminó, hasta que quedó lista (segundos)
    $creada = [int64]$e.creada
    if ($creada -le 0) { return -1 }
    $hasta = if ($finalesProg -contains [string]$e.estado) { [int64]$e.inicio } else { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    return [double]($hasta - $creada)
}

function Apuntar-TiemposMaquinas {
    # Cada máquina que termina de configurarse queda en el historial de tiempos (estado\tiempos.csv)
    foreach ($par in @((Leer-ProgresoVm).GetEnumerator())) {
        $e = $par.Value
        if ($finalesProg -notcontains [string]$e.estado -or [int64]$e.creada -le 0 -or -not $e.enCurso) { continue }
        # (una máquina antigua que se enciende días después no es un tiempo de configuración)
        if ((Tiempo-Total $e) -gt 6 * 3600) { continue }
        $m = @($script:maquinas | Where-Object { ([string]$_.Vmx).ToLower() -eq $par.Key }) | Select-Object -First 1
        $sis = if ($m -and $m.Base) { [string]$m.Base } else { [string]$e.base }   # (las desechables ya no están en la lista)
        $det = "$([int]$e.total) pasos" + $(if ($e.lab) { " · laboratorio $($e.lab)" } else { '' })
        Apuntar-Tiempo "maq|$($e.nombre)|$($e.creada)" 'maquina' ([string]$e.nombre) $sis (Tiempo-Total $e) ([string]$e.estado) $det
    }
}

function Progreso-DeMaquina($m) {
    # Paso de una máquina, si se está configurando o acaba de terminar (media hora)
    if (-not $m.Encendida) { return $null }
    $e = (Leer-ProgresoVm)[([string]$m.Vmx).ToLower()]
    if (-not $e -or -not $e.enCurso) { return $null }
    $i = Info-Paso $e
    if ($i.SinDatos) { return $null }
    if ($i.Final -and ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$e.inicio) -gt 1800 -and [string]$e.estado -eq 'ok') { return $null }
    return $i
}

# ---------------------------------------------------------------- filas de la lista
$fondoDeColor = @{ '#2F7A45' = '#E3F3E8'; '#8A6D1F' = '#FBF3DD'; '#C62828' = '#FDECEC'; '#39824D' = '#E3F1E7'; '#5F6F65' = '#EEF2EF' }

# Encender o apagar tarda unos segundos: mientras, la tarjeta dice «Encendiendo…» o «Apagando…»
# (vmx en minúsculas -> @{ Texto; Encendida = cómo quedará; Hasta = cuándo se deja de esperar })
$script:transiciones = @{}
function Marcar-Transicion($m, [string]$texto, [bool]$quedaEncendida, [int]$segundos = 90) {
    $script:transiciones[([string]$m.Vmx).ToLower()] = @{ Texto = $texto; Encendida = $quedaEncendida; Hasta = (Get-Date).AddSeconds($segundos) }
    foreach ($f in @($script:filas)) { if ($f -and $f.Vmx -eq $m.Vmx) { [void](Aplicar-Estado $f) } }
}

function Aplicar-Estado($fila) {
    # Estado que se ve en la tarjeta: el de la máquina o, si se está configurando, su progreso
    $m = $fila.Datos
    $clave = ([string]$m.Vmx).ToLower()
    $tr = $script:transiciones[$clave]
    if ($tr -and ((Get-Date) -gt $tr.Hasta -or [bool]$m.Encendida -eq $tr.Encendida)) { $script:transiciones.Remove($clave); $tr = $null }
    $i = if ($tr) { $null } else { Progreso-DeMaquina $m }
    if ($tr) {
        $txt = $tr.Texto; $color = $Colores.Verde; $conf = $false; $pct = 0
    } elseif ($i -and -not ($i.Final -and $i.Color -eq $Colores.Ok)) {
        # Configurándose, o terminó con avisos o error (eso se sigue viendo en la tarjeta)
        $txt = $i.Corto; $color = $i.Color
        $conf = -not $i.Final; $pct = [double]$i.Pct
    } else {
        # Sin configurar o ya lista: su estado normal (Encendida, Apagada…); «Lista» queda en el panel
        $txt = [string]$m.Estado; $conf = $false; $pct = 0
        $color = switch ($m.Estado) { 'Encendida' { $Colores.Ok } 'Suspendida' { $Colores.Aviso } 'Sin base' { $Colores.Error } default { $Colores.Suave } }
    }
    if ($fila.EstadoTexto -ne $txt) { $fila.EstadoTexto = $txt }
    $colorT = Hex-Tema $color   # (el de este tema; las tarjetas se enlazan al texto del color)
    if ($fila.EstadoColor -ne $colorT) { $fila.EstadoColor = $colorT; $fila.EstadoFondo = Hex-Tema $fondoDeColor[$color] }
    if ($fila.Configurando -ne $conf) { $fila.Configurando = $conf }
    if ($fila.Trabajando -ne [bool]$tr) { $fila.Trabajando = [bool]$tr }   # encendiendo o apagando: ruedecita en el botón rápido
    if ([Math]::Abs($fila.Progreso - $pct) -gt 0.5) { $fila.Progreso = $pct }
    return $i
}

# Logotipos (trazados vectoriales de interfaz\logos.xaml): Windows 11, Windows 10 y Server, Ubuntu
$script:logos = @{
    win11 = [System.Windows.Application]::Current.FindResource('LogoWindows11')
    win10 = [System.Windows.Application]::Current.FindResource('LogoWindows10')
    ubuntu = [System.Windows.Application]::Current.FindResource('LogoUbuntu')
}
function Logo-DeMaquina($fila) {
    $fam = [string]$fila.Familia
    if ($fam -like 'Windows*') {
        if ($fam -like '*Server*') { return $script:logos.win10 }
        # Windows 11: por el nombre de la máquina, de su base o de su archivo .vmx, o porque VMware la
        # tiene apuntada como Windows 11 (las hechas a mano suelen llamarse «Windows 11 x64.vmx»)
        $textos = "$($fila.Nombre) $($fila.Base) $([IO.Path]::GetFileNameWithoutExtension([string]$fila.Vmx))"
        if ($textos -match 'win(dows)?[ _-]?11') { return $script:logos.win11 }
        try { if ([string](Leer-ValorVmx $fila.Vmx 'guestOS') -like 'windows11*') { return $script:logos.win11 } } catch {}
        return $script:logos.win10
    }
    if ($fam -match 'ubuntu' -and $fam -notmatch 'lubuntu') { return $script:logos.ubuntu }
    return $null
}

function Estilo-Icono([string]$fam) {
    # Glifo y color de fondo del icono según el sistema (cuando no hay logo, sale el glifo). En modo sobrio, todos grises
    if ([bool]$Config.Sobrio) {
        $gl = $(if ($fam -like 'Windows*') { Glifo 0xE7F4 } elseif ($fam -like '*Kali*') { Glifo 0xE72E } else { Glifo 0xE756 })
        return @($gl, '#5F6A72')
    }
    if ($fam -like 'Windows Server*') { return @((Glifo 0xE7F4), '#12261A') }
    if ($fam -like 'Windows*') { return @((Glifo 0xE7F4), '#39824D') }
    if ($fam -like '*Kali*') { return @((Glifo 0xE72E), '#2A9D8F') }
    return @((Glifo 0xE756), '#9C9C54')
}

# Símbolos de sistema (ficha 5): clave guardada en el .vmx (guestinfo.vmtareas.sistema) → recurso de iconos.xaml, color de la pastilla y nombre
$script:Simbolos = [ordered]@{
    kali        = @{ Recurso = 'LogoKali';       Color = '#2F6FDE'; Nombre = 'Kali' }
    parrot      = @{ Recurso = 'LogoParrot';     Color = '#1FA9D6'; Nombre = 'Parrot' }
    debian      = @{ Recurso = 'LogoDebian';     Color = '#C2185B'; Nombre = 'Debian' }
    lubuntu     = @{ Recurso = 'LogoLubuntu';    Color = '#0068C8'; Nombre = 'Lubuntu / Ubuntu ligero' }
    rocky       = @{ Recurso = 'LogoRocky';      Color = '#10B981'; Nombre = 'Rocky / Alma' }
    arch        = @{ Recurso = 'LogoArch';       Color = '#1793D1'; Nombre = 'Arch Linux' }
    cortafuegos = @{ Recurso = 'SisCortafuegos'; Color = '#C4511A'; Nombre = 'Cortafuegos' }
    proxmox     = @{ Recurso = 'LogoProxmox';    Color = '#E57000'; Nombre = 'Proxmox' }
    freebsd     = @{ Recurso = 'LogoFreeBSD';    Color = '#B5000F'; Nombre = 'FreeBSD' }
    otro        = @{ Recurso = 'SisOtro';        Color = '#5F6F65'; Nombre = 'Otro' }
}
function Sistema-Guardado([string]$vmx) {
    # El que se eligió al crear la base o con «Cambiar símbolo» (vacío = ninguno)
    if (-not $vmx) { return '' }
    try { $v = ([string](Leer-ValorVmx $vmx 'guestinfo.vmtareas.sistema')).Trim().ToLower() } catch { return '' }
    if ($script:Simbolos.Contains($v)) { return $v }
    return ''
}
function Sistema-DeMaquina($fila) {
    # Símbolo de una máquina: 1) el guardado en su .vmx o en el de su base; 2) Windows y Ubuntu, sin símbolo (siguen con su logo);
    # 3) deducido por nombres y tipo de sistema de VMware; si no se sabe, «otro». Devuelve $null si lleva logo de siempre.
    $g = Sistema-Guardado ([string]$fila.Vmx)
    if (-not $g -and $fila.Base -and -not $fila.EsBase -and $Config.CarpetaBases) {
        $vb = Get-ChildItem -LiteralPath (Join-Path $Config.CarpetaBases ([string]$fila.Base)) -Filter *.vmx -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vb) { $g = Sistema-Guardado $vb.FullName }
    }
    if ($g) { return $g }
    $fam = [string]$fila.Familia
    $guest = ''
    try { $guest = [string](Leer-ValorVmx $fila.Vmx 'guestOS') } catch {}
    $texto = "$($fila.Nombre) $($fila.Base) $([IO.Path]::GetFileNameWithoutExtension([string]$fila.Vmx)) $guest".ToLower()
    $ligero = ($texto -match 'lubuntu|xubuntu|kubuntu|ubuntu[ _-]?mate|budgie')
    if ($fam -like 'Windows*' -or $guest.ToLower() -like 'windows*') { return $null }
    if ($fam -match 'ubuntu' -and -not $ligero) { return $null }
    if ($fam -match 'ubuntu') { return 'lubuntu' }
    if ($texto -match 'kali') { return 'kali' }
    if ($texto -match '(^|[\s_-])arch(linux)?([\s_-]|$)|archdesk') { return 'arch' }
    if ($texto -match 'parrot') { return 'parrot' }
    if ($texto -match 'pfsense|opnsense') { return 'cortafuegos' }
    if ($texto -match 'proxmox') { return 'proxmox' }
    if ($texto -match 'freebsd') { return 'freebsd' }
    if ($texto -match 'rocky|alma|centos|rhel|red ?hat|fedora') { return 'rocky' }
    if ($ligero) { return 'lubuntu' }
    if ($texto -match 'debian') { return 'debian' }
    return 'otro'
}
function Poner-Simbolo($obj, [string]$clave) {
    # Pastilla con el símbolo (en modo sobrio la pastilla se queda gris)
    $d = $script:Simbolos[$clave]
    # Los «Logo…» son siluetas rellenas (logos oficiales calcados); los «Sis…» son símbolos de línea
    $res = [System.Windows.Application]::Current.FindResource($d.Recurso)
    if ([string]$d.Recurso -like 'Logo*') { $obj.IconoLogo = $res; $obj.IconoSimbolo = $null }
    else { $obj.IconoSimbolo = $res; $obj.IconoLogo = $null }
    $obj.IconoGlifo = ''
    if (-not [bool]$Config.Sobrio) { $obj.IconoFondo = $d.Color }
}

function Nueva-Fila($m) {
    $fila = New-Object FullCowlWpf.Maquina
    $fila.Datos = $m
    $fila.Vmx = [string]$m.Vmx
    $fila.Nombre = [string]$m.Nombre
    $fila.Familia = [string]$m.Familia
    $fila.Base = [string]$m.Base
    $fila.Tipo = [string]$m.Tipo
    $fila.Red = [string]$m.Red
    $fila.IP = [string]$m.IP
    $fila.Dominio = [string]$m.Dominio
    $fila.Carpeta = [string]$m.Carpeta
    $fila.Encendida = [bool]$m.Encendida
    $fila.EsBase = [bool]$m.EsBase
    $fila.EsDesechable = [bool]$m.Desechable
    $fila.EsFc = ([bool]$m.Tipo -and -not [bool]$m.EsBase)   # «Clon enlazado», «Clon completo», «Desechable», «Importada»: las hizo Full Cowl
    # Etiquetas y nota (ficha 18). La etiqueta «Lab …» de las máquinas de un laboratorio se calcula, no se guarda
    $fila.Etiquetas = [string[]]@($m.Etiquetas | Where-Object { $_ })
    $fila.EtiquetaLab = Etiqueta-DeLab ([string]$m.Lab)
    $fila.Nota = [string]$m.Nota
    $todasEtq = @(@($fila.EtiquetaLab) + @($fila.Etiquetas) | Where-Object { $_ })
    $visiblesEtq = @($todasEtq | Select-Object -First 2)
    if ($todasEtq.Count -gt 2) { $visiblesEtq += "+$($todasEtq.Count - 2)" }
    $fila.EtqVisibles = [string[]]$visiblesEtq
    $fila.EtqTodo = ((@($todasEtq) + @($fila.Nota)) -join ' ')
    $fila.TieneNota = [bool]$fila.Nota.Trim()
    $fila.TieneEtqONota = ($todasEtq.Count -gt 0 -or $fila.TieneNota)
    $fila.Tamano = [double]$m.Tamano
    $fila.TamanoTexto = $(if ($fila.Tamano -gt 0) { Formato-Tamano $fila.Tamano } else { '' })
    # Icono por sistema, con los colores de Full Cowl
    $fam = $fila.Familia
    $estilo = Estilo-Icono $fam
    $fila.IconoGlifo = $estilo[0]; $fila.IconoFondo = $estilo[1]
    # Línea de debajo del nombre: sistema · de qué base · tipo · red · IP
    $partes = @($fam)
    if ($fila.Base -and -not $fila.EsBase) { $partes += "de $($fila.Base)" }
    if ($fila.Tipo -and -not $fila.EsBase -and -not $fila.EsDesechable) { $partes += $fila.Tipo }
    if ($fila.Red) { $partes += $fila.Red }
    if ($fila.IP) { $partes += $fila.IP }
    $fila.Linea = (@($partes | Where-Object { $_ }) -join '  ·  ')
    # RAM (de su .vmx) y línea corta de las tarjetas: sistema · red · RAM
    $fila.Ram = ''
    try {
        $mb = [int](Leer-ValorVmx $fila.Vmx 'memsize')
        if ($mb -ge 1024) { $fila.Ram = ('{0:0.#} GB' -f ($mb / 1024)) } elseif ($mb -gt 0) { $fila.Ram = "$mb MB" }
    } catch {}
    $fila.LineaCorta = (@(@($fam, [string]$fila.Red, $fila.Ram) | Where-Object { $_ }) -join '  ·  ')
    $sis = Sistema-DeMaquina $fila
    if ($sis) { Poner-Simbolo $fila $sis }
    else {
        $logo = Logo-DeMaquina $fila
        if ($logo) { $fila.IconoLogo = $logo; $fila.IconoGlifo = '' }
    }
    [void](Aplicar-Estado $fila)
    Poner-AccionesRapidas $fila
    return $fila
}

# ---------------------------------------------------------------- filtros y búsqueda
# Filtro por etiquetas (ficha 18): vale la máquina que tenga CUALQUIERA de las etiquetas marcadas ($script:filtroEtq, en minúsculas)
$script:filtroEtq = @()
function Etiquetas-DeFila($o) { return @(@($o.EtiquetaLab) + @($o.Etiquetas) | Where-Object { $_ }) }
function Pasa-FiltroEtq($o) {
    if (-not $script:filtroEtq.Count) { return $true }
    foreach ($etqFila in (Etiquetas-DeFila $o)) { if ($script:filtroEtq -contains ([string]$etqFila).ToLowerInvariant()) { return $true } }
    return $false
}
function Estadisticas-Etiquetas {
    # Cada etiqueta que existe (también la «Lab …») con cuántas máquinas la tienen, por orden alfabético
    $cuentaEtq = [ordered]@{}
    foreach ($o in @($script:filas)) {
        foreach ($etqFila in (Etiquetas-DeFila $o)) {
            $k = ([string]$etqFila).ToLowerInvariant()
            if (-not $cuentaEtq.Contains($k)) { $cuentaEtq[$k] = @{ Nombre = [string]$etqFila; N = 0 } }
            $cuentaEtq[$k].N++
        }
    }
    return @($cuentaEtq.Values | Sort-Object { $_.Nombre })
}
function Etiquetas-Usadas {
    # Las etiquetas que ya llevan otras máquinas (sin las «Lab …»), las más usadas primero: son las sugerencias del editor
    $cuentaUsa = @{}
    foreach ($mq in @($script:maquinas)) { foreach ($etqMq in @($mq.Etiquetas)) { if ($etqMq) { $cuentaUsa[[string]$etqMq] = 1 + [int]$cuentaUsa[[string]$etqMq] } } }
    return @($cuentaUsa.GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } } | ForEach-Object { $_.Key })
}
function Actualizar-BotonFiltroEtq {
    $nEtq = $script:filtroEtq.Count
    $BtnFiltroEtq.Content = $(if ($nEtq) { "Etiquetas ($nEtq) ▾" } else { 'Etiquetas ▾' })
    $BtnFiltroEtq.FontWeight = $(if ($nEtq) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Medium })
    Ref-Tema $BtnFiltroEtq ([System.Windows.Controls.Control]::ForegroundProperty) $(if ($nEtq) { 'T_acento' } else { 'T_texto' })
    $BtnQuitarFiltroEtq.Visibility = $(if ($nEtq) { 'Visible' } else { 'Collapsed' })
    $BtnLimpiarFiltroEtq.Visibility = $(if ($nEtq) { 'Visible' } else { 'Collapsed' })
}
function Pintar-FiltroEtq {
    $existentes = @(Estadisticas-Etiquetas)
    # Si una etiqueta marcada ya no la lleva ninguna máquina, se desmarca sola
    $clavesExisten = @($existentes | ForEach-Object { $_.Nombre.ToLowerInvariant() })
    $script:filtroEtq = @($script:filtroEtq | Where-Object { $clavesExisten -contains $_ })
    $ListaEtq.Children.Clear()
    $SinEtqFiltro.Visibility = $(if ($existentes.Count) { 'Collapsed' } else { 'Visible' })
    $BuscarEtq.Visibility = $(if ($existentes.Count -ge 12) { 'Visible' } else { 'Collapsed' })
    $buscaEtq = $(if ($BuscarEtq.Visibility -eq 'Visible') { $BuscarEtq.Text.Trim() } else { '' })
    foreach ($et in $existentes) {
        if ($buscaEtq -and $et.Nombre.IndexOf($buscaEtq, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $casilla = New-Object System.Windows.Controls.CheckBox
        $casilla.Style = [System.Windows.Application]::Current.FindResource('Casilla')
        $casilla.Content = "$($et.Nombre)   ($($et.N))"
        $casilla.Tag = $et.Nombre.ToLowerInvariant()
        $casilla.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
        $casilla.IsChecked = ($script:filtroEtq -contains $casilla.Tag)
        [System.Windows.Automation.AutomationProperties]::SetName($casilla, "Etiqueta $($et.Nombre), $($et.N)")
        $casilla.Add_Click({
            param($s, $a)
            $marcada = @($script:filtroEtq | Where-Object { $_ -ne $s.Tag })
            if ($s.IsChecked) { $marcada += [string]$s.Tag }
            $script:filtroEtq = $marcada
            Actualizar-BotonFiltroEtq
            Refrescar-Vista 0
        })
        [void]$ListaEtq.Children.Add($casilla)
    }
    Actualizar-BotonFiltroEtq
}
function Quitar-FiltroEtq {
    $script:filtroEtq = @()
    $PopFiltroEtq.IsOpen = $false
    Actualizar-BotonFiltroEtq
    Refrescar-Vista 1
}

function Pasa-Filtro($o) {
    if ($script:filtro -eq 'FiltroEnc' -and -not $o.Datos.Encendida) { return $false }
    if ($script:filtro -eq 'FiltroBases' -and -not $o.EsBase) { return $false }
    if ($script:filtro -eq 'FiltroDesech' -and -not $o.EsDesechable) { return $false }
    if ($script:filtro -eq 'FiltroFc' -and -not $o.EsFc) { return $false }   # solo las hechas con Full Cowl (llevan la etiqueta FC)
    if (-not (Pasa-FiltroEtq $o)) { return $false }
    $buscado = $Buscar.Text.Trim()
    if ($buscado) {
        $todo = "$($o.Nombre) $($o.Familia) $($o.Base) $($o.IP) $($o.Tipo) $($o.Dominio) $($o.Red) $($o.EtqTodo)"
        return $todo.IndexOf($buscado, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }
    return $true
}

function Animar-Entrada([double]$paso = 35) {
    # Las tarjetas aparecen una detrás de otra (ficha 22; lo decide animaciones.ps1 según el ajuste Animaciones)
    $Lista.UpdateLayout()
    $conts = @()
    for ($i = 0; $i -lt $Lista.Items.Count; $i++) {
        $cont = $Lista.ItemContainerGenerator.ContainerFromIndex($i)
        if ($cont) { $conts += $cont }
    }
    Entrada-Escalonada $conts
}

function Refrescar-Vista([double]$paso = 0) {
    if (-not $script:vista) { return }
    $script:vista.Refresh()
    $hayAlguna = -not $script:vista.IsEmpty
    $Vacio.Visibility = $(if ($script:cargado -and -not $hayAlguna) { 'Visible' } else { 'Collapsed' })
    if ($script:cargado -and -not $hayAlguna) {
        if ($script:filas.Count) {
            $mqBus = $Buscar.Text.Trim(); if ($mqBus.Length -gt 24) { $mqBus = $mqBus.Substring(0, 24) + '…' }
            $mqTit = $(if ($mqBus) { "No hay nada con «$mqBus»" } else { 'No hay máquinas que coincidan' })
            if ($script:filtroEtq.Count -and -not $mqBus -and $script:filtro -eq 'FiltroTodas') {
                Poner-Vacio $Vacio 'Ico_Etiqueta' 'No hay máquinas con esas etiquetas' 'Quita el filtro de etiquetas para ver todas.' 'Quitar filtro' { Quitar-FiltroEtq } $false
            } else {
                Poner-Vacio $Vacio 'Ico_Buscar' $mqTit 'Prueba con otra palabra o borra la búsqueda.' 'Borrar búsqueda' { $Buscar.Text = '' } $false
            }
        } else {
            Poner-Vacio $Vacio 'Ico_Maquinas' 'Aún no tienes máquinas' 'Crea la primera a partir de una base, o importa una que ya tengas.' 'Nueva máquina' { $NavNueva.IsChecked = $true } $true
        }
    }
    if ($paso -gt 0) { Animar-Entrada $paso }
}
foreach ($ch in @($FiltroTodas, $FiltroEnc, $FiltroBases, $FiltroDesech, $FiltroFc)) {
    $ch.Add_Checked({ param($s, $e) $script:filtro = $s.Name; Refrescar-Vista 1 })
}
$Buscar.Add_TextChanged({ Refrescar-Vista 0 })
# Botón «Etiquetas ▾»: abre el menú con una casilla por etiqueta (se pueden marcar varias a la vez)
# El menú se abre y se cierra a mano (StaysOpen=True), sin el cierre automático de WPF: ese cierre automático chocaba con
# el clic del propio botón y, pinchando muchas veces seguidas, lo abría y cerraba a destiempo. Ahora:
#   · pinchar el botón alterna (abre / cierra);
#   · cualquier clic en la ventana fuera del botón y del menú, Esc, cambiar de ventana, mover o cambiar de tamaño la ventana lo cierra.
function Cerrar-MenuEtq { if ($PopFiltroEtq.IsOpen) { $PopFiltroEtq.IsOpen = $false } }
$BtnFiltroEtq.Add_Click({
    if ($PopFiltroEtq.IsOpen) { Cerrar-MenuEtq; return }
    $BuscarEtq.Text = ''
    Pintar-FiltroEtq
    $PopFiltroEtq.IsOpen = $true
})
$script:ventana.Add_PreviewMouseDown({
    param($s, $a)
    if (-not $PopFiltroEtq.IsOpen) { return }
    # Un clic sobre el propio botón lo gestiona su Click (alternar). Los clics dentro del menú también suben hasta la ventana
    # (los eventos de un Popup viajan por el árbol lógico): esos no lo cierran
    $origen = $a.OriginalSource -as [System.Windows.DependencyObject]
    while ($origen) {
        if ([object]::ReferenceEquals($origen, $BtnFiltroEtq) -or [object]::ReferenceEquals($origen, $PopFiltroEtq.Child)) { return }
        $origen = $(if ($origen -is [System.Windows.Media.Visual] -or $origen -is [System.Windows.Media.Media3D.Visual3D]) { [System.Windows.Media.VisualTreeHelper]::GetParent($origen) } else { [System.Windows.LogicalTreeHelper]::GetParent($origen) })
    }
    Cerrar-MenuEtq
})
$script:ventana.Add_Deactivated({ Cerrar-MenuEtq })
$script:ventana.Add_LocationChanged({ Cerrar-MenuEtq })
$script:ventana.Add_SizeChanged({ Cerrar-MenuEtq })
$PopFiltroEtq.Child.Add_PreviewKeyDown({ param($s, $a) if ($a.Key -eq [System.Windows.Input.Key]::Escape) { Cerrar-MenuEtq; $a.Handled = $true } })
$BtnQuitarFiltroEtq.Add_Click({ Quitar-FiltroEtq })
$BtnLimpiarFiltroEtq.Add_Click({ Quitar-FiltroEtq })
$BuscarEtq.Add_TextChanged({ if ($PopFiltroEtq.IsOpen) { Pintar-FiltroEtq } })

# ---------------------------------------------------------------- selección y panel de detalle
# $script:selForzada: «Laboratorio» pone aquí las máquinas elegidas en su mapa y pulsa los botones de esta página
function Maquina-Sel { if ($script:selForzada) { return @($script:selForzada)[0] }; $sel = @($Lista.SelectedItems); if ($sel.Count -eq 1) { return $sel[0].Datos } return $null }
function Maquinas-Sel { if ($script:selForzada) { return @($script:selForzada) }; return @($Lista.SelectedItems | ForEach-Object { $_.Datos }) }

# Selector «Símbolo» del panel de detalle: Automático (deducir) + los 8 símbolos. Se guarda en el .vmx (solo con la máquina apagada y sin ser base)
$script:cargandoSimbolo = $false
$script:opcionesSimbolo = @('auto') + @($script:Simbolos.Keys)
foreach ($opS in $script:opcionesSimbolo) { [void]$CmbSimbolo.Items.Add($(if ($opS -eq 'auto') { 'Automático' } else { $script:Simbolos[$opS].Nombre })) }
function Poner-SelectorSimbolo($f) {
    $script:cargandoSimbolo = $true
    try {
        $g = Sistema-Guardado ([string]$f.Vmx)
        $CmbSimbolo.SelectedIndex = $(if ($g) { $script:opcionesSimbolo.IndexOf($g) } else { 0 })
        $CmbSimbolo.IsEnabled = (-not $f.EsBase) -and (-not $f.Encendida)
    } finally { $script:cargandoSimbolo = $false }
}
$CmbSimbolo.Add_SelectionChanged({
    if ($script:cargandoSimbolo -or $CmbSimbolo.SelectedIndex -lt 0) { return }
    $sel = @($Lista.SelectedItems)
    if ($sel.Count -ne 1 -or $sel[0].EsBase -or $sel[0].Encendida) { return }
    $clave = $script:opcionesSimbolo[$CmbSimbolo.SelectedIndex]
    try {
        Fijar-ValoresVmx ([string]$sel[0].Vmx) @{ 'guestinfo.vmtareas.sistema' = $(if ($clave -eq 'auto') { '' } else { $clave }) }
        Cargar -Silencioso
    } catch { Error-Amable 'No he podido cambiar el símbolo de la máquina.' 'Comprueba que la máquina no está ocupada y vuelve a intentarlo.' $_.Exception.Message }
})

# ---------------------------------------------------------------- notas y etiquetas del panel de detalle (ficha 18)
# Se guardan solas en el .vmx de la máquina (la que estaba elegida cuando se escribió: $script:detVmx), también encendida.
# Si no se puede escribir se avisa con el mensaje amable y lo escrito se queda en pantalla
$script:detVmx = ''
$script:detNota = ''
$script:guardandoNota = $false
$script:editorEtq = Nuevo-EditorEtiquetas
$script:editorEtq.Sugerir = { Etiquetas-Usadas }
$script:editorEtq.AlCambiar = {
    param($editor, $nuevasEtq)
    if (-not $editor.Contexto) { return $false }
    try {
        Guardar-EtiquetasNota $editor.Contexto $nuevasEtq $null
    } catch {
        Error-Amable 'No he podido guardar.' 'Apaga la máquina o prueba otra vez.' $_.Exception.Message
        return $false
    }
    Recargar-Luego 400   # la tarjeta de la lista se pone al día
    return $true
}
$HuecoEtq.Content = $script:editorEtq.Raiz

$relojGuardado = New-Object System.Windows.Threading.DispatcherTimer
$relojGuardado.Interval = [TimeSpan]::FromMilliseconds(1800)
$relojGuardado.Add_Tick({ $relojGuardado.Stop(); Animar $NotaGuardada $propOpacidad 0 400 })
function Avisar-Guardado {
    Animar $NotaGuardada $propOpacidad 1 160
    $relojGuardado.Stop(); $relojGuardado.Start()
}

function Poner-NotasDetalle($f) {
    $vmxDet = [string]$f.Vmx
    $mismaMaquina = ($script:detVmx -eq $vmxDet)
    $script:detVmx = $vmxDet
    # Mientras se escribe en una de las dos cajas, una recarga de fondo no debe pisar lo escrito
    $escribiendo = $mismaMaquina -and ($script:editorEtq.E.CampoEtq.IsKeyboardFocusWithin -or $CajaNota.IsKeyboardFocusWithin)
    if ($escribiendo) { return }
    Etq-Poner $script:editorEtq @($f.Etiquetas) @($f.EtiquetaLab) $vmxDet
    $script:cargandoNota = $true
    try { $CajaNota.Text = [string]$f.Nota } finally { $script:cargandoNota = $false }
    $script:detNota = [string]$f.Nota
    $ContadorNota.Text = "$($CajaNota.Text.Length)/500"
}
$CajaNota.Add_TextChanged({
    $ContadorNota.Text = "$($CajaNota.Text.Length)/500"
    $ContadorNota.Foreground = $(if ($CajaNota.Text.Length -ge 480) { Pincel $Colores.Aviso } else { Pincel $Colores.Suave })
})
$CajaNota.Add_LostKeyboardFocus({
    # Guardado automático al salir de la caja (sin botón)
    if ($script:guardandoNota -or -not $script:detVmx) { return }
    $notaNueva = $CajaNota.Text.Replace("`r`n", "`n")
    if ($notaNueva -eq [string]$script:detNota) { return }
    $script:guardandoNota = $true
    try {
        Guardar-EtiquetasNota $script:detVmx $null $notaNueva
        $script:detNota = $notaNueva
        Avisar-Guardado
        Recargar-Luego 400
    } catch {
        Error-Amable 'No he podido guardar.' 'Apaga la máquina o prueba otra vez. Lo que escribiste sigue en la caja.' $_.Exception.Message
    } finally { $script:guardandoNota = $false }
})

function Mostrar-Detalle([switch]$SinAnimar) {
    $sel = @($Lista.SelectedItems)
    if (-not $sel.Count) {
        $DetalleDatos.Visibility = 'Collapsed'
        $DetalleVacio.Visibility = 'Visible'
        return
    }
    $DetalleVacio.Visibility = 'Collapsed'
    $DetalleDatos.Visibility = 'Visible'
    if ($sel.Count -eq 1) {
        $f = $sel[0]; $m = $f.Datos
        $DetGlifo.Text = $f.IconoGlifo
        $DetLogo.Data = $f.IconoLogo
        $DetSimbolo.Data = $f.IconoSimbolo
        $DetIcono.Background = Pincel-Fijo $f.IconoFondo
        $DetNombre.Text = $f.Nombre
        $DetSistema.Text = $f.Familia
        # Ficha 36: idioma y zona («ES · Madrid»); las de antes, sin marca, salen como español y la zona de config
        if ($f.EsFc -or $m.EsBase) {
            try { $DetSistema.Text = "$($f.Familia)  ·  $(Texto-IdiomaZona ([string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.idioma')) ([string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.zona')))" } catch {}
        }
        $DetChips.Visibility = 'Visible'
        $DetInfo.Visibility = 'Visible'
        $DetFcChip.Visibility = $(if ($f.EsFc) { 'Visible' } else { 'Collapsed' })
        $DetTipo.Text = $(if ($f.Tipo) { $f.Tipo } else { 'No es de Full Cowl' })
        $DetTipoChip.Background = Pincel $(if ($f.EsDesechable) { '#FBF3DD' } else { '#E3F1E7' })
        $DetTipo.Foreground = Pincel $(if ($f.EsDesechable) { '#8A6D1F' } else { '#2D6A3E' })
        $colorEst = switch ($m.Estado) { 'Encendida' { $Colores.Ok } 'Suspendida' { $Colores.Aviso } 'Sin base' { $Colores.Error } default { $Colores.Suave } }
        $DetEstado.Text = [string]$m.Estado
        $trDet = $script:transiciones[([string]$m.Vmx).ToLower()]
        if ($trDet) { $DetEstado.Text = $trDet.Texto; $colorEst = $Colores.Verde }
        $DetEstado.Foreground = Pincel $colorEst
        $DetEstadoPunto.Fill = Pincel $colorEst
        $DetEstadoChip.Background = Pincel $fondoDeColor[$colorEst]
        $DetBase.Text = $(if ($f.EsBase) { 'Es una base' } else { Valor-O-Guion $f.Base })
        $DetRed.Text = Valor-O-Guion $f.Red
        $DetIP.Text = Valor-O-Guion $f.IP
        $DetDominio.Text = Valor-O-Guion $f.Dominio
        $DetTamano.Text = Valor-O-Guion $f.TamanoTexto
        $DetCarpeta.Text = Valor-O-Guion $f.Carpeta
        $DetCarpeta.ToolTip = $(if ($f.Carpeta) { $f.Carpeta } else { $null })
        Pintar-ProgresoDetalle $f
        Poner-SelectorSimbolo $f
        $DetNotas.Visibility = 'Visible'
        Poner-NotasDetalle $f
        # Igual que la ventana de siempre: las bases están protegidas y cada botón solo se activa cuando tiene sentido
        $sinBase = $m.Estado -eq 'Sin base'
        $noEsBase = -not $m.EsBase
        foreach ($acc in $script:acciones) { $acc.IsEnabled = $noEsBase }
        $AccEncender.IsEnabled = $noEsBase -and -not $m.Encendida -and -not $sinBase
        $AccApagar.IsEnabled = $noEsBase -and [bool]$m.Encendida
        $AccUsuarios.IsEnabled = $noEsBase -and -not $sinBase
        $AccConservar.IsEnabled = $noEsBase -and [bool]$m.Desechable
        $AccCarpeta.IsEnabled = $true
        if ($trDet) { $AccEncender.IsEnabled = $false; $AccApagar.IsEnabled = $false }
        $DetAvisoBase.Visibility = $(if ($m.EsBase) { 'Visible' } else { 'Collapsed' })
    } else {
        $todas = @($sel | ForEach-Object { $_.Datos })
        $hayBase = @($todas | Where-Object { $_.EsBase }).Count -gt 0
        $DetGlifo.Text = Glifo 0xE8B3
        $DetLogo.Data = $null
        $DetSimbolo.Data = $null
        $DetIcono.Background = Pincel-Fijo '#12261A'
        $DetNombre.Text = "$($sel.Count) máquinas elegidas"
        $DetSistema.Text = (@($sel | ForEach-Object { $_.Nombre }) -join ', ')
        $DetChips.Visibility = 'Collapsed'
        $DetInfo.Visibility = 'Collapsed'
        $DetNotas.Visibility = 'Collapsed'
        $DetProgresoCaja.Visibility = 'Collapsed'
        # Con varias: Encender, Apagar, Red y Borrar trabajan con todas
        foreach ($acc in $script:acciones) { $acc.IsEnabled = $false }
        $AccEncender.IsEnabled = (-not $hayBase) -and @($todas | Where-Object { -not $_.Encendida -and $_.Estado -ne 'Sin base' }).Count -gt 0
        $AccApagar.IsEnabled = (-not $hayBase) -and @($todas | Where-Object { $_.Encendida }).Count -gt 0
        $AccRed.IsEnabled = -not $hayBase
        $AccBorrar.IsEnabled = -not $hayBase
        $AccConservar.IsEnabled = (-not $hayBase) -and @($todas | Where-Object { $_.Desechable }).Count -gt 0
        $DetAvisoBase.Visibility = $(if ($hayBase) { 'Visible' } else { 'Collapsed' })
    }
    if (-not $SinAnimar) {
        # El panel entra deslizándose desde la derecha
        $mov = New-Object System.Windows.Media.TranslateTransform(18, 0)
        $DetalleDatos.RenderTransform = $mov
        Animar $DetalleDatos $propOpacidad 1 240 0
        Animar $mov $propX 0 320
    }
}

function Pintar-ProgresoDetalle($f) {
    $i = Progreso-DeMaquina $f.Datos
    if ($i) {
        $total = Tiempo-Total (Entrada-Progreso $f.Datos)
        $reloj = if ($total -lt 0) { '' } elseif ($i.Final) { "`nLista en $(Formato-Tiempo $total) desde que se creó" } else { "`nTotal: $(Formato-Tiempo $total) desde que se creó" }
        $DetProgreso.Text = $i.Largo + $(if ($i.Tiempo -and -not $i.Final) { "  ·  este paso: $($i.Tiempo)" } else { '' }) + $reloj
        $DetProgreso.Foreground = Pincel $i.Color
        $DetProgresoBarra.Value = $i.Pct
        $DetProgresoBarra.Foreground = Pincel $i.Color
        Brillo-Barra $DetProgresoBarra ([double]$i.Pct) ([string]$i.Color)
        $DetProgresoCaja.Background = Pincel $fondoDeColor[$i.Color]
        $DetProgresoCaja.Visibility = 'Visible'
    } else {
        $DetProgresoCaja.Visibility = 'Collapsed'
    }
    # Extras pedidos al crearla (ficha 20) y cómo ha ido cada uno
    $infoExt = $null
    try { $infoExt = Lineas-EstadoExtras $f.Datos (Entrada-Progreso $f.Datos) } catch { Escribir-Log ("Extras (detalle): " + $_.Exception.Message) }
    if ($infoExt) {
        $DetExtras.Text = $infoExt.Texto + $(if ($infoExt.Fallos) { "`nEl registro está dentro de la máquina: " + $(if ($f.Datos.EsWindows) { 'C:\ProgramData\VMTareas\extras.log' } else { '/var/log/fullcowl-extras.log' }) } else { '' })
        $DetExtras.Visibility = 'Visible'
    } else { $DetExtras.Visibility = 'Collapsed' }
}
$Lista.Add_SelectionChanged({ Mostrar-Detalle })

# ---------------------------------------------------------------- vista de la lista (tarjetas o lista) y tamaños
# Medidas de la ficha 8. «Min» = ancho mínimo de la tarjeta; las tarjetas se reparten en tantas columnas como quepan
$script:MedidasMaq = @{
    Tarjetas = @{
        Compacto = @{ Min = 190; Pad = 12; Circ = 30; Sep = 10; PadLogo = 7;  Glifo = 14; Detalle = $false; Botones = $false }
        Normal   = @{ Min = 236; Pad = 16; Circ = 38; Sep = 12; PadLogo = 9;  Glifo = 17; Detalle = $true;  Botones = $false }
        Grande   = @{ Min = 330; Pad = 20; Circ = 50; Sep = 14; PadLogo = 12; Glifo = 22; Detalle = $true;  Botones = $true }
    }
    Lista = @{
        Compacto = @{ Alto = 42; Circ = 24; PadLogo = 6; Glifo = 12 }
        Normal   = @{ Alto = 54; Circ = 30; PadLogo = 7; Glifo = 14 }
        Grande   = @{ Alto = 68; Circ = 38; PadLogo = 9; Glifo = 17 }
    }
}
$script:vistaMaq = 'Tarjetas'; $script:tamMaq = 'Normal'; $script:ultAncho = -1

function Poner-RecursoApp([string]$clave, $valor) {
    [System.Windows.Application]::Current.Resources[$clave] = $valor
}

function Recolocar-Tarjetas {
    # Ancho de cada tarjeta: las que quepan en una fila, repartiendo el sobrante (siempre se deja sitio a la barra de desplazamiento)
    if ($script:vistaMaq -eq 'Lista') {
        # Con poco ancho, primero se oculta la columna Red (antes que cortar la RAM)
        $anchoRed = $(if ($Lista.ActualWidth -gt 0 -and $Lista.ActualWidth -lt 800) { 0 } else { 100 })
        if ($script:ultAnchoRed -ne $anchoRed) { $script:ultAnchoRed = $anchoRed; Poner-RecursoApp 'Mq_AnchoRed' ([double]$anchoRed) }
        return
    }
    if ($script:vistaMaq -ne 'Tarjetas') { return }
    $m = $script:MedidasMaq.Tarjetas[$script:tamMaq]
    $disp = $Lista.ActualWidth - 4 - 14
    if ($disp -lt 100) { return }
    $n = [Math]::Max(1, [int][Math]::Floor(($disp + $m.Sep) / ($m.Min + $m.Sep)))
    $w = [Math]::Floor($disp / $n - $m.Sep)
    if ($script:ultAncho -ne $w) { $script:ultAncho = $w; Poner-RecursoApp 'Mq_Ancho' ([double]$w) }
}

function Aplicar-VistaMaquinas {
    # Vista (Tarjetas / Lista) y tamaño (Compacto / Normal / Grande) de Ajustes → Apariencia. Se aplica al instante;
    # la máquina elegida se queda elegida
    $script:vistaMaq = $(if ([string]$Config.Vista -eq 'Lista') { 'Lista' } else { 'Tarjetas' })
    $script:tamMaq = $(if (@('Compacto', 'Normal', 'Grande') -contains [string]$Config.Tamano) { [string]$Config.Tamano } else { 'Normal' })
    $app = [System.Windows.Application]::Current
    $T = [System.Windows.Thickness]
    if ($script:vistaMaq -eq 'Tarjetas') {
        $m = $script:MedidasMaq.Tarjetas[$script:tamMaq]
        Poner-RecursoApp 'Mq_Margen' ($T::new(0, 0, $m.Sep, $m.Sep))
        Poner-RecursoApp 'Mq_Relleno' ($T::new($m.Pad))
        Poner-RecursoApp 'Mq_Alto' ([double]::NaN)
        Poner-RecursoApp 'Mq_VerDetalle' $(if ($m.Detalle) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
        Poner-RecursoApp 'Mq_VerBotones' $(if ($m.Botones) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
        # Botones rápidos de la tarjeta (ficha 19): ninguno en «Compacto»; en «Grande» solo Copiar IP y Conectar (abajo ya hay Encender/Apagar)
        Poner-RecursoApp 'Mq_VerRapidos' $(if ($m.Detalle) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
        Poner-RecursoApp 'Mq_VerRapidoEnc' $(if ($m.Botones) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible })
        # El título (nombre y etiquetas BASE/FC) deja a la derecha el sitio de esos botones (con 3 botones ocupan 107 px desde el borde
        # de la tarjeta, con 2 -vista Grande- 78 px); se descuenta el relleno de la tarjeta, que ya hace de margen
        $reservaRap = $(if ($m.Detalle) { [Math]::Max(0, $(if ($m.Botones) { 78 } else { 107 }) - [double]$m.Pad) } else { 0 })
        Poner-RecursoApp 'Mq_MargenTitulo' ($T::new(12, 0, $reservaRap, 0))
    } else {
        $m = $script:MedidasMaq.Lista[$script:tamMaq]
        Poner-RecursoApp 'Mq_Margen' ($T::new(2, 0, 2, 6))
        Poner-RecursoApp 'Mq_Relleno' ($T::new(14, 0, 16, 0))
        Poner-RecursoApp 'Mq_Alto' ([double]$m.Alto)
        Poner-RecursoApp 'Mq_VerDetalle' ([System.Windows.Visibility]::Collapsed)
        Poner-RecursoApp 'Mq_VerBotones' ([System.Windows.Visibility]::Collapsed)
        Poner-RecursoApp 'Mq_VerRapidos' ([System.Windows.Visibility]::Collapsed)   # (en la lista ya hay botón de encender/apagar y menú de clic derecho)
        Poner-RecursoApp 'Mq_VerRapidoEnc' ([System.Windows.Visibility]::Collapsed)
        Poner-RecursoApp 'Mq_MargenTitulo' ($T::new(12, 0, 0, 0))
        Poner-RecursoApp 'Mq_Ancho' ([double]::NaN)
        $script:ultAncho = -1
    }
    # En pantallas táctiles (no hay «pasar el ratón») los botones rápidos se ven siempre y reciben el toque
    $hayTactil = Hay-Tactil
    Poner-RecursoApp 'Mq_RapidosOpacidad' ([double]$(if ($hayTactil) { 1 } else { 0 }))
    Poner-RecursoApp 'Mq_RapidosClic' ([bool]$hayTactil)
    Poner-RecursoApp 'Mq_Circulo' ([double]$m.Circ)
    Poner-RecursoApp 'Mq_PadLogo' ($T::new($m.PadLogo))
    Poner-RecursoApp 'Mq_FuenteGlifo' ([double]$m.Glifo)
    $plantilla = $(if ($script:vistaMaq -eq 'Lista') { 'PlantillaMaqFila' } else { 'PlantillaMaqTarjeta' })
    $panel = $(if ($script:vistaMaq -eq 'Lista') { 'PanelFila' } else { 'PanelTarjetas' })
    if ($Lista.ItemTemplate -ne $app.FindResource($plantilla)) {
        $Lista.ItemTemplate = $app.FindResource($plantilla)
        $Lista.ItemsPanel = $app.FindResource($panel)
    }
    $CabeceraLista.Visibility = $(if ($script:vistaMaq -eq 'Lista') { 'Visible' } else { 'Collapsed' })
    Recolocar-Tarjetas
}
$Lista.Add_SizeChanged({ try { Recolocar-Tarjetas } catch {} })

# ---------------------------------------------------------------- acciones rápidas (ficha 19)
# Tres botones en la tarjeta (Encender/Apagar, Copiar IP, Conectar) y el menú de clic derecho. REGLA FIRME: aquí Full Cowl no
# guarda ni pasa la contraseña a ningún programa (nada de cmdkey, sshpass ni contraseñas en la línea de comandos): se escribe a mano.
function Hay-Tactil {
    if ($null -eq $script:hayTactil) {
        $script:hayTactil = $false
        try { $script:hayTactil = @([System.Windows.Input.Tablet]::TabletDevices | Where-Object { $_.Type -eq [System.Windows.Input.TabletDeviceType]::Touch }).Count -gt 0 } catch {}
    }
    return [bool]$script:hayTactil
}
function Modo-Rapidos {
    # Cómo entran los botones rápidos de la tarjeta (ver ItemMaq en estilos.xaml): Fijo (táctil), Instante (animaciones «Ninguna») o Fundido
    if (Hay-Tactil) { return 'Fijo' }
    if ((Nivel-Animacion) -eq 0) { return 'Instante' }
    return 'Fundido'
}

function Conexion-DeMaquina($m) {
    # rdp, ssh o ninguna: del catálogo de sistemas (por la base de la máquina); si no se sabe, Windows = rdp y lo demás = ssh
    if ($m.EsBase) { return 'ninguna' }
    if (-not $script:conexionSistema) {
        $script:conexionSistema = @{}
        try { foreach ($sis in @(Obtener-Sistemas)) { $script:conexionSistema[[string]$sis.Clave] = [string]$sis.Conexion } } catch {}
    }
    $tipoCon = [string]$script:conexionSistema[[string]$m.Base]
    if ($tipoCon) { return $tipoCon }
    return $(if ($m.EsWindows) { 'rdp' } else { 'ssh' })
}

function Estado-Rapido($m) {
    # Qué botones están activos y qué ayuda sale en cada uno (para la tarjeta y para el menú)
    $esBaseR = [bool]$m.EsBase
    $encR = [bool]$m.Encendida
    $conexionR = Conexion-DeMaquina $m
    $ipFijaR = [string]$m.IP
    $sabeIp = ($ipFijaR -and (Es-IPv4 $ipFijaR)) -or $encR   # encendida: la IP se pregunta a VMware al pulsar
    $r = @{ Conexion = $conexionR }
    if ($esBaseR) { $r.PuedeIp = $false; $r.AyudaIp = 'Las bases no tienen IP' }
    elseif ($sabeIp) { $r.PuedeIp = $true; $r.AyudaIp = 'Copiar la IP' }
    else { $r.PuedeIp = $false; $r.AyudaIp = 'Aún no tiene IP: enciéndela y espera un momento' }
    if ($esBaseR) { $r.PuedeCon = $false; $r.AyudaCon = 'Las bases no se abren desde aquí' }
    elseif ($conexionR -eq 'ninguna') { $r.PuedeCon = $false; $r.AyudaCon = 'Este sistema no tiene conexión automática: usa su ventana de VMware' }
    elseif (-not $encR) { $r.PuedeCon = $false; $r.AyudaCon = 'Enciende la máquina para conectarte' }
    else { $r.PuedeCon = $true; $r.AyudaCon = $(if ($conexionR -eq 'rdp') { 'Conectar por Escritorio remoto' } else { 'Conectar por SSH' }) }
    return $r
}

function Poner-AccionesRapidas($fila) {
    $fila.ModoRapidos = Modo-Rapidos
    $er = Estado-Rapido $fila.Datos
    $fila.Conexion = [string]$er.Conexion
    $fila.PuedeCopiarIp = [bool]$er.PuedeIp
    $fila.AyudaIp = [string]$er.AyudaIp
    $fila.PuedeConectar = [bool]$er.PuedeCon
    $fila.AyudaConectar = [string]$er.AyudaCon
}

function Ip-Rapida($m) {
    # La IP fija del .vmx si la tiene; si no, la que dice VMware Tools (vmrun getGuestIPAddress). $null si no se sabe
    $fija = [string]$m.IP
    if ($fija -and (Es-IPv4 $fija)) { return $fija }
    $script:vmwareCallado = $null
    if ($m.Encendida -and $script:vmrun) {
        $rIp = Vmrun-Ventana @('getGuestIPAddress', $m.Vmx)
        if ($rIp.Agotado) { $script:vmwareCallado = $rIp; return $null }      # quien llama avisa con Avisar-VmwareCallado
        $deVmware = "$(@($rIp.Lineas | Where-Object { ([string]$_).Trim() }) | Select-Object -Last 1)".Trim()
        if (Es-IPv4 $deVmware) { return $deVmware }
    }
    return $null
}

function Copiar-AlPortapapeles([string]$textoCopiar, [string]$avisoCopiado) {
    try {
        [System.Windows.Clipboard]::SetText($textoCopiar)
        Mostrar-Toast $avisoCopiado
    } catch {
        Error-Amable 'No he podido copiar al portapapeles.' 'Otro programa lo está usando. Prueba otra vez en un momento.' $_.Exception.Message
    }
}

function Avisar-VmwareCallado {
    # Si la última consulta a VMware se quedó sin respuesta, lo dice (cuadro amable) y devuelve $true.
    # «No contesta» no es lo mismo que «no tiene IP»: no se enseña el aviso de siempre.
    if (-not $script:vmwareCallado) { return $false }
    $rCallado = $script:vmwareCallado; $script:vmwareCallado = $null
    Aviso-VmrunAgotado $rCallado
    return $true
}

function Copiar-IpMaquina($m) {
    if (-not $m -or $m.EsBase) { return }
    $ipCopiar = $null
    Iniciar-Espera; try { $ipCopiar = Ip-Rapida $m } finally { Terminar-Espera }
    if (-not $ipCopiar) { if (Avisar-VmwareCallado) { return }; Mostrar-Toast 'Aún no tiene IP: enciéndela y espera un momento.' 'info'; return }
    Copiar-AlPortapapeles $ipCopiar "Copiada: $ipCopiar"
}

function Conectar-Rapido($m) {
    if (-not $m -or $m.EsBase) { return }
    $tipoCon = Conexion-DeMaquina $m
    if ($tipoCon -eq 'ninguna') { Aviso "«$($m.Nombre)» no tiene conexión automática.`nUsa su ventana de VMware (botón «Abrir en VMware»)."; return }
    if (-not $m.Encendida) { Mostrar-Toast "Enciende antes «$($m.Nombre)»." 'info'; return }
    if (-not @($m.Tarjetas | Where-Object { $_.Tipo -ne 'pvn' }).Count) {
        Error-Amable "«$($m.Nombre)» solo está en segmentos LAN y tu PC no llega a ellos." 'Añádele una tarjeta NAT con «Red» o usa su ventana de VMware.'; return
    }
    $ipCon = $null
    Iniciar-Espera; try { $ipCon = Ip-Rapida $m } finally { Terminar-Espera }
    if (-not $ipCon) { if (Avisar-VmwareCallado) { return }; Error-Amable "Aún no sé la IP de «$($m.Nombre)»." 'Espera un momento a que termine de arrancar (Windows necesita las VMware Tools) y vuelve a probar.'; return }
    $usuarioCon = [string](Usuario-DeVm $m.Vmx)
    if ($tipoCon -eq 'rdp') {
        $abierto = $false
        Iniciar-Espera; try { $abierto = Puerto-Abierto $ipCon 3389 } finally { Terminar-Espera }
        if (-not $abierto) {
            Error-Amable "El Escritorio remoto no responde en $ipCon." 'Actívalo en la máquina (Configuración > Sistema > Escritorio remoto) o créala marcando «Escritorio remoto (RDP)».'; return
        }
        try { Start-Process mstsc.exe -ArgumentList "/v:$ipCon" }
        catch { Error-Amable 'No he podido abrir el Escritorio remoto.' 'Comprueba que Windows tiene «Conexión a Escritorio remoto» (mstsc.exe).' $_.Exception.Message; return }
        $quien = $(if ($m.Netbios) { "$($m.Netbios)\$usuarioCon" } else { $usuarioCon })
        Mostrar-Toast "Escritorio remoto a «$($m.Nombre)» ($ipCon). Usuario: $quien. La contraseña la escribes tú."
        return
    }
    # SSH: una consola con «ssh usuario@IP». El nombre y la IP se comprueban antes de ponerlos en una línea de comandos
    if (-not (Usuario-SeguroEnOrden $usuarioCon)) { Error-Amable 'El usuario de la máquina tiene caracteres raros.' 'Conéctate a mano desde una consola.'; return }
    if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
        Error-Amable 'Este PC no tiene el cliente SSH.' 'Windows 10 y 11 lo traen: actívalo en Configuración > Aplicaciones > Características opcionales > «Cliente OpenSSH». Hay más ayuda en el manual (Solución de problemas).'; return
    }
    $abierto = $false
    Iniciar-Espera; try { $abierto = Puerto-Abierto $ipCon 22 } finally { Terminar-Espera }
    if (-not $abierto) { Error-Amable "SSH no responde en $ipCon." '¿Está instalado y arrancado el servidor (openssh-server)? Espera un momento si la máquina acaba de encenderse.'; return }
    $tituloSsh = ("SSH $($m.Nombre)" -replace '[^\w .-]', '')
    try {
        if (Get-Command wt.exe -ErrorAction SilentlyContinue) { Start-Process wt.exe -ArgumentList "new-tab --title `"$tituloSsh`" ssh $usuarioCon@$ipCon" }
        else { Start-Process cmd.exe -ArgumentList "/k `"title $tituloSsh & ssh $usuarioCon@$ipCon`"" }
    } catch { Error-Amable 'No he podido abrir la consola de SSH.' 'Prueba a abrir una consola y escribir: ssh usuario@IP' $_.Exception.Message; return }
    Mostrar-Toast "SSH a «$($m.Nombre)» ($ipCon). Usuario: $usuarioCon. La primera vez pregunta por la huella: escribe yes. La contraseña la escribes tú."
}

function Abrir-EnNavegador($m) {
    if (-not $m -or $m.EsBase) { return }
    $ipWeb = $null
    Iniciar-Espera; try { $ipWeb = Ip-Rapida $m } finally { Terminar-Espera }
    if (-not $ipWeb) { if (Avisar-VmwareCallado) { return }; Mostrar-Toast 'Aún no tiene IP: enciéndela y espera un momento.' 'info'; return }
    try { Start-Process "http://$ipWeb" } catch { Error-Amable 'No he podido abrir el navegador.' "Abre a mano: http://$ipWeb" $_.Exception.Message }
}

function Abrir-CarpetaMaquina($m) {
    if ($m -and $m.Carpeta -and (Test-Path -LiteralPath $m.Carpeta)) { Start-Process explorer.exe -ArgumentList "`"$($m.Carpeta)`"" }
    else { Mostrar-Toast 'No encuentro la carpeta de la máquina.' 'info' }
}

# ---------------------------------------------------------------- menú de clic derecho (ficha 19)
function Opciones-MenuMaquina($datos) {
    # Lista de filas del menú para esas máquinas: @{ T = texto; Accion; Icono; Ok; Ayuda } o @{ Sep = $true }
    $d = @($datos | Where-Object { $_ })
    $ops = @()
    if (-not $d.Count) { return $ops }
    if ($d.Count -gt 1) {
        # Con varias solo Encender y Apagar
        $sinBases = @($d | Where-Object { -not $_.EsBase })
        $porEncender = @($sinBases | Where-Object { -not $_.Encendida -and $_.Estado -ne 'Sin base' })
        $porApagar = @($sinBases | Where-Object { $_.Encendida })
        if ($porEncender.Count) { $ops += @{ T = "Encender ($($porEncender.Count))"; Accion = 'Encender'; Icono = 'Encender'; Ok = $true; Datos = $porEncender } }
        if ($porApagar.Count) { $ops += @{ T = "Apagar ($($porApagar.Count))"; Accion = 'Apagar'; Icono = 'Apagar'; Ok = $true; Datos = $porApagar } }
        return $ops
    }
    $m = $d[0]
    $er = Estado-Rapido $m
    if (-not $m.EsBase) {
        if ($m.Encendida) { $ops += @{ T = 'Apagar'; Accion = 'Apagar'; Icono = 'Apagar'; Ok = $true; Datos = @($m) } }
        else { $ops += @{ T = 'Encender'; Accion = 'Encender'; Icono = 'Encender'; Ok = ($m.Estado -ne 'Sin base'); Ayuda = $(if ($m.Estado -eq 'Sin base') { 'Su base ya no existe: no arrancará' } else { '' }); Datos = @($m) } }
        $ops += @{ T = 'Copiar IP'; Accion = 'CopiarIp'; Icono = 'Copiar'; Ok = $er.PuedeIp; Ayuda = [string]$er.AyudaIp; Datos = @($m) }
        $ops += @{ T = $(if ($er.Conexion -eq 'ssh') { 'Conectar (SSH)' } elseif ($er.Conexion -eq 'rdp') { 'Conectar (Escritorio remoto)' } else { 'Conectar' }); Accion = 'Conectar'; Icono = 'Conectar'; Ok = $er.PuedeCon; Ayuda = [string]$er.AyudaCon; Datos = @($m) }
        if ($m.Web) { $ops += @{ T = 'Abrir en el navegador'; Accion = 'Navegador'; Icono = 'Abrir'; Ok = [bool]$m.Encendida; Ayuda = $(if ($m.Encendida) { '' } else { 'Enciende la máquina primero' }); Datos = @($m) } }
        $ops += @{ Sep = $true }
    }
    $ops += @{ T = 'Copiar nombre'; Accion = 'CopiarNombre'; Icono = 'Copiar'; Ok = $true; Datos = @($m) }
    if (-not $m.EsBase -and $er.Conexion -eq 'ssh') {
        $ops += @{ T = 'Copiar usuario@IP'; Accion = 'CopiarUsuarioIp'; Icono = 'Copiar'; Ok = $er.PuedeIp; Ayuda = $(if ($er.PuedeIp) { '' } else { [string]$er.AyudaIp }); Datos = @($m) }
    }
    $ops += @{ T = 'Abrir carpeta de la máquina'; Accion = 'Carpeta'; Icono = 'Carpeta'; Ok = $true; Datos = @($m) }
    return $ops
}

function Ejecutar-AccionMaq([string]$accion, $datos) {
    $d = @($datos | Where-Object { $_ })
    if (-not $d.Count) { return }
    switch ($accion) {
        'Encender' { Con-Seleccion $d $AccEncender }
        'Apagar' { Con-Seleccion $d $AccApagar }
        'CopiarIp' { Copiar-IpMaquina $d[0] }
        'Conectar' { Conectar-Rapido $d[0] }
        'Navegador' { Abrir-EnNavegador $d[0] }
        'CopiarNombre' { Copiar-AlPortapapeles ([string]$d[0].Nombre) "Copiado: $($d[0].Nombre)" }
        'CopiarUsuarioIp' {
            $ipUsu = $null
            Iniciar-Espera; try { $ipUsu = Ip-Rapida $d[0] } finally { Terminar-Espera }
            if (-not $ipUsu) { if (Avisar-VmwareCallado) { return }; Mostrar-Toast 'Aún no tiene IP: enciéndela y espera un momento.' 'info'; return }
            $textoUsu = "$(Usuario-DeVm $d[0].Vmx)@$ipUsu"
            Copiar-AlPortapapeles $textoUsu "Copiado: $textoUsu"
        }
        'Carpeta' { Abrir-CarpetaMaquina $d[0] }
        'LabGuardarInicial' { Guardar-EstadoAhoraLab @(Filas-EstadoLab) }
        'LabQuitarInicial' { Quitar-EstadoInicialLab }
    }
}

$script:popMenuMaq = $null
function Mostrar-MenuContextual($ancla, $opciones, [bool]$enRaton, [bool]$conTeclado = $false) {
    # Menú con los colores de la app (los menús de Windows desentonan). Abre en el puntero o debajo del ancla. Esc lo cierra,
    # arriba/abajo y Tab se mueven por las filas
    $ops = @($opciones)
    if (-not $ops.Count) { return }
    try { if ($script:popMenuMaq) { $script:popMenuMaq.IsOpen = $false } } catch {}
    $pop = New-Object System.Windows.Controls.Primitives.Popup
    $pop.PlacementTarget = $ancla
    $pop.Placement = $(if ($enRaton) { 'MousePoint' } else { 'Bottom' })
    $pop.StaysOpen = $false; $pop.AllowsTransparency = $true
    $marco = New-Object System.Windows.Controls.Border
    $marco.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $marco.Padding = New-Object System.Windows.Thickness(5)
    $marco.BorderThickness = New-Object System.Windows.Thickness(1)
    $marco.Margin = New-Object System.Windows.Thickness(8, 4, 10, 12)
    Ref-Tema $marco ([System.Windows.Controls.Border]::BackgroundProperty) 'T_superficie'
    Ref-Tema $marco ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'
    $sombra = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sombra.BlurRadius = 14; $sombra.ShadowDepth = 2; $sombra.Opacity = 0.22; $sombra.Color = [System.Windows.Media.Colors]::Black
    $marco.Effect = $sombra
    $pila = New-Object System.Windows.Controls.StackPanel
    $primero = $null
    foreach ($op in $ops) {
        if ($op.Sep) {
            $raya = New-Object System.Windows.Shapes.Rectangle
            $raya.Height = 1; $raya.Margin = New-Object System.Windows.Thickness(6, 4, 6, 4)
            Ref-Tema $raya ([System.Windows.Shapes.Shape]::FillProperty) 'T_linea'
            [void]$pila.Children.Add($raya)
            continue
        }
        $fila = New-Object System.Windows.Controls.Button
        $fila.Style = [System.Windows.Application]::Current.FindResource('BotonMenuFila')
        $cuerpoFila = New-Object System.Windows.Controls.StackPanel
        $cuerpoFila.Orientation = 'Horizontal'
        $icono = Nuevo-Icono ([string]$op.Icono) 14 '#39824D'
        Ref-Tema $icono ([System.Windows.Controls.Control]::ForegroundProperty) 'T_acento'
        $icono.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
        [void]$cuerpoFila.Children.Add($icono)
        $rotulo = New-Object System.Windows.Controls.TextBlock
        $rotulo.Text = [string]$op.T; $rotulo.VerticalAlignment = 'Center'
        [void]$cuerpoFila.Children.Add($rotulo)
        $fila.Content = $cuerpoFila
        $fila.IsEnabled = [bool]$op.Ok
        if ($op.Ayuda) { $fila.ToolTip = [string]$op.Ayuda }
        [System.Windows.Automation.AutomationProperties]::SetName($fila, [string]$op.T)
        $fila.Tag = @{ Accion = [string]$op.Accion; Datos = @($op.Datos) }
        $fila.Add_Click({
            param($s, $a)
            try { $script:popMenuMaq.IsOpen = $false } catch {}
            try { Ejecutar-AccionMaq $s.Tag.Accion $s.Tag.Datos } catch { Escribir-Log ("Menú de máquina: " + ($_ | Out-String)); Error-Amable 'No he podido hacer eso.' 'Prueba otra vez; si sigue igual, mira el registro.' $_.Exception.Message }
        })
        if (-not $primero -and $op.Ok) { $primero = $fila }
        [void]$pila.Children.Add($fila)
    }
    $marco.Child = $pila
    $marco.Add_PreviewKeyDown({
        param($s, $a)
        $foco = [System.Windows.Input.Keyboard]::FocusedElement -as [System.Windows.UIElement]
        if ($a.Key -eq [System.Windows.Input.Key]::Escape) { try { $script:popMenuMaq.IsOpen = $false } catch {}; $a.Handled = $true }
        elseif ($foco -and $a.Key -eq [System.Windows.Input.Key]::Down) { [void]$foco.MoveFocus((New-Object System.Windows.Input.TraversalRequest([System.Windows.Input.FocusNavigationDirection]::Next))); $a.Handled = $true }
        elseif ($foco -and $a.Key -eq [System.Windows.Input.Key]::Up) { [void]$foco.MoveFocus((New-Object System.Windows.Input.TraversalRequest([System.Windows.Input.FocusNavigationDirection]::Previous))); $a.Handled = $true }
    })
    $pop.Child = $marco
    $script:popMenuMaq = $pop
    $script:menuPrimero = $(if ($conTeclado) { $primero } else { $null })
    $pop.Add_Opened({ if ($script:menuPrimero) { [void]$script:menuPrimero.Focus() } })
    $pop.IsOpen = $true
}

function Fila-DeElemento($origen) {
    # La fila (de «Mis máquinas») sobre la que se ha pulsado, o $null
    $dep = $origen -as [System.Windows.DependencyObject]
    if (-not $dep) { return $null }
    $cont = [System.Windows.Controls.ItemsControl]::ContainerFromElement($Lista, $dep)
    if ($cont) { return $cont.DataContext }
    return $null
}
# Clic derecho: elige la máquina (si no estaba ya entre las elegidas) y, al soltar, abre el menú
$Lista.Add_PreviewMouseRightButtonDown({
    param($s, $a)
    $filaClic = Fila-DeElemento $a.OriginalSource
    if (-not $filaClic) { return }
    if (-not $Lista.SelectedItems.Contains($filaClic)) { $Lista.SelectedItems.Clear(); [void]$Lista.SelectedItems.Add($filaClic) }
    $a.Handled = $true
})
$Lista.Add_PreviewMouseRightButtonUp({
    param($s, $a)
    if (-not (Fila-DeElemento $a.OriginalSource)) { return }
    $a.Handled = $true
    Mostrar-MenuContextual $Lista (Opciones-MenuMaquina @($Lista.SelectedItems | ForEach-Object { $_.Datos })) $true
})
# Tecla de menú (o Mayús+F10): el menú sale debajo de la máquina elegida
$Lista.Add_PreviewKeyDown({
    param($s, $a)
    $esMenu = ($a.Key -eq [System.Windows.Input.Key]::Apps) -or ($a.Key -eq [System.Windows.Input.Key]::F10 -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Shift)
    if (-not $esMenu -or -not $Lista.SelectedItems.Count) { return }
    $a.Handled = $true
    $contSel = $Lista.ItemContainerGenerator.ContainerFromItem($Lista.SelectedItems[0])
    Mostrar-MenuContextual $(if ($contSel) { $contSel } else { $Lista }) (Opciones-MenuMaquina @($Lista.SelectedItems | ForEach-Object { $_.Datos })) $false $true
})

# Botones rápidos de las tarjetas grandes y de la lista (Encender / Apagar / Abrir): eligen esa máquina y usan los botones del panel
$Lista.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $b = $e.OriginalSource
    if ($b -isnot [System.Windows.Controls.Button] -or -not $b.Tag -or -not $b.DataContext) { return }
    $e.Handled = $true
    # Copiar IP y Conectar (botones rápidos de la tarjeta, ficha 19) no cambian la selección
    if ([string]$b.Tag -eq 'Copiar') { Copiar-IpMaquina $b.DataContext.Datos; return }
    if ([string]$b.Tag -eq 'Conectar') { Conectar-Rapido $b.DataContext.Datos; return }
    if ($b.DataContext.Trabajando) { return }   # ya se está encendiendo o apagando
    $Lista.SelectedItems.Clear(); [void]$Lista.SelectedItems.Add($b.DataContext)
    $clic = New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
    switch ([string]$b.Tag) {
        'Enc' { $AccEncender.RaiseEvent($clic) }
        'Apa' { $AccApagar.RaiseEvent($clic) }
        'Abrir' { Abrir-EnVmware }
    }
})

# ---------------------------------------------------------------- espacio en disco y restos
$DiscoMarco.Add_SizeChanged({
    $DiscoMarco.Clip = New-Object System.Windows.Media.RectangleGeometry((New-Object System.Windows.Rect(0, 0, $DiscoMarco.ActualWidth, $DiscoMarco.ActualHeight)), 5, 5)
})
function Pintar-Disco($d) {
    if (-not $d -or -not $d.Total) { $DiscoTexto.Text = 'No se ha podido leer el disco.'; return }
    $otros = [Math]::Max([double]0, $d.Total - $d.Libre - $d.Bases - $d.Maq)
    $estrella = [System.Windows.GridUnitType]::Star
    $DiscoColBases.Width = New-Object System.Windows.GridLength($d.Bases, $estrella)
    $DiscoColBases.MinWidth = $(if ($d.Bases -gt 0) { 4 } else { 0 })   # un tramo muy pequeño se sigue viendo
    $DiscoColMaq.Width = New-Object System.Windows.GridLength($d.Maq, $estrella)
    $DiscoColOtros.Width = New-Object System.Windows.GridLength($otros, $estrella)
    $DiscoColLibre.Width = New-Object System.Windows.GridLength($d.Libre, $estrella)
    $DiscoUnidad.Text = "Disco $($d.Unidad)"
    $DiscoTexto.Text = "$(Formato-Tamano $d.Libre) libres de $(Formato-Tamano $d.Total)"
    $DiscoTexto.Foreground = Pincel $(if ($d.Libre / $d.Total -lt 0.1) { $Colores.Error } else { $Colores.Suave })
    $DiscoLeyBases.Text = "Bases  $(Formato-Tamano $d.Bases)"
    $DiscoLeyMaq.Text = "Máquinas  $(Formato-Tamano $d.Maq)"
    $DiscoLeyOtros.Text = "Otros  $(Formato-Tamano $otros)"
    # Cada base con lo que ocupa y cuántas máquinas enlazadas dependen de ella
    $det = @()
    foreach ($b in @($script:maquinas | Where-Object { $_.EsBase } | Sort-Object Nombre)) {
        $n = @($script:maquinas | Where-Object { $_.Base -eq $b.Nombre -and $_.Copia -eq 'Enlazada' }).Count
        $det += "$($b.Nombre) $(Formato-Tamano $b.Tamano)" + $(if ($n -eq 1) { ' (1 enlazada)' } elseif ($n) { " ($n enlazadas)" } else { ' (sin enlazadas)' })
    }
    $DiscoBasesDet.Text = $(if ($det.Count) { $det -join "`n" } else { 'Todavía no hay bases.' })
    $DiscoBasesDet.ToolTip = 'Una base sin máquinas enlazadas se puede rehacer o borrar sin romper ninguna máquina.'
    # El detalle por base ya no ocupa sitio en el panel: sale al pasar el ratón por la barra y la leyenda
    $textoBases = $DiscoBasesDet.Text + "`n`nUna base sin máquinas enlazadas se puede rehacer o borrar sin romper ninguna máquina."
    foreach ($el in @($DiscoMarco, $DiscoLeyBases)) { $el.ToolTip = $textoBases }
    $tamRestos = [double](($script:restos | Measure-Object Length -Sum).Sum)
    $DiscoRestos.Text = $(if ($script:restos.Count) { "Restos que se pueden borrar: $(Formato-Tamano $tamRestos)" } else { 'No hay restos que limpiar.' })
    $BtnLimpiar.IsEnabled = $script:restos.Count -gt 0
    # La barra se rellena de izquierda a derecha solo la primera vez; en las recargas (cada cambio de estado)
    # se queda como está, para que no se vea vacía mientras se vuelve a animar
    $escalaDisco = New-Object System.Windows.Media.ScaleTransform(1, 1)
    $DiscoBarra.RenderTransform = $escalaDisco
    if (-not $script:discoPintado -and -not $script:cargaSilenciosa) {
        $script:discoPintado = $true
        Animar $escalaDisco $propEscalaX 1 900 0 250
    }
}

$BtnLimpiar.Add_Click({
    $restos = @(Buscar-Restos)
    if (-not $restos.Count) { Cargar; return }
    $t = [double](($restos | Measure-Object Length -Sum).Sum)
    if (-not (Pregunta "Se borrarán $($restos.Count) archivos ($(Formato-Tamano $t)): registros antiguos, cachés de VMware de máquinas apagadas y temporales de los scripts.`n`nNo afecta a ninguna máquina ni base." 'Limpiar restos' 'Limpiar')) { return }
    $n = 0
    Iniciar-Espera; try {
        foreach ($fi in $restos) { try { Remove-Item -LiteralPath $fi.FullName -Force -ErrorAction Stop; $n++ } catch {} }
        # Carpetas que quedan vacías
        $dirs = @(Leer-Clones | ForEach-Object { Join-Path $_.Carpeta 'caches' })
        if ($Config.CarpetaBases -and (Test-Path -LiteralPath $Config.CarpetaBases)) { $dirs += @(Get-ChildItem $Config.CarpetaBases -Directory | ForEach-Object { Join-Path $_.FullName 'caches' }) }
        $dirs += (Join-Path $dirFc 'build')
        foreach ($dv in $dirs) {
            if ((Test-Path -LiteralPath $dv) -and -not (Get-ChildItem -LiteralPath $dv -Recurse -File -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $dv -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } finally { Terminar-Espera }
    Mostrar-Toast "Limpieza hecha: $(Formato-Tamano $t) liberados."
    Cargar
})

# ---------------------------------------------------------------- lectura de las máquinas (en segundo plano)
# Leer-Maquinas -ConTamano y Buscar-Restos tardan (cuentan lo que ocupa cada carpeta): se hacen en un
# hilo aparte para que la ventana no se congele. Solo leen: no encienden ni cambian nada.
$scriptCarga = @'
param($carpeta)
$EsVentana = $true
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $carpeta 'comun.ps1')
    if (-not (Config-Completa)) { return @{ Estado = 'SinConfig' } }
    # Como en la ventana de siempre: si una máquina da problemas, se sigue con las demás
    $ErrorActionPreference = 'Continue'
    $maquinas = @(Leer-Maquinas -ConTamano)
    $raizDisco = [IO.Path]::GetPathRoot($Config.CarpetaVMs)
    $unidad = New-Object System.IO.DriveInfo($raizDisco)
    $tamBases = [double]0
    $tamMaq = [double]0
    foreach ($m in $maquinas) {
        if ($m.EsBase) { $tamBases += [double]$m.Tamano }
        elseif ([IO.Path]::GetPathRoot($m.Carpeta) -eq $raizDisco) { $tamMaq += [double]$m.Tamano }
    }
    $restos = @()
    try { $restos = @(Buscar-Restos) } catch {}
    return @{ Estado = 'Ok'; Maquinas = $maquinas; Carpeta = $Config.CarpetaVMs; Unidad = $raizDisco.TrimEnd('\')
              Total = [double]$unidad.TotalSize; Libre = [double]$unidad.AvailableFreeSpace; Bases = $tamBases; Maq = $tamMaq; Restos = $restos }
} catch {
    return @{ Estado = 'Error'; Mensaje = ($_ | Out-String) + $_.ScriptStackTrace }
}
'@
$script:giro = New-Object System.Windows.Media.RotateTransform
$RefrescarGlifo.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
$RefrescarGlifo.RenderTransform = $script:giro

function Cargar([switch]$Silencioso) {
    # -Silencioso: recarga tras una acción, sin las tarjetas «latiendo» ni la entrada animada
    if ($script:cargando) { return }
    $script:cargando = $true
    $script:cargaSilenciosa = [bool]$Silencioso
    $script:inicioCarga = Get-Date
    if (-not $Silencioso -or -not $script:cargado) {
        $Esqueleto.Visibility = 'Visible'
        $Lista.Visibility = 'Collapsed'
        $Vacio.Visibility = 'Collapsed'
    }
    $vuelta = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 360, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(900))))
    $vuelta.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $script:giro.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $vuelta)
    # Hilo aparte con permiso para cargar comun.ps1 aunque la directiva de scripts del PC sea estricta. El espacio de
    # PowerShell se crea UNA vez y se reutiliza: abrirlo cuesta medio segundo largo con la ventana congelada, y antes se
    # abría uno nuevo cada vez que se entraba en «Mis máquinas»
    if (-not $script:espacio -or $script:espacio.RunspaceStateInfo.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
        try { if ($script:espacio) { $script:espacio.Dispose() } } catch {}
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
        $script:espacio = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $script:espacio.Open()
    }
    $script:hilo = [PowerShell]::Create()
    $script:hilo.Runspace = $script:espacio
    [void]$script:hilo.AddScript($scriptCarga).AddArgument($dirFc)
    $script:asincrono = $script:hilo.BeginInvoke()
    $relojCarga.Start()
}

function Terminar-Carga {
    $res = $null
    try { $res = $script:hilo.EndInvoke($script:asincrono) } catch { Escribir-Log ("Lectura de máquinas: " + ($_ | Out-String)) }
    try { $script:hilo.Dispose() } catch {}   # (el espacio se queda abierto para la próxima vez)
    $script:finCarga = Get-Date
    # El resultado es la tabla que devuelve el hilo. Ojo: llega envuelta (PSObject) y su contenido
    # se saca con .psobject.BaseObject (con .BaseObject a secas, PowerShell lo busca como clave y da vacío)
    $d = $null
    foreach ($r in @($res)) {
        $x = $r
        if ($null -ne $x -and $x.psobject) { $x = $x.psobject.BaseObject }
        if ($x -is [hashtable] -and $x.ContainsKey('Estado')) { $d = $x }
    }
    $AvisoDemo.Visibility = 'Collapsed'
    $seleccion = @($Lista.SelectedItems | ForEach-Object { $_.Vmx })
    if ($d -and $d.Estado -eq 'Ok') {
        $script:maquinas = @($d.Maquinas)
        $script:restos = @($d.Restos)
        $disco = $d
        $carpetaVms = [string]$d.Carpeta
    } else {
        if (-not $d) { Escribir-Log ("Lectura de máquinas: resultado no reconocido (" + @($res).Count + " elementos)") }
        elseif ($d.Mensaje) { Escribir-Log ("Lectura de máquinas: " + $d.Mensaje) }
        $AvisoDemoTexto.Text = 'No se han podido leer tus máquinas. El detalle está en full-cowl\estado\interfaz.log'
        $AvisoDemo.Visibility = 'Visible'
        $script:maquinas = @()
        $script:restos = @()
        $disco = $null
        $carpetaVms = [string]$Config.CarpetaVMs
    }

    $script:disco = $disco   # (lo usa la página Inicio)
    $filas = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($m in @($script:maquinas | Sort-Object @{ Expression = { -not $_.EsBase } }, Nombre)) { $filas.Add((Nueva-Fila $m)) }
    $script:filas = $filas
    $Lista.ItemsSource = $filas
    $script:vista = [System.Windows.Data.CollectionViewSource]::GetDefaultView($filas)
    $script:vista.Filter = [Predicate[object]]{ param($o) Pasa-Filtro $o }
    Pintar-FiltroEtq   # (también quita del filtro las etiquetas que ya no lleva ninguna máquina)

    $nBases = @($filas | Where-Object { $_.EsBase }).Count
    $nMaq = $filas.Count - $nBases
    $nEnc = @($script:maquinas | Where-Object { $_.Encendida -and -not $_.EsBase }).Count
    $StatMaqEtq.Text = $(if ($nMaq -eq 1) { 'Máquina' } else { 'Máquinas' })
    $StatEncEtq.Text = $(if ($nEnc -eq 1) { 'Encendida' } else { 'Encendidas' })
    $StatBasesEtq.Text = $(if ($nBases -eq 1) { 'Base' } else { 'Bases' })
    $TxtResumen.Text = "$(Plural $nMaq 'máquina' 'máquinas') y $(Plural $nBases 'base' 'bases')"
    $TxtCarpetaVms.Text = $carpetaVms
    $TxtCarpetaVms.ToolTip = $carpetaVms
    if ($script:cargaSilenciosa) {
        $StatMaq.Text = [string]$nMaq; $StatEnc.Text = [string]$nEnc; $StatBases.Text = [string]$nBases
        if ($disco) { $StatLibre.Text = '{0:N0}' -f ($disco.Libre / 1GB) }
    } else {
        Contar $StatMaq $nMaq
        Contar $StatEnc $nEnc
        Contar $StatBases $nBases
        if ($disco) { Contar $StatLibre ($disco.Libre / 1GB) '{0:N0}' }
    }
    Pintar-Disco $disco

    $script:cargado = $true
    $Esqueleto.Visibility = 'Collapsed'
    $Lista.Visibility = 'Visible'
    # Las tarjetas se animan solo la primera vez de la sesión (o al cambiar de filtro), no al refrescar
    Refrescar-Vista $(if ($script:cargaSilenciosa -or $script:maqYaAnimadas) { 0 } else { 1 })
    $script:maqYaAnimadas = $true
    # Se vuelven a elegir las que estaban elegidas
    foreach ($f in $filas) { if ($seleccion -contains $f.Vmx) { [void]$Lista.SelectedItems.Add($f) } }
    Mostrar-Detalle -SinAnimar:$script:cargaSilenciosa
    $script:giro.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $script:cargando = $false
    # La página Inicio (si se está viendo) se pone al día con lo recién leído
    try { if ($paginaInicio.IsVisible) { Pintar-Inicio } } catch { Escribir-Log ("Inicio: " + ($_ | Out-String)) }
}

$relojCarga = New-Object System.Windows.Threading.DispatcherTimer
$relojCarga.Interval = [TimeSpan]::FromMilliseconds(120)
$relojCarga.Add_Tick({
    if (-not $script:asincrono.IsCompleted) { return }
    # Un mínimo de tiempo con las tarjetas «latiendo», para que el cambio no dé un salto brusco
    if (-not $script:cargaSilenciosa -and ((Get-Date) - $script:inicioCarga).TotalMilliseconds -lt 650) { return }
    $relojCarga.Stop()
    try { Terminar-Carga } catch { $script:cargando = $false; throw }
})
$BtnRefrescar.Add_Click({ Cargar })

# Recarga al rato de encender, apagar... (lo que tarda VMware en cambiar de estado)
$relojRecarga = New-Object System.Windows.Threading.DispatcherTimer
$relojRecarga.Add_Tick({ $relojRecarga.Stop(); Cargar -Silencioso })
function Recargar-Luego([int]$ms = 6000) { $relojRecarga.Stop(); $relojRecarga.Interval = [TimeSpan]::FromMilliseconds($ms); $relojRecarga.Start() }

# Qué máquinas están encendidas: cada pocos segundos se pregunta a VMware (vmrun list, sin esperar
# a que conteste: se recoge en la vuelta siguiente). Si algo cambió, la lista se recarga sola.
$script:procLista = $null
$relojEstado = New-Object System.Windows.Threading.DispatcherTimer
$relojEstado.Interval = [TimeSpan]::FromSeconds(3)
$relojEstado.Add_Tick({
    if (-not $script:cargado -or $script:cargando -or -not $script:vmrun) { return }
    try {
        if ($script:procLista) {
            if (-not $script:procLista.HasExited) {
                # VMware no contesta: a los 20 s se cierra ese vmrun (solo ese) y se vuelve a preguntar en la próxima vuelta.
                # No se cambia nada en la lista: «no contesta» no es «apagada».
                if ($script:procListaDesde -and ((Get-Date) - $script:procListaDesde).TotalSeconds -gt 20) {
                    try { Matar-ProcesoPropio $script:procLista.Id } catch {}
                    try { $script:procLista.Dispose() } catch {}
                    $script:procLista = $null
                }
                return
            }
            if ($script:procLista.ExitCode -ne 0) { $script:procLista.Dispose(); $script:procLista = $null; return }
            $salida = $script:procLista.StandardOutput.ReadToEnd()
            $script:procLista.Dispose(); $script:procLista = $null
            $nuestras = @($script:maquinas | ForEach-Object { ([string]$_.Vmx).ToLower() })
            $ahora = @($salida -split "`r?`n" | Select-Object -Skip 1 | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -and $nuestras -contains $_ } | Sort-Object)
            $antes = @($script:maquinas | Where-Object { $_.Encendida } | ForEach-Object { ([string]$_.Vmx).ToLower() } | Sort-Object)
            if (($ahora -join '|') -ne ($antes -join '|')) { Cargar -Silencioso }
            return
        }
        $psi = New-Object System.Diagnostics.ProcessStartInfo($script:vmrun, '-T ws list')
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
        $script:procLista = [System.Diagnostics.Process]::Start($psi)
        $script:procListaDesde = Get-Date
    } catch { $script:procLista = $null }
})

# Progreso de la configuración en las tarjetas (cada 5 s; solo lee estado\progreso.json)
$relojProgreso = New-Object System.Windows.Threading.DispatcherTimer
$relojProgreso.Interval = [TimeSpan]::FromSeconds(5)
$relojProgreso.Add_Tick({
    if (-not $script:cargado -or -not $script:filas) { return }
    try {
        foreach ($f in $script:filas) { [void](Aplicar-Estado $f) }
        Apuntar-TiemposMaquinas
        $sel = @($Lista.SelectedItems)
        if ($sel.Count -eq 1) { Pintar-ProgresoDetalle $sel[0] }
    } catch {}
})

# =====================================================================
#  Acciones
# =====================================================================
function Texto-SinPassword {
    $t = "Este PC todavía no tiene guardada la contraseña de las máquinas virtuales.`n`nSe guarda (cifrada) al crear la primera base en este PC con «Crear base». Sin ella no puedo entrar en las máquinas."
    if ($script:motivoPassword) { $t += "`n`nDetalle: $($script:motivoPassword)"; Escribir-Log "Contraseña de las VMs: $($script:motivoPassword)" }
    return $t
}

function Hay-Vmrun {
    if ($script:vmrun) { return $true }
    Aviso 'No encuentro vmrun.exe (VMware Workstation).'
    return $false
}
function Vmrun-Fondo([string]$linea) {
    # vmrun sin esperar (encender/apagar pueden tardar y no deben congelar la ventana)
    Iniciar-Oculto $script:vmrun $linea
}

function Abrir-EnVmware {
    $m = Maquina-Sel
    if (-not $m) { return }
    if ($m.EsBase) { Aviso "«$($m.Nombre)» es una base: no se abre ni se arranca, porque sus clones enlazados dependen de ella tal como está.`nPara cambiarla, rehazla en «Crear base»." 'Base protegida'; return }
    $exe = if ($script:vmrun) { Join-Path (Split-Path $script:vmrun) 'vmware.exe' } else { $null }
    if ($exe -and (Test-Path $exe)) { Start-Process $exe -ArgumentList "`"$($m.Vmx)`"" } else { Start-Process $m.Vmx }
}
$AccAbrir.Add_Click({ Abrir-EnVmware })
$Lista.Add_MouseDoubleClick({ Abrir-EnVmware })
$AccCarpeta.Add_Click({ $m = Maquina-Sel; if ($m -and (Test-Path -LiteralPath $m.Carpeta)) { Start-Process explorer.exe -ArgumentList "`"$($m.Carpeta)`"" } })

$AccEncender.Add_Click({
    if (-not (Hay-Vmrun)) { return }
    $elegidas = @(Maquinas-Sel | Where-Object { -not $_.Encendida -and $_.Estado -ne 'Sin base' -and -not $_.EsBase })
    if (-not $elegidas.Count) { return }
    foreach ($m in $elegidas) { Vmrun-Fondo "-T ws start `"$($m.Vmx)`" gui"; Marcar-Transicion $m 'Encendiendo…' $true }
    Mostrar-Toast "Encendiendo: $(($elegidas | ForEach-Object { $_.Nombre }) -join ', ')…"
    Mostrar-Detalle -SinAnimar
    Recargar-Luego 8000
})

$AccApagar.Add_Click({
    if (-not (Hay-Vmrun)) { return }
    $elegidas = @(Maquinas-Sel | Where-Object { $_.Encendida })
    if (-not $elegidas.Count) { return }
    $nombres = ($elegidas | ForEach-Object { $_.Nombre }) -join ', '
    $r = Mensaje "¿Cómo apagar $($nombres)?`n`nApagado normal: el sistema se cierra ordenadamente (necesita las VMware Tools).`nForzar: como quitarle la corriente." 'Apagar' 'pregunta' @(
        @{ Texto = 'Cancelar'; Valor = $null; Estilo = 'BotonSecundario' },
        @{ Texto = 'Forzar'; Valor = 'hard'; Estilo = 'BotonPeligro' },
        @{ Texto = 'Apagado normal'; Valor = 'soft'; Estilo = 'BotonPrimario' })
    if (-not $r) { return }
    foreach ($m in $elegidas) { Vmrun-Fondo "-T ws stop `"$($m.Vmx)`" $r"; Marcar-Transicion $m 'Apagando…' $false $(if ($r -eq 'soft') { 180 } else { 60 }) }
    Mostrar-Toast "Apagando: $nombres…"
    Mostrar-Detalle -SinAnimar
    Recargar-Luego $(if ($r -eq 'soft') { 20000 } else { 5000 })
})

$AccBorrar.Add_Click({
    $elegidas = @(Maquinas-Sel | Where-Object { -not $_.EsBase })
    if (-not $elegidas.Count) { return }
    $total = [double](($elegidas | Measure-Object Tamano -Sum).Sum)
    $txt = if ($elegidas.Count -eq 1) { "¿Borrar la máquina «$($elegidas[0].Nombre)»?" } else { "¿Borrar estas $($elegidas.Count) máquinas?`n$(($elegidas | ForEach-Object { $_.Nombre }) -join ', ')" }
    $txt += "`n`nSe borran sus carpetas enteras ($(Formato-Tamano $total)) y no se puede deshacer."
    foreach ($m in @($elegidas | Where-Object { $_.Dominio })) { $txt += "`n`nOjo: «$($m.Nombre)» es el controlador del dominio $($m.Dominio). Las máquinas unidas a él se quedarán sin dominio." }
    if (@($elegidas | Where-Object { $_.Encendida }).Count) { $txt += "`n`nLas que estén encendidas se apagarán a la fuerza." }
    $ext = @($elegidas | Where-Object { $_.Externa })
    if ($ext.Count) { $txt += "`n`n$(($ext | ForEach-Object { $_.Nombre }) -join ', ') no las creó Full Cowl (están en la biblioteca de VMware): también se borran del disco." }
    if (-not (Pregunta $txt 'Borrar máquinas' 'Borrar' 'Cancelar' 'BotonRojo')) { return }
    $quedan = @(); $conservadas = @(); $hechas = @(); $calladas = @(); $rCallada = $null
    Iniciar-Espera; try {
        foreach ($m in $elegidas) {
            if ($script:vmrun) {
                # Con límite de tiempo (ficha 34). Si VMware no contesta con una máquina, esa NO se toca más (ni se borra
                # su carpeta a mano por debajo de VMware): se anota y se sigue con las demás.
                if ($m.Encendida) {
                    $rParar = Vmrun-Ventana @('stop', $m.Vmx, 'hard')
                    if ($rParar.Agotado) { $calladas += $m.Nombre; $rCallada = $rParar; continue }
                    Start-Sleep 2
                }
                $rQuitar = Vmrun-Ventana @('deleteVM', $m.Vmx)
                if ($rQuitar.Agotado) { $calladas += $m.Nombre; $rCallada = $rQuitar; continue }
            }
            # La carpeta solo se borra entera si es segura: una de la carpeta de máquinas, o una que
            # solo tenga archivos de VMware (nunca, por ejemplo, Documentos con un .vmx suelto)
            if (-not (Carpeta-BorrableSegura $m.Carpeta)) {
                if (Test-Path -LiteralPath $m.Vmx) { $quedan += $m.Carpeta } else { $conservadas += $m.Carpeta; $hechas += $m.Nombre }
                continue
            }
            for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $m.Carpeta); $i++) {
                Remove-Item -LiteralPath $m.Carpeta -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $m.Carpeta) { Start-Sleep 1 }
            }
            # Solo se da por borrada si su .vmx ya no está
            if (Test-Path -LiteralPath $m.Carpeta) { $quedan += $m.Carpeta } else { $hechas += $m.Nombre }
        }
    } finally { Terminar-Espera }
    if ($calladas.Count) {
        Error-Amable "$(Plural $hechas.Count 'máquina borrada' 'máquinas borradas'), $($calladas.Count) sin respuesta de VMware: $($calladas -join ', ')." "VMware no ha contestado en $([int]$rCallada.Limite) segundos y esas no se han tocado más. Puede que siga trabajando y la operación haya terminado igualmente: espera un poco y mira la lista. Si se repite, cierra VMware y ábrelo de nuevo." "Operación de VMware: $($rCallada.Operacion)."
    }
    if ($quedan.Count) { Aviso "No se pudo borrar todo. Cierra sus pestañas en VMware y borra a mano:`n$($quedan -join "`n")" }
    elseif ($hechas.Count) { Mostrar-Toast "Borradas: $($hechas -join ', '). Si VMware las sigue mostrando en su biblioteca: clic derecho > Remove." }
    if ($conservadas.Count) { Aviso "Se borraron las máquinas, pero no estas carpetas porque tienen otros archivos tuyos (revísalas a mano):`n$($conservadas -join "`n")" }
    $Lista.SelectedItems.Clear()
    Cargar -Silencioso
})

$AccConservar.Add_Click({
    $elegidas = @(Maquinas-Sel | Where-Object { $_.Desechable })
    if (-not $elegidas.Count) { return }
    $txt = "¿Conservar $(($elegidas | ForEach-Object { $_.Nombre }) -join ', ')?`n`nDejarán de ser desechables: no se borrarán al apagarse."
    $labs = @($elegidas | Where-Object { $_.Lab } | ForEach-Object { $_.Lab } | Select-Object -Unique)
    if ($labs.Count) { $txt += "`nEl resto de máquinas del laboratorio $($labs -join ', ') sí se borrará al apagarse." }
    if (-not (Pregunta $txt 'Conservar' 'Conservar')) { return }
    foreach ($m in $elegidas) { Conservar-Maquina $m.Vmx ([bool]$m.Encendida) }
    Mostrar-Toast "Conservadas: $(($elegidas | ForEach-Object { $_.Nombre }) -join ', ')."
    Cargar -Silencioso
})

$AccExportar.Add_Click({
    $m = Maquina-Sel
    if (-not $m) { return }
    if ($m.Encendida) { Aviso "Apaga antes «$($m.Nombre)» para exportarla."; return }
    if ($m.Estado -eq 'Suspendida') { Aviso "«$($m.Nombre)» está suspendida: enciéndela y apágala del todo antes de exportarla."; return }
    $carpetaExp = Join-Path $Config.CarpetaVMs '_Exportadas'
    New-Item -ItemType Directory -Force -Path $carpetaExp | Out-Null
    $fd = New-Object Microsoft.Win32.SaveFileDialog
    $fd.Title = "Exportar «$($m.Nombre)»"; $fd.Filter = 'Máquina virtual (*.ova)|*.ova'
    $fd.FileName = "$($m.Nombre).ova"; $fd.InitialDirectory = $carpetaExp
    if (-not $fd.ShowDialog($script:ventana)) { return }
    Lanzar 'exportar.ps1' ([ordered]@{ vmx = $m.Vmx; nombre = $m.Nombre; destino = $fd.FileName })
    Mostrar-Toast "Exportando «$($m.Nombre)»: el progreso sale en la consola que se ha abierto."
})

# ---------------------------------------------------------------- conectar (Escritorio remoto / SSH)
function Puerto-Abierto($ip, [int]$puerto) {
    $cli = New-Object System.Net.Sockets.TcpClient
    try {
        $r = $cli.BeginConnect($ip, $puerto, $null, $null)
        return ($r.AsyncWaitHandle.WaitOne(1500) -and $cli.Connected)
    } catch { return $false } finally { $cli.Close() }
}
function Ip-DeMaquina($m) {
    $ip = ''
    $script:vmwareCallado = $null
    if ($script:vmrun) {
        $rIp = Vmrun-Ventana @('getGuestIPAddress', $m.Vmx)
        if ($rIp.Agotado) { $script:vmwareCallado = $rIp }
        else { $ip = "$(@($rIp.Lineas | Where-Object { ([string]$_).Trim() }) | Select-Object -Last 1)".Trim() }
    }
    if (-not (Es-IPv4 $ip)) { $ip = [string]$m.IP }
    if (Es-IPv4 $ip) { return $ip } else { return $null }
}
$AccConectar.Add_Click({
    $m = Maquina-Sel
    if (-not $m) { return }
    if (-not $m.Encendida) { Aviso "Enciende antes «$($m.Nombre)»."; return }
    if (-not @($m.Tarjetas | Where-Object { $_.Tipo -ne 'pvn' }).Count) {
        Aviso "«$($m.Nombre)» solo está en segmentos LAN y tu PC no llega a ellos.`nAñádele una tarjeta NAT con «Red» o usa su ventana de VMware."; return
    }
    $ip = $null
    Iniciar-Espera; try { $ip = Ip-DeMaquina $m } finally { Terminar-Espera }
    if (-not $ip) {
        if (Avisar-VmwareCallado) { return }
        if ($m.Manual) { Aviso "Sin IP automática: «$($m.Nombre)» viene de una base de instalación manual y Full Cowl no sabe su IP. Míralas dentro de la máquina (FreeBSD y cortafuegos: ifconfig o su menú; Linux: ip a) y conéctate tú, o usa su ventana de VMware."; return }
        Aviso "No sé la IP de «$($m.Nombre)». ¿Ha terminado de arrancar? (Windows necesita las VMware Tools)"; return
    }
    if ($m.EsWindows) {
        $abierto = $false
        Iniciar-Espera; try { $abierto = Puerto-Abierto $ip 3389 } finally { Terminar-Espera }
        if (-not $abierto) {
            Aviso "El Escritorio remoto no responde en $ip.`nActívalo en la máquina (Configuración > Sistema > Escritorio remoto) o créala marcando «Escritorio remoto (RDP)»."; return
        }
        Abrir-EscritorioRemoto $m.Vmx $ip $m.Netbios
        $quien = if ($m.Netbios) { "$($m.Netbios)\$(Usuario-DeVm $m.Vmx)" } else { ".\$(Usuario-DeVm $m.Vmx)" }
        Mostrar-Toast "Escritorio remoto a «$($m.Nombre)» ($ip) como $quien. Si pide contraseña, es la de las máquinas."
    } else {
        $abierto = $false
        Iniciar-Espera; try { $abierto = Puerto-Abierto $ip 22 } finally { Terminar-Espera }
        if (-not $abierto) { Aviso "SSH no responde en $ip. ¿Está instalado y arrancado (openssh-server)?"; return }
        # El usuario sale del .vmx y el nombre puede ser de una máquina hecha por otra persona: van a una línea de
        # PowerShell, así que el usuario se comprueba y el título se limpia (sin comillas, punto y coma ni $)
        $usuSsh = [string](Usuario-DeVm $m.Vmx)
        if (-not (Usuario-SeguroEnOrden $usuSsh)) { Aviso "El usuario apuntado en esta máquina tiene caracteres raros y no lo pongo en una orden.`nConéctate a mano desde una consola: ssh usuario@$ip"; return }
        $tituloSshPanel = ("SSH $($m.Nombre)" -replace '[^\p{L}\p{Nd} ._-]', '')
        Start-Process powershell.exe -ArgumentList "-NoExit -Command `"`$Host.UI.RawUI.WindowTitle = '$tituloSshPanel'; ssh -o StrictHostKeyChecking=accept-new $usuSsh@$ip`""
        Mostrar-Toast "SSH a «$($m.Nombre)» ($ip): la contraseña es la de siempre."
    }
})

# ---------------------------------------------------------------- instantáneas
$AccSnap.Add_Click({
    $m = Maquina-Sel
    if (-not $m -or -not (Hay-Vmrun)) { return }
    $e = Nuevo-Dialogo 'dialogo-instantaneas.xaml' 'Instantáneas' $m.Nombre 520
    Poner-PastillaDlg $e $m
    # La instantánea «inicio-lab» (ficha 28) se ve como «Estado inicial del laboratorio»; $nombresSnap: texto que se ve -> nombre real
    $nombresSnap = @{}
    $recargar = {
        $e.ListaSnap.Items.Clear()
        $nombresSnap.Clear()
        $rSnaps = Vmrun-Ventana @('listSnapshots', $m.Vmx)
        foreach ($l in @($rSnaps.Lineas | Select-Object -Skip 1)) {
            $nombreReal = "$l".Trim()
            if ($nombreReal) {
                $nombreVisto = $(if ($nombreReal -ceq (Nombre-EstadoInicial)) { 'Estado inicial del laboratorio' } else { $nombreReal })
                $nombresSnap[$nombreVisto] = $nombreReal
                [void]$e.ListaSnap.Items.Add($nombreVisto)
            }
        }
        $hay = $e.ListaSnap.Items.Count -gt 0
        $e.BtnSnapVolver.IsEnabled = $hay
        $e.BtnSnapBorrar.IsEnabled = $hay
        $e.SinSnap.Visibility = $(if ($hay) { 'Collapsed' } else { 'Visible' })
        if ($hay) { $e.ListaSnap.SelectedIndex = $e.ListaSnap.Items.Count - 1 }
        if ($rSnaps.Agotado) { Terminar-Espera; Aviso-VmrunAgotado $rSnaps }     # lista vacía porque VMware no contestó, no porque no haya
    }
    Iniciar-Espera; try { & $recargar } finally { Terminar-Espera }

    # Crear, volver o borrar puede tardar minutos (con la máquina encendida se guarda también su memoria):
    # vmrun va en segundo plano y la ventana sigue respondiendo; un reloj mira cuándo ha terminado
    $op = @{ Proc = $null; Sal = $null; Err = $null; Ok = ''; Mal = ''; Desde = $null; Limite = 600; Operacion = '' }
    $relojSnap = New-Object System.Windows.Threading.DispatcherTimer
    $relojSnap.Interval = [TimeSpan]::FromMilliseconds(300)
    $ocupado = {
        param([string]$texto)
        $libre = -not $texto
        foreach ($b in @($e.BtnSnapNueva, $e.BtnSnapVolver, $e.BtnSnapBorrar, $e.BtnSnapCerrar)) { $b.IsEnabled = $libre }
        $e.ListaSnap.IsEnabled = $libre
        $e.SnapTrabajando.Visibility = $(if ($libre) { 'Collapsed' } else { 'Visible' })
        $e.SnapTrabajandoTexto.Text = $texto
    }
    $lanzar = {
        # (los textos de bien y mal se guardan ya hechos: cuando acabe, este botón ya no estará en marcha)
        param([string]$argumentos, [string]$texto, [string]$ok, [string]$mal)
        & $ocupado $texto
        $psi = New-Object System.Diagnostics.ProcessStartInfo($script:vmrun, $argumentos)
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $op.Proc = $proc; $op.Sal = $proc.StandardOutput.ReadToEndAsync(); $op.Err = $proc.StandardError.ReadToEndAsync()
        $op.Ok = $ok; $op.Mal = $mal
        # Límite de tiempo (ficha 34): el de la operación (crear, volver o borrar: 10 min)
        $op.Operacion = Operacion-Vmrun @($argumentos -split ' ' | Select-Object -First 3)
        $op.Limite = Limite-Vmrun $op.Operacion; $op.Desde = Get-Date
        $relojSnap.Start()
    }
    $relojSnap.Add_Tick({
        if (-not $op.Proc) { return }
        if (-not $op.Proc.HasExited) {
            if (-not $op.Desde -or ((Get-Date) - $op.Desde).TotalSeconds -lt $op.Limite) { return }
            # VMware no ha contestado a tiempo: se cierra SOLO el vmrun lanzado (VMware puede seguir y terminar por su cuenta)
            $relojSnap.Stop()
            try { Matar-ProcesoPropio $op.Proc.Id } catch {}
            try { $op.Proc.Dispose() } catch {}
            $op.Proc = $null
            Apuntar-Vmrun $op.Operacion "SIN RESPUESTA en $($op.Limite) s (se cerró el vmrun lanzado)" ([double]$op.Limite)
            & $ocupado ''
            & $recargar
            Aviso-VmrunAgotado ([pscustomobject]@{ Limite = $op.Limite; Operacion = $op.Operacion; Segundos = $op.Limite }) -Larga
            return
        }
        $relojSnap.Stop()
        $codigo = $op.Proc.ExitCode
        $salida = ("$($op.Sal.Result)" + "$($op.Err.Result)").Trim()
        $op.Proc.Dispose(); $op.Proc = $null
        & $ocupado ''
        & $recargar
        if ($codigo -ne 0) { Error-Msg "$($op.Mal)`n$salida" } else { Mostrar-Toast $op.Ok }
    })
    # Si se cierra mientras VMware trabaja, se avisa: VMware sigue y acaba por su cuenta
    $e.Ventana.Add_Closing({
        param($s, $a)
        if ($op.Proc -and -not $op.Proc.HasExited) {
            if (-not (Pregunta "VMware sigue trabajando en la instantánea.`n`nSi cierras, seguirá por su cuenta hasta terminar (no lo canceles desde VMware a medias)." 'Instantáneas' 'Cerrar igualmente' 'Esperar')) { $a.Cancel = $true }
        }
    })
    $comoVa = $(if ($m.Encendida) { ' Con la máquina encendida se guarda también lo que tiene en memoria: puede tardar unos minutos.' } else { '' })
    $vmxEntre = "`"$($m.Vmx)`""

    $e.BtnSnapCerrar.Add_Click({ $e.Ventana.Close() })
    $e.BtnSnapNueva.Add_Click({
        $n = Pedir-Texto 'Nueva instantánea' 'Nombre de la instantánea:' ('antes de ' + (Get-Date).ToString('dd-MM HH.mm'))
        $n = "$n".Trim()
        if (-not $n) { return }
        if ($n -match '["\\]') { Aviso 'El nombre no puede llevar comillas ni barras invertidas.'; return }
        if ($n -ceq (Nombre-EstadoInicial) -or $n -eq 'Estado inicial del laboratorio') { Aviso 'Ese nombre está reservado para el estado inicial del laboratorio. Elige otro.'; return }
        if (@($e.ListaSnap.Items) -contains $n) { Aviso 'Ya hay una instantánea con ese nombre.'; return }
        & $lanzar "-T ws snapshot $vmxEntre `"$n`"" "Creando la instantánea «$n»…$comoVa" "Instantánea «$n» creada." 'No se pudo crear la instantánea:'
    })
    $e.BtnSnapVolver.Add_Click({
        $nVisto = [string]$e.ListaSnap.SelectedItem
        if (-not $nVisto) { Aviso 'Elige una instantánea de la lista.'; return }
        $n = $(if ($nombresSnap.ContainsKey($nVisto)) { [string]$nombresSnap[$nVisto] } else { $nVisto })
        $txtVolver = "¿Volver a «$nVisto»?`n`nSe pierde todo lo hecho en la máquina desde entonces."
        # Una máquina de un laboratorio con dominio no debería volver sola al pasado: sus cuentas de equipo se descuadran
        if ($m.Lab -and ($m.Dominio -or $m.Netbios)) {
            $txtVolver += "`n`nOjo: es una máquina del laboratorio $($m.Lab), que tiene dominio. Si solo vuelve ella, su cuenta con el dominio puede descuadrarse. Para volver todas a la vez usa Laboratorio → «Volver al estado inicial»."
        }
        if (-not (Pregunta $txtVolver 'Volver a una instantánea' 'Volver')) { return }
        & $lanzar "-T ws revertToSnapshot $vmxEntre `"$n`"" "Volviendo a «$nVisto»…" "«$($m.Nombre)» ha vuelto a «$nVisto»." 'No se pudo volver a la instantánea:'
    })
    $e.BtnSnapBorrar.Add_Click({
        $nVisto = [string]$e.ListaSnap.SelectedItem
        if (-not $nVisto) { Aviso 'Elige una instantánea de la lista.'; return }
        $n = $(if ($nombresSnap.ContainsKey($nVisto)) { [string]$nombresSnap[$nVisto] } else { $nVisto })
        $txt = "¿Borrar la instantánea «$nVisto»?`n`nLa máquina se queda como está ahora; solo se pierde la posibilidad de volver a ese punto."
        if ($n -eq 'inicio') { $txt += "`n`n«inicio» es la de recién creada: sin ella no podrás repetir la configuración automática." }
        if ($n -ceq (Nombre-EstadoInicial)) { $txt += "`n`nEs el estado inicial del laboratorio: sin él, «Volver al estado inicial» no podrá devolver esta máquina a como estaba." }
        if (-not (Pregunta $txt 'Borrar instantánea' 'Borrar' 'Cancelar' 'BotonRojo')) { return }
        & $lanzar "-T ws deleteSnapshot $vmxEntre `"$n`"" "Borrando «$nVisto» (VMware junta sus cambios con el disco: puede tardar)…" "Instantánea «$nVisto» borrada." 'No se pudo borrar la instantánea:'
    })
    [void]$e.Ventana.ShowDialog()
    $relojSnap.Stop()
    Cargar -Silencioso
})

# ---------------------------------------------------------------- usuarios en masa
function Leer-CsvUsuarios($ruta) {
    # CSV de Excel (; y ANSI) o UTF-8 con , o ;  ->  objetos usuario/nombre/apellidos/password/grupo/ou
    $bytes = [IO.File]::ReadAllBytes($ruta)
    try { $texto = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { $texto = [Text.Encoding]::GetEncoding(1252).GetString($bytes) }
    $texto = $texto.TrimStart([char]0xFEFF)
    $lineas = @($texto -split "`r?`n" | Where-Object { $_.Trim() })
    if ($lineas.Count -lt 2) { throw 'El CSV no tiene filas: la primera línea debe ser la cabecera y luego un usuario por línea.' }
    $sep = if ($lineas[0].Split(';').Count -ge $lineas[0].Split(',').Count) { ';' } else { ',' }
    $filasCsv = @($lineas | ConvertFrom-Csv -Delimiter $sep)
    $cab = @($filasCsv[0].PSObject.Properties.Name)
    $patrones = [ordered]@{
        usuario = '^(usuario|user|username|login|cuenta|samaccountname)$'
        nombre = '^(nombre|name|givenname|first ?name)$'
        apellidos = '^(apellidos?|surname|last ?name)$'
        password = '(pass|contrase|clave)'
        grupo = '^(grupo|group|grupos)$'
        ou = '^(ou|unidad.*)$'
    }
    $columnas = @{}
    foreach ($k in $patrones.Keys) { $columnas[$k] = $cab | Where-Object { $_.Trim() -match $patrones[$k] } | Select-Object -First 1 }
    if (-not $columnas.usuario) { throw "No encuentro la columna 'usuario' en la cabecera.`nColumnas encontradas: $($cab -join ', ')" }
    return @(foreach ($fi in $filasCsv) {
        $o = [ordered]@{}
        foreach ($k in $patrones.Keys) { $o[$k] = if ($columnas[$k]) { ([string]$fi.($columnas[$k])).Trim() } else { '' } }
        if ($o.usuario) { [pscustomobject]$o }
    })
}

function Es-Compleja($clave) {
    # Requisitos por defecto de Active Directory: 7+ caracteres y 3 de 4 tipos
    if ($clave.Length -lt 7) { return $false }
    $n = 0
    foreach ($patron in '[A-Z]', '[a-z]', '[0-9]', '[^A-Za-z0-9]') { if ($clave -cmatch $patron) { $n++ } }
    return $n -ge 3
}

$AccUsuarios.Add_Click({
    $m = Maquina-Sel
    if (-not $m) { return }
    # Para crear usuarios hay que entrar en la máquina: se comprueba antes de pedir nada
    if (-not (Obtener-Password -SinPreguntar)) { Aviso (Texto-SinPassword) 'Falta la contraseña de las VMs'; return }
    if (-not $m.Tipo) {
        if (-not (Pregunta "«$($m.Nombre)» no la creó Full Cowl.`n`nPara crear usuarios hay que entrar en ella con el usuario «$(Usuario-DeVm $m.Vmx)» y la contraseña de las máquinas de Full Cowl, y tiene que tener las VMware Tools. Si usa otro usuario u otra contraseña, no funcionará." 'Máquina hecha a mano' 'Probar igualmente')) { return }
    }
    if ($m.Encendida -and $script:vmrun) {
        $tools = $false
        Iniciar-Espera; try { $tools = Tools-Listas $script:vmrun $m.Vmx $script:pulsoVmrun } finally { Terminar-Espera; Soltar-Ventanas }
        if (-not $tools) { Aviso "Las VMware Tools no responden en «$($m.Nombre)». Si acaba de encenderse, espera a que termine de arrancar. Si no las tiene instaladas, instálalas desde VMware (menú VM > Install VMware Tools)." 'VMware Tools'; return }
    }
    $dest = if ($m.EsWindows -and $m.Dominio) { 'ad' } elseif ($m.EsWindows) { 'local' } else { 'linux' }
    $e = Nuevo-Dialogo 'dialogo-usuarios.xaml' 'Crear usuarios' $m.Nombre 560
    Poner-PastillaDlg $e $m
    $e.DestinoUsu.Text = switch ($dest) {
        'ad'    { "Se crean en Active Directory (dominio $($m.Dominio))." }
        'local' { 'Se crean como usuarios locales de Windows (grupo Usuarios).' }
        default { "Se crean como usuarios de $(if ($m.Familia) { $m.Familia } else { 'Linux' }), con su carpeta personal." }
    }
    # Active Directory y los Windows Server (también sus usuarios locales) exigen contraseñas complejas
    $pideCompleja = ($dest -eq 'ad') -or ($dest -eq 'local' -and [string]$m.Familia -like '*Server*')
    $e.NotaPassUsu.Text = $(if ($dest -eq 'ad') { 'Active Directory pide 7 o más y 3 tipos (Aa1.)' } elseif ($pideCompleja) { 'Windows Server pide 7 o más y 3 tipos (Aa1.)' } else { 'Para todos (el CSV puede traer la suya)' })
    $e.NotaOuUsu.Text = $(if ($dest -eq 'ad') { 'Opcional · se crea si no existe' } else { 'Solo en Active Directory' })
    $e.OuUsu.IsEnabled = ($dest -eq 'ad')
    $e.AvisoUsu.Text = $(if ($m.EsWindows) { 'Se enciende la máquina si hace falta. Necesita las VMware Tools instaladas en Windows.' } else { 'Se enciende la máquina si hace falta.' })

    $actualizarEj = {
        $patron = [bool]$e.OpUsuPatron.IsChecked
        $e.PanelUsuPatron.Visibility = $(if ($patron) { 'Visible' } else { 'Collapsed' })
        $e.PanelUsuCsv.Visibility = $(if ($patron) { 'Collapsed' } else { 'Visible' })
        $nombresPrev = @(); $total = 0; $aviso = ''
        try {
            if ($patron) {
                $a = Numero $e.DesdeUsu.Text; $b = Numero $e.HastaUsu.Text
                $pre = $e.PrefijoUsu.Text.Trim()
                if ($a -ge 0 -and $b -ge $a -and $pre) {
                    $dig = [Math]::Max(2, ([string]$b).Length)
                    $total = $b - $a + 1
                    $nombresPrev = @($a, ($a + 1), $b | Select-Object -Unique | Where-Object { $_ -le $b } | ForEach-Object { $pre + $_.ToString("D$dig") })
                    if ($total -gt 3) { $nombresPrev = @($nombresPrev[0], $nombresPrev[1], '…', $nombresPrev[$nombresPrev.Count - 1]) }
                    if ($total -gt 500) { $aviso = 'Como mucho 500 usuarios de una vez.' }
                }
            } elseif ($e.CsvUsu.Text.Trim() -and (Test-Path -LiteralPath $e.CsvUsu.Text.Trim())) {
                $filasPrev = @(Leer-CsvUsuarios $e.CsvUsu.Text.Trim())
                $total = $filasPrev.Count
                $todos = @($filasPrev | ForEach-Object { $_.usuario })
                $nombresPrev = $(if ($total -gt 4) { @($todos[0], $todos[1], $todos[2], '…', $todos[$total - 1]) } else { $todos })
            }
        } catch { $aviso = 'No se puede leer ese CSV: comprueba que tiene cabecera y un usuario por línea.' }
        $g = $e.GrupoUsu.Text.Trim()
        if ($aviso) { $e.PrevUsuTitulo.Text = $aviso; $e.PrevUsuLista.Text = '' }
        elseif ($total -gt 0) {
            $e.PrevUsuTitulo.Text = "Se crearán $(Plural $total 'usuario' 'usuarios')"
            $e.PrevUsuLista.Text = ($nombresPrev -join ', ') + $(if ($g) { "  ·  grupo $g" } else { '' }) + $(if ($dest -eq 'ad' -and $e.OuUsu.Text.Trim()) { "  ·  OU $($e.OuUsu.Text.Trim())" } else { '' })
        } else { $e.PrevUsuTitulo.Text = 'Todavía no hay usuarios que crear'; $e.PrevUsuLista.Text = $(if ($patron) { 'Escribe el prefijo y los números.' } else { 'Elige el archivo CSV.' }) }
        $e.EjemploUsu.Text = ''
    }
    & $actualizarEj
    foreach ($ctl in $e.PrefijoUsu, $e.DesdeUsu, $e.HastaUsu, $e.CsvUsu, $e.GrupoUsu, $e.OuUsu) { $ctl.Add_TextChanged({ & $actualizarEj }) }
    $e.OpUsuPatron.Add_Checked({ & $actualizarEj })
    $e.OpUsuCsv.Add_Checked({ & $actualizarEj })
    $e.BtnUsuNo.Add_Click({ $e.Ventana.Close() })
    # La contraseña va oculta; el ojo la enseña (y la vuelve a ocultar)
    $e.BtnVerPass.Add_Checked({ $e.PassUsuVer.Text = $e.PassUsu.Password; $e.PassUsu.Visibility = 'Collapsed'; $e.PassUsuVer.Visibility = 'Visible' })
    $e.BtnVerPass.Add_Unchecked({ $e.PassUsu.Password = $e.PassUsuVer.Text; $e.PassUsuVer.Visibility = 'Collapsed'; $e.PassUsu.Visibility = 'Visible' })

    $e.BtnUsuExaminar.Add_Click({
        $fi = New-Object Microsoft.Win32.OpenFileDialog
        $fi.Title = 'CSV de usuarios'; $fi.Filter = 'CSV (*.csv)|*.csv|Texto (*.txt)|*.txt|Todos (*.*)|*.*'
        if ($fi.ShowDialog($e.Ventana)) { $e.CsvUsu.Text = $fi.FileName; $e.OpUsuCsv.IsChecked = $true }
    })
    $e.BtnUsuEjemplo.Add_Click({
        $fi = New-Object Microsoft.Win32.SaveFileDialog
        $fi.Title = 'Guardar CSV de ejemplo'; $fi.Filter = 'CSV (*.csv)|*.csv'; $fi.FileName = 'usuarios.csv'
        $fi.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if (-not $fi.ShowDialog($e.Ventana)) { return }
        $ej = "usuario;nombre;apellidos;password;grupo`r`njgarcia;Juan;García López;Alumno.2026;Alumnos`r`nmlopez;María;López Ruiz;Alumno.2026;Alumnos`r`nprofe1;Ana;Martín Sanz;Profe.2026;Profesores`r`n"
        [IO.File]::WriteAllText($fi.FileName, $ej, [Text.UTF8Encoding]::new($true))
        $e.CsvUsu.Text = $fi.FileName; $e.OpUsuCsv.IsChecked = $true
        try { Start-Process $fi.FileName } catch {}
    })

    $e.BtnUsuOk.Add_Click({
        $pass = if ($e.BtnVerPass.IsChecked) { $e.PassUsuVer.Text } else { $e.PassUsu.Password }
        $grupo = $e.GrupoUsu.Text.Trim()
        $nuevosUsu = @()
        if ($e.OpUsuPatron.IsChecked) {
            $pre = $e.PrefijoUsu.Text.Trim()
            if ($pre -notmatch '^[A-Za-z][A-Za-z0-9._-]*$') { Aviso 'El prefijo debe empezar por una letra y llevar solo letras, números, punto, guion o guion bajo.'; return }
            $a = Numero $e.DesdeUsu.Text; $b = Numero $e.HastaUsu.Text
            if ($a -lt 0 -or $b -lt 0) { Aviso 'Escribe los números de los usuarios (desde y hasta).'; return }
            if ($b -lt $a) { Aviso 'El número final tiene que ser mayor o igual que el inicial.'; return }
            if ($b - $a + 1 -gt 500) { Aviso 'Como mucho 500 usuarios de una vez.'; return }
            if (-not $pass) { Aviso 'Escribe la contraseña para los usuarios.'; return }
            $dig = [Math]::Max(2, ([string]$b).Length)
            for ($i = $a; $i -le $b; $i++) {
                $nuevosUsu += [pscustomobject]@{ usuario = $pre + $i.ToString("D$dig"); nombre = ''; apellidos = ''; password = $pass; grupo = $grupo; ou = '' }
            }
        } else {
            if (-not $e.CsvUsu.Text -or -not (Test-Path -LiteralPath $e.CsvUsu.Text)) { Aviso 'Elige el archivo CSV (botón Examinar).'; return }
            try { $filasCsv = @(Leer-CsvUsuarios $e.CsvUsu.Text) } catch { Error-Amable 'No he podido leer el archivo CSV.' 'Comprueba que no está abierto en otro programa y que tiene el formato de la plantilla.' $_.Exception.Message; return }
            # Los que traen contraseña en el CSV se quedan con la suya (no con la que se escribe aquí)
            $conPropia = @($filasCsv | Where-Object { $_.password } | ForEach-Object { $_.usuario })
            if ($pass -and $conPropia.Count) {
                if (-not (Pregunta "$(Plural $conPropia.Count 'usuario trae' 'usuarios traen') su propia contraseña en el CSV (columna «password»): $(($conPropia | Select-Object -First 6) -join ', ')$(if ($conPropia.Count -gt 6) { '…' }).`n`nA $(if ($conPropia.Count -eq 1) { 'ese' } else { 'esos' }) se les pone la del CSV, no la que has escrito aquí (esa solo vale para los que no traen ninguna)." 'Contraseñas del CSV' 'Entendido, seguir' 'Cancelar' 'BotonPrimario')) { return }
            }
            foreach ($fi in $filasCsv) {
                if (-not $fi.password) { $fi.password = $pass }
                if (-not $fi.grupo) { $fi.grupo = $grupo }
                $nuevosUsu += $fi
            }
            if (-not $nuevosUsu.Count) { Aviso 'El CSV no tiene usuarios.'; return }
            $sinPass = @($nuevosUsu | Where-Object { -not $_.password })
            if ($sinPass.Count) { Aviso "Faltan contraseñas (por ejemplo, «$($sinPass[0].usuario)»). Ponlas en el CSV o escribe una común."; return }
        }
        # Comprobaciones de nombres
        $malos = @()
        foreach ($u in $nuevosUsu) {
            if ($dest -eq 'linux') {
                $u.usuario = $u.usuario.ToLower()
                if ($u.usuario -notmatch '^[a-z_][a-z0-9_.-]{0,31}$') { $malos += $u.usuario }
            } elseif ($u.usuario -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$') { $malos += $u.usuario }
        }
        if ($malos.Count) {
            Aviso "Nombres de usuario no válidos (sin espacios ni tildes$(if ($dest -eq 'linux') { ', en minúsculas' } else { ', máx. 20' })):`n$(($malos | Select-Object -First 8) -join ', ')"
            return
        }
        $repes = @($nuevosUsu | Group-Object usuario | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        if ($repes.Count) { Aviso "Usuarios repetidos: $($repes -join ', ')"; return }
        if ($pideCompleja) {
            $debiles = @($nuevosUsu | Where-Object { -not (Es-Compleja $_.password) } | ForEach-Object { $_.usuario })
            if ($debiles.Count -and -not (Pregunta "$(if ($dest -eq 'ad') { 'Active Directory' } else { 'Windows Server' }) rechazará contraseñas sencillas (necesita 7 caracteres y 3 tipos: mayúsculas, minúsculas, números, símbolos).`nNo cumplen: $(($debiles | Select-Object -First 6) -join ', ')`n`n¿Probar igualmente?" 'Contraseñas sencillas' 'Probar igualmente')) { return }
        }
        $pedido = [ordered]@{
            vmx = $m.Vmx; nombre = $m.Nombre; destino = $dest; dominio = $m.Dominio; netbios = $m.Netbios
            ou = $(if ($dest -eq 'ad') { $e.OuUsu.Text.Trim() } else { '' })
            cambiar = [bool]$e.CambiarUsu.IsChecked
            usuarios = @($nuevosUsu | ForEach-Object { [ordered]@{ usuario = $_.usuario; nombre = $_.nombre; apellidos = $_.apellidos; password = $_.password; grupo = $_.grupo; ou = $_.ou } })
        }
        Lanzar 'usuarios.ps1' $pedido
        Mostrar-Toast "Creando $($nuevosUsu.Count) usuarios en «$($m.Nombre)»: el progreso sale en la consola que se ha abierto."
        $e.Ventana.Close()
    })
    [void]$e.Ventana.ShowDialog()
})

# ---------------------------------------------------------------- red del laboratorio
function Apagar-Esperando($elegidas) {
    # Apagado normal de varias máquinas, esperando a que terminen (si no, a la fuerza)
    $sinApagar = @(); $rSinApagar = $null
    Iniciar-Espera; try {
        foreach ($m in $elegidas) {
            # Apagado normal (2 min como mucho); si no contesta o falla, a la fuerza (1 min como mucho)
            $rSuave = Vmrun-Ventana @('stop', $m.Vmx, 'soft')
            if ($rSuave.Agotado -or $rSuave.Codigo -ne 0) {
                $rFuerte = Vmrun-Ventana @('stop', $m.Vmx, 'hard')
                if ($rFuerte.Agotado) { $sinApagar += $m.Nombre; $rSinApagar = $rFuerte }
            }
        }
    } finally { Terminar-Espera }
    if ($sinApagar.Count) { Aviso-VmrunAgotado $rSinApagar }
}

$AccRed.Add_Click({
    $sel = @(Maquinas-Sel | Where-Object { -not $_.EsBase })
    if (-not $sel.Count -or -not (Hay-Vmrun)) { return }
    $susp = @($sel | Where-Object { $_.Estado -eq 'Suspendida' })
    if ($susp.Count) { Aviso "Estas máquinas están suspendidas: $(($susp | ForEach-Object { $_.Nombre }) -join ', ').`nEnciéndelas y apágalas del todo antes de cambiar su red."; return }
    $enc = @($sel | Where-Object { $_.Encendida })
    if ($enc.Count) {
        if (-not (Pregunta "Para cambiar las tarjetas de red, las máquinas tienen que estar apagadas: Full Cowl las apaga ahora, cambia las tarjetas y, si les pones IP (fija o automática), las vuelve a encender él solo para ponérsela.`n`nEncendidas: $(($enc | ForEach-Object { $_.Nombre }) -join ', ')`n`n¿Apagarlas ahora (apagado normal)?" 'Red del laboratorio' 'Apagar')) { return }
        Apagar-Esperando $enc
        # Se vuelven a leer para ver si ya están apagadas (y con sus datos al día)
        $vmxSel = @($sel | ForEach-Object { $_.Vmx })
        $nuevas = @()
        Iniciar-Espera; try { $nuevas = @(Leer-Maquinas | Where-Object { $vmxSel -contains $_.Vmx }) } finally { Terminar-Espera }
        $sel = $nuevas
        if (@($sel | Where-Object { $_.Encendida }).Count) { Aviso 'Alguna máquina sigue encendida. Apágala y vuelve a intentarlo.'; Cargar -Silencioso; return }
    }
    $sel = @($sel | Sort-Object Nombre)
    $primera = $sel[0]

    $opc = New-Object System.Collections.ArrayList
    foreach ($o in @(Opciones-Red)) { [void]$opc.Add($o) }
    # Redes que ya tienen las máquinas y no están en la lista (segmentos sin nombre...)
    foreach ($t in @($sel | ForEach-Object { $_.Tarjetas })) {
        $k = Clave-Tarjeta $t
        if (-not @($opc | Where-Object { $_.Clave -eq $k }).Count) {
            [void]$opc.Add([pscustomobject]@{ Clave = $k; Texto = $(if ($t.Tipo -eq 'pvn') { 'Segmento LAN (sin nombre)' } else { Texto-Tarjeta $t $null }); Tipo = $t.Tipo; Vnet = $t.Vnet; Pvn = $t.Pvn })
        }
    }
    $textoNuevo = 'Nuevo segmento LAN…'
    $redNat = Leer-RedNat

    $e = Nuevo-Dialogo 'dialogo-red.xaml' 'Red del laboratorio' "$(Plural $sel.Count 'máquina' 'máquinas')" 720
    $e.MaquinasRed.Text = "Máquinas: $(($sel | ForEach-Object { $_.Nombre }) -join ', ')"
    $e.InfoRed.Text = "Se muestran las tarjetas de «$($primera.Nombre)». Lo que elijas se aplica igual a todas (con IP fija, una seguida de otra)."

    $filasRed = @()
    for ($i = 0; $i -lt 4; $i++) {
        $n = $i + 1
        $fila = @{
            Indice = $i; Caja = $e["CajaTarj$n"]; Chk = $e["ChkTarj$n"]; Red = $e["RedTarj$n"]; Modo = $e["ModoTarj$n"]
            Fija = $e["FijaTarj$n"]; Ip = $e["IpTarj$n"]; Pre = $e["PreTarj$n"]; Gw = $e["GwTarj$n"]; Dns = $e["DnsTarj$n"]; Ico = $e["IcoTarj$n"]
            Anterior = 0
        }
        foreach ($o in $opc) { [void]$fila.Red.Items.Add($o.Texto) }
        [void]$fila.Red.Items.Add($textoNuevo)
        $fila.Modo.SelectedIndex = 0
        # Estado inicial: las tarjetas de la primera máquina
        $t = @($primera.Tarjetas)[$i]
        $fila.Red.SelectedIndex = 0
        if ($t) {
            $fila.Chk.IsChecked = $true
            $k = Clave-Tarjeta $t
            for ($j = 0; $j -lt $opc.Count; $j++) { if ($opc[$j].Clave -eq $k) { $fila.Red.SelectedIndex = $j } }
        }
        $fila.Anterior = $fila.Red.SelectedIndex
        $filasRed += $fila
    }
    $filasRed[0].Chk.IsChecked = $true; $filasRed[0].Chk.IsEnabled = $false   # al menos una tarjeta

    # Icono de cada tarjeta según la red elegida (solo dibujo: no toca ningún dato)
    $icoRed = {
        param($fila)
        try {
            if (-not $fila.Ico) { return }
            $ix = $fila.Red.SelectedIndex
            $tipoRed = $(if ($ix -ge 0 -and $ix -lt $opc.Count) { [string]$opc[$ix].Tipo } else { 'pvn' })
            $cod = switch ($tipoRed) { 'nat' { 0xE774 } 'bridged' { 0xE839 } 'hostonly' { 0xE80F } default { 0xE968 } }
            $fila.Ico.Text = [string][char]$cod
        } catch { Escribir-Log ("Icono de red: " + ($_ | Out-String)) }
    }
    foreach ($filaI in $filasRed) { & $icoRed $filaI }
    if ($sel.Count -eq 1) { Poner-PastillaDlg $e $primera }

    $refrescar = {
        $prev = @()
        foreach ($fila in $filasRed) {
            $on = [bool]$fila.Chk.IsChecked
            $fila.Red.IsEnabled = $on; $fila.Modo.IsEnabled = $on
            $fila.Caja.Opacity = $(if ($on) { 1 } else { 0.6 })
            $fija = $on -and $fila.Modo.SelectedIndex -eq 2
            $fila.Fija.Visibility = $(if ($fija) { 'Visible' } else { 'Collapsed' })
            if ($fija -and (Es-IPv4 $fila.Ip.Text.Trim())) {
                $b = $fila.Ip.Text.Trim().Split('.')
                $ips = for ($k = 0; $k -lt $sel.Count; $k++) { "$($sel[$k].Nombre) .$([int]$b[3] + $k)" }
                $prev += "Tarjeta $($fila.Indice + 1): $($ips -join ' · ')"
            }
        }
        $e.PrevRed.Text = $(if ($prev.Count) { ($prev -join "`n") } else { 'Sin IP fija: solo se cambia a qué red va cada tarjeta.' })
    }

    foreach ($fila in $filasRed) {
        $fila.Chk.Add_Click({
            param($emisor, $a)
            $pos = -1
            for ($q = 0; $q -lt $filasRed.Count; $q++) { if ($filasRed[$q].Chk -eq $emisor) { $pos = $q } }
            # Las tarjetas van seguidas: marcar una marca las anteriores; desmarcarla, las siguientes
            if ($emisor.IsChecked) { for ($q = 0; $q -lt $pos; $q++) { $filasRed[$q].Chk.IsChecked = $true } }
            else { for ($q = $pos + 1; $q -lt $filasRed.Count; $q++) { $filasRed[$q].Chk.IsChecked = $false } }
            & $refrescar
        })
        $fila.Ip.Add_TextChanged({ & $refrescar })
        $fila.Red.Add_SelectionChanged({ param($cb, $a) foreach ($fx in $filasRed) { if ($fx.Red -eq $cb) { & $icoRed $fx } } })
        $fila.Modo.Add_SelectionChanged({
            param($emisor, $a)
            $f2 = $filasRed | Where-Object { $_.Modo -eq $emisor } | Select-Object -First 1
            if ($f2 -and $emisor.SelectedIndex -eq 2 -and -not $f2.Ip.Text) {
                # Propuesta: en NAT, la red de VMware; en un segmento, 192.168.(100 + nº de tarjeta).10
                $o = $opc[[Math]::Max(0, $f2.Red.SelectedIndex)]
                if ($o.Tipo -eq 'nat' -and $redNat) {
                    $b = $redNat.Subred.Split('.')
                    $f2.Ip.Text = "$($b[0]).$($b[1]).$($b[2]).30"; $f2.Pre.Text = [string]$redNat.Prefijo
                    $f2.Gw.Text = $redNat.Puerta; $f2.Dns.Text = $redNat.Puerta
                } else {
                    $f2.Ip.Text = "192.168.$(100 + $f2.Indice).10"; $f2.Pre.Text = '24'
                }
            }
            & $refrescar
        })
        $fila.Red.Add_SelectionChanged({
            param($cb, $a)
            $f2 = $filasRed | Where-Object { $_.Red -eq $cb } | Select-Object -First 1
            if (-not $f2) { return }
            if ($cb.SelectedIndex -ne $opc.Count) { $f2.Anterior = $cb.SelectedIndex; return }
            # «Nuevo segmento LAN…»: se pide el nombre y se añade a todas las tarjetas
            $nombre = Pedir-Texto 'Nuevo segmento LAN' "Nombre del segmento (por ejemplo LAB-AD).`nLas máquinas que estén en el mismo segmento se ven entre ellas, sin Internet." 'LAB'
            $nombre = "$nombre".Trim()
            if (-not $nombre) { $cb.SelectedIndex = [int]$f2.Anterior; return }
            $motivo = Validar-NombreSegmento $nombre
            if ($motivo) { Aviso $motivo; $cb.SelectedIndex = [int]$f2.Anterior; return }
            if (@($opc | Where-Object { $_.Tipo -eq 'pvn' -and $_.Texto -eq "Segmento LAN: $nombre" }).Count) {
                Aviso "Ya existe el segmento «$nombre»."; $cb.SelectedIndex = [int]$f2.Anterior; return
            }
            $id = Nuevo-Segmento $nombre
            $o = [pscustomobject]@{ Clave = "pvn:$id"; Texto = "Segmento LAN: $nombre"; Tipo = 'pvn'; Vnet = ''; Pvn = $id }
            $pos = $opc.Count
            [void]$opc.Add($o)
            foreach ($f3 in $filasRed) { $f3.Red.Items.Insert($pos, $o.Texto) }
            $f2.Anterior = $pos
            $cb.SelectedIndex = $pos
        })
    }
    & $refrescar
    $e.BtnRedNo.Add_Click({ $e.Ventana.Close() })

    $e.BtnRedOk.Add_Click({
        # Comprobar
        $activas = @($filasRed | Where-Object { $_.Chk.IsChecked })
        foreach ($fila in $activas) {
            if ($fila.Modo.SelectedIndex -ne 2) { continue }
            $ip = $fila.Ip.Text.Trim()
            if (-not (Es-IPv4 $ip)) { Aviso "Tarjeta $($fila.Indice + 1): la primera IP no es válida."; return }
            if ([int]$ip.Split('.')[3] + $sel.Count - 1 -gt 254) { Aviso "Tarjeta $($fila.Indice + 1): no caben $($sel.Count) IPs seguidas a partir de $ip."; return }
            $pre = Numero $fila.Pre.Text
            if ($pre -lt 1 -or $pre -gt 32) { Aviso "Tarjeta $($fila.Indice + 1): el prefijo tiene que ser un número del 1 al 32 (por ejemplo 24)."; return }
            if ($fila.Gw.Text.Trim() -and -not (Es-IPv4 $fila.Gw.Text.Trim())) { Aviso "Tarjeta $($fila.Indice + 1): la puerta de enlace no es válida (o déjala vacía)."; return }
            $dns = @($fila.Dns.Text -split '\s*,\s*' | Where-Object { $_ })
            if (@($dns | Where-Object { -not (Es-IPv4 $_) }).Count) { Aviso "Tarjeta $($fila.Indice + 1): algún DNS no es válido (sepáralos por comas)."; return }
        }
        $dentro = @($activas | Where-Object { $_.Modo.SelectedIndex -gt 0 }).Count -gt 0
        $manuales = @($sel | Where-Object { $_.Manual })
        if ($dentro -and $manuales.Count) {
            Aviso "Sin IP automática: $(($manuales | ForEach-Object { $_.Nombre }) -join ', ') viene de una base de instalación manual y Full Cowl no puede ponerle la IP por dentro. Deja esa tarjeta en «IP: no tocar» (solo se cambia la red en VMware) y pon la IP tú dentro de la máquina." 'Sin IP automática'
            return
        }
        $hayWindows = @($sel | Where-Object { $_.EsWindows }).Count -gt 0
        $correr = $dentro -or ($e.PingRed.IsChecked -and $hayWindows)
        if ($correr -and -not (Obtener-Password -SinPreguntar)) { Aviso (Texto-SinPassword) 'Falta la contraseña de las VMs'; return }

        # Tarjetas en VMware (.vmx) y lo que hay que hacer dentro de cada máquina
        $pedidoMaq = @()
        try {
            Iniciar-Espera; try {
                for ($k = 0; $k -lt $sel.Count; $k++) {
                    $m = $sel[$k]
                    $viejas = @($m.Tarjetas)
                    $modeloDef = if ($viejas.Count -and $viejas[0].Modelo) { $viejas[0].Modelo } elseif ($m.EsWindows) { 'e1000e' } else { 'vmxnet3' }
                    $nuevas = @(); $dentroMaq = @(); $primeraIp = $null
                    foreach ($fila in $activas) {
                        $o = $opc[$fila.Red.SelectedIndex]
                        $v = $viejas[$fila.Indice]
                        $mac = if ($v -and $v.Mac) { $v.Mac } else { Nueva-Mac }
                        $nuevas += [pscustomobject]@{
                            Tipo = $o.Tipo; Vnet = $o.Vnet; Pvn = $o.Pvn
                            Modelo = $(if ($v -and $v.Modelo) { $v.Modelo } else { $modeloDef })
                            Mac = $mac; MacFija = $(if ($v -and $v.Mac) { [bool]$v.MacFija } else { $true })
                        }
                        $modo = switch ($fila.Modo.SelectedIndex) { 1 { 'dhcp' } 2 { 'fija' } default { 'igual' } }
                        $t = [ordered]@{ mac = $mac.ToLower(); modo = $modo; ip = ''; prefix = 0; gw = ''; dns = @(); nombre = ($o.Texto -replace '^Segmento LAN: ', '' -replace ' \(.*$', '') }
                        if ($modo -eq 'fija') {
                            $b = $fila.Ip.Text.Trim().Split('.')
                            $t.ip = "$($b[0]).$($b[1]).$($b[2]).$([int]$b[3] + $k)"
                            $t.prefix = Numero $fila.Pre.Text; $t.gw = $fila.Gw.Text.Trim()
                            $t.dns = @($fila.Dns.Text -split '\s*,\s*' | Where-Object { $_ })
                            if (-not $primeraIp) { $primeraIp = $t.ip }
                        }
                        $dentroMaq += $t
                    }
                    Guardar-Tarjetas $m.Vmx $nuevas
                    if ($primeraIp) { Fijar-ValoresVmx $m.Vmx @{ 'guestinfo.vmtareas.ip' = $primeraIp } }
                    $pedidoMaq += [ordered]@{ nombre = $m.Nombre; vmx = $m.Vmx; eswindows = [bool]$m.EsWindows; netbios = $m.Netbios; tarjetas = @($dentroMaq) }
                }
            } finally { Terminar-Espera }
        } catch {
            Error-Msg "No se pudo cambiar la configuración de red:`n$($_.Exception.Message)"; return
        }
        if ($correr) {
            Lanzar 'red-ip.ps1' ([ordered]@{ ping = [bool]$e.PingRed.IsChecked; maquinas = @($pedidoMaq) })
            Mostrar-Toast "Red cambiada en $(Plural $sel.Count 'máquina' 'máquinas'). Se encienden y se configura la IP dentro: mira la consola."
        } else {
            Mostrar-Toast "Red cambiada en $(Plural $sel.Count 'máquina' 'máquinas')."
        }
        $e.Ventana.Close()
    })
    [void]$e.Ventana.ShowDialog()
    Cargar -Silencioso
})

# ---------------------------------------------------------------- pasar archivos entre el PC y la máquina
$AccArchivos.Add_Click({
    $m = Maquina-Sel
    if (-not $m -or -not (Hay-Vmrun)) { return }
    if (-not $m.Encendida) { Aviso "Enciende antes «$($m.Nombre)»."; return }
    $pass = Obtener-Password -SinPreguntar
    if (-not $pass) { Aviso (Texto-SinPassword) 'Falta la contraseña de las VMs'; return }
    $esLinux = -not $m.EsWindows
    $usu = $null; $carpeta = $null; $problema = $null; $archCallado = $null
    Iniciar-Espera; try {
        if (-not (Tools-Listas $script:vmrun $m.Vmx $script:pulsoVmrun)) {
            $problema = "Las VMware Tools no responden en «$($m.Nombre)». Espera a que arranque. Si es Windows y en VMware sale «Install VMware Tools», su base es anterior al 29/10/2026: rehazla (o instálalas a mano en esta máquina)."
        } else {
            $usu = Entrar-Invitado $script:vmrun $m.Vmx $esLinux $m.Netbios $pass 1
            if (-not $usu) { $problema = "No se pudo entrar en «$($m.Nombre)» con el usuario «$(Usuario-DeVm $m.Vmx)»." }
        }
        if (-not $problema) {
            $u = ($usu -split '\\')[-1]
            if ($esLinux) { $candidatas = @("/home/$u/Escritorio", "/home/$u/Desktop", "/home/$u") }
            else {
                # Primero el escritorio de quien tiene la sesión abierta en la máquina (puede no ser el usuario de vmrun)
                $dueno = Usuario-ConSesion $script:vmrun $m.Vmx $usu $pass
                $candidatas = @($(if ($dueno) { "C:\Users\$dueno\Desktop" }), "C:\Users\$u\Desktop", $(if ($m.Netbios) { "C:\Users\$u.$($m.Netbios)\Desktop" }), 'C:\Users\Public\Desktop')
                try { Escribir-Log "Pasar archivos: usuario vmrun=$usu, sesión abierta=$dueno" } catch {}
            }
            $rDir = $null
            foreach ($cand in @($candidatas | Where-Object { $_ })) {
                $rDir = Vmrun-Ventana @('-gu', $usu, '-gp', $pass, 'directoryExistsInGuest', $m.Vmx, $cand)
                if ($rDir.Agotado) { break }
                if ($rDir.Codigo -eq 0) { $carpeta = $cand; break }
            }
            if ($rDir -and $rDir.Agotado) { $archCallado = $rDir; $problema = 'VMware no contesta.' }
            elseif (-not $carpeta) { $problema = 'No encuentro el escritorio dentro de la máquina.' }
        }
    } finally { Terminar-Espera; Soltar-Ventanas }
    if ($archCallado) { Aviso-VmrunAgotado $archCallado; return }
    if ($problema) { Aviso $problema; return }
    $sep = if ($esLinux) { '/' } else { '\' }
    $escritorioPC = [Environment]::GetFolderPath('Desktop')

    $e = Nuevo-Dialogo 'dialogo-archivos.xaml' 'Pasar archivos' $m.Nombre 580
    Poner-PastillaDlg $e $m
    $e.CarpetaArch.Text = "Escritorio de la máquina: $carpeta"
    $listar = {
        $e.ListaArch.Items.Clear()
        Iniciar-Espera; try {
            $rLista = Vmrun-Ventana @('-gu', $usu, '-gp', $pass, 'listDirectoryInGuest', $m.Vmx, $carpeta)
            foreach ($l in @($rLista.Lineas | Select-Object -Skip 1)) {
                $n = "$l".Trim()
                if ($n -and $n -notmatch '^(desktop\.ini|\..*)$') { [void]$e.ListaArch.Items.Add($n) }
            }
        } finally { Terminar-Espera }
        if ($rLista -and $rLista.Agotado) { $e.ResArch.Text = "VMware no ha contestado en $([int]$rLista.Limite) segundos: pulsa «Actualizar» dentro de un momento." }
        $e.SinArch.Visibility = $(if ($e.ListaArch.Items.Count) { 'Collapsed' } else { 'Visible' })
    }
    & $listar
    $e.BtnArchCerrar.Add_Click({ $e.Ventana.Close() })
    $e.BtnArchActualizar.Add_Click({ & $listar })
    $e.BtnArchEnviar.Add_Click({
        $fd = New-Object Microsoft.Win32.OpenFileDialog
        $fd.Title = "Archivos para enviar a $($m.Nombre)"; $fd.Multiselect = $true; $fd.Filter = 'Todos los archivos (*.*)|*.*'
        if (-not $fd.ShowDialog($e.Ventana)) { return }
        $bien = 0; $mal = @(); $lentos = @(); $numArch = 0; $totalArch = @($fd.FileNames).Count
        Iniciar-Espera; try {
            foreach ($ruta in $fd.FileNames) {
                $numArch++
                $e.ResArch.Text = "Copiando $numArch de ${totalArch}: $(Split-Path $ruta -Leaf)…"
                # Límite según el tamaño: 2 min + 1 s por cada 10 MB (30 min como mucho). El tamaño, en [double]
                $pesoArch = [double]0; try { $pesoArch = [double](New-Object IO.FileInfo($ruta)).Length } catch {}
                $rCopia = Vmrun-Ventana @('-gu', $usu, '-gp', $pass, 'copyFileFromHostToGuest', $m.Vmx, $ruta, ($carpeta + $sep + (Split-Path $ruta -Leaf))) (Limite-CopiaVmrun $pesoArch)
                if ($rCopia.Agotado) { $lentos += (Split-Path $ruta -Leaf); break }      # VMware no contesta: no se insiste con los demás
                if ($rCopia.Codigo -eq 0) { $bien++ } else { $mal += (Split-Path $ruta -Leaf) }
            }
        } finally { Terminar-Espera }
        $e.ResArch.Text = "Enviados $bien archivo(s) al escritorio de la máquina." + $(if ($mal.Count) { "  No se pudieron enviar: $($mal -join ', ')" } else { '' }) + $(if ($lentos.Count) { "  VMware no contestó a tiempo con «$($lentos -join ', ')» (puede haberse copiado igualmente); el resto no se ha intentado." } else { '' })
        & $listar
    })
    $e.BtnArchTraer.Add_Click({
        $elegidos = @($e.ListaArch.SelectedItems | ForEach-Object { [string]$_ })
        if (-not $elegidos.Count) { Aviso 'Elige en la lista los archivos que quieres traer.'; return }
        $bien = 0; $mal = @(); $lentos = @(); $numArch = 0
        Iniciar-Espera; try {
            foreach ($n in $elegidos) {
                $numArch++
                $e.ResArch.Text = "Copiando $numArch de $($elegidos.Count): $n…"
                # El nombre lo da la máquina: se limpia para que no pueda salirse del escritorio (..\, rutas,
                # caracteres raros) y no se pisa ningún archivo que ya exista
                $limpio = (($n -replace '[\\/:*?"<>|\x00-\x1F]', '_').Trim(' .'))
                if (-not $limpio -or $limpio -match '^\.+$') { $mal += $n; continue }
                $destino = Join-Path $escritorioPC $limpio
                $nomBase = [IO.Path]::GetFileNameWithoutExtension($limpio); $ext = [IO.Path]::GetExtension($limpio); $k = 2
                while (Test-Path -LiteralPath $destino) { $destino = Join-Path $escritorioPC "$nomBase ($k)$ext"; $k++ }
                if ((Split-Path $destino) -ne $escritorioPC) { $mal += $n; continue }
                # No se sabe el tamaño de antemano: el límite más largo de copia (30 min)
                $rCopia = Vmrun-Ventana @('-gu', $usu, '-gp', $pass, 'copyFileFromGuestToHost', $m.Vmx, ($carpeta + $sep + $n), $destino) 1800
                if ($rCopia.Agotado) { $lentos += $n; break }
                if ($rCopia.Codigo -eq 0) { $bien++ } else { $mal += $n }
            }
        } finally { Terminar-Espera }
        $e.ResArch.Text = "Traídos $bien archivo(s) a tu escritorio." + $(if ($mal.Count) { "  No se pudieron traer (¿son carpetas?): $($mal -join ', ')" } else { '' }) + $(if ($lentos.Count) { "  VMware no contestó a tiempo con «$($lentos -join ', ')»; el resto no se ha intentado." } else { '' })
    })
    [void]$e.Ventana.ShowDialog()
})

# ---------------------------------------------------------------- teclado de la lista
$Lista.Add_PreviewKeyDown({
    param($s, $a)
    if ($a.Key -eq [System.Windows.Input.Key]::Enter) { Abrir-EnVmware; $a.Handled = $true }
    elseif ($a.Key -eq [System.Windows.Input.Key]::Delete -and $AccBorrar.IsEnabled) { $AccBorrar.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))); $a.Handled = $true }
})

# Vista y tamaño elegidos en Ajustes
Aplicar-VistaMaquinas
