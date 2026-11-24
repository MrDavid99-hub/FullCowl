# =====================================================================
#  Interfaz nueva: Ajustes como «hub» (ficha 10)
#  Portada con los apartados (Apariencia, Actualizaciones, General, Este PC, Ayuda y registros) y cada
#  apartado como página dentro de la ventana. Apariencia es apariencia.xaml, metida aquí dentro.
#  Ojo con los nombres de variables: PowerShell no distingue mayúsculas y una local con el nombre de un
#  elemento de la ventana lo tapa (ver NOTAS-TECNICAS). Las de aquí llevan el prefijo «hb».
# =====================================================================
$script:seccionHub = 'portada'
$script:cargandoHub = $false
$script:hubSecciones = [ordered]@{
    portada    = @{ Panel = $HubPortada;        Pill = $null;          Titulo = '' }
    apariencia = @{ Panel = $paginaApariencia;  Pill = $PillApariencia; Titulo = 'Apariencia' }
    act        = @{ Panel = $HubAct;            Pill = $PillAct;       Titulo = 'Actualizaciones' }
    general    = @{ Panel = $HubGeneral;        Pill = $PillGeneral;   Titulo = 'General' }
    pc         = @{ Panel = $HubPc;             Pill = $PillPc;        Titulo = 'Este PC' }
    espacio    = @{ Panel = $paginaEspacio;     Pill = $PillEspacio;   Titulo = 'Espacio y limpieza' }
    ayuda      = @{ Panel = $HubAyuda;          Pill = $PillAyuda;     Titulo = 'Ayuda y registros' }
}

function Version-Instalada {
    try { return ([IO.File]::ReadAllText((Join-Path (Split-Path $dirFc) 'VERSION'))).Trim() } catch { return '' }
}

# ---------------------------------------------------------------- resúmenes de la portada
function Poner-Insignia($borde, $texto, [string]$texto2, [string]$fondoClave, [string]$colorClave) {
    if (-not $texto2) { $borde.Visibility = 'Collapsed'; return }
    $texto.Text = $texto2
    $borde.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $fondoClave)
    $texto.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $colorClave)
    $borde.Visibility = 'Visible'
}

function Estado-Actualizacion {
    # @{ Insignia; Hay; Linea1; Linea2 } según lo último que se buscó
    $hbR = $script:actualizacion
    $hbV = Version-Instalada
    if ($hbR -and $hbR.hayNueva) {
        $hbL2 = "Instalada: $hbV"
        $hbCambios = @($hbR.cambios)
        if ($hbCambios.Count) { $hbL2 += " · $([string]$hbCambios[0])" }
        return @{ Insignia = 'Hay una nueva'; Hay = $true; Linea1 = "Hay una versión nueva: $([string]$hbR.nueva)"; Linea2 = $hbL2 }
    }
    if ($hbR -and $hbR.sinGit) { return @{ Insignia = ''; Hay = $false; Linea1 = 'Falta Git para buscar actualizaciones'; Linea2 = "Se instala con: $script:comandoGit" } }
    if ($hbR -and $hbR.sinConexion) { return @{ Insignia = ''; Hay = $false; Linea1 = 'No se pudo conectar con GitHub'; Linea2 = "Versión $hbV · comprueba la conexión a Internet" } }
    if ($hbR) {
        $hbL2 = "Versión $hbV"
        if ($script:ultimaRevision) { $hbL2 += " · última revisión $($script:ultimaRevision)" }
        return @{ Insignia = 'Al día'; Hay = $false; Linea1 = 'Está al día'; Linea2 = $hbL2 }
    }
    return @{ Insignia = ''; Hay = $false; Linea1 = 'Todavía no se ha buscado'; Linea2 = "Versión $hbV" }
}

