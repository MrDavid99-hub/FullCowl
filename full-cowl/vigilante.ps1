# =====================================================================
#  Vigilante de máquinas desechables y del progreso (proceso oculto, uno solo a la vez)
#
#  Progreso: las máquinas nuevas publican su paso en guestinfo.vmtareas.progreso (desde
#  dentro, con las VMware Tools); aquí se lee con vmrun y se guarda en estado\progreso.json
#  para la ventana. Cuando termina un laboratorio (o una máquina suelta) sale un aviso.
#
#  Las máquinas desechables llevan en su .vmx  guestinfo.vmtareas.desechable = <grupo>.
#  Un grupo es un laboratorio (o una máquina suelta). Cuando TODAS las máquinas
#  del grupo están apagadas (no suspendidas) desde hace 30 s, y alguna llegó a
#  encenderse, se borran del disco. Reiniciar no cuenta como apagar.
#  Se cierra solo cuando ya no queda ninguna desechable ni ninguna máquina configurándose.
#  Registro: estado\vigilante.log
# =====================================================================
$EsVentana = $true            # proceso oculto: nada de preguntas por consola
. "$PSScriptRoot\comun.ps1"
if (-not (Config-Completa)) { exit }

$mutex = New-Object System.Threading.Mutex($false, 'Local\FullCowlVigilante')
if (-not $mutex.WaitOne(0)) { exit }   # ya hay otro vigilando

$vmrun = Buscar-Vmrun -Silencioso
if (-not $vmrun) { exit }
$dirEstado = Join-Path $PSScriptRoot 'estado'
New-Item -ItemType Directory -Force -Path $dirEstado | Out-Null
$log = Join-Path $dirEstado 'vigilante.log'
$archivoVistos = Join-Path $dirEstado 'desechables.json'
function L($t) { try { Add-Content -Path $log -Value "$(Get-Date -Format 'dd/MM HH:mm:ss')  $t" -Encoding UTF8 } catch {} }


