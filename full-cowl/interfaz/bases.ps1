# =====================================================================
#  Interfaz nueva: página «Crear base»
#  Antes era una pestaña de la ventana de siempre (gui.ps1, quitada en la 2.0): lanza
#  crear-base.ps1 en una consola aparte y enseña su progreso, que lee de
#  estado\<sistema>.json cada 2 segundos.
# =====================================================================

$sistemas = @(Obtener-Sistemas)
$dirEstadoFc = Join-Path $dirFc 'estado'
$script:lanzandoBase = $false

$script:claveBaseElegida = ''
$script:okPintado = ''

function Sistema-Actual {
    foreach ($sx in $sistemas) { if ([string]$sx.Clave -eq $script:claveBaseElegida) { return $sx } }
    return $null
}

# ---- Selector de sistemas (tarjetas): UNA tarjeta por línea de sistema (Ubuntu, Windows Server…) y, dentro, chips de versión y
# edición. Por defecto solo salen las líneas con ISO en tu carpeta o con base creada; «Ver todos» enseña también las demás.
$script:verTodosBase = $false
$script:nombresIso = @()

function Tiene-IsoSistema($sx) {
    foreach ($n in $script:nombresIso) { if ($n -match $sx.Patron) { return $true } }
    return $false
}
function Base-Creada($sx) {
    try { return [bool](Test-Path (Join-Path $Config.CarpetaBases ([string]$sx.Clave))) } catch { return $false }
}
function Etiqueta-BaseCreada($vars) {
    # «Base creada · ES · Madrid» (ficha 36); en las manuales no se sabe con qué idioma se instaló de verdad
    $vc = @($vars | Where-Object { Base-Creada $_ }) | Select-Object -First 1
    if (-not $vc -or [string]$vc.Tipo -eq 'manual') { return 'Base creada' }
    try {
        $ib = Idioma-DeBaseExistente (Join-Path $Config.CarpetaBases ([string]$vc.Clave))
        return "Base creada · $(Texto-IdiomaZona $ib.Idioma $ib.Zona)"
    } catch { return 'Base creada' }
}
function Linea-Sistema($sx) { $l = [string]$sx.Linea; if ($l) { return $l } return [string]$sx.Nombre }
function Variantes-Linea([string]$linea) { return @($sistemas | Where-Object { (Linea-Sistema $_) -eq $linea }) }
function Variante-PorDefecto($vars) {
    # La que tiene ISO (y no es antigua); si no, la primera que no sea antigua
    foreach ($f in @({ param($x) (Tiene-IsoSistema $x) -and -not $x.Antiguo }, { param($x) Tiene-IsoSistema $x }, { param($x) -not $x.Antiguo })) {
        foreach ($x in $vars) { if (& $f $x) { return $x } }
    }
    return $vars[0]
}
function Diferir-Base([scriptblock]$accion) {
    # Repintar un control desde su propio clic es delicado: se hace un instante después
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(15); $t.Tag = $accion
    $t.Add_Tick({ param($s, $ev) $s.Stop(); try { & $s.Tag } catch { Escribir-Log ("Selector de bases: " + ($_ | Out-String)) } })
    $t.Start()
}