function Pintar-Hub {
    # Resúmenes en vivo de las tarjetas de la portada (con los valores reales)
    $hbTema = switch ([string]$Config.Tema) { 'Oscuro' { 'oscuro' } 'Automatico' { 'automático' } default { 'claro' } }
    $hbAc = [string]$Config.Acento
    if (-not $script:Acentos.Contains($hbAc)) { $hbAc = 'FullCowl' }
    $hbT = "Tema $hbTema · $(if ($Config.ColorTotal -eq $false) { 'acento' } else { 'color' }) $($script:NombresAcento[$hbAc])"
    if ([bool]$Config.Sobrio) { $hbT += ' · modo sobrio' }
    $ResAp1.Text = $hbT
    $hbVista = $(if ([string]$Config.Vista -eq 'Lista') { 'en lista' } else { 'en tarjetas' })
    $hbTam = $(switch ([string]$Config.Tamano) { 'Compacto' { 'compactas' } 'Grande' { 'grandes' } default { 'normales' } })
    $hbLetra = $(if ([string]$Config.Letra -eq 'Grande') { 'grande' } else { 'normal' })
    $ResAp2.Text = "Mis máquinas $hbVista ($hbTam) · letra $hbLetra · animaciones $((Animaciones-Modo).ToLower())"

    $hbA = Estado-Actualizacion
    $ResAct1.Text = $hbA.Linea1; $ResAct2.Text = $hbA.Linea2
    if ($hbA.Hay) { Poner-Insignia $ResActBadge $ResActBadgeTxt $hbA.Insignia 'T_avisoFondo' 'T_aviso' }
    else { Poner-Insignia $ResActBadge $ResActBadgeTxt $hbA.Insignia 'T_encendidaFondo' 'T_encendida' }

    $hbNom = ([string]$Config.Nombre).Trim()
    if (-not $hbNom) { $hbNom = $env:USERNAME }
    $hbIni = $(if ([string]$Config.PaginaInicial -eq 'Maquinas') { 'Mis máquinas' } else { 'Inicio' })
    $ResGen1.Text = "Te llamamos $hbNom y Full Cowl se abre en $hbIni."
    $ResGen2.Text = 'Tu nombre para el saludo de Inicio y la pantalla con la que arranca.'

    $ResPc1.Text = $(if ($Config.CarpetaISOs) { "ISOs en $([string]$Config.CarpetaISOs)" } else { 'Sin carpeta de ISOs todavía' })
    $ResPc2.Text = 'Carpetas, usuario y contraseña de las máquinas. Se guarda solo en este equipo.'

    $hbEsp = @(Resumen-EspacioHub)
    $ResEsp1.Text = [string]$hbEsp[0]; $ResEsp2.Text = [string]$hbEsp[1]

    $ResAy1.Text = "Versión $(Version-Instalada) · novedades, manual y registros."
    $ResAy2.Text = 'Para cuando algo falla o quieres saber qué ha cambiado.'
}

# ---------------------------------------------------------------- General (se aplica al momento)
[void]$GenInicio.Items.Add('Inicio'); [void]$GenInicio.Items.Add('Mis máquinas')
function Cargar-General {
    $script:cargandoHub = $true
    try {
        $GenNombre.Text = [string]$Config.Nombre
        $GenInicio.SelectedIndex = $(if ([string]$Config.PaginaInicial -eq 'Maquinas') { 1 } else { 0 })
    } finally { $script:cargandoHub = $false }
}
function Guardar-General {
    if ($script:cargandoHub) { return }
    $hbNombre = $GenNombre.Text.Trim()
    $hbPag = $(if ($GenInicio.SelectedIndex -eq 1) { 'Maquinas' } else { 'Inicio' })
    if ($hbNombre -ceq ([string]$Config.Nombre).Trim() -and $hbPag -ceq [string]$Config.PaginaInicial) { return }
    try { Guardar-ConfigLocal @{ Nombre = $hbNombre; PaginaInicial = $hbPag } } catch { Escribir-Log ("General: " + $_.Exception.Message); return }
    try { if ($paginaInicio.IsVisible) { Pintar-Inicio } } catch {}
}
$GenNombre.Add_LostKeyboardFocus({ Guardar-General })
$GenNombre.Add_KeyDown({ param($s, $a) if ($a.Key -eq [System.Windows.Input.Key]::Enter) { Guardar-General; $a.Handled = $true } })
$GenInicio.Add_SelectionChanged({ Guardar-General })

