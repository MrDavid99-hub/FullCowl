param([string]$Pedido)   # archivo JSON con lo elegido en la ventana; sin él, pregunta por consola
# =====================================================================
#  Crea (o vuelve a crear) una VM base desde su ISO, sin intervención.
#  Se hace UNA vez por sistema. Luego cada práctica se clona con
#  nueva-maquina.ps1 en segundos.
# =====================================================================
. "$PSScriptRoot\comun.ps1"

# --- Necesita permisos de administrador (para leer las ediciones de la ISO de Windows)
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Pedido) { $argumentos += " -Pedido `"$Pedido`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argumentos
    exit
}

Refrescar-Path
$packerExe = Obtener-Packer
if (-not $packerExe) {
    # Sin Packer: se instala aquí mismo (descarga oficial comprobada; sin administrador)
    Write-Host "Packer no está instalado: lo descargo de HashiCorp y compruebo su suma SHA-256…" -ForegroundColor Yellow
    $resPk = Instalar-Packer
    if (-not $resPk.Ok) { Salir-ConError $resPk.Mensaje }
    Write-Host $resPk.Mensaje -ForegroundColor Green
    $packerExe = $resPk.Ruta
}
$vmrun = Buscar-Vmrun
$sistemas = @(Obtener-Sistemas)

# Recursos de la base (los cambia la ventana; si no, los de config.ps1)
$ramBase = $Config.RAM_MB
$cpuBase = $Config.CPUs
$discoBase = $null

if ($Pedido) {
    # ---------------- Datos elegidos en la ventana
    $P = Leer-Pedido $Pedido
    $s = $sistemas | Where-Object { $_.Clave -eq $P.sistema } | Select-Object -First 1
    if (-not $s) { Salir-ConError "Sistema desconocido: $($P.sistema)" }
    $iso = $P.iso
    if (-not $iso -or -not (Test-Path $iso)) { Salir-ConError "No encuentro la ISO:`n  $iso" }
    if ($P.ram) { $ramBase = [int]$P.ram }
    if ($P.cpus) { $cpuBase = [int]$P.cpus }
    if ($P.disco) { $discoBase = [int]$P.disco }
    Escribir-Titulo "Crear VM base: $($s.Nombre)"
    Write-Host "  ISO: $(Split-Path $iso -Leaf)" -ForegroundColor Green
    $salida = Join-Path $Config.CarpetaBases $s.Clave
}
else {
    # ---------------- Preguntas por consola
    Escribir-Titulo "Crear VM base"
    for ($i = 0; $i -lt $sistemas.Count; $i++) {
        $x = $sistemas[$i]
        $marca = if (Test-Path (Join-Path $Config.CarpetaBases $x.Clave)) { '  (ya creada)' } else { '' }
        Write-Host ("  {0}) {1}{2}" -f ($i + 1), $x.Nombre, $marca)
    }
    Write-Host ""
    $op = Read-Host "Elige un número"
    if (-not ($op -as [int]) -or [int]$op -lt 1 -or [int]$op -gt $sistemas.Count) { Salir-ConError "Opción no válida." }
    $s = $sistemas[[int]$op - 1]

    # ISO: se buscan en la carpeta cada vez (las que añadas aparecen solas)
    $candidatas = @(Buscar-IsosSistema $s)
    if ($candidatas.Count -eq 0) {
        Salir-ConError "No hay ninguna ISO para '$($s.Nombre)' en:`n  $($Config.CarpetaISOs)"
    }
    if ($candidatas.Count -eq 1) {
        $iso = $candidatas[0].FullName
    } else {
        Write-Host ""
        Write-Host "ISO disponibles:"
        for ($i = 0; $i -lt $candidatas.Count; $i++) {
            $f = $candidatas[$i]
            Write-Host ("  {0}) {1}  ({2:N1} GB, {3:dd/MM/yyyy})" -f ($i + 1), $f.Name, ($f.Length / 1GB), $f.LastWriteTime)
        }
        $r = Read-Host "¿Cuál? [1]"
        $k = if ($r -as [int] -and [int]$r -ge 1 -and [int]$r -le $candidatas.Count) { [int]$r - 1 } else { 0 }
        $iso = $candidatas[$k].FullName
    }
    Write-Host "  ISO: $(Split-Path $iso -Leaf)" -ForegroundColor Green

    $salida = Join-Path $Config.CarpetaBases $s.Clave
    if (Test-Path $salida) {
        Write-Host ""
        Write-Host "La base '$($s.Clave)' ya existe." -ForegroundColor Yellow
        Write-Host "Si la rehaces, los clones ENLAZADOS que dependan de ella dejarán de funcionar." -ForegroundColor Yellow
        if ((Read-Host "¿Rehacerla? (s/N)") -notmatch '^[sS]') { exit }
    }
}
if (-not $discoBase) { $discoBase = if ($s.Tipo -eq 'windows') { $Config.DiscoWin_GB } else { $Config.DiscoLinux_GB } }

# --- Progreso para la ventana: estado\<sistema>.json
$dirEstado = Join-Path $PSScriptRoot 'estado'
New-Item -ItemType Directory -Force -Path $dirEstado | Out-Null
$script:archivoEstado = Join-Path $dirEstado "$($s.Clave).json"
$ahora = (Get-Date).ToString('o')
$script:est = [ordered]@{
    sistema = $s.Clave; nombre = $s.Nombre; paso = 'Preparando'; pct = 2; hasta = 2
    inicio = $ahora; inicioFase = $ahora; esperadoSeg = 0
    estado = 'curso'; mensaje = ''; pid = $PID; actualizado = ''
}
# La ventana pide cancelar creando estado\<sistema>.abortar
$script:archivoAbortar = Join-Path $dirEstado "$($s.Clave).abortar"
Remove-Item $script:archivoAbortar -Force -ErrorAction SilentlyContinue

function Cancelar-Creacion {
    # Apaga la VM a medio crear, borra su carpeta y los temporales, y cierra la consola
    Write-Host ""
    Write-Host "Cancelando la creación de la base..." -ForegroundColor Yellow
    if ($script:vigia) { try { $script:vigia.Stop(); $script:vigia.Dispose() } catch {} }
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'conhost.exe' } |
        ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null }
    Get-ChildItem $salida -Filter *.vmx -ErrorAction SilentlyContinue | ForEach-Object {
        & $vmrun -T ws stop $_.FullName hard 2>$null | Out-Null
    }
    $env:PKR_VAR_password = $null; $env:PACKER_LOG = $null; $env:PACKER_LOG_PATH = $null
    Remove-Item (Join-Path $PSScriptRoot 'build') -Recurse -Force -ErrorAction SilentlyContinue
    # VMware tarda unos segundos en soltar los archivos de la VM
    for ($i = 0; $i -lt 15 -and (Test-Path $salida); $i++) {
        Start-Sleep 2
        Remove-Item $salida -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $script:archivoAbortar -Force -ErrorAction SilentlyContinue
    $script:est.estado = 'cancelada'
    $script:est.mensaje = if (Test-Path $salida) { "No se pudo borrar del todo: $salida" } else { '' }
    Guardar-Estado
    Write-Host "Creación cancelada." -ForegroundColor Yellow
    if (Test-Path $salida) {
        Write-Host "Quedan restos en $salida (cierra su pestaña en VMware y bórrala a mano)." -ForegroundColor Yellow
        Read-Host "Pulsa Enter para cerrar"
    } else {
        Write-Host "VM a medio crear apagada y borrada. Esta ventana se cierra sola."
        Start-Sleep 5
    }
    exit 2
}

