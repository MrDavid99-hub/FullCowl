# =====================================================================
#  Interfaz nueva: Ajustes → Espacio y limpieza (ficha 30)
#  La lógica (medir, dependencias y borrado seguro) está en limpieza.ps1; aquí solo se pinta y se pregunta.
#  Medir y borrar se hacen en un hilo aparte (runspace propio) para que la ventana no se congele.
#  Variables con el prefijo «ez» para no tapar elementos de la ventana (ver NOTAS-TECNICAS).
# =====================================================================
. (Join-Path $dirFc 'limpieza.ps1')

$script:ezDatos = $null            # @{ Elementos; Disco; Cuando } del último cálculo
$script:ezMarcados = @{}           # Id -> $true
$script:ezPestana = 'bases'
$script:ezPorTamano = $true
$script:ezProgreso = $null
$script:ezHilo = $null
$script:ezAsinc = $null
$script:ezEspacio = $null
$script:ezModo = ''                # 'analizar' o 'borrar' mientras trabaja el hilo
$script:ezPintados = -1
$script:ezRecalcular = $false

$scriptEspacio = @'
param($carpeta, $modo, $progreso, $elementos)
$EsVentana = $true
try {
    . (Join-Path $carpeta 'comun.ps1')
    . (Join-Path $carpeta 'limpieza.ps1')
    $ErrorActionPreference = 'Continue'
    if ($modo -eq 'borrar') { Borrar-ElementosLimpieza $elementos $progreso } else { Analizar-Espacio $progreso }
} catch { $progreso.Error = ($_ | Out-String) }
$progreso.Fin = $true
'@

function Trabajando-Espacio { return [bool]$script:ezModo }

function Lanzar-HiloEspacio([string]$modo, $elementos) {
    if (Trabajando-Espacio) { return $false }
    $script:ezProgreso = [hashtable]::Synchronized(@{ Fase = ''; Total = 0; Hecho = 0; Fin = $false; Error = ''; Disco = $null
        Elementos = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        Resultados = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)) })
    if (-not $script:ezEspacio -or $script:ezEspacio.RunspaceStateInfo.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
        try { if ($script:ezEspacio) { $script:ezEspacio.Dispose() } } catch {}
        $ezIss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $ezIss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
        $script:ezEspacio = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($ezIss)
        $script:ezEspacio.Open()
    }
    $script:ezHilo = [PowerShell]::Create()
    $script:ezHilo.Runspace = $script:ezEspacio
    [void]$script:ezHilo.AddScript($scriptEspacio).AddArgument($dirFc).AddArgument($modo).AddArgument($script:ezProgreso).AddArgument(@($elementos))
    $script:ezModo = $modo
    $script:ezPintados = -1
    $script:ezAsinc = $script:ezHilo.BeginInvoke()
    $EspBarraCalc.Value = 0
    $EspBarraCalc.Visibility = 'Visible'
    $BtnEspCalcular.IsEnabled = $false
    $relojEspacio.Start()
    Pintar-BarraEspacio
    return $true
}

function Calcular-Espacio {
    if (-not (Config-Completa)) { return }
    [void](Lanzar-HiloEspacio 'analizar' @())
}

# ---------------------------------------------------------------- lo que se ve
function Elementos-Espacio {
    # Mientras calcula, lo que ya se ha medido; después, el resultado guardado
    if ($script:ezModo -eq 'analizar' -and $script:ezProgreso) { return @($script:ezProgreso.Elementos.ToArray()) }
    if ($script:ezDatos) { return @($script:ezDatos.Elementos) }
    return @()
}

function Elementos-DePestana([string]$pest) {
    $ezTodos = @(Elementos-Espacio)
    switch ($pest) {
        'bases'  { return @($ezTodos | Where-Object { $_.Tipo -eq 'base' }) }
        'maq'    { return @($ezTodos | Where-Object { $_.Tipo -eq 'maquina' }) }
        'snap'   { return @($ezTodos | Where-Object { $_.Tipo -eq 'instantanea' }) }
        default  { return @($ezTodos | Where-Object { $_.EnRestos }) }
    }
}