$script:buscarBase = ''
$script:filtroBase = ''
function Sin-Acentos([string]$t) {
    # Minúsculas y sin tildes, para buscar «escritorio» y encontrar «Escritório», etc.
    $n = $t.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    return (-join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' }))
}

function Pintar-SelectorBase([switch]$SoloFiltro) {
    # -SoloFiltro: viene del buscador (cada pulsación): no vuelve a mirar la carpeta de ISOs ni repinta chips de versión
    if (-not $SoloFiltro) { $script:nombresIso = @() }
    try { if (-not $SoloFiltro -and $Config.CarpetaISOs) { $script:nombresIso = @(Get-ChildItem -LiteralPath $Config.CarpetaISOs -Filter *.iso -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } } catch {}
    $actual = Sistema-Actual
    $lineaActual = $(if ($actual) { Linea-Sistema $actual } else { '' })
    $lineas = [ordered]@{}
    foreach ($sx in $sistemas) { $l = Linea-Sistema $sx; if (-not $lineas.Contains($l)) { $lineas[$l] = @() }; $lineas[$l] += $sx }
    $info = @()
    foreach ($l in $lineas.Keys) {
        $vars = @($lineas[$l])
        $conIso = [bool](@($vars | Where-Object { Tiene-IsoSistema $_ }).Count)
        $creadas = @($vars | Where-Object { Base-Creada $_ }).Count
        $info += [pscustomobject]@{ Linea = $l; Vars = $vars; ConIso = $conIso; Creadas = $creadas; Util = ($conIso -or $creadas -gt 0 -or $l -eq $lineaActual) }
    }
    # Sin ninguna ISO detectada se enseña todo (si no, la pantalla saldría vacía)
    $verTodo = ($script:verTodosBase -or -not @($info | Where-Object { $_.Util }).Count)
    $ops = @(); $ocultas = 0
    foreach ($x in $info) {
        if (-not $x.Util -and -not $verTodo) { $ocultas++; continue }
        $rep = Variante-PorDefecto $x.Vars
        if ($lineaActual -eq $x.Linea -and $actual) { $rep = $actual }
        $versiones = @($x.Vars | ForEach-Object { [string]$_.Version } | Where-Object { $_ } | Select-Object -Unique)
        if ($x.Vars.Count -gt 1) { $nombre = $x.Linea; $sub = $versiones -join '  ·  ' }
        else { $p = Partir-NombreSistema ([string]$rep.Nombre); $nombre = $p[0]; $sub = $p[1] }
        $sub2 = $(if (-not $x.ConIso) { 'No hay ISO en tu carpeta' } else { '' })
        $etq = $(if ($x.Creadas -gt 1) { "$($x.Creadas) bases" } elseif ($x.Creadas -eq 1) { Etiqueta-BaseCreada $x.Vars } elseif (@($x.Vars | Where-Object { [string]$_.Estado -ne 'Nuevo' }).Count -eq 0) { $(if ([string]$rep.Tipo -eq 'manual') { 'Nuevo · Manual' } else { 'Nuevo' }) } elseif ([string]$rep.Tipo -eq 'manual') { 'Manual' } else { '' })
        $ops += @{ Clave = [string]$rep.Clave; Nombre = $nombre; Sub = $sub; Sub2 = $sub2; Grupo = (Grupo-Sistema $rep); Etiqueta = $etq; EtiquetaAviso = $false
                   Apagada = (-not $x.ConIso); Fila = (Fila-IconoSistema $rep) }
    }
    # Buscador y filtros: solo salen con muchas tarjetas (más de 12) o si ya hay una búsqueda/filtro activo
    $totalOps = $ops.Count
    $hayFiltro = ($script:buscarBase -or $script:filtroBase)
    $BaseBusqueda.Visibility = $(if ($totalOps -gt 12 -or $hayFiltro) { 'Visible' } else { 'Collapsed' })
    if ($BaseBusqueda.Visibility -eq 'Visible') {
        if (-not ($SoloFiltro -and $BaseFiltros.Children.Count)) {
        $BaseFiltros.Children.Clear()
        foreach ($g in @(@('', 'Todos'), @('Windows', 'Windows'), @('Linux', 'Linux'), @('Redes y otros', 'Redes y otros'))) {
            $rbF = New-Object System.Windows.Controls.RadioButton
            $rbF.Style = [System.Windows.Application]::Current.FindResource('Chip'); $rbF.GroupName = 'BaseFiltroGrupo'
            $rbF.Content = $g[1]; $rbF.DataContext = [string]$g[0]; $rbF.IsChecked = ([string]$script:filtroBase -eq [string]$g[0])
            $rbF.Add_Click({ param($sF, $evF) $script:filtroBase = [string]$sF.DataContext; Pintar-SelectorBase -SoloFiltro })
            [void]$BaseFiltros.Children.Add($rbF)
        }
        }
        $ops = @($ops | Where-Object {
            $op = $_
            $lineaOp = @($sistemas | Where-Object { (Linea-Sistema $_) -eq (Linea-Sistema (@($sistemas | Where-Object { [string]$_.Clave -eq [string]$op.Clave })[0])) })
            $okG = (-not $script:filtroBase) -or ([string]$op.Grupo -eq $script:filtroBase)
            $texto = Sin-Acentos (@($op.Nombre, $op.Sub, @($lineaOp | ForEach-Object { "$($_.Nombre) $($_.Version) $($_.Edicion) $($_.Linea)" })) -join ' ')
            $okT = $true
            foreach ($palabra in @((Sin-Acentos ([string]$script:buscarBase)) -split '\s+' | Where-Object { $_ })) { if (-not $texto.Contains($palabra)) { $okT = $false } }
            $okG -and $okT
        })
    }
    $BaseSinCoincidencias.Visibility = $(if ($BaseBusqueda.Visibility -eq 'Visible' -and -not $ops.Count) { 'Visible' } else { 'Collapsed' })
    $claveMarcada = $(if ($actual) { [string](@($ops | Where-Object { $_.Clave -eq [string]$actual.Clave }) | Select-Object -First 1).Clave } else { '' })
    Pintar-Selector $BaseSelector $ops $claveMarcada { param($clave) Elegir-LineaBase $clave } 'SistemaBase'
    $BtnBaseVerTodos.Visibility = $(if ($ocultas -gt 0 -or ($script:verTodosBase -and @($info | Where-Object { $_.Util }).Count)) { 'Visible' } else { 'Collapsed' })
    $BtnBaseVerTodos.Content = $(if ($script:verTodosBase) { 'Ocultar los sistemas sin ISO' } else { "Ver todos los sistemas ($ocultas más, sin ISO)" })
    if (-not $SoloFiltro) { Pintar-Variantes }
}

function Pintar-Variantes {
    # Chips de versión y edición del sistema elegido, y «Dónde la consigo» si no hay ISO
    $BaseVersiones.Children.Clear(); $BaseEdiciones.Children.Clear()
    $actual = Sistema-Actual
    if (-not $actual) { $BaseVariantes.Visibility = 'Collapsed'; return }
    $vars = Variantes-Linea (Linea-Sistema $actual)
    $versiones = @($vars | ForEach-Object { [string]$_.Version } | Where-Object { $_ } | Select-Object -Unique)
    $ediciones = @($vars | Where-Object { [string]$_.Version -eq [string]$actual.Version } | ForEach-Object { [string]$_.Edicion } | Where-Object { $_ } | Select-Object -Unique)
    $alguna = [bool](@($vars | Where-Object { Tiene-IsoSistema $_ }).Count)
    $nuevoChip = {
        param($panel, [string]$texto, [string]$clave, [bool]$marcado)
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = [System.Windows.Application]::Current.FindResource('Chip'); $rb.GroupName = ('BaseChip' + $panel.Name)
        $rb.Content = $texto; $rb.DataContext = $clave; $rb.IsChecked = $marcado
        $rb.Add_Click({ param($s, $ev) Elegir-SistemaBase ([string]$s.DataContext) $false; Diferir-Base { Pintar-Variantes } })
        [void]$panel.Children.Add($rb)
    }
    if ($versiones.Count -gt 1) {
        foreach ($v in $versiones) {
            # La misma edición si existe en esa versión; si no, la primera
            $cand = @($vars | Where-Object { [string]$_.Version -eq $v })
            $dest = @($cand | Where-Object { [string]$_.Edicion -eq [string]$actual.Edicion }) | Select-Object -First 1
            if (-not $dest) { $dest = $cand[0] }
            $sinIso = ($alguna -and -not [bool](@($cand | Where-Object { Tiene-IsoSistema $_ }).Count))
            & $nuevoChip $BaseVersiones ($v + $(if ($sinIso) { '  (sin ISO)' } else { '' })) ([string]$dest.Clave) ([string]$actual.Version -eq $v)
        }
    }
    if ($ediciones.Count -gt 1) {
        foreach ($ed in $ediciones) {
            $dest = @($vars | Where-Object { [string]$_.Version -eq [string]$actual.Version -and [string]$_.Edicion -eq $ed }) | Select-Object -First 1
            & $nuevoChip $BaseEdiciones $ed ([string]$dest.Clave) ([string]$actual.Edicion -eq $ed)
        }
    }
    $BaseFilaVersion.Visibility = $(if ($versiones.Count -gt 1) { 'Visible' } else { 'Collapsed' })
    $BaseFilaEdicion.Visibility = $(if ($ediciones.Count -gt 1) { 'Visible' } else { 'Collapsed' })
    $sinIsoActual = -not (Tiene-IsoSistema $actual)
    $BaseFilaDonde.Visibility = $(if ($sinIsoActual -and [string]$actual.Web) { 'Visible' } else { 'Collapsed' })
    $BaseVariantes.Visibility = $(if ($versiones.Count -gt 1 -or $ediciones.Count -gt 1 -or $BaseFilaDonde.Visibility -eq 'Visible') { 'Visible' } else { 'Collapsed' })
}

function Elegir-LineaBase([string]$claveRep) {
    # Clic en una tarjeta: si ya estás en esa línea no cambia nada; si no, se elige su variante por defecto
    $rep = @($sistemas | Where-Object { [string]$_.Clave -eq $claveRep }) | Select-Object -First 1
    $actual = Sistema-Actual
    if (-not $rep -or ($actual -and (Linea-Sistema $actual) -eq (Linea-Sistema $rep))) { return }
    Elegir-SistemaBase $claveRep $false
    Diferir-Base { Pintar-Variantes }
}

function Elegir-SistemaBase([string]$clave, [bool]$repintar = $true) {
    $script:claveBaseElegida = $clave
    Cambio-Sistema
    if ($repintar) { Pintar-SelectorBase }   # (desde fuera, p. ej. «Crear esa base» de un laboratorio: que se vea la tarjeta elegida)
}

function Nota-Base([string]$texto, [string]$color = '') {
    # Una línea de «Antes de empezar»
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $texto
    $t.TextWrapping = 'Wrap'
    $t.FontSize = 13
    $t.LineHeight = 20
    $t.Margin = New-Object System.Windows.Thickness(0, 0, 0, 9)
    $t.Foreground = Pincel $(if ($color) { $color } else { $Colores.Texto })
    [void]$BaseNotas.Items.Add($t)
}

function Nota-LineaArranque([string]$tipo) {
    # Kali, Debian, Rocky/Alma y Arch: lo que hay que escribir a mano en el menú de arranque del instalador, con la IP real
    # de este PC, y lo que se pulsa en un teclado español (el menú usa teclado inglés). Kali y Debian: una línea entera tras
    # ESC; Rocky/Alma y Arch: un texto que se añade al final de la línea que sale con Tab.
    $info = $null
    try { $info = Info-Arranque $tipo } catch {}
    if (-not $info) {
        Nota-Base '•  No encuentro la red NAT de VMware (VMnet8): sin ella este sistema no se puede instalar. Abre VMware Workstation y comprueba que existe (Editar > Editor de red virtual).' $Colores.Aviso
        return
    }
    $linea = [string]$info.Texto
    $pasos = @(
        $(if ($info.Modo -eq 'completa') { ,@('1.  Haz clic dentro de la ventana de la máquina (menú del instalador) y pulsa ESC: abajo sale un prompt «boot:».', $false) }
          else { ,@('1.  Haz clic dentro de la ventana de la máquina (menú del instalador), deja marcada la primera opción y pulsa TAB: abajo sale la línea de arranque.', $false) }),
        $(if ($info.Modo -eq 'completa') { ,@('2.  Escribe esta línea entera:', $false) } else { ,@('2.  Ve al final de esa línea, escribe un espacio y a continuación este texto (sin borrar lo que ya había):', $false) }),
        @($linea, $true),
        @('Con un teclado ESPAÑOL (el menú usa teclado inglés), pulsa exactamente esto:', $false),
        @((Linea-KaliTeclado $linea), $true),
        @('    =  es la tecla ¡ (a la derecha del 0)     :  es Mayús+ñ (una Ñ mayúscula)     /  es la tecla - (a la derecha del punto)     el punto y los números, como siempre', $false),
        @('3.  Revisa que en pantalla ponga lo mismo que la primera caja y pulsa Intro. Si a los 2 minutos sigue preguntando idioma, la línea no se leyó bien: reinicia la máquina (VM > Power > Restart Guest) y repítela.', $false)
    )
    foreach ($p in $pasos) {
        if ($p[1]) {
            $caja = New-Object System.Windows.Controls.TextBox
            $caja.Text = $p[0]; $caja.IsReadOnly = $true; $caja.TextWrapping = 'Wrap'
            $caja.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas'); $caja.FontSize = 13
            $caja.Padding = New-Object System.Windows.Thickness(10, 7, 10, 7)
            $caja.Margin = New-Object System.Windows.Thickness(0, 0, 0, 9)
            $caja.Background = Pincel '#F2F6F3'; $caja.BorderBrush = Pincel '#DCE6DF'
            $caja.Foreground = Pincel $Colores.Texto
            [void]$BaseNotas.Items.Add($caja)
        } else {
            Nota-Base $p[0]
        }
    }
}

function Nota-RedProxmox {
    # Datos de red listos para copiar en «Management Network» del instalador de Proxmox (ficha 27)
    $d = $null
    try { $d = Datos-RedProxmox } catch {}
    if (-not $d) { Nota-Base '•  No he podido leer la red NAT de VMware (VMnet8): en el instalador pon una IP libre de esa red, su puerta de enlace (la .2) y el mismo DNS.' $Colores.Aviso; return }
    Nota-Base '•  Red de esta máquina (NAT de VMware). Datos para el instalador, listos para copiar:'
    $texto = "IP (CIDR):          $($d.Cidr)`r`nPuerta de enlace:   $($d.Puerta)`r`nDNS:                $($d.Dns)`r`nNombre (FQDN):      pve.lab.local"
    $fila = New-Object System.Windows.Controls.DockPanel
    $fila.Margin = New-Object System.Windows.Thickness(0, 0, 0, 9)
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = 'Copiar'; $btn.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0); $btn.VerticalAlignment = 'Top'
    try { $btn.Style = [System.Windows.Application]::Current.FindResource('BotonSecundario') } catch {}
    [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
    $btn.Tag = $texto
    $btn.Add_Click({ param($o, $e) try { [System.Windows.Clipboard]::SetText([string]$o.Tag); $o.Content = 'Copiado' } catch { $o.Content = 'No se pudo' } })
    [void]$fila.Children.Add($btn)
    $caja = New-Object System.Windows.Controls.TextBox
    $caja.Text = $texto; $caja.IsReadOnly = $true; $caja.TextWrapping = 'Wrap'
    $caja.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas'); $caja.FontSize = 13
    $caja.Padding = New-Object System.Windows.Thickness(10, 7, 10, 7)
    $caja.Background = Pincel '#F2F6F3'; $caja.BorderBrush = Pincel '#DCE6DF'
    $caja.Foreground = Pincel $Colores.Texto
    [void]$fila.Children.Add($caja)
    [void]$BaseNotas.Items.Add($fila)
    Nota-Base "•  La IP .120 está fuera del reparto automático de VMware (empieza en .128) y de las IP de los laboratorios (empiezan en .50). Si ya la usa otra máquina, cambia el último número." $Colores.Suave
}

# ---------------------------------------------------------------- idioma, teclado y zona (ficha 36)
function Idioma-DeBaseExistente([string]$carpeta) {
    # Idioma y zona de una base ya creada (las de antes de la ficha 36: español y la zona de config)
    $vmxB = Get-ChildItem -LiteralPath $carpeta -Filter *.vmx -ErrorAction SilentlyContinue | Select-Object -First 1
    $i = ''; $z = ''
    if ($vmxB) { $i = [string](Leer-ValorVmx $vmxB.FullName 'guestinfo.vmtareas.idioma'); $z = [string](Leer-ValorVmx $vmxB.FullName 'guestinfo.vmtareas.zona') }
    return [pscustomobject]@{ Idioma = [string](Resolver-Idioma $i).Clave; Zona = [string](Resolver-Zona $z).Clave }
}
function Pintar-BaseExiste($s) {
    $carpeta = Join-Path $Config.CarpetaBases $s.Clave
    if (Test-Path $carpeta) {
        $ant = Idioma-DeBaseExistente $carpeta
        $txt = "Ya existe ($((Get-Item $carpeta).LastWriteTime.ToString('dd/MM/yyyy')), $(Texto-IdiomaZona $ant.Idioma $ant.Zona)): se rehará"
        $nuevaIdi = Clave-Combo $BaseIdioma
        if ([string]$s.Tipo -ne 'manual' -and $nuevaIdi -and $nuevaIdi -ne $ant.Idioma) {
            $txt += " · está en $((Resolver-Idioma $ant.Idioma).Nombre), la nueva será en $((Resolver-Idioma $nuevaIdi).Nombre)"
        }
        $BaseExiste.Text = $txt
        $BaseExisteChip.Background = Pincel '#FBF3DD'; $BaseExiste.Foreground = Pincel $Colores.Aviso
        Poner-Icono $BaseExisteGlifo 'Aviso'; $BaseExisteGlifo.Foreground = Pincel $Colores.Aviso
    } else {
        $BaseExiste.Text = 'Todavía no creada en este PC'
        $BaseExisteChip.Background = Pincel '#EEF2EF'; $BaseExiste.Foreground = Pincel $Colores.Suave
        Poner-Icono $BaseExisteGlifo 'Info'; $BaseExisteGlifo.Foreground = Pincel $Colores.Suave
    }
}
function Idioma-DeIsoWindows([string]$iso) {
    # Pista por el nombre del archivo (las ISO de Microsoft lo llevan: es-es_windows_11..., ..._en-us.iso). '' si no se sabe.
    $hoja = [string](Split-Path $iso -Leaf)
    if ($hoja -match '(?i)(^|[^a-z])es[-_]es([^a-z]|$)|spanish|espa') { return 'es' }
    if ($hoja -match '(?i)(^|[^a-z])en[-_](us|gb)([^a-z]|$)|english') { return 'en' }
    return ''
}
function Actualizar-FilaIdioma($s) {
    if (-not $s) { return }
    if ([string]$s.Tipo -eq 'manual') {
        $BaseIdiomaFila.Visibility = 'Collapsed'
        $BaseIdiomaNota.Text = 'En este sistema el idioma y la zona los eliges tú al instalar; la guía de pasos te dice qué elegir.'
        $BaseIdiomaNota.Foreground = Pincel $Colores.Suave
        $BaseIdiomaNota.Visibility = 'Visible'
        return
    }
    $BaseIdiomaFila.Visibility = 'Visible'
    $BaseIdiomaNota.Visibility = 'Collapsed'
    if ([string]$s.Tipo -eq 'windows') {
        $pedida = Clave-Combo $BaseIdioma
        $deIso = Idioma-DeIsoWindows $BaseIso.Text.Trim()
        $nomIso = $(if ($deIso -eq 'en') { 'inglés' } else { 'español' })
        if ($deIso -and $pedida -and $deIso -ne $pedida) {
            $BaseIdiomaNota.Text = "Tu ISO solo trae ${nomIso}: Windows se verá en $nomIso, pero el teclado, los formatos (fechas, comas) y la hora serán los que has elegido."
            $BaseIdiomaNota.Foreground = Pincel $Colores.Aviso; $BaseIdiomaNota.Visibility = 'Visible'
        } elseif (-not $deIso -and $pedida -and $pedida -ne 'es') {
            $BaseIdiomaNota.Text = 'En Windows el idioma de los menús lo pone la ISO: si tu ISO solo trae español, Windows se verá en español (el teclado, los formatos y la hora sí serán los elegidos). Al crear la base se comprueba y se avisa.'
            $BaseIdiomaNota.Foreground = Pincel $Colores.Suave; $BaseIdiomaNota.Visibility = 'Visible'
        }
    }
}

function Cambio-Sistema {
    $s = Sistema-Actual
    if (-not $s) { return }
    Pintar-BaseExiste $s
    Actualizar-FilaIdioma $s

    $guardada = Pref @('crearBase', 'sistemas', $s.Clave) $null
    $isos = @(Buscar-IsosSistema $s)
    $BaseIso.Text = $(if ($guardada -and $guardada.iso -and (Test-Path $guardada.iso)) { $guardada.iso } elseif ($isos.Count) { $isos[0].FullName } else { '' })
    $BaseIsoNota.Text = $(if ($isos.Count) { "$(Plural $isos.Count 'ISO de tu carpeta encaja' 'ISO de tu carpeta encajan') con este sistema." } else { "No hay ninguna ISO para este sistema en $($Config.CarpetaISOs): elígela con «Examinar»." })
    $BaseIsoNota.Foreground = Pincel $(if ($isos.Count) { $Colores.Suave } else { $Colores.Aviso })

    # Lo que hayas guardado para este sistema; si no, lo recomendado para él (y la nota dice cuál es)
    $reco = Recomendado-Sistema $s
    $BaseRam.Text = Gb-Texto ([double]$(if ($guardada -and $guardada.ram) { $guardada.ram } else { $reco.Ram }))
    $BaseCpu.Text = [string]$(if ($guardada -and $guardada.cpus) { $guardada.cpus } else { $reco.Cpus })
    $BaseDisco.Text = [string]$(if ($guardada -and $guardada.disco) { $guardada.disco } else { $reco.Disco })
    $BaseRecoNota.Text = "Recomendado para este sistema: $(Gb-Texto ([double]$reco.Ram)) GB de RAM · $($reco.Cpus) $(if ([int]$reco.Cpus -eq 1) { 'procesador' } else { 'procesadores' }) · $($reco.Disco) GB de disco."

    $BaseNotas.Items.Clear()
    if ($s.Tipo -eq 'windows') {
        Nota-Base '•  Se instala sola y en segundo plano (no se abre la ventana de la máquina). Tarda unos 15-30 minutos.'
        Nota-Base '•  El progreso sale abajo y en la consola que se abre. Windows pedirá permisos de administrador.'
    } elseif ($s.Tipo -eq 'manual') {
        Nota-Base '•  Instalación MANUAL: Full Cowl crea la máquina vacía con la ISO conectada y la abre en VMware; el sistema lo instalas tú. Cuando acabes, pulsa «Ya he terminado» (en Progreso) o apaga el sistema desde dentro: así se guarda como base.'
        Nota-Base '•  Las máquinas hechas con una base manual se clonan tal cual: Full Cowl no cambia su nombre, IP ni usuarios por dentro (no hay IP fija, dominio ni extras).' $Colores.Aviso
        $nPasoM = 0
        foreach ($pasoM in (Receta-Manual $s (Clave-Combo $BaseIdioma) (Clave-Combo $BaseTeclado) (Clave-Combo $BaseZona))) { $nPasoM++; Nota-Base ("$nPasoM.  $pasoM") }
        if ($s.Clave -eq 'Proxmox') { Nota-RedProxmox }
        if ([int]$s.Nics -ge 2) { Nota-Base '•  Lleva 2 tarjetas de red (WAN en NAT y LAN solo-anfitrión). El Laboratorio aún aplica la misma red a todas las máquinas, así que una DMZ de verdad necesita redes distintas por máquina (más adelante).' $Colores.Aviso }
    } elseif ($s.Tipo -in 'kali', 'debian', 'rhel', 'arch') {
        $queEs = $(if ($s.Tipo -eq 'kali') { ' con escritorio Xfce' } elseif ($s.Desktop) { ' con escritorio' } else { '' })
        Nota-Base "•  La máquina arranca en segundo plano y a los pocos segundos se abre su ventana. En el menú de arranque del instalador hay que escribir UNA línea (te la damos abajo); después se instala sola$queEs. Tarda unos 30-45 minutos."
        Nota-Base '•  Si Windows pregunta si permites a «packer» en la red, acepta: la máquina descarga de ahí su configuración.'
        if ($s.Tipo -eq 'rhel') { Nota-Base '•  Hace falta la ISO «DVD» (la grande, de unos 8-10 GB), no la «boot» ni la «minimal».' }
        if ($s.Tipo -eq 'debian') { Nota-Base '•  Hace falta la ISO «netinst» (la pequeña, de unos 600 MB); los paquetes se bajan de Internet durante la instalación.' }
        if ($s.Tipo -eq 'arch') { Nota-Base '•  Arch se instala descargando todo de Internet (pacstrap); la ISO solo arranca el instalador. Tarda según tu conexión.' }
        if ($s.Estado -eq 'Nuevo') { Nota-Base '•  Sistema nuevo en Full Cowl: aún está poco probado. Si algo falla, el registro de la creación está en la carpeta «estado».' $Colores.Aviso }
        Nota-LineaArranque ([string]$s.Tipo)
    } else {
        if ($s.IsoDesktop) {
            Nota-Base '•  Al poco de empezar se abre la ventana de la máquina. A los ~30 segundos el instalador pregunta «Continue with autoinstall? (yes|no)»: haz clic en ella, escribe  yes  y pulsa Intro.'
        } else {
            Nota-Base '•  La instalación empieza sola: al poco de arrancar se abre la ventana de la máquina, pero no hay que escribir nada.'
            Nota-Base '•  Si a los 2-3 minutos la máquina enseña «FULL COWL: no he podido arrancar…» o no avanza: pulsa Cancelar, desmarca la casilla de abajo y vuelve a crearla. Entonces se hace como antes: cuando pregunte «Continue with autoinstall? (yes|no)», haz clic en la máquina, escribe  yes  y pulsa Intro.'
        }
        Nota-Base '•  Tarda unos 20-30 minutos. Windows pedirá permisos de administrador al empezar.'
    }
    Nota-Base '•  La primera vez se pide la contraseña del usuario de las máquinas (se guarda cifrada en este PC).'
    Nota-Base '•  No arranques nunca la base: para usarla, crea máquinas en «Nueva máquina».'
    $ultima = Ultimo-Tiempo 'base' $s.Clave
    if ($ultima) { Nota-Base "•  En este PC, la última vez tardó $ultima." $Colores.VerdeOscuro }
    if ($s.Tipo -eq 'manual') { Nota-Base '•  Sin IP automática: las máquinas de esta base no reciben IP fija, nombre de equipo ni dominio de Full Cowl. La IP la miras y la pones tú dentro (FreeBSD y cortafuegos: ifconfig o su menú; Linux: ip a) y para conectarte usas la ventana de VMware.' $Colores.Aviso }
    if ($existe) { Nota-Base '•  Al rehacerla, las máquinas ENLAZADAS creadas a partir de ella dejarán de funcionar.' $Colores.Aviso }
    if ($existe) { Nota-Base '•  Antes de rehacerla, CIERRA su pestaña en VMware (la de «Base …»): si queda abierta, enseña la base vieja como «Powered off» y no puedes escribir la línea de arranque en la nueva.' $Colores.Aviso }
    # Ficha 26: la casilla solo tiene sentido en Ubuntu con la ISO Server
    $BaseSinYes.Visibility = $(if ($s.Tipo -eq 'ubuntu' -and -not $s.IsoDesktop) { 'Visible' } else { 'Collapsed' })
    Actualizar-ResumenBase
}

# ---------------------------------------------------------------- cifras libres (− y +) y resumen
$BtnBaseRamMenos.Add_Click({ Paso-Cifra $BaseRam -1 1 128 })
$BtnBaseRamMas.Add_Click({ Paso-Cifra $BaseRam 1 1 128 })
$BtnBaseCpuMenos.Add_Click({ Paso-Cifra $BaseCpu -1 1 64 })
$BtnBaseCpuMas.Add_Click({ Paso-Cifra $BaseCpu 1 1 64 })
$BtnBaseDiscoMenos.Add_Click({ Paso-Cifra $BaseDisco -10 20 2000 })
$BtnBaseDiscoMas.Add_Click({ Paso-Cifra $BaseDisco 10 20 2000 })
$BtnBaseReco.Add_Click({
    $sx = Sistema-Actual
    if (-not $sx) { return }
    $r = Recomendado-Sistema $sx
    $BaseRam.Text = Gb-Texto ([double]$r.Ram); $BaseCpu.Text = [string]$r.Cpus; $BaseDisco.Text = [string]$r.Disco
})

$script:resClave = ''
$script:resAbajo = $false
$script:cacheComprob = @{ Hora = [datetime]::MinValue; Packer = $false; Vmware = $false; Pass = $false }

function Fila-Resumen([string]$etiqueta, [string]$valor) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(96)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, 'Star')
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $a = New-Object System.Windows.Controls.TextBlock; $a.Text = $etiqueta; $a.FontSize = 12.5
    Ref-Tema $a ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_textoSuave'
    $b = New-Object System.Windows.Controls.TextBlock; $b.Text = $valor; $b.FontSize = 13; $b.FontWeight = [System.Windows.FontWeights]::Medium; $b.TextTrimming = 'CharacterEllipsis'
    Ref-Tema $b ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
    [System.Windows.Controls.Grid]::SetColumn($b, 1)
    [void]$g.Children.Add($a); [void]$g.Children.Add($b)
    return $g
}

