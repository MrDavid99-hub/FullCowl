#  «Mis laboratorios» (ficha 13, parte 1): lista de laboratorios, mapa de red de cada uno, ficha de la máquina
#  elegida y acciones. Un laboratorio = las máquinas de «Mis máquinas» que llevan la misma marca de laboratorio.
#  Los datos salen de $script:filas (las filas de «Mis máquinas», que ya se mantienen al día): aquí no se lee
#  ningún .vmx por su cuenta. Las acciones reutilizan los botones de «Mis máquinas» (no se duplica su código).

$script:labElegido = ''        # nombre del laboratorio elegido
$script:labMaq = ''            # vmx de la máquina principal (la de la ficha)
$script:labSel = @()           # vmx de todas las elegidas (Ctrl+clic suma o quita)
$script:labFirma = ''          # para no repintar si nada cambió
$script:labPestana = ''        # 'mis' o 'crear'
$script:labComoLista = $false
$script:labModelo = $null
$script:cargandoPestana = $false
$script:selForzada = $null

# ---------------------------------------------------------------- datos
function Grupos-Lab {
    $g = [ordered]@{}
    foreach ($fl in @($script:filas | Sort-Object { [string]$_.Datos.Lab }, { $_.Nombre })) {
        if (-not $fl -or $fl.EsBase) { continue }
        $nl = [string]$fl.Datos.Lab
        if (-not $nl) { continue }
        if (-not $g.Contains($nl)) { $g[$nl] = New-Object System.Collections.ArrayList }
        [void]$g[$nl].Add($fl)
    }
    return $g
}

function Estado-DeLab($filasLab) {
    # @{ Texto; Fondo; Color } para la pastilla de estado
    $n = @($filasLab).Count
    $conf = @($filasLab | Where-Object { $_.Configurando }).Count
    $enc = @($filasLab | Where-Object { $_.Encendida }).Count
    if ($conf) { return @{ Texto = 'Configurándose'; Fondo = 'T_encendidaFondo'; Color = 'T_acento' } }
    if ($enc -eq $n) { return @{ Texto = 'Encendido'; Fondo = 'T_encendidaFondo'; Color = 'T_encendida' } }
    if ($enc) { return @{ Texto = 'En parte'; Fondo = 'T_avisoFondo'; Color = 'T_aviso' } }
    return @{ Texto = 'Apagado'; Fondo = 'T_neutro'; Color = 'T_textoSuave' }
}

function Nueva-PastillaLab([string]$texto, [string]$fondo, [string]$color, [double]$tam = 11) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius(9); $b.Padding = New-Object System.Windows.Thickness(8, 2, 8, 2)
    $b.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0); $b.VerticalAlignment = 'Center'
    $b.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $fondo)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $texto; $t.FontSize = $tam; $t.FontWeight = [System.Windows.FontWeights]::SemiBold
    $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $color)
    $b.Child = $t
    return $b
}

function Fila-LabElegida {
    $g = Grupos-Lab
    if (-not $g.Contains($script:labElegido)) { return $null }
    return @($g[$script:labElegido] | Where-Object { $_.Vmx -eq $script:labMaq }) | Select-Object -First 1
}