function Marcados-Espacio {
    # Elementos marcados que siguen existiendo y se pueden borrar
    return @(Elementos-Espacio | Where-Object { $script:ezMarcados[[string]$_.Id] -and -not $_.Bloqueo })
}

function Texto-TamanoEsp($el) {
    return $(if ($el.Aprox) { [string][char]0x2248 + ' ' } else { '' }) + (Formato-Tamano ([double]$el.Tamano))
}

function Nueva-PastillaEsp([string]$texto, [string]$fondo = 'T_campo', [string]$color = 'T_textoSuave') {
    $ezB = New-Object System.Windows.Controls.Border
    $ezB.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $ezB.Padding = New-Object System.Windows.Thickness(7, 1, 7, 2)
    $ezB.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    $ezB.VerticalAlignment = 'Center'
    $ezB.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $fondo)
    $ezT = New-Object System.Windows.Controls.TextBlock
    $ezT.Text = $texto; $ezT.FontSize = 11; $ezT.FontWeight = [System.Windows.FontWeights]::SemiBold
    $ezT.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $color)
    $ezB.Child = $ezT
    return $ezB
}

$script:ezAlMarcar = {
    param($s, $a)
    $ezId = [string]$s.Tag
    if ($s.IsChecked) { $script:ezMarcados[$ezId] = $true } else { $script:ezMarcados.Remove($ezId) }
    Pintar-PieEspacio
}

