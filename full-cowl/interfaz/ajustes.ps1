# =====================================================================
#  Interfaz nueva: «Ajustes de este PC»
#  Carpetas de ISOs y de máquinas y usuario de las VMs (config.local.json).
#  Es lo mismo que el botón Ajustes de la ventana de siempre, y también sale
#  solo la primera vez que se abre Full Cowl en un PC.
# =====================================================================
Add-Type -AssemblyName System.Windows.Forms   # (solo para la ventanita de elegir carpeta)

$patronUsuario = '^[a-z_][a-z0-9_-]{0,19}$'

function Carpeta-VmsVmware {
    # Carpeta de máquinas que tiene VMware Workstation configurada en este PC
    try {
        $prefsVm = Join-Path $env:APPDATA 'VMware\preferences.ini'
        foreach ($l in [IO.File]::ReadAllLines($prefsVm)) { if ($l -match '^\s*prefvmx\.defaultVMPath\s*=\s*"(.+)"') { return $Matches[1] } }
    } catch {}
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Virtual Machines')
}

function Usuario-EnArchivo {
    # Lo que pone de verdad en config.local.json (config.ps1 lo cambia por «alumno» si no vale)
    try { return [string](([IO.File]::ReadAllText($ArchivoConfigLocal, [Text.Encoding]::UTF8) | ConvertFrom-Json).Usuario) } catch { return '' }
}

function Elegir-Carpeta($caja, [string]$titulo, $ventanaDuena) {
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = $titulo; $fb.ShowNewFolderButton = $true
    if ($caja.Text -and (Test-Path -LiteralPath $caja.Text)) { $fb.SelectedPath = $caja.Text }
    # Que salga encima de la ventana de Ajustes y no detrás
    $duenaWin = New-Object System.Windows.Forms.NativeWindow
    try {
        $duenaWin.AssignHandle((New-Object System.Windows.Interop.WindowInteropHelper($ventanaDuena)).Handle)
        if ($fb.ShowDialog($duenaWin) -eq 'OK') { $caja.Text = $fb.SelectedPath }
    } finally { $duenaWin.ReleaseHandle(); $fb.Dispose() }
}