# ---------------------------------------------------------------- pintado
function Pintar-ListaLab($grupos) {
    $LabListaMis.Children.Clear()
    foreach ($nl in $grupos.Keys) {
        $fs = @($grupos[$nl])
        $elegido = ($nl -eq $script:labElegido)
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $script:estiloMapaMaq
        $btn.Tag = $nl
        $btn.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
        $btn.Padding = New-Object System.Windows.Thickness(14, 11, 14, 11)
        $btn.HorizontalContentAlignment = 'Stretch'
        $btn.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'T_superficie')
        $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, $(if ($elegido) { 'T_acento' } else { 'T_borde' }))
        $btn.BorderThickness = New-Object System.Windows.Thickness($(if ($elegido) { 2 } else { 1 }))
        $est = Estado-DeLab $fs
        $btn.SetValue([System.Windows.Automation.AutomationProperties]::NameProperty, "Laboratorio $nl, $($est.Texto), $(Plural $fs.Count 'máquina' 'máquinas')")
        $col = New-Object System.Windows.Controls.StackPanel
        $cab = New-Object System.Windows.Controls.Grid
        $ca = New-Object System.Windows.Controls.ColumnDefinition
        $cb = New-Object System.Windows.Controls.ColumnDefinition; $cb.Width = [System.Windows.GridLength]::Auto
        $cab.ColumnDefinitions.Add($ca); $cab.ColumnDefinitions.Add($cb)
        $nombre = Nuevo-Texto $nl 15 'T_texto' $true
        $pas = Nueva-PastillaLab $est.Texto $est.Fondo $est.Color
        $pas.Margin = New-Object System.Windows.Thickness(0); [System.Windows.Controls.Grid]::SetColumn($pas, 1)
        [void]$cab.Children.Add($nombre); [void]$cab.Children.Add($pas)
        [void]$col.Children.Add($cab)
        $fams = @($fs | ForEach-Object { [string]$_.Familia } | Where-Object { $_ } | Select-Object -Unique)
        $desc = Nuevo-Texto ($fams -join ' · ') 12.5 'T_texto'; $desc.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0); $desc.TextTrimming = 'CharacterEllipsis'
        [void]$col.Children.Add($desc)
        $conf = @($fs | Where-Object { $_.Configurando })
        if ($conf.Count) {
            $listas = $fs.Count - $conf.Count
            $lin = Nuevo-Texto "$listas de $($fs.Count) listas" 12 'T_textoSuave'
        } else {
            $enc = @($fs | Where-Object { $_.Encendida }).Count
            $lin = Nuevo-Texto "$(Plural $fs.Count 'máquina' 'máquinas') · $(Plural $enc 'encendida' 'encendidas')" 12 'T_textoSuave'
        }
        $lin.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        [void]$col.Children.Add($lin)
        if ($conf.Count) {
            $media = [double](($fs | ForEach-Object { $(if ($_.Configurando) { [double]$_.Progreso } else { 100.0 }) } | Measure-Object -Average).Average)
            $pista = New-Object System.Windows.Controls.Border
            $pista.Height = 3; $pista.CornerRadius = New-Object System.Windows.CornerRadius(2); $pista.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
            $pista.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'T_pista')
            $rel = New-Object System.Windows.Controls.Border
            $rel.Height = 3; $rel.HorizontalAlignment = 'Left'; $rel.CornerRadius = New-Object System.Windows.CornerRadius(2)
            $rel.Width = [Math]::Max(2, 210 * [Math]::Min(100, $media) / 100)
            $rel.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'T_acento')
            $pista.Child = $rel
            [void]$col.Children.Add($pista)
        }
        $btn.Content = $col
        $btn.Add_Click({ param($s, $a) Elegir-Lab ([string]$s.Tag) })
        [void]$LabListaMis.Children.Add($btn)
    }
}

function Pintar-FichaLab {
    $fl = Fila-LabElegida
    if (-not $fl) { $LabFicha.Visibility = 'Collapsed'; return }
    $LabFicha.Visibility = 'Visible'
    $LabFSimbolo.Child = Pastilla-Sistema $fl 44
    $LabFNombre.Text = [string]$fl.Nombre
    $maq = @($script:labModelo.Maquinas | Where-Object { $_.Vmx -eq $fl.Vmx }) | Select-Object -First 1
    $rol = ''
    if ($maq) { $rol = $(if ($maq.EsDc) { 'Controlador de dominio' } elseif ($maq.Etiqueta) { $maq.Etiqueta } elseif ($script:labModelo.Dominio) { 'Fuera del dominio' } else { '' }) }
    $LabFSub.Text = (@(@([string]$fl.Familia, $rol) | Where-Object { $_ }) -join ' · ')
    $cpus = ''; try { $nc = [int](Leer-ValorVmx $fl.Vmx 'numvcpus'); if ($nc -gt 0) { $cpus = Plural $nc 'CPU' 'CPUs' } } catch {}
    $LabFRed.Text = (@(@([string]$fl.Red, [string]$fl.IP, $(if ($fl.Ram) { "$($fl.Ram) de RAM" } else { '' }), $cpus) | Where-Object { $_ }) -join ' · ')
    $elegidas = @(Filas-LabElegidas)
    $varias = ($elegidas.Count -gt 1)
    if ($varias) {
        $LabFNombre.Text = "$($elegidas.Count) máquinas elegidas"
        $LabFSub.Text = (@($elegidas | ForEach-Object { [string]$_.Nombre }) -join ', ')
        $LabFRed.Text = 'Ctrl+clic suma o quita máquinas. Los botones actúan sobre todas las elegidas.'
    }
    $BtnLmAbrir.IsEnabled = -not $varias; $BtnLmConectar.IsEnabled = -not $varias
    $apagar = [bool]($elegidas.Count -and -not @($elegidas | Where-Object { -not $_.Encendida }).Count)
    $BtnLmEncender.Content = $(if ($apagar) { 'Apagar' } else { 'Encender' })
    $BtnLmEncender.Style = [System.Windows.Application]::Current.FindResource($(if ($apagar) { 'BotonSecundario' } else { 'BotonPrimario' }))
    $BtnLmEncender.Tag = [System.Windows.Application]::Current.FindResource($(if ($apagar) { 'Ico_Apagar' } else { 'Ico_Encender' }))
    try { Pintar-EstadoLab } catch { Escribir-Log ("Estado inicial del laboratorio: " + ($_ | Out-String)) }   # botones del estado inicial (ficha 28)
}

