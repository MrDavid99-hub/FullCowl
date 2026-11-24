#  Ficha del laboratorio (ficha 29): un documento (PDF, o Markdown) con las IP, usuarios y roles de cada máquina de un
#  laboratorio, para la memoria de una práctica.
#  - Se genera SIN tocar las máquinas (no las enciende ni entra en ellas). La IP sale de lo que Full Cowl tiene apuntado
#    (guestinfo.vmtareas.ip); en las que están encendidas y no tienen IP fija se le pregunta a VMware (solo lectura).
#  - REGLA FIRME: nunca la contraseña (ni la temporal, ni la clave del CD, ni nada de password.sec). Aquí no se lee nada de eso.
#  - Todo texto que va al HTML pasa por Esc-Html (< > & " '): un nombre de máquina no puede romper ni inyectar nada.
#  - El PDF se hace con Microsoft Edge sin ventana (viene con Windows); sin Edge o si falla se deja el HTML (o el .md).

function Esc-Html([string]$t) { return [System.Net.WebUtility]::HtmlEncode($t) }

function Texto-Corto([string]$t, [int]$max) {
    if ($t.Length -le $max) { return $t }
    return ($t.Substring(0, [Math]::Max(1, $max - 1)) + '…')
}

function Celda-Md([string]$t) {
    # Una celda de tabla Markdown: sin saltos de línea y con las barras escapadas
    return (([string]$t) -replace '\r?\n', ' ' -replace '\|', '\|').Trim()
}

function Disco-Maquina([string]$vmx) {
    # Tamaño del primer disco (el que dice su .vmx) leyendo la cabecera del .vmdk; '' si no se puede saber
    try {
        $dir = Split-Path $vmx
        foreach ($bus in @('scsi0:0', 'sata0:0', 'nvme0:0', 'ide0:0')) {
            $f = [string](Leer-ValorVmx $vmx "$bus.fileName")
            if (-not $f) { continue }
            $ruta = $(if ([IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $dir $f })
            if (-not (Test-Path -LiteralPath $ruta)) { continue }
            $fs = [IO.File]::OpenRead($ruta)
            try {
                $buf = New-Object byte[] 8192
                $n = $fs.Read($buf, 0, $buf.Length)
                $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $n)
            } finally { $fs.Dispose() }
            $sec = [double]0
            foreach ($m in [regex]::Matches($txt, '(?m)^RW\s+(\d+)\s')) { $sec += [double]$m.Groups[1].Value }
            if ($sec -gt 0) {
                $gb = $sec * 512 / 1GB
                return $(if ($gb -ge 10) { ('{0:0} GB' -f $gb) } else { ('{0:0.#} GB' -f $gb) })
            }
        }
    } catch {}
    return ''
}

function Ram-Maquina([string]$vmx) {
    $mb = 0; try { $mb = Numero (Leer-ValorVmx $vmx 'memsize') 0 } catch {}
    if ($mb -ge 1024) { return ('{0:0.#} GB' -f ($mb / 1024)) }
    if ($mb -gt 0) { return "$mb MB" }
    return ''
}