function Abrir-Ajustes([bool]$primeraVez = $false) {
    # Devuelve $true si se guardó algo
    $e = Nuevo-Dialogo 'dialogo-ajustes.xaml' $(if ($primeraVez) { 'Bienvenido a Full Cowl' } else { 'Ajustes de este PC' }) $(if ($primeraVez) { 'Primera configuración de este PC' } else { $env:COMPUTERNAME }) 600
    $e.AjIsos.Text = $(if ($Config.CarpetaISOs) { [string]$Config.CarpetaISOs } else { '' })
    $e.AjVms.Text = $(if ($Config.CarpetaVMs) { [string]$Config.CarpetaVMs } else { Carpeta-VmsVmware })
    $usuarioAntes = [string]$Config.Usuario
    $e.AjUsuario.Text = $usuarioAntes
    $e.AjUsuarioNota.Text = 'Se crea al hacer cada base (administrador / sudo) y lo tienen todas sus máquinas. Solo minúsculas, números, guion o guion bajo, empezando por letra.'
    # Con qué usuario se hizo cada base (las máquinas llevan el de su base, no el de aquí)
    $basesAhora = @(Obtener-Bases)
    if ($basesAhora.Count) {
        $e.AjUsuarioNota.Text += "`nTus bases: " + (@($basesAhora | ForEach-Object { "$($_.Nombre) ($($_.Usuario))" }) -join ', ') + '.'
    }
    if ($primeraVez) { $e.BtnAjNo.Content = 'Salir' }
    # Actualizaciones: versión instalada, buscar a mano y qué hacer al abrir
    $modosAct = @('Avisar', 'Solo', 'No')
    foreach ($tx in @('Avisarme', 'Actualizar solo', 'No buscar')) { [void]$e.AjActModo.Items.Add($tx) }
    $indAct = [array]::IndexOf($modosAct, (Modo-Actualizaciones))
    $e.AjActModo.SelectedIndex = $(if ($indAct -ge 0) { $indAct } else { 0 })
    $versionAjustes = ''; try { $versionAjustes = ([IO.File]::ReadAllText((Join-Path (Split-Path $dirFc) 'VERSION'))).Trim() } catch {}
    $textoAct = {
        $t = "Versión instalada: $versionAjustes"
        if ($script:ultimaRevision) { $t += "  ·  última revisión: $script:ultimaRevision" }
        $r = $script:actualizacion
        if ($r) {
            if ($r.sinGit) { $t += "`nGit no está instalado: $script:comandoGit" }
            elseif ($r.sinConexion) { $t += "`nNo se pudo conectar con GitHub." }
            elseif ($r.hayNueva) { $t += "`nHay una versión nueva ($([string]$r.nueva)). Cierra Ajustes y pulsa «Actualizar ahora» en Inicio." }
            else { $t += "`nEstá al día." }
        }
        $e.AjActInfo.Text = $t
    }
    & $textoAct
    $relojAjAct = New-Object System.Windows.Threading.DispatcherTimer
    $relojAjAct.Interval = [TimeSpan]::FromMilliseconds(700)
    $relojAjAct.Add_Tick({ if (-not $script:buscandoAct) { $relojAjAct.Stop(); $e.BtnAjBuscarAct.IsEnabled = $true; $e.BtnAjBuscarAct.Content = 'Buscar actualizaciones'; & $textoAct } })
    $e.BtnAjBuscarAct.Add_Click({
        $e.BtnAjBuscarAct.IsEnabled = $false; $e.BtnAjBuscarAct.Content = 'Buscando…'
        Buscar-Actualizacion $false
        $relojAjAct.Start()
    })
    $e.Ventana.Add_Closed({ $relojAjAct.Stop() })
    $e.AjNombre.Text = [string]$Config.Nombre
    [void]$e.AjPaginaInicial.Items.Add('Inicio')
    [void]$e.AjPaginaInicial.Items.Add('Mis máquinas')
    $e.AjPaginaInicial.SelectedIndex = $(if ([string]$Config.PaginaInicial -eq 'Maquinas') { 1 } else { 0 })

    # Si config.local.json trae un usuario que no vale (p. ej. con mayúsculas), se está usando «alumno»: avisarlo
    $enArchivo = Usuario-EnArchivo
    $usuarioMalo = $enArchivo -and $enArchivo -cnotmatch $patronUsuario

    $revisar = {
        $ri = $e.AjIsos.Text.Trim()
        if ($ri -and (Test-Path -LiteralPath $ri)) {
            $n = @(Listar-Isos $ri).Count
            $e.AjIsosNota.Text = "$(Plural $n 'ISO encontrada' 'ISO encontradas') (también dentro de sus subcarpetas). Se detectan solas: puedes añadir más cuando quieras."
            $e.AjIsosNota.Foreground = Pincel $Colores.Suave
        } else {
            $e.AjIsosNota.Text = $(if ($ri) { 'Esa carpeta no existe.' } else { 'Elige la carpeta donde tienes las ISO.' })
            $e.AjIsosNota.Foreground = Pincel $Colores.Error
        }
        $rv = $e.AjVms.Text.Trim()
        if ($rv) {
            $e.AjVmsNota.Text = "Cada máquina en su subcarpeta; las bases en $(Join-Path $rv '_Bases')." + $(if (-not (Test-Path -LiteralPath $rv)) { ' (Se creará.)' } else { '' })
            $e.AjVmsNota.Foreground = Pincel $Colores.Suave
        } else { $e.AjVmsNota.Text = 'Elige una carpeta.'; $e.AjVmsNota.Foreground = Pincel $Colores.Error }

        $u = $e.AjUsuario.Text.Trim()
        $avisos = @()
        if ($u -and $u -cnotmatch $patronUsuario) {
            $avisos += $(if ($u -cmatch '[A-Z]') { "«$u» lleva mayúsculas: Linux no las admite en los usuarios. Ponlo en minúsculas (por ejemplo «$($u.ToLower())»)." } else { "«$u» no vale: solo minúsculas, números, guion o guion bajo, empezando por letra (máximo 20)." })
        } elseif ($usuarioMalo -and $u -ceq $usuarioAntes) {
            $avisos += "En config.local.json ponía «$enArchivo», que no vale (Linux no admite mayúsculas), así que Full Cowl está usando «$usuarioAntes». Al guardar se queda «$usuarioAntes» apuntado."
        }
        if ($u -and $u -cmatch $patronUsuario -and $u -cne $usuarioAntes -and -not $primeraVez) {
            $avisos += "«$u» será para las bases que crees a partir de ahora. Las que ya tienes se quedan con su usuario, y las máquinas que hagas con ellas también (es una copia de la base). Para tener «$u» en todo, vuelve a crear las bases en «Crear base»."
        }
        $e.AjUsuarioAvisoTexto.Text = $avisos -join "`n`n"
        $e.AjUsuarioAviso.Visibility = $(if ($avisos.Count) { 'Visible' } else { 'Collapsed' })
    }
    & $revisar
    $e.AjIsos.Add_TextChanged({ & $revisar })
    $e.AjVms.Add_TextChanged({ & $revisar })
    $e.AjUsuario.Add_TextChanged({ & $revisar })
    $e.BtnAjIsos.Add_Click({ Elegir-Carpeta $e.AjIsos 'Carpeta donde tienes las ISO de los sistemas' $e.Ventana })
    $e.BtnAjVms.Add_Click({ Elegir-Carpeta $e.AjVms 'Carpeta donde se guardarán las máquinas virtuales' $e.Ventana })
    $e.BtnAjNo.Add_Click({ $e.Ventana.Close() })
    $resultado = @{ Guardado = $false }
    $e.BtnAjOk.Add_Click({
        $ri = $e.AjIsos.Text.Trim(); $rv = $e.AjVms.Text.Trim(); $u = $e.AjUsuario.Text.Trim()
        if (-not $ri -or -not (Test-Path -LiteralPath $ri)) { Aviso 'La carpeta de ISOs no existe.'; return }
        if (-not $rv) { Aviso 'Elige la carpeta de las máquinas.'; return }
        if ($u -cnotmatch $patronUsuario) { Aviso 'Usuario no válido: minúsculas, números, guion o guion bajo (máximo 20), empezando por letra.'; return }
        if ($u -cne $usuarioAntes -and -not $primeraVez) {
            if (-not (Pregunta "¿Cambiar el usuario de «$usuarioAntes» a «$u»?`n`nSolo afecta a las bases nuevas. Las que ya tienes (y sus máquinas) siguen con su usuario; Full Cowl lo recuerda." 'Cambiar el usuario' 'Cambiar' 'Cancelar')) { return }
            # Las bases que aún no lo tienen apuntado se hicieron con el usuario de antes
            Marcar-UsuarioBases $usuarioAntes
        }
        try { New-Item -ItemType Directory -Force -Path $rv | Out-Null } catch { Aviso "No se pudo crear la carpeta de máquinas:`n$($_.Exception.Message)"; return }
        Guardar-ConfigLocal @{ CarpetaISOs = $ri; CarpetaVMs = $rv; Usuario = $u; Actualizaciones = $modosAct[[Math]::Max(0, $e.AjActModo.SelectedIndex)]; Nombre = $e.AjNombre.Text.Trim(); PaginaInicial = $(if ($e.AjPaginaInicial.SelectedIndex -eq 1) { 'Maquinas' } else { 'Inicio' }) }
        $resultado.Guardado = $true
        $e.Ventana.Close()
    })
    [void]$e.Ventana.ShowDialog()
    return $resultado.Guardado
}