function Pintar-ListaMaquinasLab {
    # «Ver como lista»: nombre, sistema, rol, red, IP y estado (para muchas máquinas y lectores de pantalla)
    $LabMapaLista.Children.Clear()
    foreach ($m in $script:labModelo.Maquinas) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $script:estiloMapaMaq; $btn.Tag = $m.Vmx
        $btn.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6); $btn.Padding = New-Object System.Windows.Thickness(10, 7, 10, 7)
        $btn.HorizontalContentAlignment = 'Stretch'
        $btn.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'T_superficie')
        $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, $(if ($script:labSel -contains $m.Vmx) { 'T_acento' } else { 'T_borde' }))
        $btn.BorderThickness = New-Object System.Windows.Thickness(1)
        $estado = $(if ($m.Configurando) { $m.Texto } elseif ($m.Encendida) { 'Encendida' } else { 'Apagada' })
        $rol = $(if ($m.EsDc) { 'Controlador' } elseif ($m.Etiqueta) { $m.Etiqueta } else { '' })
        $red = (@($m.Redes | ForEach-Object { $script:labModelo.Todas[$_].Nombre }) -join ' + ')
        $btn.Content = Nuevo-Texto ((@(@($m.Nombre, [string]$m.Fila.Familia, $rol, $red, $m.Ip, $estado) | Where-Object { $_ })) -join '  ·  ') 12.5 'T_texto'
        $btn.Add_Click({ param($s, $a) Al-PulsarMaquinaLab $s })
        [void]$LabMapaLista.Children.Add($btn)
    }
}