# Grupos que ya se han visto encendidos (sobrevive a reinicios del PC)
$vistos = @{}
try { foreach ($prop in ([IO.File]::ReadAllText($archivoVistos) | ConvertFrom-Json).PSObject.Properties) { $vistos[$prop.Name] = $true } } catch {}
function Guardar-Vistos { try { [IO.File]::WriteAllText($archivoVistos, ($vistos | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) } catch {} }

$apagadoDesde = @{}
$fallos = @{}
$vueltasSinNada = 0
$sinRespuesta = $false

# ---- Progreso de las máquinas que se están configurando
$archivoProgreso = Join-Path $dirEstado 'progreso.json'
$finales = @('ok', 'fallos', 'error')
$progreso = @{}            # vmx (minúsculas) -> datos del paso
$avisados = New-Object System.Collections.ArrayList   # laboratorios ya avisados
try {
    $j = [IO.File]::ReadAllText($archivoProgreso) | ConvertFrom-Json
    foreach ($prop in $j.maquinas.PSObject.Properties) { $progreso[$prop.Name] = $prop.Value }
    foreach ($a in @($j.avisados)) { if ($a) { [void]$avisados.Add([string]$a) } }
} catch {}
$script:ultimoProgreso = ''
function Guardar-Progreso {
    $txt = [ordered]@{ maquinas = $progreso; avisados = @($avisados | Select-Object -Last 50) } | ConvertTo-Json -Depth 5
    if ($txt -eq $script:ultimoProgreso) { return }
    try { [IO.File]::WriteAllText($archivoProgreso, $txt, [Text.UTF8Encoding]::new($false)); $script:ultimoProgreso = $txt } catch {}
}

function Revisar-Progreso($clones, $encendidas) {
    # Devuelve cuántas máquinas siguen pendientes (configurándose o recién creadas sin arrancar)
    $ahoraEp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $pendientes = 0
    $nuevo = @{}
    $terminadas = @()
    foreach ($m in $clones) {
        if (-not (Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.agente')) { continue }
        $k = $m.Vmx.ToLower()
        $creada = [int64]0; [void][int64]::TryParse([string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.creada'), [ref]$creada)
        $reciente = $creada -gt 0 -and ($ahoraEp - $creada) -lt 3600
        $ant = $progreso[$k]
        if ($encendidas -notcontains $k) {
            # Apagada: si se acaba de crear y aún no ha arrancado, se espera (el laboratorio las arranca al final).
            # Si ya tenía progreso, se conserva tal cual: apagar una máquina de un laboratorio no la quita
            # de su barra (antes desaparecía y el laboratorio no llegaba a avisar de que estaba listo)
            if ($ant) { $nuevo[$k] = $ant }
            elseif ($reciente) { $pendientes++ }
            continue
        }
        if ($ant -and @('ok', 'fallos') -contains [string]$ant.estado) { $nuevo[$k] = $ant; continue }   # ya terminó (con 'error' se sigue mirando: reintenta al reiniciar)
        $lectura = Vmrun-ConLimite $vmrun @('-T', 'ws', 'readVariable', $m.Vmx, 'guestVar', 'vmtareas.progreso')
        if ($lectura.Agotado) {
            # VMware no contesta por esta máquina: se deja como estaba y se sigue con la siguiente (ficha 34)
            if ($ant) { $nuevo[$k] = $ant } elseif ($reciente) { $pendientes++ }
            continue
        }
        $valor = ([string]$lectura.Salida).Trim()
        $e = $null
        if ($valor -match '^1\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|([a-z]+)\|([a-z-]+)$') {
            $e = [ordered]@{ paso = [int]$Matches[1]; total = [int]$Matches[2]; esperado = [int]$Matches[3]; inicio = [int64]$Matches[4]
                             estado = $Matches[5]; clave = $Matches[6] }
        } elseif ($reciente) {
            # Aún no ha dicho nada: primer arranque de Windows/Linux (preparación del sistema)
            $ini = if ($ant -and $ant.clave -eq 'preparar') { [int64]$ant.inicio } else { $ahoraEp }
            $e = [ordered]@{ paso = 1; total = 0; esperado = 240; inicio = $ini; estado = 'curso'; clave = 'preparar' }
        } else { continue }   # máquina antigua o sin VMware Tools: nada que mostrar
        # La hora la pone este PC al ver cada paso nuevo, no la máquina: el reloj de un Linux recién clonado
        # suele ir una hora adelantado (lee el reloj de VMware, que va en hora local, como si fuera UTC) y los
        # contadores salían con una hora de más
        if ($ant -and [int]$ant.paso -eq $e.paso -and [string]$ant.estado -eq $e.estado -and [string]$ant.clave -eq $e.clave) {
            $e.inicio = [int64]$ant.inicio
        } elseif ($e.clave -ne 'preparar') {
            $e.inicio = $ahoraEp
        }
        # Extras (ficha 20): cómo va cada uno, según lo publica la máquina. Solo si se le pidieron.
        if ($e.clave -ne 'preparar' -and (Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.extras')) {
            $txtExtras = ''
            try { $txtExtras = ([string](Vmrun-ConLimite $vmrun @('-T', 'ws', 'readVariable', $m.Vmx, 'guestVar', 'vmtareas.extras.estado')).Salida).Trim() } catch {}
            $leidos = @(Leer-EstadoExtras $txtExtras)
            if ($leidos.Count) { $e.extras = (@($leidos | ForEach-Object { "$($_.Id)=$($_.Estado)" }) -join ';') }
            elseif ($ant -and $ant.extras) { $e.extras = [string]$ant.extras }
        }
        $e.nombre = $m.Nombre
        $e.lab = [string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.lab')
        $e.labid = [string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.labid')
        $e.base = [string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.base')
        $e.creada = $creada
        $e.visto = $ahoraEp
        $e.enCurso = [bool]($ant -and $ant.enCurso) -or ($finales -notcontains $e.estado)
        $nuevo[$k] = [pscustomobject]$e
        if ($finales -contains $e.estado) {
            if ($e.enCurso -and -not ($ant -and $finales -contains [string]$ant.estado)) { $terminadas += $nuevo[$k] }
        } else { $pendientes++ }
    }
    $progreso.Clear()
    foreach ($k in $nuevo.Keys) { $progreso[$k] = $nuevo[$k] }

    # Avisos: un laboratorio cuando han terminado todas sus máquinas; una máquina suelta al terminar
    foreach ($t in $terminadas) {
        if ($t.labid) {
            if ($avisados -contains $t.labid) { continue }
            $delLab = @($progreso.Values | Where-Object { $_.labid -eq $t.labid })
            $sinTerminar = @($delLab | Where-Object { $finales -notcontains [string]$_.estado })
            $apagadasNuevas = @($clones | Where-Object {
                [string](Leer-ValorVmx $_.Vmx 'guestinfo.vmtareas.labid') -eq $t.labid -and -not $progreso[$_.Vmx.ToLower()] })
            if ($sinTerminar.Count -or $apagadasNuevas.Count) { continue }
            [void]$avisados.Add([string]$t.labid)
            $malas = @($delLab | Where-Object { $_.estado -ne 'ok' } | ForEach-Object nombre)
            if ($malas.Count) { Aviso-Windows "Laboratorio '$($t.lab)' terminado, con avisos en: $($malas -join ', '). Mira 'Configuración de la VM' en su escritorio." }
            else { Aviso-Windows "Laboratorio '$($t.lab)' listo: ya puedes empezar a trabajar ($($delLab.Count) máquinas)." }
            L "Laboratorio listo: $($t.lab) ($(($delLab | ForEach-Object nombre) -join ', '))"
            # Estado inicial (ficha 28): si se pidió al crear el laboratorio, se guarda ahora que todas han terminado bien
            try {
                $pidenInicio = Leer-IniciosPendientes
                if ($pidenInicio.ContainsKey([string]$t.labid)) {
                    Quitar-InicioPendiente ([string]$t.labid)
                    $vmxLab = @($clones | Where-Object { [string](Leer-ValorVmx $_.Vmx 'guestinfo.vmtareas.labid') -eq [string]$t.labid } | ForEach-Object { $_.Vmx })
                    if ($malas.Count -or -not $vmxLab.Count) { L "Estado inicial de $($t.lab): no se guarda porque hubo avisos al configurar (se puede guardar a mano desde Laboratorio)" }
                    else {
                        L "Guardando el estado inicial de $($t.lab) ($($vmxLab.Count) máquinas)"
                        Lanzar-OperacionLab 'guardar' ([string]$t.lab) $vmxLab @('ApagarAntes', 'Aviso')
                    }
                }
            } catch { L "Error al lanzar el estado inicial: $_" }
        } else {
            if ($t.estado -eq 'ok') { Aviso-Windows "'$($t.nombre)' está lista: ya puedes trabajar con ella." }
            else { Aviso-Windows "'$($t.nombre)' terminó de configurarse con avisos. Mira 'Configuración de la VM' en su escritorio." }
            L "Máquina lista: $($t.nombre) ($($t.estado))"
        }
    }
    Guardar-Progreso
    return $pendientes
}
L 'Vigilante en marcha'

while ($true) {
    try {
        # Regla de oro (ficha 34): si VMware no contesta NO se sabe qué está encendido, y «no lo sé» nunca es «apagada».
        # Esa vuelta no se hace nada (ni borrar desechables, ni quitar marcas, ni tocar el progreso) y se vuelve a preguntar.
        $estadoEnc = Leer-Encendidas $vmrun
        if (-not $estadoEnc.Sabido) {
            if (-not $sinRespuesta) { L 'VMware no contesta a «list»: se espera sin tocar nada' }
            $sinRespuesta = $true
            Start-Sleep 10
            continue
        }
        if ($sinRespuesta) { L 'VMware vuelve a contestar'; $sinRespuesta = $false }
        $encendidas = @($estadoEnc.Lista)
        $conservar = @(Leer-Conservar)

        # Las que se marcaron para conservar estando encendidas: al apagarse, quitarles la marca
        $quedan = @()
        foreach ($vmx in $conservar) {
            if (-not $vmx -or -not (Test-Path -LiteralPath $vmx)) { continue }
            if ($encendidas -contains $vmx.ToLower()) { $quedan += $vmx; continue }
            Conservar-Maquina $vmx $false
            L "Conservada: $vmx"
        }
        if ($quedan.Count -ne $conservar.Count) { Guardar-Conservar $quedan }

        $clones = @(Leer-Clones)
        $pendientes = 0
        try { $pendientes = Revisar-Progreso $clones $encendidas } catch { L "Error en el progreso: $_" }

        # CD con la contraseña (máquinas con dominio): fuera en cuanto la máquina se apaga configurada
        foreach ($m in $clones) {
            if (-not $m.Externa -and $encendidas -notcontains $m.Vmx.ToLower()) { try { Limpiar-CdClave $m } catch {} }
        }

        # Agrupar las desechables (solo las de la carpeta de máquinas: una copia o una exportación
        # de una desechable que esté en otro sitio nunca se borra)
        $grupos = @{}
        foreach ($m in $clones) {
            if ($m.Externa) { continue }
            if ($quedan -contains $m.Vmx) { continue }
            $id = [string](Leer-ValorVmx $m.Vmx 'guestinfo.vmtareas.desechable')
            if (-not $id) { continue }
            if (-not $grupos.ContainsKey($id)) { $grupos[$id] = New-Object System.Collections.ArrayList }
            [void]$grupos[$id].Add($m)
        }
        if ($grupos.Count -eq 0 -and $quedan.Count -eq 0 -and $pendientes -eq 0) {
            $vueltasSinNada++
            if ($vueltasSinNada -ge 6) { L 'No quedan desechables ni máquinas configurándose: fin'; break }
        } else { $vueltasSinNada = 0 }

        foreach ($id in @($grupos.Keys)) {
            $maqs = @($grupos[$id])
            $activas = @($maqs | Where-Object {
                ($encendidas -contains $_.Vmx.ToLower()) -or [bool](Get-ChildItem -LiteralPath $_.Carpeta -Filter *.vmss -ErrorAction SilentlyContinue)
            })
            if ($activas.Count) {
                if (-not $vistos[$id]) { $vistos[$id] = $true; Guardar-Vistos; L "En uso: grupo $id ($(($maqs | ForEach-Object Nombre) -join ', '))" }
                $apagadoDesde.Remove($id)
                continue
            }
            if (-not $vistos[$id]) { continue }                    # todavía no se ha encendido nunca
            if (-not $apagadoDesde.ContainsKey($id)) { $apagadoDesde[$id] = Get-Date; continue }
            if (((Get-Date) - $apagadoDesde[$id]).TotalSeconds -lt 30) { continue }

            # Todas apagadas: borrar. Antes se vuelve a preguntar AHORA (mirar el progreso puede haber tardado):
            # si VMware no contesta o alguna se ha encendido entretanto, no se borra nada en esta vuelta
            $estadoAhora = Leer-Encendidas $vmrun
            if (-not $estadoAhora.Sabido) { L "Grupo $($id): VMware no contesta; no se borra en esta vuelta"; continue }
            $encAhora = @($estadoAhora.Lista)
            if (@($maqs | Where-Object { $encAhora -contains $_.Vmx.ToLower() }).Count) { $apagadoDesde.Remove($id); continue }
            $lab = [string](Leer-ValorVmx $maqs[0].Vmx 'guestinfo.vmtareas.lab')
            $nombres = ($maqs | ForEach-Object Nombre) -join ', '
            $restos = @()
            foreach ($m in $maqs) {
                $borrado = Vmrun-ConLimite $vmrun @('-T', 'ws', 'deleteVM', $m.Vmx)
                if ($borrado.Agotado) { L "deleteVM de $($m.Nombre): VMware no contestó en $($borrado.Limite) s; se reintenta en la próxima vuelta"; $restos += $m.Nombre; continue }
                if (Carpeta-BorrableSegura $m.Carpeta) {
                    for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $m.Carpeta); $i++) {
                        Remove-Item -LiteralPath $m.Carpeta -Recurse -Force -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $m.Carpeta) { Start-Sleep 2 }
                    }
                }
                if (Test-Path -LiteralPath $m.Vmx) { $restos += $m.Nombre }
            }
            if ($restos.Count) {
                $fallos[$id] = 1 + [int]$fallos[$id]
                L "No se pudo borrar todavía: $($restos -join ', ') (intento $($fallos[$id]))"
                if ($fallos[$id] -eq 3) { Aviso-Windows "No puedo borrar $($restos -join ', '). Cierra su pestaña en VMware y lo vuelvo a intentar." }
                continue
            }
            $vistos.Remove($id); Guardar-Vistos
            $apagadoDesde.Remove($id); $fallos.Remove($id)
            $que = if ($lab) { "Laboratorio '$lab' borrado ($($maqs.Count) máquina$(if ($maqs.Count -ne 1) { 's' }))" } else { "Máquina desechable '$nombres' borrada" }
            L "$($que): $nombres"
            Aviso-Windows "$que al apagarse."
        }
    } catch { L "Error: $_" }
    Start-Sleep 10
}
$mutex.ReleaseMutex()