function Nueva-FilaEsp($el) {
    $ezCaja = New-Object System.Windows.Controls.Border
    $ezCaja.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $ezCaja.Padding = New-Object System.Windows.Thickness(12, 9, 14, 9)
    $ezCaja.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    $ezCaja.BorderThickness = New-Object System.Windows.Thickness(1)
    $ezCaja.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'T_superficie')
    $ezCaja.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'T_borde')
    $ezGrid = New-Object System.Windows.Controls.Grid
    foreach ($ezAncho in @('auto', 'resto', 'auto')) {
        $ezCol = New-Object System.Windows.Controls.ColumnDefinition
        $ezCol.Width = $(if ($ezAncho -eq 'resto') { New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto })
        [void]$ezGrid.ColumnDefinitions.Add($ezCol)
    }
    $ezChk = New-Object System.Windows.Controls.CheckBox
    $ezChk.Style = [System.Windows.Application]::Current.FindResource('Casilla')
    $ezChk.VerticalAlignment = 'Center'
    $ezChk.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $ezChk.Tag = [string]$el.Id
    [System.Windows.Automation.AutomationProperties]::SetName($ezChk, "Marcar $([string]$el.Nombre)")
    if ($el.Bloqueo) {
        $ezChk.IsEnabled = $false; $ezChk.IsChecked = $false
        $ezCaja.ToolTip = [string]$el.Bloqueo
        [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($ezChk, $true)
    } else {
        $ezChk.IsChecked = [bool]$script:ezMarcados[[string]$el.Id]
        $ezChk.Add_Click($script:ezAlMarcar)
    }
    [void]$ezGrid.Children.Add($ezChk)

    $ezCentro = New-Object System.Windows.Controls.StackPanel
    $ezCentro.VerticalAlignment = 'Center'
    $ezLinea = New-Object System.Windows.Controls.WrapPanel
    $ezNom = New-Object System.Windows.Controls.TextBlock
    $ezNom.Text = [string]$el.Nombre; $ezNom.FontWeight = [System.Windows.FontWeights]::SemiBold; $ezNom.FontSize = 13.5
    $ezNom.TextTrimming = 'CharacterEllipsis'
    $ezNom.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_texto')
    [void]$ezLinea.Children.Add($ezNom)
    if ($el.Necesaria) { [void]$ezLinea.Children.Add((Nueva-PastillaEsp 'Necesaria' 'T_avisoFondo' 'T_avisoTexto')) }
    if ($el.Etiqueta) { [void]$ezLinea.Children.Add((Nueva-PastillaEsp ([string]$el.Etiqueta))) }
    if ($el.Tipo -eq 'maquina' -or $el.Tipo -eq 'base') {
        $ezEnc = ($el.Estado -eq 'Encendida' -or $el.Estado -eq 'En uso')
        if ($el.Estado) { [void]$ezLinea.Children.Add((Nueva-PastillaEsp ([string]$el.Estado).ToLower() $(if ($ezEnc) { 'T_encendidaFondo' } else { 'T_campo' }) $(if ($ezEnc) { 'T_encendida' } else { 'T_textoSuave' }))) }
    }
    [void]$ezCentro.Children.Add($ezLinea)
    $ezSubTexto = [string]$el.Sub
    if ($el.Tipo -eq 'maquina' -and $el.Fecha) { $ezSubTexto += $(if ($ezSubTexto) { ' · ' } else { '' }) + "último uso $(([datetime]$el.Fecha).ToString('dd/MM/yyyy'))" }
    if ($el.Tipo -eq 'base' -and $el.Fecha) { $ezSubTexto += $(if ($ezSubTexto) { ' · ' } else { '' }) + "del $(([datetime]$el.Fecha).ToString('dd/MM/yyyy'))" }
    if ($ezSubTexto) {
        $ezSub = New-Object System.Windows.Controls.TextBlock
        $ezSub.Text = $ezSubTexto; $ezSub.FontSize = 12; $ezSub.TextWrapping = 'Wrap'
        $ezSub.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        $ezSub.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_textoSuave')
        [void]$ezCentro.Children.Add($ezSub)
    }
    if ($el.Bloqueo) {
        $ezBloq = New-Object System.Windows.Controls.TextBlock
        $ezBloq.Text = [string]$el.Bloqueo; $ezBloq.FontSize = 12; $ezBloq.TextWrapping = 'Wrap'
        $ezBloq.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        $ezBloq.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_aviso')
        [void]$ezCentro.Children.Add($ezBloq)
    }
    [System.Windows.Controls.Grid]::SetColumn($ezCentro, 1)
    [void]$ezGrid.Children.Add($ezCentro)

    $ezTam = New-Object System.Windows.Controls.TextBlock
    $ezTam.Text = Texto-TamanoEsp $el
    $ezTam.FontSize = 14; $ezTam.FontWeight = [System.Windows.FontWeights]::SemiBold
    $ezTam.VerticalAlignment = 'Center'; $ezTam.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    $ezTam.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_texto')
    if ($el.Aprox) { $ezTam.ToolTip = 'Aproximado: lo que pesan los archivos de sus instantáneas. Al borrarlas, VMware junta los discos y lo liberado puede ser menos.' }
    [System.Windows.Controls.Grid]::SetColumn($ezTam, 2)
    [void]$ezGrid.Children.Add($ezTam)
    $ezCaja.Child = $ezGrid
    return $ezCaja
}

function Nuevo-RotuloEsp([string]$texto) {
    $ezR = New-Object System.Windows.Controls.TextBlock
    $ezR.Text = $texto; $ezR.FontSize = 12.5; $ezR.FontWeight = [System.Windows.FontWeights]::SemiBold
    $ezR.Margin = New-Object System.Windows.Thickness(2, 8, 0, 6)
    $ezR.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'T_textoSuave')
    return $ezR
}

function Ordenar-Esp($lista) {
    if ($script:ezPorTamano) { return @($lista | Sort-Object @{ Expression = { [double]$_.Tamano }; Descending = $true }, @{ Expression = { [string]$_.Nombre } }) }
    return @($lista | Sort-Object { [string]$_.Nombre })
}