function Pintar-MisLab([switch]$Forzar) {
    $grupos = Grupos-Lab
    $LabTabMisNum.Text = [string]$grupos.Count
    if (-not $script:cargado) { return }
    if (-not $script:estiloMapaMaq) { $script:estiloMapaMaq = $paginaLab.FindResource('MapaMaq') }
    if (-not $grupos.Count) {
        $LabMisCuerpo.Visibility = 'Collapsed'; $LabMisVacio.Visibility = 'Visible'
        Poner-Vacio $LabMisVacio 'Ico_Laboratorio' 'Aún no tienes ningún laboratorio' 'Un laboratorio junta varias máquinas en una red para practicar.' 'Crear laboratorio' { Poner-PestanaLab 'crear' } $true
        $script:labFirma = ''
        return
    }
    $LabMisCuerpo.Visibility = 'Visible'; $LabMisVacio.Visibility = 'Collapsed'
    if (-not $grupos.Contains($script:labElegido)) { $script:labElegido = @($grupos.Keys)[0]; $script:labMaq = '' }
    $fs = @($grupos[$script:labElegido])
    if (-not @($fs | Where-Object { $_.Vmx -eq $script:labMaq }).Count) {
        $dc = @($fs | Where-Object { [string]$_.Datos.Dominio }) | Select-Object -First 1
        $script:labMaq = $(if ($dc) { $dc.Vmx } else { $fs[0].Vmx })
    }
    # La selección múltiple solo puede tener máquinas de este laboratorio
    $script:labSel = @(@($script:labSel) | Where-Object { $v = $_; @($fs | Where-Object { $_.Vmx -eq $v }).Count })
    if (-not $script:labSel.Count) { $script:labSel = @($script:labMaq) }
    elseif ($script:labSel -notcontains $script:labMaq) { $script:labMaq = $script:labSel[0] }
    # Firma de lo que se ve: si no cambió nada, no se repinta (así los pulsos no se reinician cada 3 s)
    $firma = (@($grupos.Keys | ForEach-Object { $k = $_; @($grupos[$k] | ForEach-Object { "$k|$($_.Vmx)|$($_.Encendida)|$($_.Configurando)|$([int]$_.Progreso)|$($_.EstadoTexto)|$($_.IP)|$($_.Datos.Desechable)|$($_.Datos.Dominio)|$($_.Red)" }) }) -join ';') + "#$($script:labElegido)#$($script:labMaq)#$(@($script:labSel) -join ',')#$($script:labComoLista)#$($Config.Sobrio)#$($script:temaActual)"
    if (-not $Forzar -and $firma -eq $script:labFirma) { return }
    $script:labFirma = $firma
    Pintar-ListaLab $grupos
    $script:labModelo = Construir-ModeloLab $fs
    # cabecera del laboratorio elegido
    $LabMTitulo.Text = $script:labElegido
    $fams = @($fs | ForEach-Object { [string]$_.Familia } | Where-Object { $_ } | Select-Object -Unique)
    $LabMDesc.Text = "$(Plural $fs.Count 'máquina' 'máquinas') · $($fams -join ', ')"
    $LabMPildoras.Children.Clear()
    $esDes = [bool]@($fs | Where-Object { $_.EsDesechable }).Count
    [void]$LabMPildoras.Children.Add((Nueva-PastillaLab $(if ($esDes) { 'Desechable' } else { 'Conservado' }) 'T_encendidaFondo' 'T_encendida'))
    if ($script:labModelo.Dominio) { [void]$LabMPildoras.Children.Add((Nueva-PastillaLab "Dominio $($script:labModelo.Dominio)" 'T_encendidaFondo' 'T_encendida')) }
    $BtnLmEncTodas.IsEnabled = [bool]@($fs | Where-Object { -not $_.Encendida }).Count
    $BtnLmApaTodas.IsEnabled = [bool]@($fs | Where-Object { $_.Encendida }).Count
    $BtnLmConservar.IsEnabled = $esDes
    # mapa o lista
    $LabMapaScroll.Visibility = $(if ($script:labComoLista) { 'Collapsed' } else { 'Visible' })
    $LabMapaListaCaja.Visibility = $(if ($script:labComoLista) { 'Visible' } else { 'Collapsed' })
    $LabVerLista.Text = $(if ($script:labComoLista) { 'Ver como mapa' } else { 'Ver como lista' })
    if ($script:labComoLista) { Pintar-ListaMaquinasLab } else { Dibujar-MapaLab $LabMapa $script:labModelo $script:labSel 1.0; Ajustar-EscalaCanvas $LabMapaScroll $LabMapa 0.7 }
    Pintar-FichaLab
    Actualizar-AnimLab
}

function Actualizar-AnimLab {
    # Pulsos solo con el mapa a la vista y animaciones Normales; si no, todo quieto (y sin gastar procesador)
    if ($LabMis.Visibility -eq 'Visible') { $host1 = $LabMapa; $mod = $script:labModelo; $lista = $script:labComoLista }
    else { $host1 = $LabPrevMapa; $mod = $script:prevModelo; $lista = $false }
    $ver = ($paginaLab.IsVisible -and $mod -and -not $lista -and (Mapa-PuedeAnimar $host1))
    $hayEnc = [bool]($mod -and @($mod.Maquinas | Where-Object { $_.Encendida }).Count)
    if ($ver -and $hayEnc) { Arrancar-AnimMapa } else { Parar-AnimMapa }
}

