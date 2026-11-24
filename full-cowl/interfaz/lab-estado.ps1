#  Estado inicial del laboratorio (ficha 28): «Volver al estado inicial» y, en el menú ···, «Guardar el estado de
#  ahora como inicial» y «Quitar el estado inicial». Salen en la cabecera de cada laboratorio de «Mis laboratorios».
#  El trabajo lo hace lab-estado.ps1 sin ventana (y sigue aunque se cierre Full Cowl); aquí solo se elige, se confirma
#  y se enseña cómo va (en la propia cabecera y en «En marcha» de Inicio).

$script:opLabVistas = @{}      # «acción|laboratorio» de lo que se ha visto en marcha: al terminar se avisa

function Filas-EstadoLab {
    # Máquinas del laboratorio elegido con su estado inicial: @{ Fila; Tiene; Fecha }. Se lee del .vmsd (instantáneo)
    $res = @()
    $grupoEl = (Grupos-Lab)[$script:labElegido]
    foreach ($fl in @($grupoEl)) {
        $snap = @(Leer-Instantaneas $fl.Vmx | Where-Object { $_.Nombre -ceq (Nombre-EstadoInicial) }) | Select-Object -First 1
        $res += [pscustomobject]@{ Fila = $fl; Tiene = [bool]$snap; Fecha = $(if ($snap) { $snap.Fecha } else { $null }) }
    }
    return $res
}

function Pintar-EstadoLab {
    # Botones de la cabecera según el laboratorio elegido: ocultos en un desechable, «Volver» apagado si ninguna máquina
    # tiene estado inicial, y todo apagado mientras hay una operación en marcha
    if (-not $script:labElegido) { return }
    $filasE = @(Filas-EstadoLab)
    $desechable = [bool]@($filasE | Where-Object { $_.Fila.EsDesechable }).Count
    $vis = $(if ($desechable -or -not $filasE.Count) { 'Collapsed' } else { 'Visible' })
    $BtnLmVolver.Visibility = $vis; $BtnLmMas.Visibility = $vis
    if ($vis -eq 'Collapsed') { return }
    $opE = Leer-OperacionLab $script:labElegido
    $enCurso = [bool]($opE -and [string]$opE.estado -eq 'curso')
    $conEstado = @($filasE | Where-Object { $_.Tiene }).Count
    $BtnLmVolver.IsEnabled = ($conEstado -gt 0) -and -not $enCurso
    $BtnLmMas.IsEnabled = -not $enCurso
    if ($enCurso) { $BtnLmVolver.ToolTip = 'Hay una operación del estado inicial en marcha.' }
    elseif (-not $conEstado) { $BtnLmVolver.ToolTip = 'Este laboratorio no tiene estado inicial guardado. Se guarda al crearlo, o desde ··· «Guardar el estado de ahora como inicial».' }
    elseif ($conEstado -lt $filasE.Count) { $BtnLmVolver.ToolTip = "Solo $conEstado de $($filasE.Count) máquinas tienen estado inicial: el cuadro te dirá cuáles faltan." }
    else {
        $fechas = @($filasE | Where-Object { $_.Fecha } | ForEach-Object { $_.Fecha } | Sort-Object)
        $BtnLmVolver.ToolTip = $(if ($fechas.Count) { 'Todas las máquinas vuelven a como estaban al crear el laboratorio (guardado el ' + $fechas[0].ToString('dd/MM/yyyy') + ').' } else { 'Todas las máquinas vuelven a como estaban al crear el laboratorio.' })
    }
}

function Pintar-OperacionLab {
    # Barra de progreso en la cabecera (se llama cada segundo mientras se ve «Laboratorio»)
    $opL = $(if ($script:labElegido) { Leer-OperacionLab $script:labElegido } else { $null })
    if (-not $opL -or [string]$opL.estado -ne 'curso') { $LabOpCaja.Visibility = 'Collapsed'; return }
    $LabOpCaja.Visibility = 'Visible'
    $LabOpTexto.Text = [string]$opL.paso
    $segs = 0; try { $segs = ((Get-Date) - [datetime]$opL.inicio).TotalSeconds } catch {}
    $LabOpReloj.Text = Formato-Tiempo $segs
    Poner-BarraProg $LabOpBarra ([double]$opL.pct) $Colores.Verde
}

function Registrar-OperacionLab([string]$accion, [string]$labNombre) { $script:opLabVistas["$accion|$labNombre"] = $true }