function Fila-Comprobacion([bool]$bien, [string]$texto, [string]$ayuda = '') {
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(22)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, 'Star')
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $m = New-Object System.Windows.Controls.TextBlock
    $m.Text = $(if ($bien) { [string][char]0x2713 } else { [string][char]0x2717 }); $m.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Symbol'); $m.FontSize = 13; $m.FontWeight = [System.Windows.FontWeights]::Bold
    Ref-Tema $m ([System.Windows.Controls.TextBlock]::ForegroundProperty) $(if ($bien) { 'T_acentoClaro' } else { 'T_peligro' })
    $col = New-Object System.Windows.Controls.StackPanel
    $a = New-Object System.Windows.Controls.TextBlock; $a.Text = $texto; $a.FontSize = 12.5; $a.TextWrapping = 'Wrap'
    Ref-Tema $a ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_texto'
    [void]$col.Children.Add($a)
    if ($ayuda -and -not $bien) {
        $h = New-Object System.Windows.Controls.TextBlock; $h.Text = $ayuda; $h.FontSize = 11.5; $h.TextWrapping = 'Wrap'
        Ref-Tema $h ([System.Windows.Controls.TextBlock]::ForegroundProperty) 'T_aviso'
        [void]$col.Children.Add($h)
    }
    [System.Windows.Controls.Grid]::SetColumn($col, 1)
    [void]$g.Children.Add($m); [void]$g.Children.Add($col)
    return $g
}