# ---------------------------------------------------------------- elegir
function Elegir-Lab([string]$nombre) {
    if ($nombre -eq $script:labElegido) { return }
    $script:labElegido = $nombre; $script:labMaq = ''; $script:labSel = @()
    Pintar-MisLab -Forzar
}
function Elegir-MaqLab([string]$vmx, [bool]$suma = $false) {
    # Clic: solo esa. Ctrl+clic: la suma o la quita de las elegidas (siempre queda al menos una)
    if (-not $vmx) { return }
    $sel = @($script:labSel)
    if ($suma) {
        if ($sel -contains $vmx) { if ($sel.Count -gt 1) { $sel = @($sel | Where-Object { $_ -ne $vmx }) } }
        else { $sel = @($sel + $vmx) }
        $script:labMaq = $(if ($sel -contains $vmx) { $vmx } else { $sel[0] })
    } else {
        if ($sel.Count -eq 1 -and $sel[0] -eq $vmx) { return }
        $sel = @($vmx); $script:labMaq = $vmx
    }
    $script:labSel = $sel
    if ($script:labComoLista) { Pintar-MisLab -Forzar; return }
    $script:labFirma = ''
    Marcar-CartaElegida $script:labSel
    Pintar-FichaLab
}
function Al-PulsarMaquinaLab($s) {
    $ctrl = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)
    Elegir-MaqLab ([string]$s.Tag) $ctrl
}
function Menu-MaquinaLab($tarjeta, [bool]$soltar) {
    # Clic derecho en una máquina del mapa (ficha 19): al pulsar la elige (si no lo estaba) y al soltar abre el menú con
    # Encender/Apagar, Copiar IP, Conectar... (las mismas opciones que en «Mis máquinas»)
    $vmxTarj = [string]$tarjeta.Tag
    $filaTarj = @($script:filas | Where-Object { $_.Datos.Vmx -eq $vmxTarj })[0]
    if (-not $filaTarj) { return $false }   # tarjetas de vista previa u otras sin máquina real: nada
    if (-not $soltar) {
        if (@($script:labSel) -notcontains $vmxTarj) { Elegir-MaqLab $vmxTarj }
        return $true
    }
    $elegidas = @($script:filas | Where-Object { @($script:labSel) -contains $_.Datos.Vmx } | ForEach-Object { $_.Datos })
    if (-not ($elegidas | Where-Object { $_.Vmx -eq $vmxTarj })) { $elegidas = @($filaTarj.Datos) }
    Mostrar-MenuContextual $LabMapa (Opciones-MenuMaquina $elegidas) $true
    return $true
}
function Filas-LabElegidas {
    $g = Grupos-Lab
    if (-not $g.Contains($script:labElegido)) { return @() }
    return @($g[$script:labElegido] | Where-Object { $script:labSel -contains $_.Vmx })
}

# ---------------------------------------------------------------- pestañas
function Poner-PestanaLab([string]$cual) {
    $script:labPestana = $cual
    $mis = ($cual -eq 'mis')
    $script:cargandoPestana = $true
    try { $LabTabMis.IsChecked = $mis; $LabTabCrear.IsChecked = -not $mis } finally { $script:cargandoPestana = $false }
    $LabMis.Visibility = $(if ($mis) { 'Visible' } else { 'Collapsed' })
    $LabCrear.Visibility = $(if ($mis) { 'Collapsed' } else { 'Visible' })
    if ($mis) { Pintar-MisLab -Forzar } else { Refrescar-Lab }
    Actualizar-AnimLab
    Entrada-Pantalla $(if ($mis) { $LabMis } else { $LabCrear })
}
$LabTabMis.Add_Checked({ if (-not $script:cargandoPestana) { Poner-PestanaLab 'mis' } })
$LabTabCrear.Add_Checked({ if (-not $script:cargandoPestana) { Poner-PestanaLab 'crear' } })
$BtnLabNuevo.Add_Click({ Poner-PestanaLab 'crear' })
$LabVerLista.Add_MouseLeftButtonUp({ $script:labComoLista = -not $script:labComoLista; Pintar-MisLab -Forzar })

function Entrar-MisLab {
    $script:labFirma = ''   # al volver a la página se repintan los botones (por si algo terminó mientras tanto)
    # Al entrar: la pestaña en la que se estaba; la primera vez, «Mis laboratorios» si hay alguno y si no «Crear»
    $hay = [bool]((Grupos-Lab).Count)
    $cual = $script:labPestana
    if (-not $cual) { $cual = $(if ($hay -or -not $script:cargado) { 'mis' } else { 'crear' }) }
    Poner-PestanaLab $cual
}

