# =====================================================================
#  Compartir laboratorios (ficha 21): archivos .fclab
#  Un .fclab es la RECETA de un laboratorio (JSON en UTF-8, solo datos): máquinas con la clave de su base, recursos,
#  red y dominio. No lleva discos, rutas, usuarios, contraseñas ni nada de este PC. Se exporta desde «Crear
#  laboratorio» (plantillas) y desde «Mis laboratorios», y se importa con una pantalla de revisión antes de crear nada.
#  Lo carga ventana-nueva.ps1 después de laboratorio.ps1, lab-mapa.ps1, lab-mis.ps1 y lab-prev.ps1.
# =====================================================================

$script:FormatoFclab = 1
$script:ClavesTipoLab = @{ servidor = 'WinServer2022'; clientewin = 'Win11Pro'; linux = 'Ubuntu2404'; kali = 'Kali' }
$script:popMenuLab = $null

# ---------------------------------------------------------------- utilidades
function Version-Fclab { try { return ([IO.File]::ReadAllText((Join-Path (Split-Path $dirFc) 'VERSION'))).Trim() } catch { return '' } }
function Prop-Fclab($o, [string]$n) {
    if ($o -is [System.Management.Automation.PSCustomObject]) { $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value } }
    return $null
}
function Texto-Fclab($v, [int]$max) {
    if ($null -eq $v) { return '' }
    $t = (([string]$v) -replace '[\x00-\x1F\x7F]', ' ').Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max).Trim() }
    return $t
}
function Entero-Fclab($v, [int]$min, [int]$max, [int]$def, [string]$que, $avisos) {
    $n = 0
    if ($null -eq $v) { return $def }
    if (-not [int]::TryParse(([string]$v), [ref]$n)) { [void]$avisos.Add("$que no es un número: se usa $def."); return $def }
    if ($n -lt $min) { [void]$avisos.Add("$que ($n) es demasiado bajo: se usa $min."); return $min }
    if ($n -gt $max) { [void]$avisos.Add("$que ($n) es demasiado alto: se usa $max."); return $max }
    return $n
}
function Lista-Fclab($v, [string]$que, $avisos) {
    $r = New-Object System.Collections.ArrayList; $malos = 0
    if ($null -ne $v) { foreach ($x in @($v)) { $t = [string]$x; if ($t -cmatch '^[A-Za-z0-9_.-]{1,40}$' -and $r.Count -lt 20) { [void]$r.Add($t) } else { $malos++ } } }
    if ($malos) { [void]$avisos.Add("${que}: se ignoran $(Plural $malos 'valor no válido' 'valores no válidos').") }
    return ,@($r.ToArray())
}
function Ip-Fclab([string]$s) { if (Es-IPv4 $s) { return $s } return '' }
function Nombre-AmigableBase([string]$clave) {
    $s = @(Obtener-Sistemas | Where-Object { [string]$_.Clave -eq $clave }) | Select-Object -First 1
    if ($s) { return (([string]$s.Nombre) -replace '\s*\(.*\)\s*$', '').Trim() }
    return $clave
}

# ---------------------------------------------------------------- plantilla de este PC  →  archivo
function Plantilla-AFclab($pl, [string]$descripcion = '') {
    # $pl: plantilla guardada, de serie o la del creador. Devuelve @{ Objeto; NoCatalogo }
    $catalogo = @(Obtener-Sistemas | ForEach-Object { [string]$_.Clave })
    $noCat = $false
    $grupos = New-Object System.Collections.ArrayList
    foreach ($m in @($pl.maquinas)) {
        $base = [string]$m.base
        if ($m.tipo) {
            # Las plantillas de serie piden un tipo («un Ubuntu»): se exporta la base que se usaría en este PC y, si no hay, la del catálogo
            $base = ''
            try { Cargar-BasesLab; $base = Base-ParaTipoLab ([string]$m.tipo) } catch {}
            if (-not $base) { $base = [string]$script:ClavesTipoLab[[string]$m.tipo] }
        }
        if ($catalogo -notcontains $base) { $base = 'personalizada'; $noCat = $true }
        $dc = [bool]$m.dc
        $ram = [int]$m.ram; $cpus = [int]$m.cpus; $vram = $(if ($null -ne $m.vram) { [int]$m.vram } else { 0 })
        $extras = @($m.extras | Where-Object { $_ }); $etiq = @($m.etiquetas | Where-Object { $_ })
        $g = $null
        if (-not $dc) {
            foreach ($x in $grupos) {
                if (-not $x.controlador -and $x.base -eq $base -and $x.ram -eq $ram -and $x.cpus -eq $cpus -and $x.vram -eq $vram -and ((@($x.extras) -join ',') -eq ($extras -join ',')) -and ((@($x.etiquetas) -join ',') -eq ($etiq -join ','))) { $g = $x; break }
            }
        }
        if ($g) { $g.cantidad = [int]$g.cantidad + 1 }
        else { [void]$grupos.Add([ordered]@{ base = $base; cantidad = 1; ram = $ram; cpus = $cpus; vram = $vram; controlador = $dc; extras = @($extras); etiquetas = @($etiq) }) }
    }
    $claveRed = [string]$pl.red
    $tipoRed = $(if ($claveRed -in @('nat', 'bridged', 'hostonly')) { $claveRed } else { 'aislada' })
    $fija = ($pl.ip -and [string]$pl.ip.modo -eq 'fija')
    $red = [ordered]@{ tipo = $tipoRed; direcciones = $(if ($fija) { 'fija' } else { 'dhcp' }) }
    if ($fija) {
        $red.desde = Ip-Fclab ([string]$pl.ip.desde); $red.prefijo = [int]$pl.ip.prefix
        $red.puerta = Ip-Fclab ([string]$pl.ip.gw)
        $red.dns = @(@($pl.ip.dns) | ForEach-Object { Ip-Fclab ([string]$_) } | Where-Object { $_ })
    }
    $dom = $null
    if ($pl.conDominio -and [string]$pl.dominio) { $dom = [ordered]@{ nombre = [string]$pl.dominio; netbios = [string]$pl.netbios } }
    $obj = [ordered]@{
        formato = $script:FormatoFclab; creadoCon = "Full Cowl $(Version-Fclab)"
        nombre = (Texto-Fclab $pl.nombre 60); descripcion = (Texto-Fclab $descripcion 300)
        red = $red; dominio = $dom; desechable = [bool]$pl.desechable; ping = [bool]$pl.ping
        maquinas = @($grupos.ToArray())
    }
    return @{ Objeto = $obj; NoCatalogo = $noCat }
}