function Pintar-ListaEspacio {
    $EspLista.Children.Clear()
    $ezDe = @(Elementos-DePestana $script:ezPestana)
    $BtnEspTodosRestos.Visibility = $(if ($script:ezPestana -eq 'restos') { 'Visible' } else { 'Collapsed' })
    $BtnEspOrden.Content = $(if ($script:ezPorTamano) { 'Orden: tamaño' } else { 'Orden: nombre' })
    $EspNota.Text = $(switch ($script:ezPestana) {
        'bases'  { 'Una base solo se puede borrar si ninguna máquina enlazada depende de ella. Para borrarla hay que escribir su nombre.' }
        'maq'    { 'Solo las máquinas de tu carpeta de máquinas. Las encendidas no se pueden marcar.' }
        'snap'   { 'Las instantáneas «base» y el estado inicial de un laboratorio son necesarias y no se tocan. El tamaño es aproximado.' }
        default  { 'Cosas que sobran: carpetas sin máquina, restos de crear bases, CD de configuración ya usados, desechables apagadas y registros antiguos.' }
    })
    if (-not $ezDe.Count) {
        $EspVacio.Visibility = 'Visible'
        if (Trabajando-Espacio) { Poner-Vacio $EspVacio 'Ico_Actualizar' 'Calculando…' 'Las filas van saliendo según se miden.' '' $null $false $true }
        elseif (-not $script:ezDatos) { Poner-Vacio $EspVacio 'Ico_Info' 'Aún no se ha calculado' 'Pulsa «Volver a calcular».' '' $null $false $true }
        elseif ($script:ezPestana -eq 'restos') { Poner-Vacio $EspVacio 'Ico_Limpiar' 'Todo limpio' 'No hay restos que borrar.' '' $null $false $true }
        else { Poner-Vacio $EspVacio 'Ico_Limpiar' 'Todo limpio' 'No hay nada en este apartado.' '' $null $false $true }
        return
    }
    $EspVacio.Visibility = 'Collapsed'
    if ($script:ezPestana -eq 'maq') {
        # Las del laboratorio, juntas bajo su nombre
        $ezLabs = @($ezDe | Where-Object { $_.Lab } | ForEach-Object { [string]$_.Lab } | Sort-Object -Unique)
        foreach ($ezLab in $ezLabs) {
            $ezDelLab = @($ezDe | Where-Object { [string]$_.Lab -eq $ezLab })
            $ezSuma = [double](($ezDelLab | ForEach-Object { [double]$_.Tamano } | Measure-Object -Sum).Sum)
            [void]$EspLista.Children.Add((Nuevo-RotuloEsp "Laboratorio $ezLab · $(Formato-Tamano $ezSuma)"))
            foreach ($ezEl in (Ordenar-Esp $ezDelLab)) { [void]$EspLista.Children.Add((Nueva-FilaEsp $ezEl)) }
        }
        $ezSueltas = @($ezDe | Where-Object { -not $_.Lab })
        if ($ezSueltas.Count -and $ezLabs.Count) { [void]$EspLista.Children.Add((Nuevo-RotuloEsp 'Sin laboratorio')) }
        foreach ($ezEl in (Ordenar-Esp $ezSueltas)) { [void]$EspLista.Children.Add((Nueva-FilaEsp $ezEl)) }
    } else {
        foreach ($ezEl in (Ordenar-Esp $ezDe)) { [void]$EspLista.Children.Add((Nueva-FilaEsp $ezEl)) }
    }
}

function Pintar-PieEspacio {
    $ezSel = @(Marcados-Espacio)
    if (-not $ezSel.Count) {
        $EspMarcado.Text = 'Nada marcado.'
        $BtnEspBorrar.IsEnabled = $false
        return
    }
    $ezSuma = [double](($ezSel | ForEach-Object { [double]$_.Tamano } | Measure-Object -Sum).Sum)
    $ezAprox = [bool]@($ezSel | Where-Object { $_.Aprox }).Count
    $EspMarcado.Text = "Marcado: $(Plural $ezSel.Count 'elemento' 'elementos') · liberarás $(if ($ezAprox) { 'unos ' } else { '' })$(Formato-Tamano $ezSuma)"
    $BtnEspBorrar.IsEnabled = (-not (Trabajando-Espacio))
}