# ---------------------------------------------------------------- Este PC (con Guardar propio)
$script:pcAntes = $null
$script:usuarioMalo = $false
$script:enArchivo = ''

function Pc-Sucio {
    if (-not $script:pcAntes) { return $false }
    return ($PcIsos.Text.Trim() -cne $script:pcAntes.Isos) -or ($PcVms.Text.Trim() -cne $script:pcAntes.Vms) -or ($PcFichas.Text.Trim() -cne $script:pcAntes.Fichas) -or ($PcUsuario.Text.Trim() -cne $script:pcAntes.Usuario)
}

function Revisar-Pc {
    $hbRi = $PcIsos.Text.Trim()
    if ($hbRi -and (Test-Path -LiteralPath $hbRi)) {
        $hbN = @(Listar-Isos $hbRi).Count
        $PcIsosNota.Text = "$(Plural $hbN 'ISO encontrada' 'ISO encontradas') (también dentro de sus subcarpetas). Se detectan solas: puedes añadir más cuando quieras."
        $PcIsosNota.Foreground = Pincel $Colores.Suave
    } else {
        $PcIsosNota.Text = $(if ($hbRi) { 'Esa carpeta no existe.' } else { 'Elige la carpeta donde tienes las ISO.' })
        $PcIsosNota.Foreground = Pincel $Colores.Error
    }
    $hbRv = $PcVms.Text.Trim()
    if ($hbRv) {
        $PcVmsNota.Text = "Cada máquina en su subcarpeta; las bases en $(Join-Path $hbRv '_Bases')." + $(if (-not (Test-Path -LiteralPath $hbRv)) { ' (Se creará.)' } else { '' })
        $PcVmsNota.Foreground = Pincel $Colores.Suave
    } else { $PcVmsNota.Text = 'Elige una carpeta.'; $PcVmsNota.Foreground = Pincel $Colores.Error }

    $hbRf = $PcFichas.Text.Trim()
    if ($hbRf) {
        $PcFichasNota.Text = "Aquí se proponen guardar las fichas de «Laboratorio → Mis laboratorios»." + $(if (-not (Test-Path -LiteralPath $hbRf)) { ' (Se creará al hacer la primera.)' } else { '' }) + $(if ($hbRf -ceq (Carpeta-FichasPorDefecto)) { ' Es la carpeta de siempre.' } else { ' Vacío = ' + (Carpeta-FichasPorDefecto) + '.' })
        $PcFichasNota.Foreground = Pincel $Colores.Suave
    } else { $PcFichasNota.Text = 'Elige una carpeta (o deja la de siempre: ' + (Carpeta-FichasPorDefecto) + ').'; $PcFichasNota.Foreground = Pincel $Colores.Suave }

    $hbU = $PcUsuario.Text.Trim()
    $hbAvisos = @()
    if ($hbU -and $hbU -cnotmatch $patronUsuario) {
        $hbAvisos += $(if ($hbU -cmatch '[A-Z]') { "«$hbU» lleva mayúsculas: Linux no las admite en los usuarios. Ponlo en minúsculas (por ejemplo «$($hbU.ToLower())»)." } else { "«$hbU» no vale: solo minúsculas, números, guion o guion bajo (máximo 20), empezando por letra." })
    } elseif ($script:usuarioMalo -and $script:pcAntes -and $hbU -ceq $script:pcAntes.Usuario) {
        $hbAvisos += "En config.local.json ponía «$($script:enArchivo)», que no vale (Linux no admite mayúsculas), así que Full Cowl está usando «$($script:pcAntes.Usuario)». Al guardar se queda «$($script:pcAntes.Usuario)» apuntado."
    }
    if ($script:pcAntes -and $hbU -and $hbU -cmatch $patronUsuario -and $hbU -cne $script:pcAntes.Usuario) {
        $hbAvisos += "«$hbU» será para las bases que crees a partir de ahora. Las que ya tienes se quedan con su usuario, y las máquinas que hagas con ellas también (es una copia de la base)."
    }
    $PcUsuarioAvisoTexto.Text = $hbAvisos -join "`n`n"
    $PcUsuarioAviso.Visibility = $(if ($hbAvisos.Count) { 'Visible' } else { 'Collapsed' })
    $PcSucioTexto.Visibility = $(if (Pc-Sucio) { 'Visible' } else { 'Collapsed' })
}

