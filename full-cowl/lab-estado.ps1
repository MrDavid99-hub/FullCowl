param(
    [string]$Accion,        # guardar | volver | quitar
    [string]$Lab,           # nombre del laboratorio (solo para los textos y el archivo de progreso)
    [string]$Vmx,           # los .vmx de sus máquinas, separados por |
    [switch]$ApagarAntes,   # guardar: apagar con cortesía antes y volver a encender las que lo estaban (si no, se guarda con la memoria)
    [switch]$Encender,      # volver: dejar las máquinas encendidas al terminar (el controlador de dominio primero)
    [switch]$Parcial,       # volver: solo las que tienen estado inicial (si no, todo o nada)
    [switch]$Aviso          # al terminar, globo de Windows (lo pide el vigilante, que lo lanza con Full Cowl posiblemente cerrado)
)
# =====================================================================
#  Estado inicial de un laboratorio (ficha 28), sin ventana:
#    guardar  -> instantánea «inicio-lab» en todas sus máquinas, de una vez
#    volver   -> todas vuelven a «inicio-lab» (apagadas con cortesía, el controlador de dominio arranca primero)
#    quitar   -> borra las «inicio-lab»
#  Solo toca la instantánea «inicio-lab»: nunca «base» ni «inicio» ni las de otros laboratorios.
#  El progreso va a estado\lab\<laboratorio>.json (lo lee la ventana). No necesita la contraseña de las máquinas.
# =====================================================================
. "$PSScriptRoot\comun.ps1"
$ErrorActionPreference = 'Continue'
$nombreSnap = Nombre-EstadoInicial
$vmrun = Buscar-Vmrun -Silencioso
$dirOp = Carpeta-OperacionesLab
if (-not (Test-Path -LiteralPath $dirOp)) { New-Item -ItemType Directory -Path $dirOp -Force | Out-Null }
$archivoLog = Join-Path $dirOp 'lab-estado.log'
function Registrar([string]$texto) {
    try { Add-Content -LiteralPath $archivoLog -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}: {2}" -f (Get-Date), $Lab, $texto) -Encoding UTF8 } catch {}
}

# Otra operación en marcha sobre este laboratorio: no empezar (la ventana ya lo evita, esto es por si acaso)
$anterior = Leer-OperacionLab $Lab
if ($anterior -and [string]$anterior.estado -eq 'curso' -and [int]$anterior.pid -gt 0 -and [int]$anterior.pid -ne $PID) { Registrar 'Ya hay una operación en marcha; no se empieza otra.'; exit 0 }

$script:archivoEstado = Archivo-OperacionLab $Lab
$script:est = [ordered]@{ accion = $Accion; lab = $Lab; estado = 'curso'; paso = 'Preparando…'; actual = 0; total = 0; pct = 0
                          inicio = (Get-Date).ToString('o'); pid = $PID; mensaje = ''; resultado = @() }
$resultados = New-Object System.Collections.ArrayList
function Poner-Paso([string]$paso, [int]$actual, [double]$pct) {
    $script:est.paso = $paso; $script:est.actual = $actual; $script:est.pct = [Math]::Round([Math]::Min(100, [Math]::Max(0, $pct)), 1)
    Guardar-Estado
}
function Anotar([string]$nombre, [bool]$bien, [string]$mensaje) {
    [void]$resultados.Add([ordered]@{ nombre = $nombre; ok = $bien; mensaje = $mensaje })
}
function Texto-Salida($salida) { return (([string]($salida | Out-String)).Trim() -replace '\s+', ' ') }

# Todo vmrun va con límite de tiempo (ficha 34). Si VMware no contesta: fallo de ESA máquina y se sigue con las demás.
function Ejecutar-Vmrun($argumentos) { return (Vmrun-ConLimite $vmrun (@('-T', 'ws') + @($argumentos))) }
function Texto-Fallo($r) {
    # Por qué falló, en llano. Un tiempo agotado no es un «no»: VMware puede haber terminado igualmente
    if ($r.Agotado) { return "VMware tardó más de $(Formato-Limite $r.Limite) y no contestó (puede haber terminado igualmente: míralo en VMware)" }
    $t = Texto-Salida ("$($r.Salida) $($r.Error)")
    if (-not $t) { $t = "VMware dio el código $($r.Codigo)" }
    return $t
}
function Formato-Limite([int]$seg) { if ($seg -ge 120) { return "$([int]($seg / 60)) minutos" } return "$seg segundos" }
function Preguntar-Encendidas {
    # @{ Sabido; Lista }. «No contesta» no es «apagada»: se pregunta hasta 3 veces antes de rendirse
    $resp = $null
    for ($vez = 0; $vez -lt 3; $vez++) {
        $resp = Leer-Encendidas $vmrun
        if ($resp.Sabido) { return $resp }
        Registrar 'VMware no contesta a «list»; se vuelve a preguntar'
        Start-Sleep 5
    }
    return $resp
}