function Pintar-DiscoEspacio {
    $ezD = $(if ($script:ezModo -eq 'analizar' -and $script:ezProgreso -and $script:ezProgreso.Disco) { $script:ezProgreso.Disco } elseif ($script:ezDatos) { $script:ezDatos.Disco } else { $null })
    if (-not $ezD -or -not [double]$ezD.Total) { return }
    $ezFc = [double]$ezD.Bases + [double]$ezD.Maquinas
    $ezUsado = [Math]::Max([double]0, [double]$ezD.Total - [double]$ezD.Libre)
    $ezOtros = [Math]::Max([double]0, $ezUsado - $ezFc)
    $EspDiscoTexto.Text = "Disco $($ezD.Unidad) · libre $(Formato-Tamano ([double]$ezD.Libre)) de $(Formato-Tamano ([double]$ezD.Total)) · Full Cowl usa $(Formato-Tamano $ezFc)"
    $ezCols = $EspDiscoBarra.ColumnDefinitions
    $ezCols[0].Width = New-Object System.Windows.GridLength(([Math]::Max(0.0, [Math]::Min($ezFc, $ezUsado) / [double]$ezD.Total)), [System.Windows.GridUnitType]::Star)
    $ezCols[1].Width = New-Object System.Windows.GridLength(([Math]::Max(0.0, $ezOtros / [double]$ezD.Total)), [System.Windows.GridUnitType]::Star)
    $ezCols[2].Width = New-Object System.Windows.GridLength(([Math]::Max(0.0001, [double]$ezD.Libre / [double]$ezD.Total)), [System.Windows.GridUnitType]::Star)
    $EspCifFc.Text = "Full Cowl: $(Formato-Tamano $ezFc)"
    $EspCifOtros.Text = "Otros: $(Formato-Tamano $ezOtros)"
    $EspCifBases.Text = "Bases: $(Formato-Tamano ([double]$ezD.Bases))"
    $EspCifMaq.Text = "Máquinas: $(Formato-Tamano ([double]$ezD.Maquinas))"
    $EspCifSnap.Text = "Instantáneas: $([string][char]0x2248) $(Formato-Tamano ([double]$ezD.Instantaneas))"
    $EspCifSnap.ToolTip = 'Ya contadas dentro de Bases y Máquinas.'
    $EspCifIso.Text = "ISO: $(Formato-Tamano ([double]$ezD.Isos)), no se tocan"
}

function Pintar-BarraEspacio {
    $ezP = $script:ezProgreso
    if (-not (Trabajando-Espacio) -or -not $ezP) {
        $EspBarraCalc.Visibility = 'Collapsed'
        $BtnEspCalcular.IsEnabled = $true
        if ($script:ezDatos) { $EspEstado.Text = "Calculado a las $($script:ezDatos.Cuando.ToString('HH:mm')). Se guarda unos 5 minutos; «Volver a calcular» lo repite." }
        return
    }
    $ezTot = [int]$ezP.Total; $ezHe = [int]$ezP.Hecho
    $ezVerbo = $(if ($script:ezModo -eq 'borrar') { 'Borrando' } else { 'Calculando' })
    $EspEstado.Text = $(if ($ezTot) { "$ezVerbo… $([Math]::Min($ezHe + 1, $ezTot)) de $ezTot" } else { "$ezVerbo…" }) + $(if ([string]$ezP.Fase) { " · $([string]$ezP.Fase)" } else { '' })
    $ezPct = $(if ($ezTot) { [Math]::Max(3.0, [Math]::Min(97.0, 100.0 * $ezHe / $ezTot)) } else { 3.0 })
    try { Poner-BarraProg $EspBarraCalc $ezPct $Colores.Verde } catch { $EspBarraCalc.Value = $ezPct }
}

function Pintar-Espacio {
    Pintar-DiscoEspacio
    Pintar-ListaEspacio
    Pintar-PieEspacio
    Pintar-BarraEspacio
}