function Vigilar-OperacionesLab {
    # Se llama cada par de segundos (esté la página que esté): cuando termina algo que se vio en marcha, avisa
    foreach ($opV in @(Leer-OperacionesLab)) {
        $claveV = "$($opV.accion)|$($opV.lab)"
        if ([string]$opV.estado -eq 'curso') { $script:opLabVistas[$claveV] = $true; continue }
        if (-not $script:opLabVistas.ContainsKey($claveV)) { continue }
        $script:opLabVistas.Remove($claveV)
        $malV = @($opV.resultado | Where-Object { $_ -and -not $_.ok })
        if ([string]$opV.estado -eq 'ok') { Mostrar-Toast ([string]$opV.mensaje) 'ok' }
        else {
            $detalleV = (@($malV | ForEach-Object { "$($_.nombre): $($_.mensaje)" }) -join "`n")
            if (-not $detalleV) { $detalleV = [string]$opV.mensaje }
            $quePaso = $(if ([string]$opV.estado -eq 'parcial') { [string]$opV.mensaje.Split(':')[0] + '.' } else { [string]$opV.mensaje })
            Error-Amable $quePaso 'Mira «Detalles» y prueba otra vez. Las demás máquinas no se han tocado más de lo que dice arriba.' $detalleV
        }
        $script:labFirma = ''
        try { Pintar-MisLab -Forzar } catch {}
        Recargar-Luego 1500
    }
}

function Preparar-LanzamientoLab([string]$accion, [string[]]$vmxLista, [string[]]$opciones) {
    Lanzar-OperacionLab $accion ([string]$script:labElegido) $vmxLista $opciones
    Registrar-OperacionLab $accion ([string]$script:labElegido)
    $script:labFirma = ''
    try { Pintar-MisLab -Forzar; Pintar-OperacionLab } catch {}
}

# ---------------------------------------------------------------- guardar el estado de ahora como inicial
function Guardar-EstadoAhoraLab($filasG) {
    $nombreLabG = [string]$script:labElegido
    $listaG = @($filasG)
    if (-not $listaG.Count) { return }
    $encendidasG = @($listaG | Where-Object { $_.Fila.Encendida })
    $yaTienenG = @($listaG | Where-Object { $_.Tiene }).Count
    $modo = 'apagar'
    if ($encendidasG.Count) {
        $r = Mensaje "Hay $(Plural $encendidasG.Count 'máquina encendida' 'máquinas encendidas'). Se guardará también la memoria (ocupa tanto como su RAM).`n`n¿Prefieres apagarlas primero?" 'Guardar el estado de ahora como inicial' 'pregunta' @(
            @{ Texto = 'Cancelar'; Valor = 'no'; Estilo = 'BotonSecundario' }
            @{ Texto = 'Guardar encendidas'; Valor = 'encendidas'; Estilo = 'BotonSecundario' }
            @{ Texto = 'Apagar y guardar (recomendado)'; Valor = 'apagar'; Estilo = 'BotonPrimario' })
        if (@('apagar', 'encendidas') -notcontains [string]$r) { return }
        $modo = [string]$r
    } else {
        $txt = "Se guardará el estado de ahora como el estado inicial de $nombreLabG."
        if ($yaTienenG) { $txt += "`n`nSustituye al que ya tenían guardado." }
        if (-not (Pregunta $txt 'Guardar el estado inicial' 'Guardar')) { return }
    }
    Preparar-LanzamientoLab 'guardar' @($listaG | ForEach-Object { $_.Fila.Vmx }) $(if ($modo -eq 'apagar') { @('ApagarAntes') } else { @() })
    Mostrar-Toast "Guardando el estado inicial de ${nombreLabG}: el progreso sale aquí y en Inicio."
}

function Quitar-EstadoInicialLab {
    $nombreLabQ = [string]$script:labElegido
    $conQ = @(Filas-EstadoLab | Where-Object { $_.Tiene })
    if (-not $conQ.Count) { Aviso "$nombreLabQ no tiene estado inicial guardado."; return }
    if (-not (Pregunta "¿Quitar el estado inicial de $nombreLabQ?`n`nSe borran las instantáneas «Estado inicial del laboratorio» de sus máquinas. Las máquinas se quedan como están ahora; solo pierdes la posibilidad de volver a empezar con un clic." 'Quitar el estado inicial' 'Quitar el estado inicial' 'Cancelar' 'BotonRojo')) { return }
    Preparar-LanzamientoLab 'quitar' @($conQ | ForEach-Object { $_.Fila.Vmx }) @()
    Mostrar-Toast "Quitando el estado inicial de $nombreLabQ."
}