function Estado($paso, $pct, $hasta = $null, $esperado = 0) {
    # $hasta/$esperado: en fases sin mensajes, la ventana avanza la barra de $pct a $hasta en ~$esperado segundos
    $script:est.paso = $paso; $script:est.pct = $pct
    $script:est.hasta = if ($hasta) { $hasta } else { $pct }
    $script:est.esperadoSeg = $esperado
    $script:est.inicioFase = (Get-Date).ToString('o')
    Guardar-Estado
}
# Lo que suele tardar la instalación en sí (sin mensajes de Packer), en segundos
$esperadoInstal = switch ($s.Clave) {
    'WinServer2025' { 420 } 'WinServer2022' { 420 } 'WinServer2019' { 420 } 'Win10Pro' { 720 } 'Win11Pro' { 900 }
    'Ubuntu2604' { 600 } 'Ubuntu2404' { 600 } 'Ubuntu2204' { 600 } 'Lubuntu2404' { 1500 } 'Kali' { 900 }
    'Debian13' { 900 } 'Debian12' { 900 } 'Debian13Desk' { 1500 } 'Debian12Desk' { 1500 }
    'Rocky9' { 900 } 'Alma9' { 900 } 'Rocky9Desk' { 1500 } 'Alma9Desk' { 1500 }
    'Arch' { 600 } 'ArchDesk' { 1200 } default { 1200 }
}
Estado 'Preparando la instalación' 2
$script:sinYes = $false          # ficha 26: Ubuntu arranca con la mini-ISO y no pregunta
$script:faltaArranque = $false   # se pidió, pero no está la mini-ISO
function Registrar-Arranque([string]$texto) {
    # Apunta en estado\<Clave>-arranque.log cómo se arrancó la instalación (para diagnosticar)
    try { Add-Content -LiteralPath (Join-Path $dirEstado "$($s.Clave)-arranque.log") -Value ("{0}  {1}" -f (Get-Date).ToString('dd/MM/yyyy HH:mm:ss'), $texto) -Encoding UTF8 } catch { }
}

function Detectar-Paso($linea) {
    # Convierte los mensajes de Packer en pasos de la barra de progreso
    switch -Regex ($linea) {
        'Creating virtual machine disks|Building and writing VMX' { Estado 'Creando la máquina virtual' 7; break }
        'Powering on virtual machine' {
            if ($s.Tipo -eq 'windows') { Estado 'Instalando Windows (tiempo estimado)' 10 60 $esperadoInstal }
            elseif ($s.Tipo -eq 'manual') { Estado 'Esperando a que instales el sistema y lo apagues (o pulses «Ya he terminado»)' 10 90 7200 }
            elseif ($s.Tipo -in 'kali', 'debian', 'rhel', 'arch') { Estado "Instalando $($s.Linea) (escribe lo que se indica en la VM)" 10 60 $esperadoInstal }
            elseif ($script:sinYes) { Estado 'Instalando Ubuntu (empieza sola, no hay que escribir nada)' 10 60 $esperadoInstal }
            else { Estado "Instalando Ubuntu (escribe 'yes' en la VM cuando lo pida)" 10 60 $esperadoInstal }
            break
        }
        'Connected to (WinRM|SSH)' { Estado 'Conectado: configurando el sistema' 60; break }
        '== Escritorio y herramientas de Kali ==' { Estado 'Instalando el escritorio y las herramientas de Kali (varios GB)' 60 70 1500; break }
        '== Escritorio Xfce de Debian ==' { Estado 'Instalando el escritorio Xfce' 60 70 600; break }
        '== VMware Tools ==' { Estado 'Instalando VMware Tools' 62 70 240; break }
        '== Agente|== Ajustes|== Escritorio|== Red|== Actualizaciones' { Estado 'Aplicando ajustes' 70 74 60; break }
        'Restarting Machine|Waiting for machine to restart' { Estado 'Reiniciando' 75 80 180; break }
        '== Limpieza|== Preparando sysprep' { Estado 'Preparando para clonar' 80 82 60; break }
        'Gracefully halting|Executing shutdown command' {
            if ($s.Tipo -eq 'windows') { Estado 'Generalizando con sysprep y apagando' 82 90 420 }
            else { Estado 'Apagando' 85 90 60 }
            break
        }
        'Waiting for clean up|Compacting' { Estado 'Compactando el disco' 90 95 300; break }
    }
}
Write-Host ("  Recursos de la base: {0} MB de RAM, {1} procesadores, disco de {2} GB" -f $ramBase, $cpuBase, $discoBase)
New-Item -ItemType Directory -Force -Path $Config.CarpetaBases | Out-Null

# La contraseña de las VMs (password.sec) NO se usa para instalar la base: aquí solo se comprueba que
# existe, porque cada máquina la recibirá en su primer arranque. La base se instala con una contraseña
# aleatoria de un solo uso, así la real no queda en el archivo de respuestas, en el CD de instalación,
# en el disco de la base ni en las máquinas exportadas.
$null = Obtener-Password
$Password = Nueva-PasswordTemporal
# A Packer se le pasa por variable de entorno (no aparece en la línea de comandos ni en pantalla)
$env:PKR_VAR_password = $Password

# Restos de intentos anteriores (pueden contener la contraseña)
Remove-Item (Join-Path $PSScriptRoot 'build') -Recurse -Force -ErrorAction SilentlyContinue
$build = Join-Path $PSScriptRoot "build\$($s.Clave)"
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $build | Out-Null

# --- Idioma, teclado y zona horaria (ficha 36). Solo valores de las tablas cerradas de comun.ps1.
#     Sin ventana (consola) no se pregunta nada: español, teclado español y la zona de config (como siempre).
$idiSel = Resolver-Idioma $(if ($Pedido -and $P.PSObject.Properties['idioma']) { [string]$P.idioma } else { 'es' })
$tecSel = Resolver-Teclado $(if ($Pedido -and $P.PSObject.Properties['teclado']) { [string]$P.teclado } else { [string]$idiSel.Teclado })
$zonaSel = Resolver-Zona $(if ($Pedido -and $P.PSObject.Properties['zona']) { [string]$P.zona } else { Zona-PorDefecto })
$script:est.idioma = [string]$idiSel.Clave
Write-Host ("  Idioma: {0} · Teclado: {1} · Zona: {2}" -f $idiSel.Nombre, $tecSel.Nombre, $zonaSel.Nombre) -ForegroundColor Green
# Para las plantillas de Linux: nombre de la zona sin barras raras y teclado (salen de la tabla; se comprueban igualmente)
if ([string]$zonaSel.Iana -notmatch '^[A-Za-z0-9_/+-]+$' -or [string]$tecSel.Linux -notmatch '^[a-z]+$') { Salir-ConError 'Zona horaria o teclado no válidos.' }
function Poner-IdiomaLinux([string]$t) {
    # Marcadores comunes de las plantillas de Linux
    return $t.Replace('{{LOCALE}}', [string]$idiSel.Locale).Replace('{{LANGUAGE}}', [string]$idiSel.Language).
              Replace('{{PAIS}}', [string]$idiSel.Pais).Replace('{{TECLADO}}', [string]$tecSel.Linux).Replace('{{ZONA}}', [string]$zonaSel.Iana)
}