function Actualizar-ResumenBase {
    $s = Sistema-Actual
    if (-not $s) { return }
    if ($script:resClave -ne [string]$s.Clave) {
        $script:resClave = [string]$s.Clave
        $ResPastilla.Content = Pastilla-Sistema (Fila-IconoSistema $s) 44
        $pn = Partir-NombreSistema ([string]$s.Nombre)
        $ResNombre.Text = $pn[0]; $ResSub.Text = $pn[1]
    }
    $iso = $BaseIso.Text.Trim()
    $isoBien = ($iso -and (Test-Path -LiteralPath $iso -ErrorAction SilentlyContinue))
    $mb = Texto-AMb $BaseRam.Text; $cpus = Numero $BaseCpu.Text; $disco = Numero $BaseDisco.Text
    $carpeta = Join-Path $Config.CarpetaBases $s.Clave
    $existe = Test-Path $carpeta
    $ResLineas.Children.Clear()
    [void]$ResLineas.Children.Add((Fila-Resumen 'ISO' $(if ($iso) { Split-Path $iso -Leaf } else { '—' })))
    [void]$ResLineas.Children.Add((Fila-Resumen 'RAM' $(if ($mb -ge 1024) { "$(Gb-Texto $mb) GB" } else { '—' })))
    [void]$ResLineas.Children.Add((Fila-Resumen 'Procesadores' $(if ($cpus -ge 1) { [string]$cpus } else { '—' })))
    [void]$ResLineas.Children.Add((Fila-Resumen 'Disco' $(if ($disco -ge 1) { "$disco GB" } else { '—' })))
    $idiRes = $(if ([string]$s.Tipo -eq 'manual') { 'Lo eliges tú al instalar' } else {
        "$((Resolver-Idioma (Clave-Combo $BaseIdioma)).Nombre) · Teclado: $((Resolver-Teclado (Clave-Combo $BaseTeclado)).Nombre) · Zona: $((Resolver-Zona (Clave-Combo $BaseZona)).Corto)" })
    [void]$ResLineas.Children.Add((Fila-Resumen 'Idioma' $idiRes))
    [void]$ResLineas.Children.Add((Fila-Resumen 'Base' $(if ($existe) { 'Ya existe: se rehará' } else { 'Nueva' })))
    # Estimación en lenguaje llano
    $est = switch ([string]$s.Tipo) { 'windows' { 'Unos 15-30 minutos.' } 'kali' { 'Unos 30-45 minutos.' } 'debian' { 'Unos 30-45 minutos.' } 'rhel' { 'Unos 30-45 minutos.' } 'arch' { 'Unos 20-40 minutos.' } 'manual' { 'Lo que tardes en instalarlo tú.' } default { 'Unos 20-30 minutos.' } }
    $ultima = Ultimo-Tiempo 'base' $s.Clave
    if ($ultima) { $est += "`nLa última vez en este PC: $ultima." }
    $ResEstimacion.Text = $est
    # Qué falta
    $falta = ''
    if (-not $iso) { $falta = 'Falta elegir la ISO.' }
    elseif (-not $isoBien) { $falta = 'La ISO elegida no existe.' }
    elseif ($mb -lt 1024 -or $mb -gt 131072) { $falta = 'La RAM tiene que estar entre 1 y 128 GB.' }
    elseif ($cpus -lt 1 -or $cpus -gt 64) { $falta = 'Los procesadores tienen que ser entre 1 y 64.' }
    elseif ($disco -lt 20 -or $disco -gt 2000) { $falta = 'El disco tiene que estar entre 20 y 2000 GB.' }
    $ResAviso.Text = $falta
    $ResAviso.Visibility = $(if ($falta) { 'Visible' } else { 'Collapsed' })
    # Comprobaciones (lo lento se recuerda unos segundos)
    if (([datetime]::Now - $script:cacheComprob.Hora).TotalSeconds -gt 15) {
        $script:cacheComprob.Packer = [bool](Obtener-Packer)
        $vm = $null; try { $vm = Buscar-Vmrun -Silencioso } catch {}
        $script:cacheComprob.Vmware = [bool]$vm
        $script:cacheComprob.Pass = (Test-Path (Join-Path $dirFc 'password.sec'))
        $script:cacheComprob.Hora = [datetime]::Now
    }
    $ResChecks.Children.Clear()
    [void]$ResChecks.Children.Add((Fila-Comprobacion $script:cacheComprob.Packer 'Packer instalado' 'Se instala solo al crear la base (descarga oficial comprobada).'))
    [void]$ResChecks.Children.Add((Fila-Comprobacion $script:cacheComprob.Vmware 'VMware instalado' 'Instala VMware Workstation.'))
    [void]$ResChecks.Children.Add((Fila-Comprobacion ([bool]$isoBien) 'ISO elegida y existe' 'Elígela con «Examinar».'))
    $libre = -1.0
    try { $libre = ([IO.DriveInfo]([IO.Path]::GetPathRoot([string]$Config.CarpetaBases))).AvailableFreeSpace / 1GB } catch {}
    if ($libre -ge 0) {
        $hace = $(if ($disco -ge 20) { $disco + 10 } else { 70 })
        [void]$ResChecks.Children.Add((Fila-Comprobacion ($libre -ge $hace) "Espacio libre: $([int]$libre) GB (hacen falta unos $hace)" 'Libera espacio o cambia la carpeta de máquinas en Ajustes → Este PC.'))
    }
    [void]$ResChecks.Children.Add((Fila-Comprobacion $script:cacheComprob.Pass 'Contraseña de las máquinas guardada' 'Se te pedirá al empezar (se guarda cifrada).'))
}
$BaseIso.Add_TextChanged({ Actualizar-ResumenBase; Actualizar-FilaIdioma (Sistema-Actual) })
# Idioma, teclado y zona: se recuerdan para todos los sistemas (preferencias.json, crearBase.idioma/teclado/zona)
$script:llenandoIdioma = $true
Llenar-ComboClave $BaseIdioma (Obtener-Idiomas) ([string](Pref @('crearBase', 'idioma') 'es'))
Llenar-ComboClave $BaseTeclado (Obtener-Teclados) ([string](Pref @('crearBase', 'teclado') ([string](Resolver-Idioma (Clave-Combo $BaseIdioma)).Teclado)))
Llenar-ComboClave $BaseZona (Obtener-Zonas) ([string](Pref @('crearBase', 'zona') (Zona-DelPc)))
$script:llenandoIdioma = $false
$BaseIdioma.Add_SelectionChanged({
    if ($script:llenandoIdioma) { return }
    # El teclado sigue al idioma (Español → Español, Inglés → Inglés EE. UU.), pero luego se puede cambiar
    $tecIdi = [string](Resolver-Idioma (Clave-Combo $BaseIdioma)).Teclado
    foreach ($it in $BaseTeclado.Items) { if ([string]$it.Tag -eq $tecIdi) { $BaseTeclado.SelectedItem = $it } }
    $sI = Sistema-Actual
    if ($sI) { Pintar-BaseExiste $sI; Actualizar-FilaIdioma $sI }
    Actualizar-ResumenBase
})
$BaseTeclado.Add_SelectionChanged({ if (-not $script:llenandoIdioma) { Actualizar-ResumenBase } })
$BaseZona.Add_SelectionChanged({ if (-not $script:llenandoIdioma) { Actualizar-ResumenBase } })
$BaseRam.Add_TextChanged({ Actualizar-ResumenBase })
$BaseCpu.Add_TextChanged({ Actualizar-ResumenBase })
$BaseDisco.Add_TextChanged({ Actualizar-ResumenBase })