# ---------------------------------------------------------------- volver al estado inicial
function Abrir-VolverLab {
    $nombreLabV = [string]$script:labElegido
    if (-not $nombreLabV) { return }
    $filasV = @(Filas-EstadoLab)
    $tienenV = @($filasV | Where-Object { $_.Tiene })
    $faltanV = @($filasV | Where-Object { -not $_.Tiene })
    if (-not $tienenV.Count) { Aviso "$nombreLabV no tiene estado inicial guardado."; return }
    $e = Nuevo-Dialogo 'dialogo-volver-lab.xaml' "Volver al estado inicial de $nombreLabV" '' 540
    # Lista de máquinas: ✓ tiene estado inicial, ✗ no lo tiene, y si está encendida o apagada
    foreach ($fv in $filasV) {
        $filaGrid = New-Object System.Windows.Controls.Grid
        $filaGrid.Margin = New-Object System.Windows.Thickness(0, 3, 0, 3)
        foreach ($ancho in @(26, -1, -2)) {
            $col = New-Object System.Windows.Controls.ColumnDefinition
            if ($ancho -eq -1) { $col.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
            elseif ($ancho -eq -2) { $col.Width = [System.Windows.GridLength]::Auto }
            else { $col.Width = New-Object System.Windows.GridLength($ancho) }
            [void]$filaGrid.ColumnDefinitions.Add($col)
        }
        $marca = New-Object System.Windows.Controls.TextBlock
        $marca.Text = $(if ($fv.Tiene) { [string][char]0x2713 } else { [string][char]0x2717 }); $marca.FontSize = 15; $marca.FontWeight = [System.Windows.FontWeights]::Bold
        $marca.Foreground = Pincel $(if ($fv.Tiene) { $Colores.Ok } else { $Colores.Error })
        $marca.ToolTip = $(if ($fv.Tiene) { 'Tiene estado inicial' } else { 'No tiene estado inicial guardado' })
        $nombreTb = New-Object System.Windows.Controls.TextBlock
        $nombreTb.Text = [string]$fv.Fila.Nombre; $nombreTb.VerticalAlignment = 'Center'; $nombreTb.TextTrimming = 'CharacterEllipsis'
        $nombreTb.Foreground = Pincel $Colores.Texto
        $estadoTb = New-Object System.Windows.Controls.TextBlock
        $estadoTb.Text = $(if ($fv.Fila.Encendida) { 'encendida' } else { 'apagada' }); $estadoTb.VerticalAlignment = 'Center'
        $estadoTb.Foreground = Pincel $Colores.Suave; $estadoTb.FontSize = 12.5
        [System.Windows.Controls.Grid]::SetColumn($nombreTb, 1); [System.Windows.Controls.Grid]::SetColumn($estadoTb, 2)
        [void]$filaGrid.Children.Add($marca); [void]$filaGrid.Children.Add($nombreTb); [void]$filaGrid.Children.Add($estadoTb)
        [void]$e.VolverLista.Children.Add($filaGrid)
    }
    $e.ChkVolverEncender.IsChecked = [bool]@($filasV | Where-Object { $_.Fila.Encendida }).Count
    if ($faltanV.Count) {
        $e.VolverFaltanCaja.Visibility = 'Visible'
        $e.VolverFaltan.Text = "Faltan $(Plural $faltanV.Count 'máquina' 'máquinas'). El laboratorio con dominio puede quedar descuadrado si solo vuelven unas pocas."
        $e.BtnVolverOk.Content = "Volver solo las $($tienenV.Count) que se puede"
    }
    $script:volverElegido = ''
    $e.BtnVolverNo.Add_Click({ $e.Ventana.Close() })
    $e.BtnVolverGuardar.Add_Click({ $script:volverElegido = 'guardar'; $e.Ventana.Close() })
    $e.BtnVolverOk.Add_Click({ $script:volverElegido = 'volver'; $e.Ventana.Close() })
    [void]$e.Ventana.ShowDialog()
    if ($script:volverElegido -eq 'guardar') { Guardar-EstadoAhoraLab $faltanV; return }
    if ($script:volverElegido -ne 'volver') { return }
    $opcionesV = @()
    if ($e.ChkVolverEncender.IsChecked) { $opcionesV += 'Encender' }
    if ($faltanV.Count) { $opcionesV += 'Parcial' }
    Preparar-LanzamientoLab 'volver' @($tienenV | ForEach-Object { $_.Fila.Vmx }) $opcionesV
    Mostrar-Toast "Volviendo al estado inicial de ${nombreLabV}: el progreso sale aquí y en Inicio."
}

$BtnLmVolver.Add_Click({ try { Abrir-VolverLab } catch { Escribir-Log ("Volver al estado inicial: " + ($_ | Out-String)); Error-Amable 'No he podido abrir el cuadro.' 'Prueba otra vez; si sigue igual, mira Ajustes → Ayuda y registros.' $_.Exception.Message } })
$BtnLmMas.Add_Click({
    $opsMas = @(
        @{ T = 'Guardar el estado de ahora como inicial'; Accion = 'LabGuardarInicial'; Icono = 'Instantaneas'; Ok = $true; Datos = @('lab') }
        @{ T = 'Quitar el estado inicial'; Accion = 'LabQuitarInicial'; Icono = 'Limpiar'; Ok = [bool]@(Filas-EstadoLab | Where-Object { $_.Tiene }).Count
           Ayuda = $(if (@(Filas-EstadoLab | Where-Object { $_.Tiene }).Count) { '' } else { 'Este laboratorio no tiene estado inicial guardado' }); Datos = @('lab') }
    )
    Mostrar-MenuContextual $BtnLmMas $opsMas $false $true
})