function Cargar-Pc {
    # Pone en las cajas lo que hay guardado (sirve también para Descartar)
    $PcIsos.Text = $(if ($Config.CarpetaISOs) { [string]$Config.CarpetaISOs } else { '' })
    $PcVms.Text = $(if ($Config.CarpetaVMs) { [string]$Config.CarpetaVMs } else { Carpeta-VmsVmware })
    $PcFichas.Text = (Carpeta-FichasLab)
    $PcUsuario.Text = [string]$Config.Usuario
    $script:pcAntes = @{ Isos = $PcIsos.Text.Trim(); Vms = $PcVms.Text.Trim(); Fichas = $PcFichas.Text.Trim(); Usuario = $PcUsuario.Text.Trim() }
    $script:enArchivo = Usuario-EnArchivo
    $script:usuarioMalo = [bool]($script:enArchivo -and $script:enArchivo -cnotmatch $patronUsuario)
    $PcUsuarioNota.Text = 'Se crea al hacer cada base (administrador / sudo) y lo tienen todas sus máquinas. Solo minúsculas, números, guion o guion bajo, empezando por letra.'
    $hbBases = @(Obtener-Bases)
    if ($hbBases.Count) { $PcUsuarioNota.Text += "`nTus bases: " + (@($hbBases | ForEach-Object { "$($_.Nombre) ($($_.Usuario))" }) -join ', ') + '.' }
    Revisar-Pc
}

$PcIsos.Add_TextChanged({ Revisar-Pc })
$PcVms.Add_TextChanged({ Revisar-Pc })
$PcFichas.Add_TextChanged({ Revisar-Pc })
$PcUsuario.Add_TextChanged({ Revisar-Pc })
$BtnPcIsos.Add_Click({ Elegir-Carpeta $PcIsos 'Carpeta donde tienes las ISO de los sistemas' $ventana })
$BtnPcVms.Add_Click({ Elegir-Carpeta $PcVms 'Carpeta donde se guardarán las máquinas virtuales' $ventana })
$BtnPcFichas.Add_Click({ Elegir-Carpeta $PcFichas 'Carpeta donde guardar las fichas del laboratorio' $ventana })
$BtnPcDescartar.Add_Click({ Cargar-Pc })
$BtnPcGuardar.Add_Click({
    $hbRi = $PcIsos.Text.Trim(); $hbRv = $PcVms.Text.Trim(); $hbU = $PcUsuario.Text.Trim(); $hbRf = $PcFichas.Text.Trim()
    if (-not $hbRi -or -not (Test-Path -LiteralPath $hbRi)) { Aviso 'La carpeta de ISOs no existe.'; return }
    if (-not $hbRv) { Aviso 'Elige la carpeta de las máquinas.'; return }
    if ($hbU -cnotmatch $patronUsuario) { Aviso 'Usuario no válido: minúsculas, números, guion o guion bajo (máximo 20), empezando por letra.'; return }
    $hbUsuarioAntes = [string]$Config.Usuario
    if ($hbU -cne $hbUsuarioAntes) {
        if (-not (Pregunta "¿Cambiar el usuario de «$hbUsuarioAntes» a «$hbU»?`n`nSolo afecta a las bases nuevas. Las que ya tienes (y sus máquinas) siguen con su usuario; Full Cowl lo recuerda." 'Cambiar el usuario' 'Cambiar' 'Cancelar')) { return }
        # Las bases que aún no lo tienen apuntado se hicieron con el usuario de antes
        Marcar-UsuarioBases $hbUsuarioAntes
    }
    try { New-Item -ItemType Directory -Force -Path $hbRv | Out-Null } catch { Error-Amable 'No puedo usar la carpeta de máquinas.' 'Elige otra en Ajustes → Este PC.' $_.Exception.Message; return }
    # Si queda la carpeta de siempre (o vacía) no se apunta nada: así sigue a «Documentos» aunque lo muevas
    if ($hbRf -ceq (Carpeta-FichasPorDefecto)) { $hbRf = '' }
    Guardar-ConfigLocal @{ CarpetaISOs = $hbRi; CarpetaVMs = $hbRv; CarpetaFichas = $hbRf; Usuario = $hbU }
    Cargar-Pc
    # Carpetas nuevas: todo se vuelve a leer
    $script:labIniciado = $false
    try { Cargar } catch {}
    Mostrar-Toast 'Ajustes guardados.'
    Pintar-Hub
})