function Colocar-ResumenBase {
    try {
        # Ancho: el resumen va a la derecha y se queda fijo. Estrecho (menos de ~1000 px): pasa debajo de los pasos.
        $ancho = $PaginaBase.ActualWidth
        if ($ancho -lt 50) { return }
        $abajo = ($ancho -lt 1000)
        if ($abajo -eq $script:resAbajo) { return }
        $script:resAbajo = $abajo
        $ResHost.Content = $null
        [void]$PasosPila.Children.Remove($ResTarjeta)
        if ($abajo) {
            $ResTarjeta.Margin = New-Object System.Windows.Thickness(0, 0, 0, 18)
            $PasosPila.Children.Insert([Math]::Max(0, $PasosPila.Children.Count - 1), $ResTarjeta)
            $ResHost.Visibility = 'Collapsed'
            $ColRes.Width = New-Object System.Windows.GridLength(0); $ColResGap.Width = New-Object System.Windows.GridLength(0)
        } else {
            $ResTarjeta.Margin = New-Object System.Windows.Thickness(0, 2, 0, 28)
            $ResHost.Content = $ResTarjeta
            $ResHost.Visibility = 'Visible'
            $ColRes.Width = New-Object System.Windows.GridLength(300); $ColResGap.Width = New-Object System.Windows.GridLength(18)
        }
    } catch { Escribir-Log ("Resumen de Crear base: " + ($_ | Out-String)) }
}
$PaginaBase.Add_SizeChanged({ Colocar-ResumenBase })