function Buscar-DatosPrivados([string]$texto) {
    # Última comprobación antes de guardar: nada de este PC puede acabar en el archivo
    $r = New-Object System.Collections.ArrayList
    foreach ($par in @(@($env:USERNAME, 'tu usuario de Windows'), @($env:COMPUTERNAME, 'el nombre de este PC'), @([string]$Config.Usuario, 'el usuario de las máquinas'),
                       @([string]$Config.CarpetaVMs, 'la carpeta de máquinas'), @([string]$Config.CarpetaISOs, 'la carpeta de ISOs'))) {
        $v = [string]$par[0]
        if ($v.Length -ge 4 -and $texto.IndexOf($v, [StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$r.Add($par[1]) }
    }
    if ($texto -match '[A-Za-z]:\\') { [void]$r.Add('una ruta de carpeta') }
    if ($texto -match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}') { [void]$r.Add('una dirección MAC') }
    return @($r.ToArray() | Select-Object -Unique)
}

function Exportar-Plantilla($pl) {
    try {
        if (-not $pl -or -not @($pl.maquinas).Count) { Aviso 'Esa plantilla no tiene máquinas.'; return }
        $conv = Plantilla-AFclab $pl ''
        if ($conv.NoCatalogo) { Aviso "Esta plantilla usa una base que no es del catálogo de Full Cowl (hecha o importada a mano).`nEn el archivo irá como «personalizada» y no se podrá reproducir en otro PC." 'Base personalizada' }
        $desc = Pedir-Texto 'Exportar plantilla' 'Descripción (opcional, hasta 300 caracteres; la verá quien la reciba):' ''
        if ($null -eq $desc) { return }
        $conv.Objeto.descripcion = Texto-Fclab $desc 300
        $texto = $conv.Objeto | ConvertTo-Json -Depth 8
        $privado = @(Buscar-DatosPrivados $texto)
        if ($privado.Count) { Error-Amable 'No exporto el archivo porque llevaría datos de este PC.' ("Aparece: " + ($privado -join ', ') + ". Quítalo del nombre o de la descripción y vuelve a probar.") ''; return }
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'Exportar plantilla de laboratorio'; $dlg.Filter = 'Laboratorio de Full Cowl (*.fclab)|*.fclab'; $dlg.DefaultExt = '.fclab'
        $dlg.FileName = (([string]$conv.Objeto.nombre) -replace '[\\/:*?"<>|]', '-') + '.fclab'
        if ($dlg.ShowDialog($script:ventana) -ne $true) { return }
        [IO.File]::WriteAllText($dlg.FileName, $texto, [Text.UTF8Encoding]::new($false))
        if (Pregunta "Plantilla «$($conv.Objeto.nombre)» exportada.`nPuedes enviar el archivo .fclab a quien quieras: lleva la receta, no los discos." 'Exportado' 'Mostrar en la carpeta' 'Cerrar') {
            Start-Process explorer.exe "/select,`"$($dlg.FileName)`""
        }
    } catch { Escribir-Log ("Exportar plantilla: " + ($_ | Out-String)); Error-Amable 'No se ha podido exportar la plantilla.' 'Prueba con otra carpeta.' $_.Exception.Message }
}

# ---------------------------------------------------------------- archivo  →  plantilla de este PC
function Leer-Fclab([string]$ruta) {
    $r = [pscustomobject]@{ Ok = $false; Error = ''; Hacer = ''; Detalle = ''; NuevoFormato = $false; Plantilla = $null; Descripcion = ''; CreadoCon = ''; Avisos = (New-Object System.Collections.ArrayList) }
    $av = $r.Avisos
    $o = $null
    try {
        $fi = Get-Item -LiteralPath $ruta -ErrorAction Stop
        if ($fi.Length -gt 1MB) { $r.Error = 'El archivo es demasiado grande para ser un laboratorio de Full Cowl.'; $r.Hacer = 'Comprueba que has elegido el archivo .fclab correcto.'; return $r }
        $o = [IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $r.Error = 'No se ha podido leer el archivo: está dañado o no es un laboratorio de Full Cowl.'; $r.Hacer = 'Pide que te lo vuelvan a enviar.'; $r.Detalle = $_.Exception.Message; return $r
    }
    $formato = 0
    if ($o -isnot [System.Management.Automation.PSCustomObject] -or $null -eq (Prop-Fclab $o 'formato') -or -not [int]::TryParse([string](Prop-Fclab $o 'formato'), [ref]$formato) -or $formato -lt 1) {
        $r.Error = 'Este archivo no tiene el formato de un laboratorio de Full Cowl.'; $r.Hacer = 'Tiene que ser un archivo .fclab exportado desde Full Cowl.'; return $r
    }
    if ($formato -gt $script:FormatoFclab) {
        $r.NuevoFormato = $true
        $r.Error = "Este laboratorio está hecho con una versión más nueva de Full Cowl (formato $formato)."; $r.Hacer = 'Actualiza Full Cowl y vuelve a abrirlo.'; return $r
    }
    # Campos que esta versión no conoce: se ignoran con aviso
    $conocidos = @('formato', 'creadoCon', 'nombre', 'descripcion', 'red', 'dominio', 'desechable', 'ping', 'maquinas')
    $raros = @($o.PSObject.Properties.Name | Where-Object { $conocidos -notcontains $_ } | ForEach-Object { ([string]$_ -replace '[^\w-]', '') } | Select-Object -First 5)
    if ($raros.Count) { [void]$av.Add("El archivo trae campos que esta versión no conoce y se ignoran: $($raros -join ', ').") }

    $nombre = Texto-Fclab (Prop-Fclab $o 'nombre') 60
    if (-not $nombre) { $nombre = [IO.Path]::GetFileNameWithoutExtension($ruta); $nombre = Texto-Fclab $nombre 60; if (-not $nombre) { $nombre = 'Laboratorio importado' } ; [void]$av.Add('El archivo no traía nombre: se usa el del archivo.') }
    $desc = Prop-Fclab $o 'descripcion'
    if ($desc -and ([string]$desc).Length -gt 300) { [void]$av.Add('La descripción era muy larga y se ha recortado.') }
    $r.Descripcion = Texto-Fclab $desc 300
    $r.CreadoCon = Texto-Fclab (Prop-Fclab $o 'creadoCon') 40

    # Red
    $rd = Prop-Fclab $o 'red'
    $tipo = Texto-Fclab (Prop-Fclab $rd 'tipo') 12
    if ($tipo -notin @('nat', 'bridged', 'hostonly', 'aislada')) { if ($tipo) { [void]$av.Add("Red «$tipo» no reconocida: se usa NAT.") }; $tipo = 'nat' }
    $claveRed = $tipo
    if ($tipo -eq 'aislada') {
        $seg = @(Opciones-Red | Where-Object { $_.Tipo -eq 'pvn' }) | Select-Object -First 1
        if ($seg) { $claveRed = [string]$seg.Clave } else { $claveRed = 'nat'; [void]$av.Add('El laboratorio usa una red aislada y este PC no tiene segmentos LAN: se usa NAT. Puedes cambiarlo en «Crear laboratorio».') }
    }
    $ip = $null
    $modoIp = Texto-Fclab (Prop-Fclab $rd 'direcciones') 6
    if ($modoIp -eq 'fija') {
        # Sin dirección en el archivo = «fija, con las de la red de este PC» (así funcionan los ejemplos en cualquier red)
        $desdeIn = Texto-Fclab (Prop-Fclab $rd 'desde') 15
        $desde = Ip-Fclab $desdeIn
        if ($desdeIn -and -not $desde) { [void]$av.Add('Las direcciones fijas del archivo no son válidas: se usarán las de este PC.') }
        $dns = @(@(Prop-Fclab $rd 'dns') | ForEach-Object { Ip-Fclab (Texto-Fclab $_ 15) } | Where-Object { $_ } | Select-Object -First 4)
        $ip = [pscustomobject]@{ modo = 'fija'; desde = $desde; prefix = (Entero-Fclab (Prop-Fclab $rd 'prefijo') 8 30 24 'El prefijo de red' $av); gw = (Ip-Fclab (Texto-Fclab (Prop-Fclab $rd 'puerta') 15)); dns = $dns }
    } elseif ($modoIp -eq 'dhcp') {
        $ip = [pscustomobject]@{ modo = 'dhcp'; desde = ''; prefix = 24; gw = ''; dns = @() }
    }
    # Dominio
    $conDom = $false; $dominio = ''; $netbios = ''
    $dm = Prop-Fclab $o 'dominio'
    if ($null -ne $dm) {
        $dn = Texto-Fclab (Prop-Fclab $dm 'nombre') 63; $nb = Texto-Fclab (Prop-Fclab $dm 'netbios') 15
        if ($dn -cmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$') {
            $conDom = $true; $dominio = $dn
            $netbios = $(if ($nb -cmatch '^[A-Za-z0-9-]{1,15}$') { $nb.ToUpper() } else { (($dn.Split('.')[0]) -replace '[^a-zA-Z0-9-]', '').ToUpper() })
            if ($netbios.Length -gt 15) { $netbios = $netbios.Substring(0, 15) }
        } else { [void]$av.Add('El nombre de dominio del archivo no es válido: el laboratorio se carga sin dominio.') }
    }
    $desechable = [bool]((Prop-Fclab $o 'desechable') -eq $true); $ping = [bool]((Prop-Fclab $o 'ping') -ne $false)
    # Máquinas
    $catalogo = @(Obtener-Sistemas | ForEach-Object { [string]$_.Clave })
    $lista = New-Object System.Collections.ArrayList
    $listaIn = @(Prop-Fclab $o 'maquinas' | ForEach-Object { $_ })
    if (-not $listaIn.Count -or $null -eq (Prop-Fclab $o 'maquinas')) { $r.Error = 'El laboratorio no trae ninguna máquina.'; $r.Hacer = 'Pide que te envíen otro archivo.'; return $r }
    $hayDc = $false; $desconocidas = @{}
    foreach ($m in ($listaIn | Select-Object -First 40)) {
        if ($m -isnot [System.Management.Automation.PSCustomObject]) { continue }
        $base = Texto-Fclab (Prop-Fclab $m 'base') 30
        if ($base -cnotmatch '^[A-Za-z0-9]{1,30}$') { $base = 'desconocida' }
        if ($catalogo -notcontains $base) { $desconocidas[$base] = $true }
        $ram = Entero-Fclab (Prop-Fclab $m 'ram') 512 65536 2048 'La RAM' $av
        $cpus = Entero-Fclab (Prop-Fclab $m 'cpus') 1 16 2 'Los procesadores' $av
        $vram = Entero-Fclab (Prop-Fclab $m 'vram') 0 8192 0 'El vídeo 3D' $av
        $cant = Entero-Fclab (Prop-Fclab $m 'cantidad') 1 20 1 'La cantidad' $av
        $dc = [bool]((Prop-Fclab $m 'controlador') -eq $true)
        if ($dc -and ($hayDc -or -not $conDom)) { $dc = $false }
        if ($dc) { $hayDc = $true; $cant = 1 }
        $ex = Lista-Fclab (Prop-Fclab $m 'extras') 'Extras' $av
        $et = Lista-Fclab (Prop-Fclab $m 'etiquetas') 'Etiquetas' $av
        for ($k = 0; $k -lt $cant -and $lista.Count -lt 40; $k++) {
            [void]$lista.Add([pscustomobject]@{ base = $base; ram = $ram; cpus = $cpus; vram = $vram; dc = $dc; extras = @($ex); etiquetas = @($et) })
        }
    }
    if ($listaIn.Count -gt 40) { [void]$av.Add('El archivo traía más de 40 máquinas: se cargan las 40 primeras.') }
    if ($desconocidas.Count) { [void]$av.Add("Bases que Full Cowl no conoce: $((@($desconocidas.Keys | Select-Object -First 5) -join ', ')). Esas máquinas se podrán quitar, pero no crear.") }
    if (-not $lista.Count) { $r.Error = 'El laboratorio no trae ninguna máquina válida.'; $r.Hacer = 'Pide que te envíen otro archivo.'; return $r }
    $r.Plantilla = [pscustomobject]@{ nombre = $nombre; red = $claveRed; ip = $ip; conDominio = $conDom; dominio = $dominio; netbios = $netbios; desechable = $desechable; ping = $ping; maquinas = @($lista.ToArray()) }
    $r.Ok = $true
    return $r
}

# ---------------------------------------------------------------- pantalla de revisión
function Guardar-PlantillaLabEnPc($nueva) {
    $todas = @($script:plantillasLab | Where-Object { $_.nombre -ne $nueva.nombre }) + @($nueva)
    [IO.File]::WriteAllText($archivoPlantillasLab, (ConvertTo-Json @($todas) -Depth 6), [Text.UTF8Encoding]::new($false))
}

function Nombre-PlantillaLibre([string]$nombre) {
    $usados = @($script:plantillasLab | ForEach-Object { [string]$_.nombre })
    if ($usados -notcontains $nombre) { return $nombre }
    for ($k = 2; $k -lt 100; $k++) { $n = "$nombre $k"; if ($usados -notcontains $n) { return $n } }
    return "$nombre $(Get-Random -Maximum 999)"
}

function Revisar-Fclab($lec) {
    # Devuelve el nombre con el que se guardó la plantilla, o '' si se cancela
    Cargar-PlantillasLab ([string]$LabPlantilla.SelectedItem)
    Cargar-BasesLab
    $pl = $lec.Plantilla
    $e = Nuevo-Dialogo 'dialogo-revisar-lab.xaml' 'Importar un laboratorio' 'Revisa la receta antes de usarla' 860
    $e.RvNombre.Text = Nombre-PlantillaLibre ([string]$pl.nombre)
    $e.RvDescripcion.Text = $(if ($lec.Descripcion) { $lec.Descripcion } else { 'Sin descripción.' })
    $maq = New-Object System.Collections.ArrayList
    foreach ($m in @($pl.maquinas)) { [void]$maq.Add($m) }
    $est = @{ Nombre = ''; Mapa = $true }
    $catalogo = @(Obtener-Sistemas | ForEach-Object { [string]$_.Clave })
    $aviso = {
        param([string]$texto, [bool]$grave = $false)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = ([string][char]0x26A0) + '  ' + $texto; $t.TextWrapping = 'Wrap'; $t.FontSize = 12.5; $t.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
        Ref-Tema $t ([System.Windows.Controls.TextBlock]::ForegroundProperty) $(if ($grave) { 'T_peligro' } else { 'T_aviso' })
        [void]$e.RvAvisos.Children.Add($t)
    }
    $pintar = {
        # --- resumen y avisos
        $gb = [Math]::Round((($maq | ForEach-Object { [double]$_.ram } | Measure-Object -Sum).Sum) / 1024, 1)
        $redOp = @(Opciones-Red | Where-Object { $_.Clave -eq [string]$pl.red }) | Select-Object -First 1
        if (-not $redOp) { $redOp = @(Opciones-Red)[0] }
        $partes = @((Plural $maq.Count 'máquina' 'máquinas'), "$gb GB de RAM", "red $([string]$redOp.Texto)")
        if ($pl.conDominio) { $partes += "dominio $($pl.dominio)" }
        if ($pl.desechable) { $partes += 'desechable' }
        $e.RvResumen.Text = ($partes -join ' · ')
        $e.RvAvisos.Children.Clear()
        foreach ($a in $lec.Avisos) { & $aviso ([string]$a) }
        if ($ramPC -and ($gb * 1GB) -gt $ramPC) { & $aviso "Las máquinas suman $gb GB de RAM y este PC tiene $([Math]::Round($ramPC / 1GB)) GB: no podrán estar todas encendidas a la vez." }
        if (@($maq | Where-Object { @($_.extras).Count }).Count -and $redOp.Tipo -notin @('nat', 'bridged')) { & $aviso 'Algunos extras necesitan Internet y esta red no tiene.' }
        # --- requisitos por base
        $e.RvRequisitos.Children.Clear()
        $bases = @($maq | ForEach-Object { [string]$_.base } | Select-Object -Unique)
        foreach ($b in $bases) {
            $n = @($maq | Where-Object { [string]$_.base -eq $b }).Count
            $conocida = ($catalogo -contains $b)
            $tiene = [bool]($conocida -and (Base-PorNombreLab $b))
            $fila = New-Object System.Windows.Controls.Grid; $fila.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
            foreach ($w in @('Auto', '*', 'Auto', 'Auto')) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength(1, 'Star') } else { [System.Windows.GridLength]::Auto }); [void]$fila.ColumnDefinitions.Add($cd) }
            $ico = New-Object System.Windows.Controls.TextBlock
            $ico.Text = $(if ($tiene) { [string][char]0x2713 } else { [string][char]0x2717 }); $ico.FontSize = 15; $ico.FontWeight = [System.Windows.FontWeights]::Bold; $ico.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0); $ico.VerticalAlignment = 'Center'
            Ref-Tema $ico ([System.Windows.Controls.TextBlock]::ForegroundProperty) $(if ($tiene) { 'T_acentoClaro' } else { 'T_peligro' })
            [void]$fila.Children.Add($ico)
            $tx = New-Object System.Windows.Controls.TextBlock; $tx.VerticalAlignment = 'Center'; $tx.TextWrapping = 'Wrap'
            $nom = $(if ($conocida) { Nombre-AmigableBase $b } else { "«$b» (no reconocida)" })
            $tx.Text = $(if ($tiene) { "Tienes la base $nom" } elseif ($conocida) { "Te falta la base $nom" } else { "Base $nom" }) + $(if ($n -gt 1) { " · $n máquinas" } else { '' })
            Ref-Tema $tx ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
            [System.Windows.Controls.Grid]::SetColumn($tx, 1); [void]$fila.Children.Add($tx)
            if (-not $tiene) {
                if ($conocida) {
                    $bc = New-Object System.Windows.Controls.Button; $bc.Style = [System.Windows.Application]::Current.FindResource('BotonPrimario'); $bc.Content = 'Crear esa base'; $bc.Height = 30; $bc.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
                    $bc.DataContext = $b
                    $bc.Add_Click({
                        param($s, $ev)
                        $clave = [string]$s.DataContext
                        $e.Ventana.Close()
                        $NavBase.IsChecked = $true
                        try { Elegir-SistemaBase $clave } catch { Escribir-Log ("Crear esa base: " + $_.Exception.Message) }
                    })
                    [System.Windows.Controls.Grid]::SetColumn($bc, 2); [void]$fila.Children.Add($bc)
                }
                $bq = New-Object System.Windows.Controls.Button; $bq.Style = [System.Windows.Application]::Current.FindResource('BotonSecundario'); $bq.Content = $(if ($n -gt 1) { "Quitar estas $n máquinas" } else { 'Quitar esta máquina' }); $bq.Height = 30; $bq.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
                $bq.DataContext = $b
                $bq.Add_Click({
                    param($s, $ev)
                    $clave = [string]$s.DataContext
                    foreach ($x in @($maq | Where-Object { [string]$_.base -eq $clave })) { $maq.Remove($x) }
                    & $pintar
                })
                [System.Windows.Controls.Grid]::SetColumn($bq, 3); [void]$fila.Children.Add($bq)
            }
            [void]$e.RvRequisitos.Children.Add($fila)
        }
        $e.BtnRvOk.IsEnabled = ($maq.Count -gt 0)
        # --- mapa (con las mismas piezas que la vista previa de «Crear laboratorio»)
        try {
            if (-not $maq.Count) { $e.RvMapa.Children.Clear(); return }
            $pf = New-Object System.Collections.ArrayList; $contador = @{}
            foreach ($m in $maq) {
                $b = [string]$m.base
                $sis = @(Obtener-Sistemas | Where-Object { [string]$_.Clave -eq $b }) | Select-Object -First 1
                $ab = $(if ($abrevBase.ContainsKey($b)) { $abrevBase[$b] } else { ($b -replace '[^A-Za-z0-9]', '').ToUpper() })
                $contador[$ab] = [int]$contador[$ab] + 1
                $papel = $(if ($m.dc) { 'dc' } else { '' })
                $fi = $(if ($sis) { Fila-IconoSistema $sis } else { [pscustomobject]@{ IconoGlifo = Glifo 0xE756; IconoFondo = '#5F6F65'; IconoLogo = $null; IconoSimbolo = $null } })
                $datos = [pscustomobject]@{ Tarjetas = @([pscustomobject]@{ Tipo = [string]$redOp.Tipo; Vnet = [string]$redOp.Vnet; Pvn = [string]$redOp.Pvn }); IP = ''
                                            Dominio = $(if ($m.dc) { [string]$pl.dominio } else { '' }); EsWindows = [bool]($sis -and $sis.Tipo -eq 'windows') }
                [void]$pf.Add([pscustomobject]@{
                    Datos = $datos; Vmx = "rev:$($pf.Count)"; Nombre = "LAB-$ab-$($contador[$ab])"; Familia = $(if ($sis) { [string](Familia-Sistema $b) } else { '' })
                    Encendida = $false; Configurando = $false; Progreso = 0; EstadoTexto = ''
                    IconoFondo = $fi.IconoFondo; IconoSimbolo = $fi.IconoSimbolo; IconoLogo = $fi.IconoLogo; IconoGlifo = $fi.IconoGlifo; Papel = $papel; Base = $b })
            }
            $modelo = Construir-ModeloLab $pf
            Dibujar-MapaLab $e.RvMapa $modelo @() 1.0 { param($s, $a) }
            Ajustar-EscalaCanvas $e.RvMapaScroll $e.RvMapa 0.55
        } catch { Escribir-Log ("Revisar laboratorio, mapa: " + ($_ | Out-String)); $e.RvMapaScroll.Visibility = 'Collapsed' }
    }
    & $pintar
    $e.BtnRvNo.Add_Click({ $e.Ventana.Close() })
    $e.BtnRvOk.Add_Click({
        $nombre = Texto-Fclab $e.RvNombre.Text 60
        if (-not $nombre) { Aviso 'Ponle un nombre a la plantilla.'; return }
        if (@($script:plantillasLab | Where-Object { [string]$_.nombre -eq $nombre }).Count) {
            if (-not (Pregunta "Ya tienes una plantilla llamada «$nombre». ¿Quieres sustituirla?" 'Nombre repetido' 'Sustituir' 'Cancelar')) { return }
        }
        $nueva = [pscustomobject]@{ nombre = $nombre; red = [string]$pl.red; ip = $pl.ip; conDominio = [bool]$pl.conDominio; dominio = [string]$pl.dominio; netbios = [string]$pl.netbios
                                    desechable = [bool]$pl.desechable; ping = [bool]$pl.ping; maquinas = @($maq.ToArray()) }
        try { Guardar-PlantillaLabEnPc $nueva } catch { Error-Amable 'No se ha podido guardar la plantilla.' 'Mira que haya espacio y permisos en la carpeta de Full Cowl.' $_.Exception.Message; return }
        $est.Nombre = $nombre
        $e.Ventana.Close()
    })
    [void]$e.Ventana.ShowDialog()
    # El mapa del diálogo comparte la animación con el resto: se vuelve a dejar al día
    try { Refrescar-Lab; Pintar-MisLab -Forzar } catch {}
    return [string]$est.Nombre
}

function Importar-Fclab([string]$ruta = '') {
    try {
        if (-not $ruta) {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Title = 'Importar un laboratorio'; $dlg.Filter = 'Laboratorio de Full Cowl (*.fclab)|*.fclab|Todos los archivos|*.*'
            if ($dlg.ShowDialog($script:ventana) -ne $true) { return }
            $ruta = $dlg.FileName
        }
        $lec = Leer-Fclab $ruta
        if (-not $lec.Ok) {
            if ($lec.NuevoFormato) {
                $r = Mensaje "$($lec.Error)`n`n$($lec.Hacer)" 'Hace falta actualizar' 'aviso' @(@{ Texto = 'Cerrar'; Valor = 'no'; Estilo = 'BotonSecundario' }, @{ Texto = 'Ir a Actualizaciones'; Valor = 'act'; Estilo = 'BotonPrimario' })
                if ($r -eq 'act') { $BtnAjustes.IsChecked = $true; Ir-Seccion 'act' }
            } else { Error-Amable $lec.Error $lec.Hacer $lec.Detalle }
            return
        }
        $nombre = Revisar-Fclab $lec
        if (-not $nombre) { return }
        # Se carga en el creador (la creación sigue siendo un paso aparte)
        $NavLab.IsChecked = $true
        Poner-PestanaLab 'crear'
        Cargar-PlantillasLab $nombre
        $guardada = @($script:plantillasLab | Where-Object { [string]$_.nombre -eq $nombre }) | Select-Object -First 1
        if ($guardada) { Aplicar-PlantillaLab $guardada; Pintar-ChipsLab; Poner-MasPl }
        Mostrar-Toast "Plantilla «$nombre» lista en «Crear laboratorio»."
    } catch { Escribir-Log ("Importar .fclab: " + ($_ | Out-String)); Error-Amable 'No se ha podido importar el laboratorio.' 'Prueba otra vez; si sigue igual, mira el registro.' $_.Exception.Message }
}

# ---------------------------------------------------------------- menús y botones
function Mostrar-MenuLab($ancla, $opciones) {
    # Menú pequeño con los colores de la app (los menús normales de Windows desentonan)
    $pop = New-Object System.Windows.Controls.Primitives.Popup
    $pop.PlacementTarget = $ancla; $pop.Placement = 'Bottom'; $pop.StaysOpen = $false; $pop.AllowsTransparency = $true
    $borde = New-Object System.Windows.Controls.Border
    $borde.CornerRadius = New-Object System.Windows.CornerRadius(10); $borde.Padding = New-Object System.Windows.Thickness(6, 6, 6, 2); $borde.BorderThickness = New-Object System.Windows.Thickness(1)
    $borde.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    Ref-Tema $borde ([System.Windows.Controls.Border]::BackgroundProperty) 'T_superficie'
    Ref-Tema $borde ([System.Windows.Controls.Border]::BorderBrushProperty) 'T_borde'
    $pila = New-Object System.Windows.Controls.StackPanel
    foreach ($op in $opciones) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = [System.Windows.Application]::Current.FindResource($(if ($op.peligro) { 'BotonPeligro' } else { 'BotonSecundario' }))
        $b.Content = $op.t; $b.Height = 32; $b.MinWidth = 200; $b.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
        $b.DataContext = $op.a
        $b.Add_Click({
            param($s, $ev)
            try { $script:popMenuLab.IsOpen = $false } catch {}
            try { & $s.DataContext } catch { Escribir-Log ("Menú de plantillas: " + ($_ | Out-String)) }
        })
        [void]$pila.Children.Add($b)
    }
    $borde.Child = $pila
    $pop.Child = $borde
    $script:popMenuLab = $pop
    $pop.IsOpen = $true
}

function Plantilla-ActualLab {
    # Lo que se está preparando en «Crear laboratorio», con la forma de las plantillas guardadas
    if (-not $script:filasLab.Count) { return $null }
    $o = $script:opcRedLab[[Math]::Max(0, $LabRed.SelectedIndex)]
    return [pscustomobject]@{
        nombre = $(if ($LabNombre.Text.Trim()) { "Laboratorio $($LabNombre.Text.Trim())" } else { 'Laboratorio' }); red = $o.Clave; desechable = [bool]$LabDesechable.IsChecked; ping = [bool]$LabPing.IsChecked
        ip = [pscustomobject]@{ modo = $(if ($LabFija.IsChecked) { 'fija' } else { 'dhcp' }); desde = $LabIp.Text.Trim(); prefix = (Numero $LabPrefijo.Text 24); gw = $LabGw.Text.Trim(); dns = @($LabDns.Text -split '\s*,\s*' | Where-Object { $_ }) }
        conDominio = [bool]$LabConDominio.IsChecked; dominio = $LabDominio.Text.Trim(); netbios = $LabNetbios.Text.Trim()
        maquinas = @(Orden-Lab | ForEach-Object { [pscustomobject]@{ base = $_.Fila.base; ram = $_.Fila.ram; cpus = $_.Fila.cpus; vram = $_.Fila.vram; dc = ($_.Papel -eq 'dc'); extras = @($_.Fila.extras | Where-Object { $_ }) } })
    }
}

function Plantilla-ElegidaLab {
    # La plantilla que marca el «···»: una guardada, una de serie o $null (En blanco)
    if ($LabPlantilla.SelectedIndex -gt 0) { return @{ Tipo = 'guardada'; Pl = $script:plantillasLab[$LabPlantilla.SelectedIndex - 1] } }
    $serie = @($script:plantillasSerieLab | Where-Object { $_.clave -eq $script:chipLab }) | Select-Object -First 1
    if ($serie) { return @{ Tipo = 'serie'; Pl = $serie } }
    return $null
}
function Poner-MasPl { try { $BtnLabMasPl.Visibility = $(if (Plantilla-ElegidaLab) { 'Visible' } else { 'Collapsed' }) } catch {} }

$BtnLabPlantillas.Add_Click({
    Mostrar-MenuLab $BtnLabPlantillas @(
        @{ t = 'Exportar lo que preparo…'; a = {
            $pl = Plantilla-ActualLab
            if (-not $pl) { Aviso 'Añade antes alguna máquina.'; return }
            $nombre = Pedir-Texto 'Exportar plantilla' 'Nombre de la plantilla:' ([string]$pl.nombre)
            if (-not $nombre) { return }
            $pl.nombre = $nombre.Trim()
            Exportar-Plantilla $pl } }
        @{ t = 'Importar…'; a = { Importar-Fclab } })
})
$BtnLabMasPl.Add_Click({
    $el = Plantilla-ElegidaLab
    if (-not $el) { return }
    $ops = @(@{ t = 'Exportar…'; a = { $x = Plantilla-ElegidaLab; if ($x) { Exportar-Plantilla $x.Pl } } })
    if ($el.Tipo -eq 'guardada') {
        $ops += @{ t = 'Renombrar…'; a = {
            $x = Plantilla-ElegidaLab; if (-not $x -or $x.Tipo -ne 'guardada') { return }
            $viejo = [string]$x.Pl.nombre
            $nuevo = Pedir-Texto 'Renombrar plantilla' 'Nuevo nombre:' $viejo
            $nuevo = "$nuevo".Trim(); if (-not $nuevo -or $nuevo -eq $viejo) { return }
            if (@($script:plantillasLab | Where-Object { [string]$_.nombre -eq $nuevo }).Count) { Aviso "Ya hay una plantilla llamada «$nuevo»."; return }
            $todas = @($script:plantillasLab | ForEach-Object { if ([string]$_.nombre -eq $viejo) { $c = $_.PSObject.Copy(); $c.nombre = $nuevo; $c } else { $_ } })
            [IO.File]::WriteAllText($archivoPlantillasLab, (ConvertTo-Json @($todas) -Depth 6), [Text.UTF8Encoding]::new($false))
            Cargar-PlantillasLab $nuevo
            Mostrar-Toast "Plantilla renombrada a «$nuevo»." } }
        $ops += @{ t = 'Borrar'; peligro = $true; a = { $BtnLabBorrarPl.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } }
    }
    Mostrar-MenuLab $BtnLabMasPl $ops
})

# ---- Mis laboratorios: «Exportar como plantilla»
function Plantilla-DesdeLabElegido {
    $ds = @(Datos-LabElegido)
    if (-not $ds.Count) { return $null }
    $dc = @($ds | Where-Object { [string]$_.Dominio }) | Select-Object -First 1
    $primero = $(if ($dc) { $dc } else { $ds[0] })
    $t0 = @($primero.Tarjetas)[0]
    $tipo = $(if ($t0) { [string]$t0.Tipo } else { 'nat' })
    $red = $(if ($tipo -in @('nat', 'bridged', 'hostonly')) { $tipo } else { 'pvn' })
    $ip = $null
    if ($dc -and (Es-IPv4 ([string]$dc.IP)) -and ([string]$dc.IP -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)')) {
        $ip = [pscustomobject]@{ modo = 'fija'; desde = [string]$dc.IP; prefix = 24; gw = ''; dns = @() }
    }
    $maq = @()
    foreach ($d in @(@($ds | Where-Object { [string]$_.Dominio }) + @($ds | Where-Object { -not [string]$_.Dominio }))) {
        $ram = 2048; $cpu = 2; $vr = 0
        try { $v = Numero (Leer-ValorVmx $d.Vmx 'memsize') 0; if ($v -gt 0) { $ram = $v } } catch {}
        try { $v = Numero (Leer-ValorVmx $d.Vmx 'numvcpus') 0; if ($v -gt 0) { $cpu = $v } } catch {}
        try { $v = Numero (Leer-ValorVmx $d.Vmx 'svga.graphicsMemoryKB') 0; if ($v -gt 0) { $vr = [int]($v / 1024) } } catch {}
        $maq += [pscustomobject]@{ base = [string]$d.Base; ram = $ram; cpus = $cpu; vram = $vr; dc = [bool]([string]$d.Dominio); extras = @(([string]$d.Extras) -split ',' | Where-Object { $_ -cmatch '^[a-z0-9]{1,24}$' }) }
    }
    $dom = $(if ($dc) { [string]$dc.Dominio } else { '' })
    $nb = (($dom.Split('.')[0]) -replace '[^a-zA-Z0-9-]', '').ToUpper(); if ($nb.Length -gt 15) { $nb = $nb.Substring(0, 15) }
    return [pscustomobject]@{ nombre = "Laboratorio $($script:labElegido)"; red = $red; ip = $ip; conDominio = [bool]$dom; dominio = $dom; netbios = $nb
                              desechable = [bool](@($ds | Where-Object { $_.Desechable }).Count); ping = $true; maquinas = $maq }
}
$BtnLmPlantilla.Add_Click({
    $pl = Plantilla-DesdeLabElegido
    if (-not $pl) { return }
    $nombre = Pedir-Texto 'Exportar como plantilla' 'Nombre de la plantilla:' ([string]$pl.nombre)
    if (-not $nombre) { return }
    $pl.nombre = $nombre.Trim()
    Exportar-Plantilla $pl
})

# ---- Soltar un .fclab sobre la ventana
$script:ventana.AllowDrop = $true
$script:ventana.Add_DragOver({
    param($s, $a)
    try {
        $f = $a.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($f -and @($f).Count -and ([string]@($f)[0]).ToLower().EndsWith('.fclab')) { $a.Effects = [System.Windows.DragDropEffects]::Copy; $a.Handled = $true }
    } catch {}
})
$script:ventana.Add_Drop({
    param($s, $a)
    try {
        $f = $a.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($f -and @($f).Count -and ([string]@($f)[0]).ToLower().EndsWith('.fclab')) { $a.Handled = $true; Importar-Fclab ([string]@($f)[0]) }
    } catch { Escribir-Log ("Soltar .fclab: " + ($_ | Out-String)) }
})

# ---- Importar → «Ver laboratorios de ejemplo»
$ImpEjemplosLab.Add_Click({
    $carpeta = Join-Path (Split-Path $dirFc) 'laboratorios'
    if (Test-Path -LiteralPath $carpeta) { Start-Process explorer.exe "`"$carpeta`"" }
    else { Aviso 'No encuentro la carpeta «laboratorios» de la instalación. Actualiza Full Cowl para tener los ejemplos.' }
})