$BtnPcClave.Add_Click({
    # La ventana (dos cajas ocultas, guardada cifrada con DPAPI) vive en asistente.ps1 y la comparte el asistente
    if (Cambiar-PasswordVms 'Contraseña de las máquinas' 'Solo para este PC') { Mostrar-Toast 'Contraseña cambiada.' }
})

# ---------------------------------------------------------------- Actualizaciones
$script:modosAct = @('Avisar', 'Solo', 'No')
foreach ($hbTx in @('Avisarme', 'Actualizar solo', 'No buscar')) { [void]$ActModo.Items.Add($hbTx) }
$script:ayudasAct = @(
    'Al abrir, busca y te avisa en Inicio (lo normal).',
    'Al abrir, actualiza solo si no hay tareas en marcha ni archivos cambiados a mano.',
    'No busca nada al abrir. Siempre puedes buscar desde aquí.'
)
function Pintar-Act {
    $script:cargandoHub = $true
    try {
        $hbA = Estado-Actualizacion
        $ActTitulo.Text = $hbA.Linea1
        $ActDetalle.Text = $hbA.Linea2
        # la insignia solo se muestra si hay versión nueva («Está al día» ya lo dice el título)
        if ($hbA.Hay) { Poner-Insignia $ActBadge $ActBadgeTxt $hbA.Insignia 'T_avisoFondo' 'T_aviso' }
        else { Poner-Insignia $ActBadge $ActBadgeTxt '' '' '' }
        $BtnActAhora.Visibility = $(if ($hbA.Hay) { 'Visible' } else { 'Collapsed' })
        $hbI = [array]::IndexOf($script:modosAct, (Modo-Actualizaciones))
        $ActModo.SelectedIndex = $(if ($hbI -ge 0) { $hbI } else { 0 })
        $ActModoAyuda.Text = $script:ayudasAct[[Math]::Max(0, $ActModo.SelectedIndex)]
    } finally { $script:cargandoHub = $false }
}
$ActModo.Add_SelectionChanged({
    if ($script:cargandoHub -or $ActModo.SelectedIndex -lt 0) { return }
    try { Guardar-ConfigLocal @{ Actualizaciones = $script:modosAct[$ActModo.SelectedIndex] } } catch { Escribir-Log ("Actualizaciones: " + $_.Exception.Message) }
    $ActModoAyuda.Text = $script:ayudasAct[$ActModo.SelectedIndex]
})
$BtnActAhora.Add_Click({ Actualizar-Ahora })
$relojHubAct = New-Object System.Windows.Threading.DispatcherTimer
$relojHubAct.Interval = [TimeSpan]::FromMilliseconds(700)
$relojHubAct.Add_Tick({
    if (-not $script:buscandoAct) {
        $relojHubAct.Stop(); $BtnActBuscar.IsEnabled = $true; $BtnActBuscar.Content = 'Buscar actualizaciones'
        Pintar-Act; Pintar-Hub
    }
})
$BtnActBuscar.Add_Click({
    $BtnActBuscar.IsEnabled = $false; $BtnActBuscar.Content = 'Buscando…'
    Buscar-Actualizacion $false
    $relojHubAct.Start()
})