$BtnBaseExaminar.Add_Click({
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Title = 'Elige la ISO'
    $d.Filter = 'Imágenes ISO (*.iso)|*.iso|Todos los archivos (*.*)|*.*'
    $d.InitialDirectory = $(if ($BaseIso.Text -and (Test-Path (Split-Path $BaseIso.Text -Parent))) { Split-Path $BaseIso.Text -Parent } else { $Config.CarpetaISOs })
    if ($d.ShowDialog($script:ventana)) { $BaseIso.Text = $d.FileName }
})

function Crear-BaseNueva {
    $s = Sistema-Actual
    if (-not $s) { Aviso 'Elige un sistema.'; return }
    $iso = $BaseIso.Text.Trim()
    if (-not $iso -or -not (Test-Path -LiteralPath $iso)) { Aviso 'Elige una ISO que exista (botón «Examinar»).'; return }
    $ram = Texto-AMb $BaseRam.Text; $cpus = Numero $BaseCpu.Text; $disco = Numero $BaseDisco.Text
    if ($ram -lt 1024 -or $ram -gt 131072) { Aviso 'La RAM tiene que ser un número de GB entre 1 y 128 (por ejemplo 4).'; return }
    if ($cpus -lt 1 -or $cpus -gt 64) { Aviso 'Los procesadores tienen que ser un número entre 1 y 64.'; return }
    if ($disco -lt 20 -or $disco -gt 2000) { Aviso 'El disco tiene que ser un número de GB entre 20 y 2000.'; return }
    if ($s.Tipo -eq 'ubuntu' -and (Split-Path $iso -Leaf) -notmatch 'server') {
        if (-not (Pregunta "Para Ubuntu hace falta la ISO *Server* (la de escritorio no se instala sola).`n¿Usar esta igualmente?" 'ISO de Ubuntu' 'Usar esta')) { return }
    }
    $carpeta = Join-Path $Config.CarpetaBases $s.Clave
    if (Test-Path $carpeta) {
        if (-not (Pregunta "La base «$($s.Clave)» ya existe y se va a rehacer.`n`nLas máquinas ENLAZADAS creadas a partir de ella dejarán de funcionar." 'Rehacer base' 'Rehacer' 'Cancelar' 'BotonRojo')) { return }
    }
    $pedido = [ordered]@{ sistema = $s.Clave; iso = $iso; ram = $ram; cpus = $cpus; disco = $disco }
    # Ficha 36: solo claves de las tablas cerradas (crear-base.ps1 las vuelve a comprobar)
    $pedido.idioma = [string](Resolver-Idioma (Clave-Combo $BaseIdioma)).Clave
    $pedido.teclado = [string](Resolver-Teclado (Clave-Combo $BaseTeclado)).Clave
    $pedido.zona = [string](Resolver-Zona (Clave-Combo $BaseZona)).Clave
    if ($s.Tipo -eq 'ubuntu') { $pedido.sinYes = [bool]$BaseSinYes.IsChecked }
    if (-not (Asegurar-PasswordVms)) { return }   # la contraseña se pide en una ventana, nunca en la consola
    Remove-Item (Join-Path $dirEstadoFc "$($s.Clave).json") -Force -ErrorAction SilentlyContinue
    Lanzar 'crear-base.ps1' $pedido
    $script:lanzandoBase = $true
    Poner-ProgresoBase 0 $Colores.Verde
    $BasePct.Text = '0 %'; $BaseTiempo.Text = ''
    $BaseProgTexto.Foreground = Pincel $Colores.Texto
    $BaseProgTexto.Text = "$($s.Nombre)  ·  empezando (acepta el permiso de administrador)"
    $BaseProgDet.Text = 'El detalle completo sale en la consola que se ha abierto.'

    # Recordar lo elegido (mismo archivo que la ventana de siempre)
    $sis = [ordered]@{}
    $ant = Pref @('crearBase', 'sistemas') $null
    if ($ant) { foreach ($pp in $ant.PSObject.Properties) { $sis[$pp.Name] = $pp.Value } }
    $sis[$s.Clave] = [ordered]@{ iso = $iso; ram = $ram; cpus = $cpus; disco = $disco }
    Guardar-Prefs ([ordered]@{
        pestana   = 1
        nueva     = Pref @('nueva') $null
        crearBase = [ordered]@{ sistema = $s.Clave; sistemas = $sis; idioma = $pedido.idioma; teclado = $pedido.teclado; zona = $pedido.zona }
    })
    Mostrar-Toast "Creando la base «$($s.Clave)»: el progreso sale aquí y en la consola que se ha abierto."
}
$BtnCrearBase.Add_Click({ Crear-BaseNueva })
$BtnCrearBase2.Add_Click({ Crear-BaseNueva })