# ---------------------------------------------------------------- reloj: sigue al hilo de trabajo
$relojEspacio = New-Object System.Windows.Threading.DispatcherTimer
$relojEspacio.Interval = [TimeSpan]::FromMilliseconds(300)
$relojEspacio.Add_Tick({
    try {
        $ezP = $script:ezProgreso
        if (-not $ezP) { $relojEspacio.Stop(); return }
        if (-not $ezP.Fin) {
            Pintar-BarraEspacio
            # Cada fila aparece al medirse
            if ($script:ezModo -eq 'analizar' -and $ezP.Elementos.Count -ne $script:ezPintados) {
                $script:ezPintados = $ezP.Elementos.Count
                if ($paginaEspacio.IsVisible) { Pintar-ListaEspacio }
            }
            return
        }
        $relojEspacio.Stop()
        try { [void]$script:ezHilo.EndInvoke($script:ezAsinc) } catch { Escribir-Log ("Espacio y limpieza (hilo): " + ($_ | Out-String)) }
        try { $script:ezHilo.Dispose() } catch {}
        $ezModoHecho = $script:ezModo
        $script:ezModo = ''
        try { Brillo-Barra $EspBarraCalc 100 $Colores.Verde } catch {}
        if ($ezModoHecho -eq 'analizar') { Terminar-AnalisisEspacio $ezP } else { Terminar-BorradoEspacio $ezP }
    } catch {
        $relojEspacio.Stop(); $script:ezModo = ''
        Escribir-Log ("Espacio y limpieza: " + ($_ | Out-String))
        try { Pintar-Espacio } catch {}
    }
})

function Terminar-AnalisisEspacio($prog) {
    if ([string]$prog.Error) {
        Escribir-Log ("Espacio y limpieza (cálculo): " + [string]$prog.Error)
        Pintar-Espacio
        Error-Amable 'No he podido calcular el espacio.' 'Pulsa «Volver a calcular». Si sigue igual, mira Ajustes → Ayuda y registros.' (Limpiar-Detalle ([string]$prog.Error))
        return
    }
    $script:ezDatos = @{ Elementos = @($prog.Elementos.ToArray()); Disco = $prog.Disco; Cuando = (Get-Date) }
    # Lo marcado que ya no existe o ya no se puede borrar se desmarca
    $ezValidos = @{}
    foreach ($ezEl in $script:ezDatos.Elementos) { if (-not $ezEl.Bloqueo) { $ezValidos[[string]$ezEl.Id] = $true } }
    foreach ($ezId in @($script:ezMarcados.Keys)) { if (-not $ezValidos[$ezId]) { $script:ezMarcados.Remove($ezId) } }
    Pintar-Espacio
    try { Pintar-Hub } catch {}
}

function Terminar-BorradoEspacio($prog) {
    $ezRes = @($prog.Resultados.ToArray())
    $ezBien = @($ezRes | Where-Object { $_.Ok })
    $ezMal = @($ezRes | Where-Object { -not $_.Ok })
    $ezLib = [double](($ezRes | ForEach-Object { [double]$_.Liberado } | Measure-Object -Sum).Sum)
    # Lo borrado desaparece ya de la lista; después se vuelve a calcular todo en segundo plano
    $ezIdsFuera = @{}
    foreach ($ezR in $ezBien) { $ezIdsFuera[[string]$ezR.Id] = $true; $script:ezMarcados.Remove([string]$ezR.Id) }
    if ($script:ezDatos) { $script:ezDatos.Elementos = @($script:ezDatos.Elementos | Where-Object { -not $ezIdsFuera[[string]$_.Id] }) }
    Pintar-Espacio
    if ([string]$prog.Error) { Escribir-Log ("Espacio y limpieza (borrado): " + [string]$prog.Error) }
    if ($ezMal.Count -or [string]$prog.Error) {
        $ezDet = (@($ezMal | ForEach-Object { "$([string]$_.Nombre): $([string]$_.Motivo)" }) + @([string]$prog.Error) | Where-Object { $_ }) -join "`n"
        Escribir-Log ("Espacio y limpieza, no borrado: " + $ezDet)
        Error-Amable "$(Plural $ezBien.Count 'elemento borrado' 'elementos borrados') ($(Formato-Tamano $ezLib) liberados). $(Plural $ezMal.Count 'no se pudo borrar' 'no se pudieron borrar')." 'Mira el motivo de cada uno en Detalles. Lo normal: cerrar su pestaña en VMware o apagar la máquina, y repetir.' (Limpiar-Detalle $ezDet)
    } elseif ($ezBien.Count) {
        Mostrar-Toast "Liberados $(Formato-Tamano $ezLib)."
    }
    # Mis máquinas e Inicio se ponen al día, y aquí se vuelve a medir
    try { if ($script:cargado) { Cargar -Silencioso } } catch {}
    Calcular-Espacio
}