$packerDir = Join-Path $PSScriptRoot 'packer'
$a = { param($ruta) $ruta -replace '\\', '/' }   # Packer prefiere barras normales
$comunes = @(
    '-var', "iso_path=$(& $a $iso)",
    '-var', "output_dir=$(& $a $salida)",
    '-var', "vm_name=Base $($s.Clave)",
    '-var', "username=$($Config.Usuario)",
    '-var', "cpus=$cpuBase",
    '-var', "memory=$ramBase"
)

if ($s.Tipo -eq 'windows') {
    # --- Leer las ediciones de la ISO para elegir la correcta
    Write-Host "`nLeyendo las ediciones de la ISO..."
    $montada = Mount-DiskImage -ImagePath $iso -PassThru
    try {
        $letra = ($montada | Get-Volume).DriveLetter
        $wim = "$($letra):\sources\install.wim"
        if (-not (Test-Path $wim)) { $wim = "$($letra):\sources\install.esd" }
        $imagenes = Get-WindowsImage -ImagePath $wim
        if ($s.Clave -like 'WinServer*') {
            $elegida = $imagenes | Where-Object { $_.ImageName -match 'Standard' -and $_.ImageName -match 'Desktop|Escritorio' } | Select-Object -First 1
        } else {
            $elegida = $imagenes | Where-Object { $_.ImageName -match '\bPro\b' -and $_.ImageName -notmatch '\bN\b|Education|Educaci|Workstation|Single' } | Select-Object -First 1
        }
        if (-not $elegida) {
            Write-Host "No sé qué edición elegir. Ediciones en la ISO:" -ForegroundColor Yellow
            $imagenes | ForEach-Object { Write-Host ("  {0}) {1}" -f $_.ImageIndex, $_.ImageName) }
            $idx = Read-Host "Número de la edición"
            $elegida = $imagenes | Where-Object { $_.ImageIndex -eq [int]$idx }
            if (-not $elegida) { throw "Edición no válida" }
        }
        $detalle = Get-WindowsImage -ImagePath $wim -Index $elegida.ImageIndex
        $idioma = (($detalle.Languages | Select-Object -First 1) -replace '\s*\(.*\)', '').Trim()
        if (-not $idioma) { $idioma = 'es-ES' }
        $idiomasIso = @($detalle.Languages | ForEach-Object { ([string]$_ -replace '\s*\(.*\)', '').Trim() })
    } catch {
        Dismount-DiskImage -ImagePath $iso | Out-Null
        Salir-ConError "No se pudo leer la ISO: $_"
    }
    Dismount-DiskImage -ImagePath $iso | Out-Null
    Write-Host ("  Edición: {0}  (índice {1}, idioma {2})" -f $elegida.ImageName, $elegida.ImageIndex, $idioma) -ForegroundColor Green
    # Ficha 36: el idioma de la INTERFAZ lo pone la ISO (es lo que trae dentro). Si se pidió otro, se avisa y se sigue:
    # el teclado, los formatos (fechas, comas) y la zona horaria sí son los elegidos.
    if ($idiomasIso -notcontains [string]$idiSel.Win) {
        $nomIsoIdi = $(if ($idioma -like 'es-*') { 'español' } elseif ($idioma -like 'en-*') { 'inglés' } else { $idioma })
        $script:est.aviso = "Tu ISO solo trae ${nomIsoIdi}: Windows se verá en $nomIsoIdi, pero el teclado, los formatos (fechas, comas) y la hora serán los que has elegido."
        Write-Host "  AVISO: $($script:est.aviso)" -ForegroundColor Yellow
    }

    # --- Clave genérica de instalación (no activa Windows; solo permite instalar sin preguntar)
    $clave = ''
    if ($elegida.ImageName -notmatch 'Evaluation|Evaluaci') {
        $clave = switch ($s.Clave) {
            'WinServer2025' { 'TVRH6-WHNXV-R9WG3-9XRFY-MY832' }
            'WinServer2022' { 'VDYBN-27WPP-V4HQT-9VMD4-VMK7H' }
            'WinServer2019' { 'N69G4-B89J2-4G8F4-WWYCC-J464C' }
            default         { 'VK7JG-NPHTM-C97JM-9MPGT-3V66T' }   # Windows 10/11 Pro
        }
    }
    $bloqueClave = if ($clave) { "        <ProductKey>`n          <Key>$clave</Key>`n          <WillShowUI>OnError</WillShowUI>`n        </ProductKey>" } else { '' }
    $grupoAdmin = if ($idioma -like 'es-*') { 'Administradores' } else { 'Administrators' }
    $nombreEquipo = ('BASE-' + $s.Clave.ToUpper()); if ($nombreEquipo.Length -gt 15) { $nombreEquipo = $nombreEquipo.Substring(0, 15) }

    $esc = { param($t) [System.Security.SecurityElement]::Escape($t) }
    $reemplazos = @{
        '{{UILANG}}'       = $idioma
        '{{INDEX}}'        = [string]$elegida.ImageIndex
        '{{PRODUCTKEY}}'   = $bloqueClave
        '{{USER}}'         = (& $esc $Config.Usuario)
        '{{PASS}}'         = (& $esc $Password)
        '{{ADMGROUP}}'     = $grupoAdmin
        '{{COMPUTERNAME}}' = $nombreEquipo
        '{{TIMEZONE}}'     = [string]$zonaSel.Win
        '{{INPUTLOCALE}}'  = [string]$tecSel.Win
        '{{FORMATOS}}'     = [string]$idiSel.Win
        '{{WINPE_EXTRA}}'  = ''
        # Windows 10/11: tras sysprep, saltar el asistente inicial (si no, Windows 11 pide crear
        # otro usuario aunque ya exista). En Server no hace falta.
        '{{OOBE_EXTRA}}'   = $(if ($s.Clave -in 'Win10Pro', 'Win11Pro') { "        <SkipMachineOOBE>true</SkipMachineOOBE>`n        <SkipUserOOBE>true</SkipUserOOBE>" } else { '' })
    }
    if ($s.Win11) {
        # Windows 11 exige TPM 2.0, arranque seguro y 64 GB: se salta la comprobación
        # (claves LabConfig de Microsoft) para instalar en una VM normal con BIOS.
        $orden = 0
        $cmds = foreach ($b in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassStorageCheck', 'BypassCPUCheck') {
            $orden++
            "          <RunSynchronousCommand wcm:action=`"add`">`n            <Order>$orden</Order>`n            <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v $b /t REG_DWORD /d 1 /f</Path>`n          </RunSynchronousCommand>"
        }
        $reemplazos['{{WINPE_EXTRA}}'] = "      <RunSynchronous>`n" + ($cmds -join "`n") + "`n      </RunSynchronous>"
    }
    $floppy = Join-Path $build 'floppy'
    New-Item -ItemType Directory -Force -Path $floppy | Out-Null
    foreach ($par in @(@('autounattend.plantilla.xml', 'autounattend.xml'), @('sysprep-oobe.plantilla.xml', 'sysprep-oobe.xml'))) {
        $texto = [IO.File]::ReadAllText((Join-Path $packerDir "windows\$($par[0])"))
        foreach ($k in $reemplazos.Keys) { $texto = $texto.Replace($k, $reemplazos[$k]) }
        [IO.File]::WriteAllText((Join-Path $floppy $par[1]), $texto, [Text.UTF8Encoding]::new($false))
    }

    $plantilla = 'windows.pkr.hcl'
    $vars = $comunes + @(
        '-var', "guest_os_type=$($s.GuestOS)",
        '-var', "floppy_dir=$(& $a $floppy)",
        '-var', "disk_gb=$discoBase"
    )
    if ($s.Win11) {
        # Además del disquete, el archivo de respuestas va en un CD (Windows 11 lo busca ahí también)
        $cdUnattend = Join-Path $build 'unattend.iso'
        Crear-Iso -Carpeta $floppy -Destino $cdUnattend -Etiqueta 'UNATTEND'
        $vars += @('-var', "extra_cd=$cdUnattend")
    }
    # VMware Tools: se instalan desde el CD que trae VMware Workstation (no hace falta Internet)
    $isoTools = Buscar-IsoTools 'windows.iso'
    if ($isoTools) {
        $vars += @('-var', "tools_iso=$isoTools")
    } else {
        Write-Host "  AVISO: no encuentro windows.iso (ni en la carpeta de ISOs ni en la de VMware); se intentarán descargar las VMware Tools de Internet." -ForegroundColor Yellow
    }
} elseif ($s.Tipo -eq 'kali') {
    # --- Kali: el instalador de Debian lee la configuración (preseed) por HTTP desde Packer.
    #     Sin VNC en Workstation, la línea de arranque que la pide se escribe a mano.
    $ipPC = Ip-PcVmnet8      # el PC dentro de la red NAT de VMware
    if (-not $ipPC) { Salir-ConError "No encuentro la red NAT de VMware (VMnet8): hace falta para instalar Kali." }
    $http = Join-Path $build 'http'
    New-Item -ItemType Directory -Force -Path $http | Out-Null
    $texto = [IO.File]::ReadAllText((Join-Path $packerDir 'kali\preseed.plantilla'))
    $texto = Poner-IdiomaLinux ($texto.Replace('{{HOSTNAME}}', 'base-kali').Replace('{{USER}}', $Config.Usuario).Replace('{{PASS}}', $Password))
    [IO.File]::WriteAllText((Join-Path $http 'k.cfg'), ($texto -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $lineaKali = Linea-ArranqueKali

    $plantilla = 'kali.pkr.hcl'
    $vars = $comunes + @(
        '-var', "http_dir=$(& $a $http)",
        '-var', "http_ip=$ipPC",
        '-var', "disk_gb=$discoBase"
    )
    # Kali NO lleva el CD de VMware Tools (linux.iso): con un segundo CD conectado, el instalador intenta
    # usarlo como fuente de paquetes y falla. open-vm-tools se instala desde el repositorio de Kali.
} elseif ($s.Tipo -eq 'manual') {
    # --- Instalación manual guiada: sin Packer (Packer apaga a la fuerza la VM nada más encenderla si no tiene con qué
    #     conectarse, y la base quedaba vacía). Full Cowl crea el disco y el .vmx, enciende la VM y espera a que acabes.
    $plantilla = $null
    $vars = @()
} elseif ($s.Tipo -in 'debian', 'rhel', 'arch') {
    # --- Debian (preseed), Rocky/Alma (kickstart) y Arch (script): el instalador lee su configuración por HTTP
    #     desde Packer; la línea de arranque que la pide se escribe a mano (no hay VNC en Workstation).
    #     Sin segundo CD de VMware Tools (daría los mismos problemas que en Kali): open-vm-tools sale de los repositorios.
    $ipPC = Ip-PcVmnet8
    if (-not $ipPC) { Salir-ConError "No encuentro la red NAT de VMware (VMnet8): hace falta para instalar $($s.Linea)." }
    $http = Join-Path $build 'http'
    New-Item -ItemType Directory -Force -Path $http | Out-Null
    $nombreEquipoLx = 'base-' + $s.Clave.ToLower()
    $esDesk = [bool]$s.Desktop
    $utf8 = [Text.UTF8Encoding]::new($false)
    switch ($s.Tipo) {
        'debian' {
            $texto = [IO.File]::ReadAllText((Join-Path $packerDir 'debian\preseed.plantilla'))
            $texto = Poner-IdiomaLinux ($texto.Replace('{{HOSTNAME}}', $nombreEquipoLx).Replace('{{USER}}', $Config.Usuario).Replace('{{PASS}}', $Password))
            [IO.File]::WriteAllText((Join-Path $http 'd.cfg'), ($texto -replace "`r`n", "`n"), $utf8)
            $plantilla = 'debian.pkr.hcl'
        }
        'rhel' {
            $texto = [IO.File]::ReadAllText((Join-Path $packerDir 'rhel\kickstart.plantilla'))
            $entorno = $(if ($esDesk) { '@^graphical-server-environment' } else { '@^minimal-environment' })
            $skipx = $(if ($esDesk) { '' } else { 'skipx' })
            $postEsc = $(if ($esDesk) { 'systemctl set-default graphical.target' } else { '' })
            $texto = $texto.Replace('{{HOSTNAME}}', $nombreEquipoLx).Replace('{{USER}}', $Config.Usuario).Replace('{{PASS}}', $Password).
                            Replace('{{ENTORNO}}', $entorno).Replace('{{SKIPX}}', $skipx).Replace('{{POST_ESCRITORIO}}', $postEsc)
            $texto = Poner-IdiomaLinux $texto
            [IO.File]::WriteAllText((Join-Path $http 'ks.cfg'), ($texto -replace "`r`n", "`n"), $utf8)
            $plantilla = 'rhel.pkr.hcl'
        }
        'arch' {
            $texto = [IO.File]::ReadAllText((Join-Path $packerDir 'arch\instalar.plantilla'))
            $paq = $(if ($esDesk) { 'xfce4 xfce4-goodies lightdm lightdm-gtk-greeter xorg-server firefox gvfs' } else { '' })
            $escr = $(if ($esDesk) { 'systemctl enable lightdm' } else { '' })
            $texto = $texto.Replace('{{HOSTNAME}}', $nombreEquipoLx).Replace('{{USER}}', $Config.Usuario).Replace('{{PASS}}', $Password).
                            Replace('{{PAQUETES}}', $paq).Replace('{{ESCRITORIO}}', $escr)
            $texto = Poner-IdiomaLinux $texto
            [IO.File]::WriteAllText((Join-Path $http 'arch.sh'), ($texto -replace "`r`n", "`n"), $utf8)
            $plantilla = 'arch.pkr.hcl'
        }
    }
    $arranque = Info-Arranque $s.Tipo
    $vars = $comunes + @(
        '-var', "http_dir=$(& $a $http)",
        '-var', "http_ip=$ipPC",
        '-var', "disk_gb=$discoBase",
        '-var', "desktop=$(([string]$esDesk).ToLower())"
    )
} else {
    # --- CD de configuración (etiqueta CIDATA) con la instalación desatendida
    if ($s.IsoDesktop) {
        # La ISO Desktop ya trae el escritorio: solo se elige la variante mínima
        # Sin firefox aquí: en 24.04 es un envoltorio que descarga el snap, y dentro del instalador falla (dpkg, código 100).
        # Se instala después, ya con el sistema arrancado (packer\ubuntu\provision.sh).
        $escritorio = "    - open-vm-tools-desktop`n    - language-pack-gnome-$($idiSel.Language)"
        $fuente = "  source:`n    id: ubuntu-desktop-minimal"
    } elseif ($s.Desktop) {
        $paqEscritorio = if ($s.Escritorio) { $s.Escritorio } else { 'ubuntu-desktop-minimal' }
        # language-pack-gnome-<idioma>: el escritorio en ese idioma (sin él sale en inglés aunque el sistema esté en español)
        # ubuntu-desktop-minimal NO va aqui: trae firefox como recomendado (envoltorio del snap) y dentro del instalador
        # falla (dpkg, codigo 100). Se instala despues, con el sistema arrancado (packer\ubuntu\provision.sh).
        $escritorio = "    - open-vm-tools-desktop`n    - language-pack-gnome-$($idiSel.Language)"
        if ($s.Escritorio) { $escritorio = "    - open-vm-tools-desktop`n    - $paqEscritorio`n    - language-pack-gnome-$($idiSel.Language)" }
        $fuente = ''
    } else { $escritorio = ''; $fuente = '' }
    # 'codecs' no existe en el instalador de Ubuntu 22.04
    $codecs = if ($s.Antiguo) { '' } else { "  codecs:`n    install: false" }
    $texto = [IO.File]::ReadAllText((Join-Path $packerDir 'ubuntu\user-data.plantilla'))
    $texto = $texto.Replace('{{PAQUETES_ESCRITORIO}}', $escritorio).Replace('{{FUENTE}}', $fuente).Replace('{{CODECS}}', $codecs).
                    Replace('{{HOSTNAME}}', ('base-' + $s.Clave.ToLower())).
                    Replace('{{USER}}', $Config.Usuario).
                    Replace('{{PASS_JSON}}', (ConvertTo-Json $Password -Compress)).
                    Replace('{{ESPEJO}}', $(if ($idiSel.Clave -eq 'es') { 'http://es.archive.ubuntu.com/ubuntu' } else { 'http://archive.ubuntu.com/ubuntu' })).
                    Replace('{{LANGPACK}}', "language-pack-$($idiSel.Language)")
    $texto = Poner-IdiomaLinux $texto
    $texto = ($texto -split "`r?`n" | Where-Object { $_ -ne '' }) -join "`n"
    $seed = Join-Path $build 'seed'
    New-Item -ItemType Directory -Force -Path $seed | Out-Null
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $seed 'user-data'), $texto + "`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $seed 'meta-data'), "instance-id: $($s.Clave.ToLower())`n", $utf8)
    $cidata = Join-Path $build 'cidata.iso'
    Crear-Iso -Carpeta $seed -Destino $cidata -Etiqueta 'CIDATA'

    $plantilla = 'ubuntu.pkr.hcl'
    $vars = $comunes + @(
        '-var', "cidata_iso=$cidata",
        '-var', "desktop=$(([string]$s.Desktop).ToLower())",
        '-var', "disk_gb=$discoBase"
    )
    # Ficha 26: arrancar con la mini-ISO que añade «autoinstall» para no tener que escribir «yes».
    # Por defecto sí; la ventana puede pedir que no (sinYes = false). Con la ISO Desktop (experimental) no se usa.
    $quiereSinYes = $true
    if ($Pedido -and $P.PSObject.Properties['sinYes']) { $quiereSinYes = [bool]$P.sinYes }
    $isoArranque = Join-Path $PSScriptRoot 'recursos\arranque\ubuntu-autoinstall.iso'
    if ($quiereSinYes -and -not $s.IsoDesktop) {
        if ((Test-Path -LiteralPath $isoArranque) -and (Get-Item -LiteralPath $isoArranque).Length -gt 1MB) {
            $script:sinYes = $true
            $vars += @('-var', "arranque_iso=$(& $a $isoArranque)")
        } else {
            $script:faltaArranque = $true
        }
    }
    # Plan B de VMware Tools (si open-vm-tools no se pudiera instalar): el linux.iso de VMware
    $isoTools = Buscar-IsoTools 'linux.iso'
    if ($isoTools) { $vars += @('-var', "tools_iso=$isoTools") }
}

# --- Construir
Escribir-Titulo "Creando '$($s.Nombre)'"
if ($s.Tipo -eq 'windows') {
    Write-Host "La VM se crea en SEGUNDO PLANO (sin ventana de VMware): no hace falta verla."
    Write-Host "El progreso sale en esta consola. Tarda unos 15-30 minutos."
} elseif ($s.Tipo -eq 'manual') {
    Write-Host "La VM se crea vacía, con la ISO conectada, y a los pocos segundos se abre su ventana en VMware. El sistema lo instalas TÚ."
} elseif ($s.Tipo -in 'kali', 'debian', 'rhel', 'arch') {
    Write-Host "La VM arranca en segundo plano y a los pocos segundos se abre su ventana en VMware. Solo hay que escribir la línea de abajo."
} elseif ($script:sinYes) {
    Write-Host "La VM arranca en segundo plano y a los pocos segundos se abre su ventana en VMware."
    Write-Host "NO toques la VM: la instalación empieza sola. Tarda unos 20-30 minutos."
} else {
    Write-Host "La VM arranca en segundo plano y a los pocos segundos se abre su ventana en VMware."
    Write-Host "NO toques la VM salvo para escribir 'yes'. Tarda unos 20-30 minutos."
}
Write-Host "Si Windows pregunta si permites a 'packer' en la red, acepta (red privada)." -ForegroundColor Yellow
if ($s.Tipo -in 'kali', 'debian', 'rhel', 'arch') {
    # Lo mismo para Kali, Debian, Rocky/Alma y Arch: cambia la tecla (ESC o Tab) y si la línea es entera o se añade
    if (-not $arranque) { $arranque = Info-Arranque $s.Tipo }
    $lineaArr = [string]$arranque.Texto
    Write-Host ""
    Write-Host "$($s.Linea.ToUpper()): se abrirá la VM con el menú de arranque del instalador (si no se abre sola: en VMware, File > Open y elige $(Join-Path $salida "Base $($s.Clave).vmx")). Entonces:" -ForegroundColor Yellow
    if ($arranque.Modo -eq 'completa') {
        Write-Host "  1. Haz clic dentro de la VM (menú del instalador) y pulsa ESC: abajo sale un prompt 'boot:'." -ForegroundColor Yellow
        Write-Host "  2. Escribe esta línea ENTERA:" -ForegroundColor Yellow
    } else {
        Write-Host "  1. Haz clic dentro de la VM (menú del instalador), deja marcada la primera opción y pulsa TAB: abajo sale la línea de arranque." -ForegroundColor Yellow
        Write-Host "  2. Ve al FINAL de esa línea, escribe un espacio y a continuación este texto (sin tocar lo que ya había):" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "       $lineaArr" -ForegroundColor White
    Write-Host ""
    Write-Host "     El menú usa teclado INGLÉS. Con un teclado ESPAÑOL, pulsa esto (es lo mismo, con las teclas de aquí):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "       $(Linea-KaliTeclado $lineaArr)" -ForegroundColor White
    Write-Host ""
    Write-Host "       =   es la tecla  ¡   (a la derecha del 0)" -ForegroundColor Yellow
    Write-Host "       :   es  Mayús + ñ  (una Ñ mayúscula)" -ForegroundColor Yellow
    Write-Host "       /   es la tecla  -   (a la derecha del punto)" -ForegroundColor Yellow
    Write-Host "     Si te equivocas, borra con Retroceso." -ForegroundColor Yellow
    Write-Host "  3. Revisa que en pantalla ponga lo mismo que la línea blanca de arriba y pulsa Enter. Lo demás es automático (30-45 min)." -ForegroundColor Yellow
    Write-Host "  Si a los 2 minutos sigue pidiendo idioma o red, la línea no se leyó bien:" -ForegroundColor DarkYellow
    Write-Host "  reinicia la VM (VM > Power > Restart Guest) y repite la línea." -ForegroundColor DarkYellow
}
if ($s.Tipo -eq 'manual') {
    Write-Host ""
    Write-Host "$($s.Nombre.ToUpper()) - INSTALACIÓN MANUAL. Pasos:" -ForegroundColor Yellow
    $nPaso = 0
    foreach ($paso in (Receta-Manual $s ([string]$idiSel.Clave) ([string]$tecSel.Clave) ([string]$zonaSel.Clave))) { $nPaso++; Write-Host "  $nPaso. $paso" -ForegroundColor Yellow }
    if ($s.Clave -eq 'Proxmox') {
        $datosPve = Datos-RedProxmox
        if ($datosPve) {
            Write-Host ""
            Write-Host "  Datos de red para el instalador de Proxmox (red NAT de VMware):" -ForegroundColor Yellow
            Write-Host "    IP (CIDR):         $($datosPve.Cidr)" -ForegroundColor White
            Write-Host "    Puerta de enlace:  $($datosPve.Puerta)" -ForegroundColor White
            Write-Host "    DNS:               $($datosPve.Dns)" -ForegroundColor White
            Write-Host "    Nombre (FQDN):     pve.lab.local" -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host "Si la ventana no se abre sola: en VMware, File > Open y elige $(Join-Path $salida "Base $($s.Clave).vmx")" -ForegroundColor DarkYellow
    Write-Host "Esta consola seguirá esperando hasta que la máquina se apague." -ForegroundColor DarkYellow
}
if ($s.Tipo -eq 'ubuntu' -and $script:sinYes) {
    Write-Host ""
    Write-Host "UBUNTU: la instalación empieza SOLA (no hay que escribir 'yes')." -ForegroundColor Yellow
    Write-Host "La máquina arranca con un CD pequeño de Full Cowl que pone en marcha el instalador de tu ISO." -ForegroundColor Yellow
    Write-Host "Si a los 2-3 minutos la ventana de la VM enseña un mensaje que empieza por 'FULL COWL: no he podido arrancar'," -ForegroundColor DarkYellow
    Write-Host "o sigue en negro sin avanzar: pulsa Cancelar, desmarca 'Empezar sin escribir yes' en Crear base y repite." -ForegroundColor DarkYellow
    Write-Host "Si aun así pregunta 'Continue with autoinstall? (yes|no)', escribe  yes  y pulsa Enter." -ForegroundColor DarkYellow
    Write-Host "Si la ventana no se abre sola: en VMware, File > Open y elige" -ForegroundColor DarkYellow
    Write-Host "   $(Join-Path $salida "Base $($s.Clave).vmx")" -ForegroundColor DarkYellow
    Registrar-Arranque "Ubuntu: arranque con la mini-ISO (autoinstall), sin escribir yes."
}
if ($s.Tipo -eq 'ubuntu' -and -not $script:sinYes) {
    Write-Host ""
    if ($script:faltaArranque) {
        Write-Host "AVISO: no encuentro el CD de arranque de Full Cowl (recursos\arranque\ubuntu-autoinstall.iso)." -ForegroundColor Red
        Write-Host "Se hace como siempre: habrá que escribir 'yes'. Para arreglarlo, ejecuta Actualizar.bat." -ForegroundColor Red
        Registrar-Arranque "Ubuntu: falta recursos\arranque\ubuntu-autoinstall.iso; se instala escribiendo yes."
        Write-Host ""
    }
    Write-Host "UBUNTU: a los ~30 s de arrancar, el instalador preguntará:" -ForegroundColor Yellow
    Write-Host "   Continue with autoinstall? (yes|no)" -ForegroundColor Yellow
    Write-Host "Haz clic en la ventana de la VM, escribe  yes  y pulsa Enter. Es lo único manual." -ForegroundColor Yellow
    Write-Host "Si la ventana no se abre sola: en VMware, File > Open y elige" -ForegroundColor DarkYellow
    Write-Host "   $(Join-Path $salida "Base $($s.Clave).vmx")" -ForegroundColor DarkYellow
    Write-Host "Después puedes dejar la pestaña abierta o cerrarla eligiendo 'Run in Background'." -ForegroundColor DarkYellow
    if ($s.IsoDesktop) {
        Write-Host ""
        Write-Host "EXPERIMENTAL: con la ISO Desktop arranca primero el escritorio de prueba y luego" -ForegroundColor Magenta
        Write-Host "el instalador. Si se queda parado pidiendo datos (idioma, tipo de instalación...)," -ForegroundColor Magenta
        Write-Host "NO lo rellenes: hazle una captura y pásamela." -ForegroundColor Magenta
    }
}
Write-Host ""

# Si la base anterior sigue encendida, Packer no puede reemplazarla
$enMarcha = & $vmrun -T ws list 2>$null
if ($enMarcha | Where-Object { $_ -like "$salida\*" }) {
    Salir-ConError "La base '$($s.Clave)' está encendida en VMware. Apágala y cierra su pestaña antes de rehacerla."
}

# Registro detallado de Packer (solo en archivo) para poder diagnosticar fallos
$env:PACKER_LOG = '1'
$env:PACKER_LOG_PATH = Join-Path $build 'packer.log'
$logError = Join-Path $PSScriptRoot 'ultimo-error-packer.log'
if (Test-Path $script:archivoAbortar) { Cancelar-Creacion }

# Vigilante en segundo plano: si la ventana pide cancelar, corta Packer y apaga la VM
# aunque Packer lleve rato sin escribir nada (esperando a WinRM, instalando...)
$script:vigia = [powershell]::Create()
[void]$script:vigia.AddScript({
    param($archivo, $padre, $vmrun, $carpeta)
    while (-not (Test-Path $archivo)) { Start-Sleep -Milliseconds 1000 }
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$padre" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'conhost.exe' } |
        ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null }
    Start-Sleep 2
    Get-ChildItem $carpeta -Filter *.vmx -ErrorAction SilentlyContinue | ForEach-Object {
        & $vmrun -T ws stop $_.FullName hard 2>$null | Out-Null
    }
}).AddArgument($script:archivoAbortar).AddArgument($PID).AddArgument($vmrun).AddArgument($salida)
[void]$script:vigia.BeginInvoke()

# Ubuntu, Kali, Debian, Rocky/Alma y Arch se crean sin ventana (con ventana, vmrun a veces deja colgado a Packer al encenderla):
# en cuanto la VM está encendida se abre en VMware para poder escribir 'yes' (Ubuntu sin la mini-ISO) o la línea de arranque (Kali),
# y con la mini-ISO para ver que la instalación avanza (o su mensaje de ayuda si no pudo arrancar)
if (@('ubuntu', 'kali', 'debian', 'rhel', 'arch') -contains $s.Tipo) {
    $script:abridor = [powershell]::Create()
    [void]$script:abridor.AddScript({
        param($vmrun, $vmx, $archivo)
        $vmware = Join-Path (Split-Path $vmrun) 'vmware.exe'
        if (-not (Test-Path $vmware)) { return }
        $buscado = ($vmx -replace '/', '\').ToLower()
        for ($i = 0; $i -lt 1800; $i++) {
            if (Test-Path $archivo) { return }
            $lista = @(& $vmrun -T ws list 2>$null | ForEach-Object { ($_.Trim() -replace '/', '\').ToLower() })
            if ($lista -contains $buscado) {
                Start-Sleep 2
                Start-Process -FilePath $vmware -ArgumentList "`"$vmx`""
                return
            }
            Start-Sleep 2
        }
    }).AddArgument($vmrun).AddArgument((Join-Path $salida "Base $($s.Clave).vmx")).AddArgument($script:archivoAbortar)
    [void]$script:abridor.BeginInvoke()
}