# ---------------------------------------------------------------- Ayuda y registros
function Abrir-Documento([string]$ruta, [string]$nombre = 'el archivo') {
    if (-not (Test-Path -LiteralPath $ruta)) { Aviso "No encuentro $nombre en esta carpeta."; return }
    try { Start-Process -FilePath $ruta } catch { try { Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$ruta`"" } catch { Error-Amable "No puedo abrir $nombre." 'Ábrelo a mano desde la carpeta de Full Cowl.' $_.Exception.Message } }
}
function Texto-InfoEquipo {
    # Solo versiones: sin rutas personales, sin usuario y sin contraseña
    $hbLin = New-Object System.Collections.Generic.List[string]
    $hbLin.Add("Full Cowl $(Version-Instalada)")
    try { $hbLin.Add("Windows $([Environment]::OSVersion.Version) ($(if ([Environment]::Is64BitOperatingSystem) { '64 bits' } else { '32 bits' }))") } catch {}
    try {
        $hbVm = Buscar-Vmrun -Silencioso
        $hbExe = Join-Path (Split-Path $hbVm) 'vmware.exe'
        $hbLin.Add("VMware Workstation $((Get-Item -LiteralPath $hbExe).VersionInfo.ProductVersion)")
    } catch { $hbLin.Add('VMware Workstation: no encontrado') }
    try {
        $hbPk = Obtener-Packer
        if (-not $hbPk) { throw 'sin packer' }
        $hbLin.Add("Packer $((Get-Item -LiteralPath $hbPk).VersionInfo.ProductVersion) · $(Origen-Packer)")
    } catch { $hbLin.Add('Packer: no encontrado') }
    $hbLin.Add("PowerShell $($PSVersionTable.PSVersion)")
    return ($hbLin -join "`n")
}
$BtnAyNovedades.Add_Click({ Abrir-Documento (Join-Path (Split-Path $dirFc) 'CHANGELOG.md') 'las novedades (CHANGELOG.md)' })
$BtnAyManual.Add_Click({ Abrir-Documento (Join-Path (Split-Path $dirFc) 'docs\MANUAL.md') 'el manual' })
$BtnAyRegistros.Add_Click({
    $hbE = Join-Path $dirFc 'estado'
    try { if (-not (Test-Path -LiteralPath $hbE)) { [void](New-Item -ItemType Directory -Path $hbE -Force) } } catch {}
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$hbE`"" } catch { Error-Amable 'No puedo abrir la carpeta de registros.' 'Ábrela a mano: está dentro de la carpeta de Full Cowl, en «full-cowl\estado».' $_.Exception.Message }
})
$BtnAyCopiar.Add_Click({
    try { Set-Clipboard -Value (Texto-InfoEquipo); Mostrar-Toast 'Información copiada.' } catch { Error-Amable 'No he podido copiar la información.' 'Vuelve a intentarlo en unos segundos.' $_.Exception.Message }
})
$HubRepetirAsistente.Add_Click({
    try {
        $res = Abrir-Asistente $true
        Aplicar-Tema (Tema-Efectivo)
        try { Aplicar-Apariencia $true } catch { Escribir-Log ("Repetir asistente, apariencia: " + $_.Exception.Message) }
        if ($res.Terminado) {
            if ($res.Destino -eq 'base') { $NavBase.IsChecked = $true } elseif ($res.Destino -eq 'importar') { $NavImportar.IsChecked = $true } elseif ($res.Destino -eq 'inicio') { $NavInicio.IsChecked = $true }
        }
    } catch { Escribir-Log ("Repetir asistente: " + ($_ | Out-String)); Error-Amable 'No se pudo abrir el asistente.' 'Prueba otra vez; si sigue igual, mira el registro.' $_.Exception.Message }
})

# ---------------------------------------------------------------- navegación
function Salir-DePcSeguro {
    # $true si se puede salir de «Este PC» (sin cambios, o el usuario los descarta)
    if (-not (Pc-Sucio)) { return $true }
    if (Pregunta 'Tienes cambios sin guardar en «Este PC». Si sales ahora, se pierden.' 'Cambios sin guardar' 'Salir sin guardar' 'Seguir aquí') { Cargar-Pc; return $true }
    return $false
}

function Ir-Seccion([string]$sec, [switch]$Forzar) {
    if (-not $script:hubSecciones.Contains($sec)) { $sec = 'portada' }
    if (-not $Forzar -and $script:seccionHub -eq 'pc' -and $sec -ne 'pc') { if (-not (Salir-DePcSeguro)) { Poner-Pildoras 'pc'; return } }
    $script:seccionHub = $sec
    foreach ($hbK in $script:hubSecciones.Keys) { $script:hubSecciones[$hbK].Panel.Visibility = 'Collapsed' }
    $hbDest = $script:hubSecciones[$sec]
    $HubBarra.Visibility = $(if ($sec -eq 'portada') { 'Collapsed' } else { 'Visible' })
    $Migas.Text = $(if ($sec -eq 'portada') { 'Full Cowl  ›  Ajustes' } else { "Full Cowl  ›  Ajustes  ›  $($hbDest.Titulo)" })
    Poner-Pildoras $sec
    # Cada apartado se pone al día al entrar
    try {
        switch ($sec) {
            'portada'    { Pintar-Hub }
            'apariencia' { Leer-Apariencia; Pintar-VistaPrevia }
            'act'        { Pintar-Act }
            'general'    { Cargar-General }
            'pc'         { Cargar-Pc }
            'espacio'    { Entrar-Espacio }
            'ayuda'      { $AyVersion.Text = "Full Cowl $(Version-Instalada)" }
        }
    } catch { Escribir-Log ("Ajustes ($sec): " + ($_ | Out-String)) }
    $hbDest.Panel.Visibility = 'Visible'
    Entrada-Pantalla $hbDest.Panel
}

function Poner-Pildoras([string]$sec) {
    $script:cargandoHub = $true
    try { foreach ($hbK in $script:hubSecciones.Keys) { $hbP = $script:hubSecciones[$hbK].Pill; if ($hbP) { $hbP.IsChecked = ($hbK -eq $sec) } } }
    finally { $script:cargandoHub = $false }
}

$HubVolver.Add_Click({ Ir-Seccion 'portada' })
# (sin GetNewClosure: un cierre no ve las funciones del script y daba «Ir-Seccion no se reconoce»)
$script:alPulsarPastilla = { param($s, $a) Ir-Seccion ([string]$s.Tag) }
foreach ($hbK in @('apariencia', 'act', 'general', 'pc', 'espacio', 'ayuda')) {
    $script:hubSecciones[$hbK].Pill.Tag = $hbK
    $script:hubSecciones[$hbK].Pill.Add_Click($script:alPulsarPastilla)
}
$TarjAp.Add_Click({ Ir-Seccion 'apariencia' })
$TarjAct.Add_Click({ Ir-Seccion 'act' })
$TarjGen.Add_Click({ Ir-Seccion 'general' })
$TarjPc.Add_Click({ Ir-Seccion 'pc' })
$TarjAy.Add_Click({ Ir-Seccion 'ayuda' })
$TarjEsp.Add_Click({ Ir-Seccion 'espacio' })