function Esperar-Tools([string]$vmxM, [int]$segundos) {
    $limite = (Get-Date).AddSeconds($segundos)
    while ((Get-Date) -lt $limite) {
        $r = Ejecutar-Vmrun @('checkToolsState', $vmxM)
        if (-not $r.Agotado -and ([string]$r.Salida).Trim() -eq 'running') { return $true }
        Start-Sleep 5
    }
    return $false
}

function Apagar-Maquinas($lista) {
    # Con cortesía (todas a la vez); a los 60 s, a la fuerza las que sigan encendidas
    # (si VMware no contesta a una pregunta, se da por «sigue encendida» y se vuelve a preguntar: nunca por apagada)
    $estadoEnc = Preguntar-Encendidas
    if (-not $estadoEnc.Sabido) { throw 'VMware no contesta y no se puede saber qué máquinas están encendidas. No se ha tocado nada: espera un poco (o cierra VMware y ábrelo de nuevo) y repite.' }
    $encendidas = @($estadoEnc.Lista)
    $on = @($lista | Where-Object { $encendidas -contains $_.Vmx.ToLower() })
    if (-not $on.Count) { return }
    foreach ($m in $on) { Iniciar-Oculto $vmrun "-T ws stop `"$($m.Vmx)`" soft" }
    $limite = (Get-Date).AddSeconds(60)
    $aun = $on
    while ($aun.Count -and (Get-Date) -lt $limite) {
        Start-Sleep 3
        $estadoEnc = Leer-Encendidas $vmrun
        if (-not $estadoEnc.Sabido) { continue }
        $enc = @($estadoEnc.Lista)
        $aun = @($on | Where-Object { $enc -contains $_.Vmx.ToLower() })
    }
    foreach ($m in $aun) {
        Registrar "No se apagó con cortesía: se apaga a la fuerza ($($m.Nombre))"
        $r = Ejecutar-Vmrun @('stop', $m.Vmx, 'hard')
        if ($r.Agotado) { Registrar "Apagar a la fuerza $($m.Nombre): $(Texto-Fallo $r)" }
    }
    $limite = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $limite) {
        Start-Sleep 2
        $estadoEnc = Leer-Encendidas $vmrun
        if (-not $estadoEnc.Sabido) { continue }
        $enc = @($estadoEnc.Lista)
        if (-not @($on | Where-Object { $enc -contains $_.Vmx.ToLower() }).Count) { break }
    }
}

function Encender-Maquinas($lista) {
    # El controlador de dominio primero y, antes de seguir con las demás, a que tenga VMware Tools. Devuelve los fallos
    $fallos = @()
    $orden = @(@($lista | Where-Object { $_.Dc }) + @($lista | Where-Object { -not $_.Dc }))
    $hayOtras = [bool]@($lista | Where-Object { -not $_.Dc }).Count
    foreach ($m in $orden) {
        $estadoEnc = Preguntar-Encendidas
        if (-not $estadoEnc.Sabido) { Registrar "No se sabe si $($m.Nombre) está encendida (VMware no contesta): no se enciende"; $fallos += "$($m.Nombre): VMware no contesta; enciéndela a mano"; continue }
        if (@($estadoEnc.Lista) -contains $m.Vmx.ToLower()) { continue }
        $r = Ejecutar-Vmrun @('start', $m.Vmx, 'gui')
        if ($r.Agotado) {
            # A veces VMware enciende la máquina pero no se lo confirma a vmrun: si ya está encendida, vale
            $estadoEnc = Preguntar-Encendidas
            if ($estadoEnc.Sabido -and (@($estadoEnc.Lista) -contains $m.Vmx.ToLower())) { Registrar "$($m.Nombre): VMware no confirmó el encendido, pero está encendida" }
            else { Registrar "No se pudo encender $($m.Nombre): $(Texto-Fallo $r)"; $fallos += "$($m.Nombre): no se pudo encender ($(Texto-Fallo $r))"; continue }
        } elseif ($r.Codigo -ne 0) { $salida = Texto-Fallo $r; Registrar "No se pudo encender $($m.Nombre): $salida"; $fallos += "$($m.Nombre): no se pudo encender ($salida)"; continue }
        if ($m.Dc -and $hayOtras) { if (-not (Esperar-Tools $m.Vmx 300)) { Registrar "El controlador $($m.Nombre) tardó más de 5 minutos en tener VMware Tools; se siguen encendiendo las demás" } }
        else { Start-Sleep 3 }
    }
    return $fallos
}

function Cerrar-Operacion([string]$verbo) {
    # Resumen final: «3 bien, 1 con problema: …»
    $malas = @($resultados | Where-Object { -not $_.ok })
    $buenas = $resultados.Count - $malas.Count
    $script:est.resultado = @($resultados)
    if (-not $malas.Count) { $script:est.estado = 'ok' }
    elseif ($buenas -gt 0) { $script:est.estado = 'parcial' }
    else { $script:est.estado = 'error' }
    $detalleMalas = (@($malas | ForEach-Object { "$($_.nombre): $($_.mensaje)" }) -join '; ')
    if (-not $malas.Count) { $script:est.mensaje = "$verbo en $buenas $(if ($buenas -eq 1) { 'máquina' } else { 'máquinas' }) de $Lab." }
    else { $script:est.mensaje = "$buenas bien, $($malas.Count) con problema: $detalleMalas" }
    $script:est.pct = 100
    $script:est.paso = 'Terminado'
    Guardar-Estado
    Registrar $script:est.mensaje
}

try {
    if (-not $vmrun) { throw 'No encuentro VMware Workstation (vmrun).' }
    if (@('guardar', 'volver', 'quitar') -notcontains $Accion) { throw "Acción desconocida: $Accion" }
    $maqs = @()
    foreach ($v in @($Vmx -split '\|' | Where-Object { $_ })) {
        if (-not (Test-Path -LiteralPath $v)) { continue }
        $nom = [string](Leer-ValorVmx $v 'displayName'); if (-not $nom) { $nom = [IO.Path]::GetFileNameWithoutExtension($v) }
        $maqs += [pscustomobject]@{ Nombre = $nom; Vmx = $v; Dc = [bool](Leer-ValorVmx $v 'guestinfo.vmtareas.dominio'); Tiene = (Tiene-EstadoInicial $v) }
    }
    $maqs = @($maqs | Sort-Object @{ Expression = { if ($_.Dc) { 0 } else { 1 } } }, Nombre)
    if (-not $maqs.Count) { throw 'No encuentro ninguna máquina del laboratorio.' }
    Registrar "Empieza: $Accion ($($maqs.Count) máquinas)$(if ($ApagarAntes) { ' apagando antes' })$(if ($Encender) { ' y dejándolas encendidas' })$(if ($Parcial) { ' solo las que se puede' })"

    switch ($Accion) {
        'guardar' {
            $script:est.total = $maqs.Count
            $estadoIni = Preguntar-Encendidas
            if (-not $estadoIni.Sabido) { throw 'VMware no contesta y no se puede saber qué máquinas están encendidas. No se ha tocado nada: espera un poco (o cierra VMware y ábrelo de nuevo) y repite.' }
            $encIni = @($estadoIni.Lista)
            $estabanOn = @($maqs | Where-Object { $encIni -contains $_.Vmx.ToLower() })
            if ($ApagarAntes -and $estabanOn.Count) {
                Poner-Paso 'Apagando las máquinas con cortesía…' 0 3
                Apagar-Maquinas $maqs
            }
            $i = 0
            foreach ($m in $maqs) {
                $i++
                Poner-Paso "Guardando el estado inicial $i de $($maqs.Count)" $i (8 + 80 * ($i - 1) / $maqs.Count)
                if ($m.Tiene) {
                    # el nuevo sustituye al anterior; si VMware no contesta al quitar el viejo, esta máquina se deja como está
                    $r = Ejecutar-Vmrun @('deleteSnapshot', $m.Vmx, $nombreSnap)
                    if ($r.Agotado) { $salida = Texto-Fallo $r; Registrar "Quitar el estado anterior de $($m.Nombre): $salida"; Anotar $m.Nombre $false $salida; continue }
                }
                $r = Ejecutar-Vmrun @('snapshot', $m.Vmx, $nombreSnap)
                if (-not $r.Agotado -and $r.Codigo -eq 0) { Anotar $m.Nombre $true '' } else { $salida = Texto-Fallo $r; Registrar "Instantánea de $($m.Nombre): $salida"; Anotar $m.Nombre $false $salida }
            }
            if ($ApagarAntes -and $estabanOn.Count) {
                Poner-Paso 'Volviendo a encender las máquinas…' $maqs.Count 90
                foreach ($f in @(Encender-Maquinas @($maqs | Where-Object { $estabanOn.Vmx -contains $_.Vmx }))) { Anotar 'Encender' $false $f }
            }
            Cerrar-Operacion 'Estado inicial guardado'
        }
        'volver' {
            $faltan = @($maqs | Where-Object { -not $_.Tiene })
            if ($faltan.Count -and -not $Parcial) { throw "Faltan máquinas sin estado inicial: $(($faltan | ForEach-Object Nombre) -join ', '). No se ha tocado nada." }
            $maqs = @($maqs | Where-Object { $_.Tiene })
            if (-not $maqs.Count) { throw 'Ninguna máquina tiene estado inicial guardado.' }
            $script:est.total = $maqs.Count
            Poner-Paso 'Apagando las máquinas con cortesía…' 0 3
            Apagar-Maquinas $maqs
            $i = 0
            foreach ($m in $maqs) {
                $i++
                Poner-Paso "Volviendo al estado inicial $i de $($maqs.Count)" $i (8 + 80 * ($i - 1) / $maqs.Count)
                $r = Ejecutar-Vmrun @('revertToSnapshot', $m.Vmx, $nombreSnap)
                if (-not $r.Agotado -and $r.Codigo -eq 0) { Anotar $m.Nombre $true '' } else { $salida = Texto-Fallo $r; Registrar "Volver de $($m.Nombre): $salida"; Anotar $m.Nombre $false $salida }
            }
            $buenas = @($maqs | Where-Object { $nom = $_.Nombre; -not @($resultados | Where-Object { $_.nombre -eq $nom -and -not $_.ok }).Count })
            if ($Encender) {
                Poner-Paso 'Encendiendo las máquinas (el controlador primero)…' $maqs.Count 90
                foreach ($f in @(Encender-Maquinas $buenas)) { Anotar 'Encender' $false $f }
            } else {
                # Una instantánea con memoria las deja encendidas al volver: se apagan para que queden como se pidió
                $estadoFin = Preguntar-Encendidas
                if (-not $estadoFin.Sabido) { Registrar 'VMware no contesta: no se sabe si alguna máquina quedó encendida tras volver (se dejan como estén)' }
                else {
                    $enc = @($estadoFin.Lista)
                    foreach ($m in @($buenas | Where-Object { $enc -contains $_.Vmx.ToLower() })) {
                        $r = Ejecutar-Vmrun @('stop', $m.Vmx, 'hard')
                        if ($r.Agotado) { Registrar "Apagar $($m.Nombre) tras volver: $(Texto-Fallo $r)" }
                    }
                }
            }
            Cerrar-Operacion 'Vuelto al estado inicial'
        }
        'quitar' {
            $con = @($maqs | Where-Object { $_.Tiene })
            if (-not $con.Count) { throw 'Ninguna máquina tiene estado inicial guardado.' }
            $script:est.total = $con.Count
            $i = 0
            foreach ($m in $con) {
                $i++
                Poner-Paso "Quitando el estado inicial $i de $($con.Count)" $i (100 * ($i - 1) / $con.Count)
                $r = Ejecutar-Vmrun @('deleteSnapshot', $m.Vmx, $nombreSnap)
                if (-not $r.Agotado -and $r.Codigo -eq 0) { Anotar $m.Nombre $true '' } else { $salida = Texto-Fallo $r; Registrar "Quitar de $($m.Nombre): $salida"; Anotar $m.Nombre $false $salida }
            }
            Cerrar-Operacion 'Estado inicial quitado'
        }
    }
} catch {
    $script:est.estado = 'error'; $script:est.mensaje = [string]$_.Exception.Message; $script:est.resultado = @($resultados); $script:est.pct = 100
    Guardar-Estado
    Registrar "Error: $($_.Exception.Message)"
}
if ($Aviso) {
    if ([string]$script:est.estado -eq 'ok') { Aviso-Windows "Laboratorio '$Lab': estado inicial guardado. Ya puedes volver a empezar la práctica con un clic." }
    else { Aviso-Windows "Laboratorio '$Lab': no se pudo guardar el estado inicial de todas las máquinas. Míralo en Full Cowl > Laboratorio." }
}