# ---------------------------------------------------------------- acciones
function Poner-PestanaEsp([string]$pest) {
    $script:ezPestana = $pest
    Pintar-ListaEspacio
    try { $EspDesliz.ScrollToTop() } catch {}
}
$EspPillBases.Add_Checked({ Poner-PestanaEsp 'bases' })
$EspPillMaq.Add_Checked({ Poner-PestanaEsp 'maq' })
$EspPillSnap.Add_Checked({ Poner-PestanaEsp 'snap' })
$EspPillRestos.Add_Checked({ Poner-PestanaEsp 'restos' })
$BtnEspOrden.Add_Click({ $script:ezPorTamano = -not $script:ezPorTamano; Pintar-ListaEspacio })
$BtnEspCalcular.Add_Click({ Calcular-Espacio })
$BtnEspTodosRestos.Add_Click({
    $ezN = 0
    foreach ($ezEl in @(Elementos-DePestana 'restos')) {
        if ($ezEl.AutoMarcar -and -not $ezEl.Bloqueo) { $script:ezMarcados[[string]$ezEl.Id] = $true; $ezN++ }
    }
    Pintar-ListaEspacio; Pintar-PieEspacio
    if (-not $ezN) { Mostrar-Toast 'No hay restos claros que marcar.' 'info' }
})

function Texto-CuentaEsp($sel) {
    # «3 máquinas, 1 base y 2 restos»
    $ezPartes = @()
    $ezNb = @($sel | Where-Object { $_.Tipo -eq 'base' }).Count
    $ezNm = @($sel | Where-Object { $_.Tipo -eq 'maquina' }).Count
    $ezNs = @($sel | Where-Object { $_.Tipo -eq 'instantanea' }).Count
    $ezNr = @($sel | Where-Object { $_.Tipo -eq 'resto' }).Count
    if ($ezNm) { $ezPartes += (Plural $ezNm 'máquina' 'máquinas') }
    if ($ezNb) { $ezPartes += (Plural $ezNb 'base' 'bases') }
    if ($ezNs) { $ezPartes += "las instantáneas de $(Plural $ezNs 'máquina' 'máquinas')" }
    if ($ezNr) { $ezPartes += (Plural $ezNr 'resto' 'restos') }
    if ($ezPartes.Count -le 1) { return [string]($ezPartes -join '') }
    return (($ezPartes[0..($ezPartes.Count - 2)] -join ', ') + ' y ' + $ezPartes[-1])
}