# ---------------------------------------------------------------- acciones (reutilizan los botones de «Mis máquinas»)
function Con-Seleccion($lote, $boton) {
    # Pone las máquinas como «seleccionadas» para las funciones de «Mis máquinas» y pulsa su botón
    $script:selForzada = @($lote | Where-Object { $_ })
    if (-not $script:selForzada.Count) { $script:selForzada = $null; return }
    try { $boton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $boton))) }
    finally { $script:selForzada = $null }
    $script:labFirma = ''
}
function Datos-LabElegido { return @((Grupos-Lab)[$script:labElegido] | ForEach-Object { $_.Datos }) }

$BtnLmEncender.Add_Click({
    $el = @(Filas-LabElegidas); if (-not $el.Count) { return }
    $todasEnc = -not @($el | Where-Object { -not $_.Encendida }).Count
    Con-Seleccion @($el | ForEach-Object { $_.Datos }) $(if ($todasEnc) { $AccApagar } else { $AccEncender })
})
$BtnLmAbrir.Add_Click({ $el = @(Filas-LabElegidas); if ($el.Count) { Con-Seleccion @($el[0].Datos) $AccAbrir } })
$BtnLmRed.Add_Click({ $el = @(Filas-LabElegidas); if ($el.Count) { Con-Seleccion @($el | ForEach-Object { $_.Datos }) $AccRed } })
$BtnLmUsuarios.Add_Click({ $el = @(Filas-LabElegidas); if ($el.Count) { Con-Seleccion @($el | ForEach-Object { $_.Datos }) $AccUsuarios } })
$BtnLmConectar.Add_Click({ $el = @(Filas-LabElegidas); if ($el.Count) { Con-Seleccion @($el[0].Datos) $AccConectar } })
$BtnLmEncTodas.Add_Click({
    # El controlador de dominio primero (las demás esperan a que él arranque)
    $ds = @(Datos-LabElegido | Where-Object { -not $_.Encendida })
    $ordenadas = @(@($ds | Where-Object { [string]$_.Dominio }) + @($ds | Where-Object { -not [string]$_.Dominio }))
    Con-Seleccion $ordenadas $AccEncender
})
$BtnLmApaTodas.Add_Click({ Con-Seleccion @(Datos-LabElegido | Where-Object { $_.Encendida }) $AccApagar })
$BtnLmConservar.Add_Click({ Con-Seleccion @(Datos-LabElegido) $AccConservar })
$BtnLmExportar.Add_Click({
    $ds = @(Datos-LabElegido)
    if (-not $ds.Count) { return }
    if (-not (Pregunta "Se exporta cada máquina de $($script:labElegido) a su propio archivo .ova (te pregunta dónde guardar cada una).`nLas máquinas tienen que estar apagadas." 'Exportar el laboratorio' 'Seguir')) { return }
    foreach ($d in $ds) { Con-Seleccion @($d) $AccExportar }
})
$BtnLmBorrar.Add_Click({
    $ds = @(Datos-LabElegido)
    if (-not $ds.Count) { return }
    Con-Seleccion $ds $AccBorrar
})

# ---------------------------------------------------------------- refresco y animación
$relojLab = New-Object System.Windows.Threading.DispatcherTimer
$relojLab.Interval = [TimeSpan]::FromSeconds(3)
$relojLab.Add_Tick({
    try {
        if ($paginaLab.IsVisible -and $LabMis.Visibility -eq 'Visible') { Pintar-MisLab; Actualizar-AnimLab }
        elseif ($script:mapaAnimando) { Parar-AnimMapa }
    } catch { Escribir-Log ("Mis laboratorios: " + ($_ | Out-String)) }
})
$relojLab.Start()
# Sin foco o minimizada: quieto al momento
$script:ventana.Add_Deactivated({ try { Parar-AnimMapa } catch {} })
$script:ventana.Add_Activated({ try { if ($paginaLab.IsVisible) { Actualizar-AnimLab } } catch {} })
$script:ventana.Add_StateChanged({ try { Actualizar-AnimLab } catch {} })
$LabMapaScroll.Add_SizeChanged({ Ajustar-EscalaCanvas $LabMapaScroll $LabMapa 0.7 })