# ---------------------------------------------------------------- progreso
function Leer-EstadoReciente {
    if (-not (Test-Path $dirEstadoFc)) { return $null }
    # Solo los archivos de progreso de las bases (estado\<sistema>.json); en la misma carpeta
    # están los del vigilante (desechables.json, conservar.json, progreso.json), que no lo son
    foreach ($fi in @(Get-ChildItem $dirEstadoFc -Filter *.json -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'importar.json' } | Sort-Object LastWriteTime -Descending)) {
        if ($fi.LastWriteTime -lt (Get-Date).AddHours(-12)) { return $null }
        try { $est = [IO.File]::ReadAllText($fi.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
        if ($est -is [psobject] -and $est.estado -and $est.inicio) { return $est }
    }
    return $null
}

function Poner-ProgresoBase([double]$pct, [string]$color) {
    # La barra avanza deslizándose hasta el valor nuevo
    $BaseBarra.Foreground = Pincel $color
    $an = New-Object System.Windows.Media.Animation.DoubleAnimation
    $an.To = $pct
    $an.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(200))
    $suave = New-Object System.Windows.Media.Animation.CubicEase
    $suave.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $an.EasingFunction = $suave
    $BaseBarra.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $an)
    Brillo-Barra $BaseBarra $pct $color
}

$BtnBaseListo.Add_Click({
    # Instalación manual: crear-base.ps1 vigila este archivo; al verlo apaga la máquina y guarda la base
    $est = Leer-EstadoReciente
    if (-not $est -or [string]$est.estado -ne 'curso') { return }
    $txt = "¿Has terminado de instalar «$($est.nombre)»?`n`nSe apagará la máquina (con cuidado, y a la fuerza si no responde en 90 segundos) y se guardará como base. Si el sistema aún no está instalado del todo, no lo pulses."
    if (-not (Pregunta $txt 'Ya he terminado' 'Sí, apagar y guardar' 'Todavía no')) { return }
    try { [IO.File]::WriteAllText((Join-Path $dirEstadoFc "$($est.sistema).listo"), (Get-Date).ToString('o')) } catch { Error-Msg "No se pudo avisar: $_"; return }
    $BtnBaseListo.IsEnabled = $false
    $BaseProgDet.Text = 'Apagando la máquina y guardándola como base…'
})

$BtnBaseCancelar.Add_Click({
    $est = Leer-EstadoReciente
    if (-not $est -or [string]$est.estado -ne 'curso') { return }
    $txt = "¿Cancelar la creación de «$($est.nombre)»?`n`nSe apagará la máquina a medio crear y se borrará su carpeta. Si estabas rehaciendo una base, la anterior ya no existe: tendrás que crearla de nuevo."
    if (-not (Pregunta $txt 'Cancelar creación' 'Cancelar la creación' 'Seguir creando' 'BotonRojo')) { return }
    try {
        [IO.File]::WriteAllText((Join-Path $dirEstadoFc "$($est.sistema).abortar"), (Get-Date).ToString('o'))
    } catch { Error-Msg "No se pudo pedir la cancelación: $_"; return }
    $BtnBaseCancelar.IsEnabled = $false
    $BaseProgDet.Text = 'Cancelando: apagando la máquina y borrando su carpeta…'
})

