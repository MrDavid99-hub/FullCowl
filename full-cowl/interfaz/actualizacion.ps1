# =====================================================================
#  Interfaz nueva: actualizar Full Cowl desde dentro
#  La lógica está en actualizar.ps1 (raíz del repositorio; es la misma que usa Actualizar.bat):
#    -Buscar            mira si hay versión nueva (git fetch; no cambia ningún archivo) y deja el
#                       resultado en estado\actualizacion.json. Aquí se lanza en segundo plano, sin ventana.
#    -Interfaz          lo lanza «Actualizar ahora»: espera a que Full Cowl se cierre, actualiza y lo reabre.
#  Ajustes: «Actualizaciones» = Avisar (por defecto) · Solo (al abrir, en abrir-nueva.ps1) · No.
# =====================================================================
$script:actualizacion = $null       # último resultado de buscar (objeto del JSON) o $null
$script:buscandoAct = $null         # proceso de la búsqueda en marcha
$script:buscandoManual = $false
$script:scriptActualizar = Join-Path (Split-Path $dirFc) 'actualizar.ps1'
$script:jsonActualizacion = Join-Path $dirFc 'estado\actualizacion.json'
$script:comandoGit = 'winget install --id Git.Git -e --source winget'

function Modo-Actualizaciones {
    $m = [string]$Config.Actualizaciones
    if ($m -in @('Avisar', 'Solo', 'No')) { return $m }
    return 'Avisar'
}

function Buscar-Actualizacion([bool]$manual = $false) {
    # En segundo plano: no retrasa nada. Al terminar, Terminar-Busqueda recoge el resultado.
    if ($script:buscandoAct) { return }
    if (-not (Test-Path -LiteralPath $script:scriptActualizar)) { if ($manual) { Aviso 'No encuentro actualizar.ps1 en la carpeta de Full Cowl.' }; return }
    $script:buscandoManual = $manual
    try { Remove-Item -LiteralPath $script:jsonActualizacion -Force -ErrorAction SilentlyContinue } catch {}
    $psi = New-Object System.Diagnostics.ProcessStartInfo((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), "-NoProfile -ExecutionPolicy Bypass -File `"$script:scriptActualizar`" -Buscar")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    try { $script:buscandoAct = [System.Diagnostics.Process]::Start($psi) } catch { $script:buscandoAct = $null; if ($manual) { Error-Amable 'No he podido comprobar si hay versión nueva.' 'Mira tu conexión y vuelve a pulsar «Buscar actualizaciones».' $_.Exception.Message }; return }
    $script:inicioBusqueda = Get-Date
    $relojBuscarAct.Start()
}

$relojBuscarAct = New-Object System.Windows.Threading.DispatcherTimer
$relojBuscarAct.Interval = [TimeSpan]::FromMilliseconds(700)
$relojBuscarAct.Add_Tick({
    try {
        $p = $script:buscandoAct
        if ($p -and -not $p.HasExited -and ((Get-Date) - $script:inicioBusqueda).TotalSeconds -lt 25) { return }
        $relojBuscarAct.Stop()
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
        $script:buscandoAct = $null
        Terminar-Busqueda
    } catch { $relojBuscarAct.Stop(); $script:buscandoAct = $null }
})

function Terminar-Busqueda {
    $manual = $script:buscandoManual; $script:buscandoManual = $false
    $r = $null
    try { if (Test-Path -LiteralPath $script:jsonActualizacion) { $r = [IO.File]::ReadAllText($script:jsonActualizacion, [Text.Encoding]::UTF8) | ConvertFrom-Json } } catch {}
    if (-not $r) { if ($manual) { Aviso 'No se pudo buscar actualizaciones.' }; return }
    $script:actualizacion = $r
    $script:ultimaRevision = [string]$r.fecha
    Poner-PuntoActualizacion
    try { if ($paginaHub.IsVisible) { if ($script:seccionHub -eq 'act') { Pintar-Act }; if ($script:seccionHub -eq 'portada') { Pintar-Hub } } } catch {}
    if ($paginaInicio.IsVisible) { try { Pintar-Inicio } catch {} }
    if (-not $manual) { return }
    if ($r.sinGit) { Aviso-SinGit; return }
    if ($r.sinConexion) { Aviso 'No se pudo conectar con GitHub. Comprueba la conexión a Internet y vuelve a probar.' 'Actualizaciones'; return }
    if ($r.hayNueva) { Actualizar-Ahora } else { Mostrar-Toast "Full Cowl está al día (v$([string]$r.actual))." }
}

function Hay-Nueva { return ($script:actualizacion -and $script:actualizacion.hayNueva) }

function Poner-PuntoActualizacion {
    # Puntito junto a la versión del menú cuando hay una nueva
    $PuntoAct.Visibility = $(if (Hay-Nueva) { 'Visible' } else { 'Collapsed' })
    if (Hay-Nueva) { $PuntoAct.ToolTip = "Hay una versión nueva de Full Cowl ($([string]$script:actualizacion.actual) → $([string]$script:actualizacion.nueva))" }
}

function Aviso-SinGit {
    if (Pregunta "Para buscar actualizaciones hace falta Git y no está instalado en este PC.`n`nSe instala abriendo PowerShell o el Terminal y escribiendo:`n`n$script:comandoGit" 'Falta Git' 'Copiar comando' 'Cerrar' 'BotonPrimario') {
        try { Set-Clipboard -Value $script:comandoGit; Mostrar-Toast 'Comando copiado.' } catch {}
    }
}

function Aviso-Actualizacion {
    # Para el bloque «Avisos» de Inicio: @{ Icono; Color; Texto; Accion; Boton } o $null
    $r = $script:actualizacion
    if (-not $r) { return $null }
    if ($r.sinGit) {
        return @{ Icono = 'Aviso'; Color = $Colores.Aviso; Nav = $null; Boton = 'Copiar comando'
                  Texto = "No se puede buscar actualizaciones porque Git no está instalado ($script:comandoGit)."
                  Accion = { try { Set-Clipboard -Value $script:comandoGit; Mostrar-Toast 'Comando copiado.' } catch {} } }
    }
    if (-not $r.hayNueva) { return $null }
    $txt = "Hay una versión nueva de Full Cowl ($([string]$r.actual) → $([string]$r.nueva))."
    $cambiosAct = @($r.cambios)
    if ($cambiosAct.Count) { $txt += ' Lo nuevo: ' + (($cambiosAct | Select-Object -First 3) -join '; ') + '.' }
    if ($r.mayor) { $txt += ' ES UNA VERSIÓN MAYOR: puede obligar a rehacer bases o ajustes (mira el CHANGELOG antes).' }
    return @{ Icono = $(if ($r.mayor) { 'Aviso' } else { 'Info' }); Color = $(if ($r.mayor) { $Colores.Error } else { $Colores.Verde }); Nav = $null
              Texto = $txt; Boton = 'Actualizar ahora'; Accion = { Actualizar-Ahora } }
}

function Actualizar-Ahora {
    $r = $script:actualizacion
    if (-not $r -or -not $r.hayNueva) { Buscar-Actualizacion $true; return }
    $tareas = @(Tareas-EnMarcha)
    if ($tareas.Count) {
        Aviso "Hay una tarea en marcha ($($tareas[0].Titulo)). Espera a que termine para actualizar." 'Actualizar Full Cowl'
        return
    }
    $texto = "Full Cowl se cerrará, se actualizará ($([string]$r.actual) → $([string]$r.nueva)) y se volverá a abrir. Tus máquinas y tus ajustes no se tocan."
    if ($r.mayor) { $texto += "`n`nOJO: es una versión mayor. Puede obligar a rehacer bases o ajustes; mira antes el CHANGELOG." }
    $nLocal = 0; try { $nLocal = [int]$r.cambiosLocales } catch {}
    if ($nLocal -gt 0) { $texto += "`n`nHay $(Plural $nLocal 'archivo cambiado a mano' 'archivos cambiados a mano') en la carpeta de Full Cowl: esos cambios se perderán." }
    else { $texto += "`n`nSi has editado a mano algún archivo de la carpeta de Full Cowl, ese cambio se perderá." }
    if (-not (Pregunta $texto 'Actualizar Full Cowl' 'Actualizar' 'Ahora no')) { return }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo((Join-Path $env:SystemRoot 'System32\conhost.exe'), "--headless `"$(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')`" -NoProfile -ExecutionPolicy Bypass -File `"$script:scriptActualizar`" -Interfaz -EsperarPid $PID")
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        [void][System.Diagnostics.Process]::Start($psi)
    } catch { Error-Msg "No se pudo lanzar la actualización:`n$($_.Exception.Message)"; return }
    $ventana.Close()
}