# Instalación manual: el botón «Ya he terminado» de la ventana crea estado\<sistema>.listo
$script:archivoListo = Join-Path $dirEstado "$($s.Clave).listo"
Remove-Item $script:archivoListo -Force -ErrorAction SilentlyContinue

if ($s.Tipo -eq 'manual') {
    # --- Crear la VM vacía a mano (disco + .vmx), encenderla y esperar a que el usuario instale y termine
    $vdisk = Join-Path (Split-Path $vmrun) 'vmware-vdiskmanager.exe'
    if (-not (Test-Path $vdisk)) { Salir-ConError "No encuentro vmware-vdiskmanager.exe junto a vmrun ($vdisk)." }
    Estado 'Creando la máquina virtual' 7
    if (Test-Path $salida) { Remove-Item $salida -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $salida | Out-Null
    $nombreVm = "Base $($s.Clave)"
    $vmdk = Join-Path $salida "$nombreVm.vmdk"
    & $vdisk -c -s "$($discoBase)GB" -a ide -t 0 $vmdk | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $vmdk)) { Salir-ConError "No se pudo crear el disco de la máquina." }
    $vmxManual = Join-Path $salida "$nombreVm.vmx"
    # Tarjeta de red: vmxnet3 (BSD, Linux, cortafuegos); para «Otro sistema» (podría ser un Windows) e1000e, que casi todos traen
    $tarjeta = $(if ($s.Clave -eq 'Otro') { 'e1000e' } else { 'vmxnet3' })
    $v = [System.Collections.Generic.List[string]]::new()
    foreach ($par in @(
        '.encoding = "UTF-8"', 'config.version = "8"', 'virtualHW.version = "19"',
        "displayName = `"$nombreVm`"", "guestOS = `"$($s.GuestOS)`"",
        "memsize = `"$ramBase`"", "numvcpus = `"$cpuBase`"", 'firmware = "bios"', 'bios.bootOrder = "hdd,cdrom"',
        'sata0.present = "TRUE"', 'sata0:0.present = "TRUE"', "sata0:0.fileName = `"$nombreVm.vmdk`"",
        'ide1:0.present = "TRUE"', 'ide1:0.deviceType = "cdrom-image"', "ide1:0.fileName = `"$iso`"", 'ide1:0.startConnected = "TRUE"',
        'ethernet0.present = "TRUE"', 'ethernet0.connectionType = "nat"', "ethernet0.virtualDev = `"$tarjeta`"", 'ethernet0.addressType = "generated"',
        'usb.present = "TRUE"', 'sound.present = "TRUE"', 'sound.autoDetect = "TRUE"',
        'mks.enable3d = "FALSE"', 'tools.syncTime = "FALSE"',
        # Puentes PCI/PCIe como los de cualquier máquina de VMware: sin ellos vmxnet3 dice «No PCIe slot available for Ethernet0»
        'pciBridge0.present = "TRUE"', 'pciBridge4.present = "TRUE"', 'pciBridge4.virtualDev = "pcieRootPort"', 'pciBridge4.functions = "8"',
        'pciBridge5.present = "TRUE"', 'pciBridge5.virtualDev = "pcieRootPort"', 'pciBridge5.functions = "8"',
        'pciBridge6.present = "TRUE"', 'pciBridge6.virtualDev = "pcieRootPort"', 'pciBridge6.functions = "8"',
        'pciBridge7.present = "TRUE"', 'pciBridge7.virtualDev = "pcieRootPort"', 'pciBridge7.functions = "8"'
    )) { $v.Add($par) }
    if ([int]$s.Nics -ge 2) {
        foreach ($par in @('ethernet1.present = "TRUE"', 'ethernet1.connectionType = "hostonly"', "ethernet1.virtualDev = `"$tarjeta`"", 'ethernet1.addressType = "generated"')) { $v.Add($par) }
    }
    if ($s.Anidada) { $v.Add('vhv.enable = "TRUE"') }
    Guardar-Vmx $vmxManual $v

    Write-Host ""
    Write-Host "Encendiendo la máquina (se abre su ventana en VMware)..." -ForegroundColor Green
    & $vmrun -T ws start $vmxManual gui | Out-Null
    if ($LASTEXITCODE -ne 0) { Salir-ConError "No se pudo encender la máquina ($vmxManual)." }
    Estado 'Esperando a que instales el sistema y pulses «Ya he terminado» (o lo apagues)' 10 90 7200

    # Espera: botón «Ya he terminado» (estado\<Clave>.listo) o que la máquina se apague desde dentro
    $buscado = ($vmxManual -replace '/', '\').ToLower()
    $vista = $false; $apagadaN = 0
    while ($true) {
        if (Test-Path $script:archivoAbortar) { Cancelar-Creacion }
        $lista = @(& $vmrun -T ws list 2>$null | ForEach-Object { ($_.Trim() -replace '/', '\').ToLower() })
        $encendida = $lista -contains $buscado
        if ($encendida) { $vista = $true; $apagadaN = 0 } elseif ($vista) { $apagadaN++ }
        if (Test-Path $script:archivoListo) { break }
        if ($vista -and $apagadaN -ge 2) { break }
        Start-Sleep 3
    }
    Estado 'Apagando la máquina' 92
    $lista = @(& $vmrun -T ws list 2>$null | ForEach-Object { ($_.Trim() -replace '/', '\').ToLower() })
    if ($lista -contains $buscado) {
        # Apagado con cuidado (pide al sistema que se apague: hace falta VMware Tools / open-vm-tools); si no, a la fuerza a los 90 s
        & $vmrun -T ws stop $vmxManual soft 2>$null | Out-Null
        for ($e = 0; $e -lt 30; $e++) {
            Start-Sleep 3
            $lista = @(& $vmrun -T ws list 2>$null | ForEach-Object { ($_.Trim() -replace '/', '\').ToLower() })
            if ($lista -notcontains $buscado) { break }
        }
        if ($lista -contains $buscado) { & $vmrun -T ws stop $vmxManual hard 2>$null | Out-Null }
    }
    Start-Sleep 4
    try { $script:vigia.Stop(); $script:vigia.Dispose() } catch {}
    $script:vigia = $null
    Remove-Item $script:archivoListo -Force -ErrorAction SilentlyContinue
} else {
Push-Location $packerDir
try {
    & $packerExe init $plantilla
    if ($LASTEXITCODE -ne 0) { throw "packer init falló" }
    Estado 'Arrancando Packer' 5
    # La salida de Packer se muestra igual que antes y además mueve la barra de progreso
    & $packerExe build -force @vars $plantilla 2>&1 | ForEach-Object {
        $linea = "$_"
        Write-Host $linea
        Detectar-Paso $linea
    }
    if (Test-Path $script:archivoAbortar) { throw 'cancelada' }
    if ($LASTEXITCODE -ne 0) { throw "packer build falló (código $LASTEXITCODE)" }
} catch {
    Pop-Location
    if (Test-Path $script:archivoAbortar) { Cancelar-Creacion }
    Copy-Item $env:PACKER_LOG_PATH $logError -Force -ErrorAction SilentlyContinue
    # Packer oculta las variables secretas, pero por si acaso: la contraseña no se queda en el registro
    try {
        $txt = [IO.File]::ReadAllText($logError)
        foreach ($forma in @($Password, [System.Security.SecurityElement]::Escape($Password), (ConvertTo-Json $Password -Compress).Trim('"'))) {
            if ($forma) { $txt = $txt.Replace($forma, '********') }
        }
        [IO.File]::WriteAllText($logError, $txt, [Text.UTF8Encoding]::new($false))
    } catch {}
    Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
    $env:PKR_VAR_password = $null; $env:PACKER_LOG = $null; $env:PACKER_LOG_PATH = $null
    Salir-ConError "$_`nRegistro detallado guardado en:`n  $logError"
}
Pop-Location
}
try { $script:vigia.Stop(); $script:vigia.Dispose() } catch {}
$script:vigia = $null
Remove-Item $script:archivoListo -Force -ErrorAction SilentlyContinue
$env:PKR_VAR_password = $null; $env:PACKER_LOG = $null; $env:PACKER_LOG_PATH = $null
# Si se pidió cancelar justo al terminar Packer, se respeta
if (Test-Path $script:archivoAbortar) { Cancelar-Creacion }

# --- Dejar la base lista para clonar
$vmx = Get-ChildItem $salida -Filter *.vmx | Select-Object -First 1
if (-not $vmx) { Salir-ConError "No encuentro el .vmx en $salida" }

$lineas = Leer-Vmx $vmx.FullName
# agente = la base sabe leer el CD de configuración (3 = además se instaló con contraseña temporal y la real llega en el CD); usuario = con quién se creó (lo heredan sus máquinas)
$extra = @{ 'floppy0.present' = 'FALSE'; 'guestinfo.vmtareas.agente' = '3'; 'guestinfo.vmtareas.usuario' = [string]$Config.Usuario }
# Ficha 36: con qué idioma, teclado y zona se instaló (lo heredan sus máquinas; las bases de antes no lo llevan)
$extra['guestinfo.vmtareas.idioma'] = [string]$idiSel.Clave
$extra['guestinfo.vmtareas.teclado'] = [string]$tecSel.Clave
$extra['guestinfo.vmtareas.zona'] = [string]$zonaSel.Clave
if ($s.Tipo -eq 'manual') {
    # Base manual: no sabe leer el CD de configuración ni cambiar nombre/IP solas; sus máquinas se clonan tal cual
    $extra['guestinfo.vmtareas.agente'] = '0'
    $extra['guestinfo.vmtareas.manual'] = 'TRUE'
}
# Símbolo del sistema (ficha 5); Windows y Ubuntu llevan su logo de siempre
$simboloSis = switch ($s.Tipo) {
    'kali'   { 'kali' }
    'debian' { 'debian' }
    'arch'   { 'arch' }
    'rhel'   { 'rocky' }
    'manual' { $(if ($s.Clave -in 'OPNsense', 'pfSense') { 'cortafuegos' } elseif ($s.Clave -eq 'Proxmox') { 'proxmox' } elseif ($s.Clave -like 'Parrot*') { 'parrot' } elseif ($s.Clave -eq 'FreeBSD') { 'freebsd' } else { 'otro' }) }
    default  { $(if ($s.Clave -like 'Lubuntu*') { 'lubuntu' } else { '' }) }
}
if ($simboloSis) { $extra['guestinfo.vmtareas.sistema'] = $simboloSis }
foreach ($l in $lineas) {
    if ($l -match '^\s*([\w]+:\d+)\.fileName\s*=\s*".*\.iso"') { $extra["$($Matches[1]).startConnected"] = 'FALSE' }
}
Fijar-ValoresVmx $vmx.FullName $extra

Estado 'Creando la instantánea para clonar' 96
& $vmrun -T ws snapshot $vmx.FullName 'base' | Out-Null
if ($LASTEXITCODE -ne 0) { Salir-ConError "No se pudo crear la instantánea 'base'." }
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue

$script:est.estado = 'ok'; $script:est.paso = 'Base creada'; $script:est.pct = 100; $script:est.hasta = 100
Guardar-Estado
Escribir-Titulo "Base '$($s.Clave)' creada"
Write-Host "  $($vmx.FullName)"
Write-Host ""
Write-Host "Ya puedes crear máquinas a partir de ella."
Write-Host ""
Read-Host "Pulsa Enter para cerrar"