function Actualizar-ProgresoBase {
    $est = Leer-EstadoReciente
    if (-not $est) {
        $BtnBaseCancelar.Visibility = 'Collapsed'; $BtnBaseListo.Visibility = 'Collapsed'
        $NavBase.Content = 'Crear base'
        if (-not $script:lanzandoBase) {
            $BaseProgTexto.Foreground = Pincel $Colores.Texto
            $BaseProgTexto.Text = 'Sin creaciones de bases recientes.'
            $BaseTiempo.Text = ''; $BasePct.Text = ''; $BaseProgDet.Text = ''
            Poner-ProgresoBase 0 $Colores.Verde
        }
        Parar-RayosBarra $BaseBarraRayos
        return
    }
    $script:lanzandoBase = $false
    $estadoB = [string]$est.estado
    $pct = [double]$est.pct
    $ahora = Get-Date
    if ($estadoB -eq 'curso') {
        # Fases sin mensajes (instalación de Windows...): avance estimado por tiempo
        if ([double]$est.hasta -gt $pct -and [double]$est.esperadoSeg -gt 0 -and $est.inicioFase) {
            $trans = ($ahora - [datetime]$est.inicioFase).TotalSeconds
            $pct = $pct + ([double]$est.hasta - $pct) * [Math]::Min(0.95, $trans / [double]$est.esperadoSeg)
        }
        # Consola cerrada a mano: el proceso ya no existe
        if ($est.pid -and -not (Get-Process -Id ([int]$est.pid) -ErrorAction SilentlyContinue)) { $estadoB = 'interrumpida' }
    }
    $pct = [Math]::Min(100, [Math]::Max(0, $pct))
    $BasePct.Text = "$([int]$pct) %"
    $fin = if ($estadoB -ne 'curso' -and $est.actualizado) { [datetime]$est.actualizado } else { $ahora }
    $BaseTiempo.Text = "Tiempo: $(Formato-Tiempo ($fin - [datetime]$est.inicio).TotalSeconds)"
    $cancelando = ($estadoB -eq 'curso') -and (Test-Path (Join-Path $dirEstadoFc "$($est.sistema).abortar"))
    $BtnBaseCancelar.Visibility = $(if ($estadoB -eq 'curso') { 'Visible' } else { 'Collapsed' })
    $BtnBaseCancelar.IsEnabled = -not $cancelando
    # «Ya he terminado» solo en las bases de instalación manual y mientras se crean
    $esManual = $false
    foreach ($sxm in $sistemas) { if ([string]$sxm.Clave -eq [string]$est.sistema -and [string]$sxm.Tipo -eq 'manual') { $esManual = $true } }
    $BtnBaseListo.Visibility = $(if ($estadoB -eq 'curso' -and $esManual) { 'Visible' } else { 'Collapsed' })
    $BtnBaseListo.IsEnabled = $(if ($estadoB -eq 'curso' -and $esManual) { -not $cancelando -and -not (Test-Path (Join-Path $dirEstadoFc "$($est.sistema).listo")) } else { $false })
    # En el menú se ve cómo va mientras se crea
    $NavBase.Content = $(if ($estadoB -eq 'curso') { "Crear base  ·  $([int]$pct) %" } else { 'Crear base' })
    switch ($estadoB) {
        'curso' {
            $script:baseVistaEnCurso = [string]$est.inicio   # (para la ráfaga de rayos de la barra al terminar)
            Parar-RayosBarra $BaseBarraRayos
            Marcar-Tarea "base|$($est.sistema)|$($est.inicio)"
            Poner-ProgresoBase $pct $Colores.Verde
            $BaseProgTexto.Foreground = Pincel $Colores.Texto
            $BaseProgTexto.Text = "$($est.nombre)  ·  $($est.paso)"
            $BaseProgDet.Text = $(if ($cancelando) { 'Cancelando: apagando la máquina y borrando su carpeta…' } else { 'El detalle completo sale en la consola. No toques la máquina hasta que termine.' })
        }
        'cancelada' {
            Parar-RayosBarra $BaseBarraRayos
            Poner-ProgresoBase $pct $Colores.Suave
            $BaseProgTexto.Foreground = Pincel $Colores.Aviso
            $BaseProgTexto.Text = "$($est.nombre)  ·  cancelada en: $($est.paso)"
            $BaseProgDet.Text = $(if ($est.mensaje) { [string]$est.mensaje } else { 'Máquina a medio crear apagada y borrada. Puedes volver a crearla cuando quieras.' })
        }
        'ok' {
            Apuntar-Tiempo "base|$($est.sistema)|$($est.inicio)" 'base' ([string]$est.nombre) ([string]$est.sistema) ($fin - [datetime]$est.inicio).TotalSeconds 'ok'
            Tarea-Terminada "base|$($est.sistema)|$($est.inicio)" "Base «$([string]$est.nombre)» creada" $NavBase ($fin - [datetime]$est.inicio).TotalSeconds
            Poner-ProgresoBase 100 $Colores.Ok
            # La barra rebosa energía (rayitos alrededor, sin parar mientras se vea); si se vio crearse, además una ráfaga al acabar
            $rafagaB = ($script:baseVistaEnCurso -eq [string]$est.inicio)
            if ((Rayos-Barra $BaseBarraRayos $BaseBarra $rafagaB) -and $rafagaB) { $script:baseVistaEnCurso = $null }
            if ($script:okPintado -ne [string]$est.inicio) { $script:okPintado = [string]$est.inicio; Pintar-SelectorBase }   # ahora sale «Base creada»
            $BaseProgTexto.Foreground = Pincel $Colores.Ok
            $BaseProgTexto.Text = "$($est.nombre)  ·  base creada"
            $BaseProgDet.Text = "Terminó el $($fin.ToString('dd/MM')) a las $($fin.ToString('HH:mm')), en $(Formato-Tiempo ($fin - [datetime]$est.inicio).TotalSeconds). Ya puedes crear máquinas a partir de ella."
            if ($est.PSObject.Properties['aviso'] -and $est.aviso) { $BaseProgDet.Text += "  Aviso: $([string]$est.aviso)" }
        }
        'error' {
            Parar-RayosBarra $BaseBarraRayos
            Apuntar-Tiempo "base|$($est.sistema)|$($est.inicio)" 'base' ([string]$est.nombre) ([string]$est.sistema) ($fin - [datetime]$est.inicio).TotalSeconds 'error' ([string]$est.paso)
            Poner-ProgresoBase $pct $Colores.Error
            $BaseProgTexto.Foreground = Pincel $Colores.Error
            $BaseProgTexto.Text = "$($est.nombre)  ·  ha fallado en: $($est.paso)"
            $BaseProgDet.Text = ([string]$est.mensaje -replace '\s+', ' ')
        }
        default {
            Parar-RayosBarra $BaseBarraRayos
            Poner-ProgresoBase $pct $Colores.Error
            $BaseProgTexto.Foreground = Pincel $Colores.Error
            $BaseProgTexto.Text = "$($est.nombre)  ·  interrumpida en: $($est.paso)"
            $BaseProgDet.Text = 'La consola se cerró antes de terminar.'
        }
    }
}

$relojBase = New-Object System.Windows.Threading.DispatcherTimer
$relojBase.Interval = [TimeSpan]::FromSeconds(2)
$relojBase.Add_Tick({ try { Actualizar-ProgresoBase } catch {} })   # un fallo aquí no debe sacar avisos cada 2 s

# Sistema elegido la última vez
$elegido = Pref @('crearBase', 'sistema') ''
$posSis = [Array]::IndexOf([string[]]@($sistemas | ForEach-Object { $_.Clave }), [string]$elegido)
if ($posSis -ge 0) { $script:claveBaseElegida = [string]$sistemas[$posSis].Clave }
else {
    # Primera vez: la primera línea con ISO en la carpeta (si no hay ninguna, la primera del catálogo)
    $script:nombresIso = @(); try { if ($Config.CarpetaISOs) { $script:nombresIso = @(Get-ChildItem -LiteralPath $Config.CarpetaISOs -Filter *.iso -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } } catch {}
    $primeroIso = @($sistemas | Where-Object { (Tiene-IsoSistema $_) -and -not $_.Antiguo }) | Select-Object -First 1
    $script:claveBaseElegida = [string]$(if ($primeroIso) { $primeroIso.Clave } else { $sistemas[0].Clave })
}
Cambio-Sistema
Pintar-SelectorBase
# Se espera un momento tras la última pulsación (si no, cada letra repintaba todas las tarjetas y la caja iba a trompicones)
$relojBuscarBase = New-Object System.Windows.Threading.DispatcherTimer
$relojBuscarBase.Interval = [TimeSpan]::FromMilliseconds(250)
$relojBuscarBase.Add_Tick({ $relojBuscarBase.Stop(); try { Pintar-SelectorBase -SoloFiltro } catch { Escribir-Log ("Buscador de bases: " + ($_ | Out-String)) } })
$BaseBuscar.Add_TextChanged({ $script:buscarBase = $BaseBuscar.Text.Trim(); $relojBuscarBase.Stop(); $relojBuscarBase.Start() })
$BtnBaseVerTodos.Add_Click({ $script:verTodosBase = -not $script:verTodosBase; Pintar-SelectorBase })
$BtnBaseActualizar.Add_Click({
    # Vuelve a mirar la carpeta de ISOs: salen las tarjetas y chips de lo recién descargado, sin reiniciar
    try {
        Pintar-SelectorBase
        $isoAct = ''; try { $isoAct = $BaseIso.Text.Trim() } catch {}
        if (-not $isoAct -or -not (Test-Path -LiteralPath $isoAct)) { Cambio-Sistema } else { Actualizar-ResumenBase }
    } catch { Escribir-Log ("Buscar ISOs de nuevo: " + ($_ | Out-String)) }
})
$BtnBaseDonde.Add_Click({
    $sx = Sistema-Actual
    if ($sx -and [string]$sx.Web -like 'https://*') { try { Start-Process ([string]$sx.Web) } catch { Aviso "No se pudo abrir el navegador. La página es:`n$($sx.Web)" } }
})