function Avisar-ResultadoActualizacion {
    # Al abrir: si acaba de actualizarse (o falló), se cuenta una vez
    $dirE = Join-Path $dirFc 'estado'
    $ok = Join-Path $dirE 'actualizado.json'
    $mal = Join-Path $dirE 'actualizar-error.json'
    try {
        if (Test-Path -LiteralPath $mal) {
            $m = [IO.File]::ReadAllText($mal, [Text.Encoding]::UTF8) | ConvertFrom-Json
            Remove-Item -LiteralPath $mal -Force -ErrorAction SilentlyContinue
            Aviso "No se pudo actualizar Full Cowl; sigue la versión de antes.`n`n$([string]$m.mensaje)`n`nEl detalle está en full-cowl\estado\actualizar.log." 'Actualizar Full Cowl'
        }
        if (Test-Path -LiteralPath $ok) {
            $m = [IO.File]::ReadAllText($ok, [Text.Encoding]::UTF8) | ConvertFrom-Json
            Remove-Item -LiteralPath $ok -Force -ErrorAction SilentlyContinue
            $t = "Full Cowl se ha actualizado a la versión $([string]$m.a)."
            $cambiosAct = @($m.cambios)
            if ($cambiosAct.Count) { $t += "`n`nLo nuevo:`n- " + (($cambiosAct | Select-Object -First 5) -join "`n- ") }
            if (Pregunta $t 'Actualizado' 'Ver todos los cambios' 'Cerrar') {
                try { Start-Process -FilePath (Join-Path (Split-Path $dirFc) 'CHANGELOG.md') } catch {}
            }
        }
    } catch {}
}

# Al abrir: buscar en silencio (sin consola, sin retrasar la apertura) salvo que se haya elegido «No buscar»
function Empezar-Actualizaciones {
    Poner-PuntoActualizacion
    Avisar-ResultadoActualizacion
    if ((Modo-Actualizaciones) -ne 'No') { Buscar-Actualizacion $false }
}