$BtnEspBorrar.Add_Click({
    try {
        if (Trabajando-Espacio) { return }
        $ezSel = @(Marcados-Espacio)
        if (-not $ezSel.Count) { return }
        $ezSuma = [double](($ezSel | ForEach-Object { [double]$_.Tamano } | Measure-Object -Sum).Sum)
        $ezAprox = [bool]@($ezSel | Where-Object { $_.Aprox }).Count
        $ezTxt = "Vas a borrar $(Texto-CuentaEsp $ezSel): liberarás $(if ($ezAprox) { 'unos ' } else { '' })$(Formato-Tamano $ezSuma). No se puede deshacer."
        $ezNombres = @($ezSel | Where-Object { $_.Tipo -eq 'maquina' -or $_.Tipo -eq 'base' } | ForEach-Object { [string]$_.Nombre })
        if ($ezNombres.Count) { $ezTxt += "`n`n$($ezNombres -join ', ')" }
        foreach ($ezS in @($ezSel | Where-Object { $_.Tipo -eq 'instantanea' })) { $ezTxt += "`n`nInstantáneas de $([string]$ezS.Nombre): $(@($ezS.Snaps) -join ', ')" }
        $ezLabs = @($ezSel | Where-Object { $_.Tipo -eq 'maquina' -and $_.Lab } | ForEach-Object { [string]$_.Lab } | Sort-Object -Unique)
        if ($ezLabs.Count) { $ezTxt += "`n`nOjo: son máquinas de laboratorio ($($ezLabs -join ', ')). Se pierde también su estado inicial guardado." }
        if (-not (Pregunta $ezTxt 'Borrar lo marcado' 'Borrar' 'Cancelar' 'BotonRojo')) { return }
        # Bases: segunda confirmación escribiendo su nombre
        foreach ($ezB in @($ezSel | Where-Object { $_.Tipo -eq 'base' })) {
            $ezEscrito = Pedir-Texto "Borrar la base $([string]$ezB.Nombre)" "Una base tarda mucho en volver a hacerse. Para confirmar, escribe su nombre: $([string]$ezB.Nombre)" ''
            if ($null -eq $ezEscrito) { return }
            if (([string]$ezEscrito).Trim() -ine [string]$ezB.Nombre) { Aviso "El nombre no coincide con «$([string]$ezB.Nombre)». No se ha borrado nada."; return }
        }
        if (-not (Lanzar-HiloEspacio 'borrar' $ezSel)) { return }
        $BtnEspBorrar.IsEnabled = $false
    } catch {
        Escribir-Log ("Borrar lo marcado: " + ($_ | Out-String))
        Error-Amable 'No he podido empezar a borrar.' 'Prueba otra vez; si sigue igual, mira Ajustes → Ayuda y registros.' $_.Exception.Message
    }
})

function Entrar-Espacio {
    # Al entrar: si no hay cálculo o tiene más de 5 minutos, se calcula; si no, se enseña el guardado
    $ezViejo = (-not $script:ezDatos) -or (((Get-Date) - $script:ezDatos.Cuando).TotalMinutes -gt 5)
    Pintar-Espacio
    if ($ezViejo -and -not (Trabajando-Espacio)) { Calcular-Espacio }
}

function Resumen-EspacioHub {
    # Dos líneas para la tarjeta de la portada de Ajustes (con lo último que se sepa)
    $ezD = $(if ($script:ezDatos -and $script:ezDatos.Disco -and [double]$script:ezDatos.Disco.Total) { $script:ezDatos.Disco } else { $null })
    if ($ezD) { return @("Libre $(Formato-Tamano ([double]$ezD.Libre)) de $(Formato-Tamano ([double]$ezD.Total)) · Full Cowl usa $(Formato-Tamano ([double]$ezD.Bases + [double]$ezD.Maquinas))", 'Qué ocupa cada base, máquina e instantánea, y borrar lo que sobra con seguridad.') }
    $ezG = $script:disco
    if ($ezG -and [double]$ezG.Total) { return @("Libre $(Formato-Tamano ([double]$ezG.Libre)) de $(Formato-Tamano ([double]$ezG.Total)) · Full Cowl usa $(Formato-Tamano ([double]$ezG.Bases + [double]$ezG.Maq))", 'Qué ocupa cada base, máquina e instantánea, y borrar lo que sobra con seguridad.') }
    return @('Mira qué ocupa cada cosa', 'Qué ocupa cada base, máquina e instantánea, y borrar lo que sobra con seguridad.')
}