function Datos-FichaLab([string]$nombreLab) {
    # Todo lo que lleva la ficha, leído de las filas de «Mis máquinas» y de los .vmx (sin encender ni tocar nada)
    $g = Grupos-Lab
    if (-not $g.Contains($nombreLab)) { return $null }
    $filasLab = @($g[$nombreLab])
    $modelo = Construir-ModeloLab $filasLab
    # Nombre claro de cada sistema (una sola lectura del catálogo)
    $catalogo = @{}
    try { foreach ($sis in @(Obtener-Sistemas)) { $catalogo[[string]$sis.Clave] = (([string]$sis.Nombre) -replace '\s*\(.*\)\s*$', '').Trim() } } catch {}
    $maq = @()
    foreach ($fl in $filasLab) {
        $d = $fl.Datos
        $mm = @($modelo.Maquinas | Where-Object { $_.Vmx -eq [string]$fl.Vmx }) | Select-Object -First 1
        $rol = ''
        if ($mm) { $rol = $(if ($mm.EsDc) { 'Controlador de dominio' } elseif ($mm.Etiqueta) { [string]$mm.Etiqueta } elseif ($modelo.Dominio) { 'Fuera del dominio' } else { '' }) }
        $ip = [string]$d.IP
        if (-not (Es-IPv4 $ip)) { $ip = ''; try { $ip = [string](Ip-Rapida $d) } catch {} }
        $base = [string]$d.Base
        $sistema = $(if ($base -and $catalogo.ContainsKey($base)) { $catalogo[$base] } else { [string]$d.Familia })
        $er = $null; try { $er = Estado-Rapido $d } catch {}
        $con = $(if ($er) { [string]$er.Conexion } else { '' })
        $usuario = ''; try { $usuario = [string](Usuario-DeVm $d.Vmx) } catch {}
        $software = @()
        if ($mm -and $mm.EsDc) { $software += "Controlador de dominio ($($modelo.Dominio))" }
        # Extras pedidos al crearla (ficha 20): solo identificadores con la forma del catálogo; se enseña su nombre
        $idsEx = @(([string]$d.Extras) -split ',' | Where-Object { $_ -cmatch '^[a-z0-9]{1,24}$' -and $_ -ne 'ping' })
        if ($idsEx.Count) { $software += @($idsEx | ForEach-Object { Nombre-Extra $_ }) }
        elseif ($d.Web) { $software += 'Servidor web (Apache, Nginx o IIS)' }
        if ([string]$d.Tipo -eq 'Importada') { $software += 'Máquina importada' }
        $maq += [pscustomobject]@{
            Nombre = [string]$fl.Nombre; Sistema = $sistema; Rol = $rol; Ip = $ip; Red = [string]$d.Red
            Usuario = $usuario; Conexion = $con; Windows = [bool]$d.EsWindows; Encendida = [bool]$fl.Encendida
            Ram = (Ram-Maquina $d.Vmx); Cpus = $(try { Numero (Leer-ValorVmx $d.Vmx 'numvcpus') 0 } catch { 0 }); Disco = (Disco-Maquina $d.Vmx)
            Software = $software; Etiquetas = @($d.Etiquetas); Nota = [string]$d.Nota
            Simbolo = $(try { $s = ([string]$fl.IconoSimbolo) -replace '^F[01]\s*', ''; if ($s -match '^M') { $s } else { '' } } catch { '' })
            Vmx = [string]$fl.Vmx
        }
    }
    $dc = @($maq | Where-Object { $_.Rol -eq 'Controlador de dominio' }) | Select-Object -First 1
    $netbios = ''; foreach ($fl in $filasLab) { if ([string]$fl.Datos.Netbios -and -not $netbios) { $netbios = [string]$fl.Datos.Netbios } }
    # Estado inicial guardado (ficha 28): fecha de la instantánea «inicio-lab» (la más antigua de sus máquinas)
    $conInicio = 0; $fechasInicio = @()
    foreach ($mq in $maq) {
        $snapIni = @(Leer-Instantaneas $mq.Vmx | Where-Object { $_.Nombre -ceq (Nombre-EstadoInicial) }) | Select-Object -First 1
        if ($snapIni) { $conInicio++; if ($snapIni.Fecha) { $fechasInicio += $snapIni.Fecha } }
    }
    $textoInicio = ''
    if ($conInicio) {
        $textoInicio = $(if ($fechasInicio.Count) { 'Guardado el ' + (@($fechasInicio | Sort-Object)[0]).ToString('dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture) } else { 'Guardado' })
        if ($conInicio -lt @($maq).Count) { $textoInicio += " (solo en $conInicio de $(@($maq).Count) máquinas)" }
    }
    return [pscustomobject]@{
        Nombre = $nombreLab; Modelo = $modelo; Maquinas = $maq; Dominio = [string]$modelo.Dominio; Netbios = $netbios
        Controlador = $dc; Desechable = [bool](@($filasLab | Where-Object { [string]$_.Datos.Desechable }).Count); EstadoInicial = $textoInicio
    }
}

function Frase-Conexion($m, [bool]$conUsuario) {
    if (-not $m.Ip) { return 'Sin IP conocida: enciende la máquina y espera a que arranque.' }
    switch ($m.Conexion) {
        'rdp' { return "Escritorio remoto a $($m.Ip)" }
        'ssh' { return "ssh $(if ($conUsuario -and $m.Usuario) { $m.Usuario } else { 'usuario' })@$($m.Ip)" }
        default { return 'Desde su ventana de VMware (sin conexión remota automática).' }
    }
}

function Esquema-SvgFicha($datos, [string]$acento) {
    # El mapa de «bandas apiladas» del laboratorio, como SVG (texto y dibujo reales, no captura), en grises y un toque de acento
    $m = $datos.Modelo
    $W = 720; $bw = 165; $gap = 20; $bh = 62
    $sb = New-Object System.Text.StringBuilder
    $y = 4
    foreach ($r in $m.Redes) {
        $rotulo = $r.Nombre
        if ($r.Subred) { $rotulo += "  ·  $($r.Subred)" }
        if ($r.Internet) { $rotulo += '  ·  con Internet' }
        [void]$sb.AppendLine("<rect x=`"0`" y=`"$y`" width=`"$W`" height=`"26`" rx=`"6`" fill=`"#EEF3F0`" stroke=`"$acento`" stroke-width=`"1.2`"/>")
        [void]$sb.AppendLine("<text x=`"12`" y=`"$($y + 17)`" font-size=`"11.5`" font-weight=`"600`" fill=`"#1F2A24`">$(Esc-Html (Texto-Corto $rotulo 95))</text>")
        $y += 26
        $lista = @($r.Primeras)
        $filas = [Math]::Ceiling($lista.Count / 4)
        for ($i = 0; $i -lt $lista.Count; $i++) {
            $mq = $lista[$i]
            $fila = [Math]::Floor($i / 4); $col = $i % 4
            $enFila = [Math]::Min(4, $lista.Count - $fila * 4)
            $x0 = ($W - ($enFila * $bw + ($enFila - 1) * $gap)) / 2
            $x = $x0 + $col * ($bw + $gap)
            $by = $y + 22 + $fila * ($bh + 22)
            $cx = $x + $bw / 2
            [void]$sb.AppendLine("<line x1=`"$cx`" y1=`"$($by - 22)`" x2=`"$cx`" y2=`"$by`" stroke=`"#9AA5A0`" stroke-width=`"1.5`"/>")
            [void]$sb.AppendLine("<rect x=`"$x`" y=`"$by`" width=`"$bw`" height=`"$bh`" rx=`"8`" fill=`"#FFFFFF`" stroke=`"#7C8A83`" stroke-width=`"1`"/>")
            $info = @($datos.Maquinas | Where-Object { $_.Vmx -eq $mq.Vmx }) | Select-Object -First 1
            $tx = $x + 10
            if ($info -and $info.Simbolo) {
                [void]$sb.AppendLine("<g transform=`"translate($($x + 9),$($by + 9)) scale(0.85)`"><path d=`"$(Esc-Html $info.Simbolo)`" fill=`"none`" stroke=`"#6B7770`" stroke-width=`"1.8`" stroke-linecap=`"round`" stroke-linejoin=`"round`"/></g>")
                $tx = $x + 36
            }
            [void]$sb.AppendLine("<text x=`"$tx`" y=`"$($by + 19)`" font-size=`"11.5`" font-weight=`"600`" fill=`"#1F2A24`">$(Esc-Html (Texto-Corto $mq.Nombre 17))</text>")
            $linea2 = $(if ($mq.Ip) { $mq.Ip } else { 'sin IP' })
            [void]$sb.AppendLine("<text x=`"$tx`" y=`"$($by + 34)`" font-size=`"10.5`" fill=`"$(if ($mq.Ip) { '#2D3B33' } else { '#9AA5A0' })`">$(Esc-Html $linea2)</text>")
            $extra = $(if ($mq.Etiqueta) { $mq.Etiqueta } elseif ($mq.Redes.Count -gt 1) { 'también en ' + (@($mq.Redes | Select-Object -Skip 1 | ForEach-Object { $m.Todas[$_].Nombre }) -join ', ') } else { '' })
            if ($extra) { [void]$sb.AppendLine("<text x=`"$($x + 10)`" y=`"$($by + 52)`" font-size=`"9.5`" font-style=`"italic`" fill=`"#6B7770`">$(Esc-Html (Texto-Corto $extra 30))</text>") }
        }
        $y += 22 + $filas * ($bh + 22) + 6
    }
    $alto = $y + 4
    return "<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 $W $alto`" width=`"100%`" role=`"img`" aria-label=`"Esquema de la red`" font-family=`"Inter, 'Segoe UI', Arial, sans-serif`">`n$($sb.ToString())</svg>"
}

function Base64-Archivo([string]$ruta) {
    try { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($ruta)) } catch { return '' }
}

function Html-FichaLab($datos, $op) {
    $dirRec = Join-Path $dirFc 'recursos'
    $acento = '#2D6A3E'; try { $acento = [string](Valor-Paleta 'acento' 0) } catch {}
    if ($acento -notmatch '^#[0-9A-Fa-f]{6}$') { $acento = '#2D6A3E' }
    $logo = Base64-Archivo (Join-Path $dirRec 'logo.png')
    $fuenteR = Base64-Archivo (Join-Path $dirRec 'fuentes\Inter-Regular.ttf')
    $fuenteS = Base64-Archivo (Join-Path $dirRec 'fuentes\Inter-SemiBold.ttf')
    $ver = Version-Fclab
    $fecha = (Get-Date).ToString('dd/MM/yyyy HH:mm')
    $titulo = Esc-Html $op.Titulo
    $nombreEnSub = $(if (([string]$op.Titulo).ToLower().Contains(([string]$datos.Nombre).ToLower())) { '' } else { "Laboratorio $(Esc-Html $datos.Nombre) · " })
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="es"><head><meta charset="utf-8">')
    [void]$sb.AppendLine("<title>$titulo</title>")
    [void]$sb.AppendLine("<meta name=`"author`" content=`"$(Esc-Html $op.Autor)`">")
    [void]$sb.AppendLine("<meta name=`"subject`" content=`"Ficha del laboratorio $(Esc-Html $datos.Nombre)`">")
    [void]$sb.AppendLine('<meta name="generator" content="Full Cowl">')
    [void]$sb.AppendLine('<style>')
    if ($fuenteR) { [void]$sb.AppendLine("@font-face { font-family: 'Inter'; font-weight: 400; src: url(data:font/ttf;base64,$fuenteR) format('truetype'); }") }
    if ($fuenteS) { [void]$sb.AppendLine("@font-face { font-family: 'Inter'; font-weight: 600; src: url(data:font/ttf;base64,$fuenteS) format('truetype'); }") }
    [void]$sb.AppendLine(@"
@page { size: A4; margin: 18mm; }
* { box-sizing: border-box; }
body { font-family: 'Inter', 'Segoe UI', Arial, sans-serif; font-size: 9.5pt; color: #1B241F; background: #FFFFFF; margin: 0; line-height: 1.4; }
header { display: flex; align-items: center; gap: 14px; border-bottom: 2px solid $acento; padding-bottom: 10px; margin-bottom: 14px; }
header img { width: 44px; height: 44px; }
header h1 { font-size: 19pt; margin: 0; font-weight: 600; }
header .sub { color: #55625A; font-size: 9pt; margin-top: 2px; }
h2 { font-size: 12.5pt; font-weight: 600; color: $acento; margin: 18px 0 6px 0; border-bottom: 1px solid #D5DDD8; padding-bottom: 3px; break-after: avoid; }
table { border-collapse: collapse; width: 100%; margin: 4px 0 6px 0; }
th, td { border: 1px solid #B7C2BB; padding: 4px 6px; text-align: left; vertical-align: top; font-size: 8.8pt; }
th { background: #EEF3F0; font-weight: 600; }
tr { break-inside: avoid; page-break-inside: avoid; }
td.gris { color: #8A958F; }
td:nth-child(4) { white-space: nowrap; }
.resumen td:first-child { width: 34%; font-weight: 600; background: #F6F9F7; }
ul { margin: 4px 0 4px 18px; padding: 0; }
.nota-linea { border-bottom: 1px solid #B7C2BB; height: 24px; }
.esquema { break-inside: avoid; margin-top: 6px; }
footer { margin-top: 22px; border-top: 1px solid #D5DDD8; padding-top: 8px; color: #55625A; font-size: 8.5pt; }
footer strong { color: #1B241F; }
code { font-family: Consolas, 'Courier New', monospace; font-size: 9pt; background: #F1F4F2; padding: 0 3px; }
"@)
    [void]$sb.AppendLine('</style></head><body>')
    # 1. Cabecera
    [void]$sb.AppendLine('<header>')
    if ($logo) { [void]$sb.AppendLine("<img src=`"data:image/png;base64,$logo`" alt=`"Full Cowl`">") }
    [void]$sb.AppendLine("<div><h1>$titulo</h1><div class=`"sub`">$nombreEnSub$fecha · Full Cowl v$(Esc-Html $ver) · Autor: $(Esc-Html $op.Autor)</div></div>")
    [void]$sb.AppendLine('</header>')
    # 2. Resumen
    $m = $datos.Modelo
    $redesTxt = (@($m.Redes | ForEach-Object { if ($_.Subred) { "$($_.Nombre) ($($_.Subred))" } else { $_.Nombre } }) -join '; ')
    [void]$sb.AppendLine('<h2>Resumen</h2><table class="resumen">')
    [void]$sb.AppendLine("<tr><td>Máquinas</td><td>$(@($datos.Maquinas).Count)</td></tr>")
    [void]$sb.AppendLine("<tr><td>Red</td><td>$(Esc-Html $redesTxt)</td></tr>")
    if ($datos.Dominio) { [void]$sb.AppendLine("<tr><td>Dominio</td><td>$(Esc-Html $datos.Dominio)$(if ($datos.Netbios) { ' (NetBIOS ' + (Esc-Html $datos.Netbios) + ')' })</td></tr>") }
    [void]$sb.AppendLine("<tr><td>Desechable</td><td>$(if ($datos.Desechable) { 'Sí' } else { 'No' })</td></tr>")
    if ($datos.EstadoInicial) { [void]$sb.AppendLine("<tr><td>Estado inicial</td><td>$(Esc-Html $datos.EstadoInicial)</td></tr>") }
    [void]$sb.AppendLine('</table>')
    # 3. Máquinas
    [void]$sb.AppendLine('<h2>Máquinas</h2><table><thead><tr><th>Máquina</th><th>Sistema</th><th>Rol</th><th>IP</th><th>Red</th>')
    if ($op.Usuarios) { [void]$sb.Append('<th>Usuario</th>') }
    if ($op.Recursos) { [void]$sb.Append('<th>Recursos</th>') }
    [void]$sb.AppendLine('</tr></thead><tbody>')
    foreach ($x in $datos.Maquinas) {
        $ipTd = $(if ($x.Ip) { "<td>$(Esc-Html $x.Ip)</td>" } else { '<td class="gris">sin IP</td>' })
        [void]$sb.Append("<tr><td><strong>$(Esc-Html $x.Nombre)</strong></td><td>$(Esc-Html $x.Sistema)</td><td>$(Esc-Html $x.Rol)</td>$ipTd<td>$(Esc-Html $x.Red)</td>")
        if ($op.Usuarios) { [void]$sb.Append("<td>$(Esc-Html $x.Usuario)</td>") }
        if ($op.Recursos) {
            $rec = @(@($x.Ram, $(if ($x.Cpus -gt 0) { Plural $x.Cpus 'CPU' 'CPUs' } else { '' }), $(if ($x.Disco) { "disco $($x.Disco)" } else { '' })) | Where-Object { $_ }) -join ' · '
            [void]$sb.Append("<td>$(Esc-Html $rec)</td>")
        }
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</tbody></table>')
    # 4. Dominio y red
    [void]$sb.AppendLine('<h2>Dominio y red</h2>')
    if ($datos.Dominio) {
        $ctl = $datos.Controlador
        [void]$sb.AppendLine("<p>Dominio <strong>$(Esc-Html $datos.Dominio)</strong>$(if ($datos.Netbios) { ' (NetBIOS ' + (Esc-Html $datos.Netbios) + ')' }). Controlador: <strong>$(if ($ctl) { Esc-Html $ctl.Nombre } else { '—' })</strong>$(if ($ctl -and $ctl.Ip) { ' (' + (Esc-Html $ctl.Ip) + ')' }).</p>")
    }
    [void]$sb.AppendLine('<table><thead><tr><th>Red</th><th>Tipo</th><th>Rango (estimado)</th><th>Internet</th></tr></thead><tbody>')
    foreach ($r in $m.Redes) {
        $tipoTxt = switch ($r.Tipo) { 'nat' { 'NAT' } 'bridged' { 'Puente' } 'hostonly' { 'Solo anfitrión' } 'custom' { 'Red de VMware' } 'pvn' { 'Segmento LAN' } default { 'Sin red' } }
        [void]$sb.AppendLine("<tr><td>$(Esc-Html $r.Nombre)</td><td>$tipoTxt</td><td>$(if ($r.Subred) { (Esc-Html $r.Subred) + ' (máscara 255.255.255.0)' } else { '—' })</td><td>$(if ($r.Internet) { 'Sí' } else { 'No' })</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table>')
    # 5. Roles y software
    $conSoft = @($datos.Maquinas | Where-Object { $_.Software.Count -or $_.Etiquetas.Count -or $_.Nota })
    if ($conSoft.Count) {
        [void]$sb.AppendLine('<h2>Roles y software</h2><ul>')
        foreach ($x in $conSoft) {
            $partes = @()
            if ($x.Software.Count) { $partes += (@($x.Software | ForEach-Object { Esc-Html $_ }) -join ', ') }
            if ($x.Etiquetas.Count) { $partes += 'etiquetas: ' + (@($x.Etiquetas | ForEach-Object { Esc-Html $_ }) -join ', ') }
            if ($x.Nota) { $partes += 'nota: ' + (Esc-Html $x.Nota) }
            [void]$sb.AppendLine("<li><strong>$(Esc-Html $x.Nombre)</strong>: $($partes -join ' · ')</li>")
        }
        [void]$sb.AppendLine('</ul>')
    }
    # 7. Esquema
    if ($op.Esquema) { [void]$sb.AppendLine('<h2>Esquema de la red</h2><div class="esquema">' + (Esquema-SvgFicha $datos $acento) + '</div>') }
    # 8. Cómo conectarse
    [void]$sb.AppendLine('<h2>Cómo conectarse</h2><ul>')
    foreach ($x in $datos.Maquinas) { [void]$sb.AppendLine("<li><strong>$(Esc-Html $x.Nombre)</strong>: <code>$(Esc-Html (Frase-Conexion $x $op.Usuarios))</code></li>") }
    [void]$sb.AppendLine('</ul>')
    # 9. Notas
    if ($op.Notas) {
        [void]$sb.AppendLine('<h2>Notas</h2><div style="break-inside: avoid">')
        1..12 | ForEach-Object { [void]$sb.AppendLine('<div class="nota-linea"></div>') }
        [void]$sb.AppendLine('</div>')
    }
    # 10. Pie
    [void]$sb.AppendLine("<footer>Generado con Full Cowl v$(Esc-Html $ver). <strong>La contraseña de las máquinas no se guarda en este documento.</strong></footer>")
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

function Carpeta-FichasPorDefecto {
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Full Cowl\Fichas')
}

function Carpeta-FichasLab {
    # Carpeta donde se proponen las fichas del laboratorio: la de Ajustes → Este PC (CarpetaFichas) o, si no hay, Documentos\Full Cowl\Fichas
    $elegida = ([string]$Config.CarpetaFichas).Trim()
    if ($elegida) { return $elegida }
    return (Carpeta-FichasPorDefecto)
}

function Md-FichaLab($datos, $op) {
    $ver = Version-Fclab
    $m = $datos.Modelo
    $l = New-Object System.Collections.ArrayList
    [void]$l.Add("# $($op.Titulo -replace '\r?\n', ' ')")
    [void]$l.Add('')
    $nombreEnSubMd = $(if (([string]$op.Titulo).ToLower().Contains(([string]$datos.Nombre).ToLower())) { '' } else { "Laboratorio **$(Celda-Md $datos.Nombre)** · " })
    [void]$l.Add("$nombreEnSubMd$((Get-Date).ToString('dd/MM/yyyy HH:mm')) · Full Cowl v$ver · Autor: $(Celda-Md $op.Autor)")
    [void]$l.Add('')
    [void]$l.Add('## Resumen')
    [void]$l.Add('')
    [void]$l.Add('| Dato | Valor |'); [void]$l.Add('|---|---|')
    [void]$l.Add("| Máquinas | $(@($datos.Maquinas).Count) |")
    [void]$l.Add("| Red | $(Celda-Md (@($m.Redes | ForEach-Object { if ($_.Subred) { "$($_.Nombre) ($($_.Subred))" } else { $_.Nombre } }) -join '; ')) |")
    if ($datos.Dominio) { [void]$l.Add("| Dominio | $(Celda-Md $datos.Dominio)$(if ($datos.Netbios) { ' (NetBIOS ' + (Celda-Md $datos.Netbios) + ')' }) |") }
    [void]$l.Add("| Desechable | $(if ($datos.Desechable) { 'Sí' } else { 'No' }) |")
    if ($datos.EstadoInicial) { [void]$l.Add("| Estado inicial | $(Celda-Md $datos.EstadoInicial) |") }
    [void]$l.Add('')
    [void]$l.Add('## Máquinas')
    [void]$l.Add('')
    $cab = @('Máquina', 'Sistema', 'Rol', 'IP', 'Red'); if ($op.Usuarios) { $cab += 'Usuario' }; if ($op.Recursos) { $cab += 'Recursos' }
    [void]$l.Add('| ' + ($cab -join ' | ') + ' |'); [void]$l.Add('|' + (($cab | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($x in $datos.Maquinas) {
        $c = @((Celda-Md $x.Nombre), (Celda-Md $x.Sistema), (Celda-Md $x.Rol), $(if ($x.Ip) { Celda-Md $x.Ip } else { 'sin IP' }), (Celda-Md $x.Red))
        if ($op.Usuarios) { $c += (Celda-Md $x.Usuario) }
        if ($op.Recursos) { $c += (Celda-Md (@(@($x.Ram, $(if ($x.Cpus -gt 0) { Plural $x.Cpus 'CPU' 'CPUs' } else { '' }), $(if ($x.Disco) { "disco $($x.Disco)" } else { '' })) | Where-Object { $_ }) -join ' · ')) }
        [void]$l.Add('| ' + ($c -join ' | ') + ' |')
    }
    [void]$l.Add('')
    [void]$l.Add('## Dominio y red')
    [void]$l.Add('')
    if ($datos.Dominio) {
        $ctl = $datos.Controlador
        [void]$l.Add("Dominio **$(Celda-Md $datos.Dominio)**. Controlador: **$(if ($ctl) { Celda-Md $ctl.Nombre } else { '—' })**$(if ($ctl -and $ctl.Ip) { ' (' + (Celda-Md $ctl.Ip) + ')' }).")
        [void]$l.Add('')
    }
    [void]$l.Add('| Red | Tipo | Rango (estimado) | Internet |'); [void]$l.Add('|---|---|---|---|')
    foreach ($r in $m.Redes) {
        $tipoTxt = switch ($r.Tipo) { 'nat' { 'NAT' } 'bridged' { 'Puente' } 'hostonly' { 'Solo anfitrión' } 'custom' { 'Red de VMware' } 'pvn' { 'Segmento LAN' } default { 'Sin red' } }
        [void]$l.Add("| $(Celda-Md $r.Nombre) | $tipoTxt | $(if ($r.Subred) { Celda-Md $r.Subred } else { '—' }) | $(if ($r.Internet) { 'Sí' } else { 'No' }) |")
    }
    [void]$l.Add('')
    $conSoft = @($datos.Maquinas | Where-Object { $_.Software.Count -or $_.Etiquetas.Count -or $_.Nota })
    if ($conSoft.Count) {
        [void]$l.Add('## Roles y software'); [void]$l.Add('')
        foreach ($x in $conSoft) {
            $partes = @()
            if ($x.Software.Count) { $partes += ($x.Software -join ', ') }
            if ($x.Etiquetas.Count) { $partes += 'etiquetas: ' + ($x.Etiquetas -join ', ') }
            if ($x.Nota) { $partes += 'nota: ' + ($x.Nota -replace '\r?\n', ' ') }
            [void]$l.Add("- **$(Celda-Md $x.Nombre)**: $($partes -join ' · ')")
        }
        [void]$l.Add('')
    }
    [void]$l.Add('## Cómo conectarse'); [void]$l.Add('')
    foreach ($x in $datos.Maquinas) { [void]$l.Add("- **$(Celda-Md $x.Nombre)**: ``$(Frase-Conexion $x $op.Usuarios)``") }
    [void]$l.Add('')
    if ($op.Notas) { [void]$l.Add('## Notas'); [void]$l.Add(''); 1..8 | ForEach-Object { [void]$l.Add('&nbsp;'); [void]$l.Add('') } }
    [void]$l.Add('---')
    [void]$l.Add("Generado con Full Cowl v$ver. **La contraseña de las máquinas no se guarda en este documento.**")
    if ($op.Esquema) { [void]$l.Add(''); [void]$l.Add('_El esquema de la red solo va en el formato PDF._') }
    return (($l -join "`r`n") + "`r`n")
}

function Buscar-NavegadorFicha {
    # Edge (viene con Windows 10/11 y Server) o, si no, Chrome: App Paths del registro y las carpetas de siempre
    $nombres = @('msedge.exe', 'chrome.exe')
    foreach ($n in $nombres) {
        foreach ($raiz in @('HKLM:', 'HKCU:')) {
            try {
                $v = (Get-ItemProperty -LiteralPath "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$n" -ErrorAction Stop).'(default)'
                if ($v -and (Test-Path -LiteralPath $v)) { return [string]$v }
            } catch {}
        }
        $pf86 = ${env:ProgramFiles(x86)}; $pf = $env:ProgramFiles
        $carpeta = $(if ($n -eq 'msedge.exe') { 'Microsoft\Edge\Application' } else { 'Google\Chrome\Application' })
        foreach ($p in @($pf86, $pf)) { if ($p) { $c = Join-Path $p "$carpeta\$n"; if (Test-Path -LiteralPath $c) { return $c } } }
    }
    return ''
}

function Html-APdf([string]$html, [string]$pdf, [string]$temp) {
    # $true si se creó el PDF. El perfil del navegador es una carpeta temporal propia (no choca con un Edge abierto)
    $nav = Buscar-NavegadorFicha
    if (-not $nav) { return $false }
    $url = ([Uri]$html).AbsoluteUri
    $perfil = Join-Path $temp 'perfil'
    $args1 = "--headless=new --disable-gpu --no-first-run --disable-extensions --no-pdf-header-footer --print-to-pdf-no-header --user-data-dir=`"$perfil`" --print-to-pdf=`"$pdf`" `"$url`""
    $p = $null
    try {
        $p = Start-Process -FilePath $nav -ArgumentList $args1 -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {}; return $false }
    } catch { return $false }
    # Edge nuevo a veces devuelve el control un instante antes de soltar el archivo
    for ($i = 0; $i -lt 20; $i++) { if ((Test-Path -LiteralPath $pdf) -and (Get-Item -LiteralPath $pdf).Length -gt 1000) { return $true }; Start-Sleep -Milliseconds 250 }
    return $false
}

function Nombre-ArchivoFicha([string]$carpeta, [string]$laboratorio, [string]$ext) {
    $limpio = (($laboratorio -replace '[\\/:*?"<>|]', '') -replace '\s+', ' ').Trim()
    if (-not $limpio) { $limpio = 'laboratorio' }
    $base = "Ficha - $limpio - $((Get-Date).ToString('yyyy-MM-dd'))"
    $ruta = Join-Path $carpeta "$base.$ext"; $n = 2
    while (Test-Path -LiteralPath $ruta) { $ruta = Join-Path $carpeta "$base ($n).$ext"; $n++ }
    return $ruta
}

function Generar-FichaLab([string]$nombreLab, $op) {
    # Devuelve @{ Ok; Ruta; Aviso } sin lanzar errores (los cuadros amables los pone quien llama). No enciende ni toca las máquinas.
    $res = @{ Ok = $false; Ruta = ''; Aviso = ''; Detalle = '' }
    $datos = Datos-FichaLab $nombreLab
    if (-not $datos -or -not @($datos.Maquinas).Count) { $res.Aviso = 'Este laboratorio no tiene máquinas.'; return $res }
    try { [void][IO.Directory]::CreateDirectory($op.Carpeta) }
    catch { $res.Aviso = "No puedo guardar en esa carpeta.`nElige otra con «Cambiar…»."; $res.Detalle = $_.Exception.Message; return $res }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('fullcowl-ficha-' + [guid]::NewGuid().ToString('N'))
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    try {
        [void][IO.Directory]::CreateDirectory($temp)
        if ($op.Formato -eq 'md') {
            $md = Md-FichaLab $datos $op
            $dest = Nombre-ArchivoFicha $op.Carpeta $nombreLab 'md'
            [IO.File]::WriteAllText($dest, $md, $utf8Bom)
            $res.Ok = $true; $res.Ruta = $dest
            return $res
        }
        $html = Html-FichaLab $datos $op
        $htmlTmp = Join-Path $temp 'ficha.html'
        [IO.File]::WriteAllText($htmlTmp, $html, (New-Object System.Text.UTF8Encoding($false)))
        $pdfTmp = Join-Path $temp 'ficha.pdf'
        if (Html-APdf $htmlTmp $pdfTmp $temp) {
            $dest = Nombre-ArchivoFicha $op.Carpeta $nombreLab 'pdf'
            Copy-Item -LiteralPath $pdfTmp -Destination $dest -Force
            $res.Ok = $true; $res.Ruta = $dest
        } else {
            # Sin navegador compatible o falló: se deja la página web y se explica cómo sacar el PDF
            $dest = Nombre-ArchivoFicha $op.Carpeta $nombreLab 'html'
            [IO.File]::WriteAllText($dest, $html, (New-Object System.Text.UTF8Encoding($false)))
            $res.Ok = $true; $res.Ruta = $dest
            $res.Aviso = "No se pudo crear el PDF; se ha guardado la ficha como página web: ábrela y pulsa Ctrl+P → Guardar como PDF."
        }
    } catch {
        $res.Ok = $false; $res.Detalle = $_.Exception.Message
        $res.Aviso = $(if ($_.Exception -is [UnauthorizedAccessException] -or $_.Exception -is [IO.IOException]) { "No puedo guardar en esa carpeta.`nElige otra con «Cambiar…»." } else { 'No he podido crear la ficha.' })
    } finally {
        # Los temporales siempre fuera (el navegador puede tardar un instante en soltar su perfil)
        try { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 800; try { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
    }
    return $res
}
