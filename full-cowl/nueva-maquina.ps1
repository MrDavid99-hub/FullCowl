param([string]$Pedido, [switch]$EnLote)   # Pedido: JSON de la ventana (sin él, pregunta por consola) · EnLote: lo llama laboratorio.ps1
# =====================================================================
#  Crea una máquina nueva para una práctica clonando una VM base.
#  Cada máquina va en su propia subcarpeta: <carpeta de máquinas>\<Nombre>\
# =====================================================================
. "$PSScriptRoot\comun.ps1"
$vmrun = Buscar-Vmrun

# --- Limpieza: CD de configuración con contraseña (Active Directory) de máquinas ya
#     configuradas y apagadas. Se quita cuando la VM lleva un rato funcionando desde que se creó.
foreach ($c in Leer-Clones) { if (-not $c.Externa) { try { Limpiar-CdClave $c } catch {} } }

$bases = @(Obtener-Bases)
if ($bases.Count -eq 0) { Salir-ConError "No hay ninguna VM base. Crea una primero." }
$red = Leer-RedNat
$usadas = @(Leer-Clones | Where-Object IP | ForEach-Object IP)
$vramDef = if ($Config.VRAM_MB -ne $null) { [int]$Config.VRAM_MB } else { 1024 }

# =====================================================================
#  1. Recoger lo que hay que hacer en $P
#     (de la ventana, o preguntando por consola: el resultado es el mismo)
# =====================================================================
if ($Pedido) {
    $P = Leer-Pedido $Pedido
}
else {
    $P = [pscustomobject]@{
        base = $null; nombre = $null; hostname = $null; tipo = 'linked'
        ram = $Config.RAM_MB; cpus = $Config.CPUs; vram = $vramDef
        ip = $null; ad = $null; extras = @(); actualizar = $false; paquetes = @(); arrancar = $true
    }

    Escribir-Titulo "Nueva máquina virtual"
    for ($i = 0; $i -lt $bases.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $bases[$i].Nombre) }
    Write-Host ""
    $op = Read-Host "¿De qué base?"
    if (-not ($op -as [int]) -or [int]$op -lt 1 -or [int]$op -gt $bases.Count) { Salir-ConError "Opción no válida." }
    $b = $bases[[int]$op - 1]
    $P.base = $b.Nombre

    Write-Host ""
    do {
        $n = (Read-Host "Nombre de la máquina (será también su carpeta)").Trim()
        $motivo = Validar-NombreMaquina $n
        if ($motivo) { Write-Host "  $motivo" -ForegroundColor Yellow }
    } until (-not $motivo)
    $P.nombre = $n

    $h = Nombre-Equipo $n
    $r = (Read-Host "Nombre de equipo dentro del sistema [$h]").Trim()
    $P.hostname = if ($r) { Nombre-Equipo $r } else { $h }

    Write-Host ""
    Write-Host "Tipo de copia:"
    Write-Host "  [Enter] Enlazada  -> segundos y ocupa poco (depende de la base: no la borres)"
    Write-Host "  C       Completa  -> independiente, tarda más y ocupa como la base entera"
    $P.tipo = if ((Read-Host "Elige") -match '^[cC]') { 'full' } else { 'linked' }

    $r = Read-Host "RAM en MB [$($Config.RAM_MB)]";  if ($r -as [int]) { $P.ram = [int]$r }
    $r = Read-Host "Procesadores [$($Config.CPUs)]"; if ($r -as [int]) { $P.cpus = [int]$r }
    $r = Read-Host "Memoria gráfica 3D en MB [$vramDef] (0 = sin aceleración 3D)"
    if ($r -ne '' -and ($r -as [int]) -ne $null) { $P.vram = [int]$r }

    function Pedir-IP($desde, $dnsDefecto) {
        if (-not $script:red) {
            Write-Host "  No encuentro la red NAT de VMware (VMnet8); escribe los datos a mano." -ForegroundColor Yellow
            $script:red = @{ Subred = '192.168.1.0'; Prefijo = 24; Puerta = '192.168.1.1' }
        }
        if (-not $dnsDefecto) { $dnsDefecto = $red.Puerta }
        Write-Host "  Red NAT de VMware: $($red.Subred)/$($red.Prefijo), puerta $($red.Puerta) (DHCP usa de .128 en adelante)" -ForegroundColor DarkGray
        do { $ip = Preguntar "  IP" (Proponer-IP $red $usadas $desde) } until (Es-IPv4 $ip)
        $pre = Preguntar "  Prefijo" $red.Prefijo
        do { $gw = Preguntar "  Puerta de enlace" $red.Puerta } until (Es-IPv4 $gw)
        $dns = Preguntar "  DNS (separados por comas)" $dnsDefecto
        return @{ addr = $ip; prefix = [int]$pre; gw = $gw; dns = @($dns -split '\s*,\s*' | Where-Object { $_ }) }
    }

    Write-Host ""
    if (-not $b.ConAgente) {
        Write-Host "Esta base es de una versión anterior y no admite opciones extra" -ForegroundColor Yellow
        Write-Host "(rehazla para tenerlas). Solo se pondrá el nombre de equipo." -ForegroundColor Yellow
    }
    elseif (Preguntar-SiNo "¿Configurar opciones extra (IP fija, servicios$(if ($b.EsWindows) { ', Active Directory' }))?") {
        if ($b.EsWindows) {
            Escribir-Titulo "Active Directory"
            Write-Host "  [Enter] Nada"
            if ($b.EsServidor) { Write-Host "  1       Crear un dominio nuevo (esta máquina será el controlador)" }
            Write-Host "  2       Unir a un dominio existente"
            $r = (Read-Host "Elige").Trim()
            if ($r -eq '1' -and $b.EsServidor) {
                do { $dom = (Read-Host "  Nombre del dominio (ej. empresa.local)").Trim().ToLower() } until (Es-Dominio $dom)
                $nb = ($dom.Split('.')[0] -replace '[^a-zA-Z0-9-]', '').ToUpper()
                if ($nb.Length -gt 15) { $nb = $nb.Substring(0, 15) }
                $nb = (Preguntar "  Nombre NetBIOS" $nb).ToUpper()
                Write-Host "  El controlador necesita IP fija:"
                $P.ip = Pedir-IP 10 $red.Puerta
                $P.ad = @{ modo = 'dc'; dominio = $dom; netbios = $nb; dcip = $P.ip.addr }
            }
            elseif ($r -eq '2') {
                $dcs = @(Leer-Clones | Where-Object { $_.Dominio -and $_.IP })
                $dom = $null; $dcip = $null; $nb = $null
                if ($dcs.Count) {
                    Write-Host "  Dominios creados con este script:"
                    for ($i = 0; $i -lt $dcs.Count; $i++) { Write-Host ("    {0}) {1}  (controlador {2}, IP {3})" -f ($i + 1), $dcs[$i].Dominio, $dcs[$i].Nombre, $dcs[$i].IP) }
                    $k = Read-Host "  Número (Enter = otro dominio)"
                    if ($k -as [int] -and [int]$k -ge 1 -and [int]$k -le $dcs.Count) {
                        $d = $dcs[[int]$k - 1]; $dom = $d.Dominio; $dcip = $d.IP; $nb = $d.Netbios
                    }
                }
                if (-not $dom) {
                    do { $dom = (Read-Host "  Nombre del dominio").Trim().ToLower() } until (Es-Dominio $dom)
                    do { $dcip = (Read-Host "  IP del controlador de dominio").Trim() } until (Es-IPv4 $dcip)
                    $nb = $dom.Split('.')[0].ToUpper()
                }
                $P.ad = @{ modo = 'unir'; dominio = $dom; netbios = $nb; dcip = $dcip }
                Write-Host "  (El DNS de la máquina apuntará al controlador $dcip. Se une con tu usuario de las VMs o, si no, con el administrador del dominio.)" -ForegroundColor DarkGray
                if (Preguntar-SiNo "  ¿IP fija para esta máquina?") { $P.ip = Pedir-IP 20 $dcip }
            }
            else {
                if (Preguntar-SiNo "¿IP fija?") { $P.ip = Pedir-IP 20 $red.Puerta }
            }
            Escribir-Titulo "Extras de Windows"
            $lista = @(Lista-ExtrasWindows $b.EsServidor | Where-Object { -not ($_.Clave -eq 'adds' -and $P.ad -and $P.ad.modo -eq 'dc') })
            $P.extras = @(Elegir-Varios $lista)
        }
        else {
            if (Preguntar-SiNo "¿IP fija?") { $P.ip = Pedir-IP 20 $red.Puerta }
            Escribir-Titulo "Software de Ubuntu"
            $sel = @(Elegir-Varios @(Lista-SoftwareUbuntu))
            $P.actualizar = $sel -contains 'actualizar'
            $P.paquetes = @($sel | Where-Object { $_ -ne 'actualizar' })
        }
    }
    $P.arrancar = $null   # se pregunta al final
}

# =====================================================================
#  2. Comprobar
# =====================================================================
$base = $bases | Where-Object { $_.Nombre -eq $P.base } | Select-Object -First 1
if (-not $base) { Salir-ConError "No encuentro la base '$($P.base)'." }
$nombre = [string]$P.nombre
$motivo = Validar-NombreMaquina $nombre
if ($motivo) { Salir-ConError $motivo }
$hostname = if ($P.hostname) { Nombre-Equipo $P.hostname } else { Nombre-Equipo $nombre }
$tipo = if ($P.tipo -eq 'full') { 'full' } else { 'linked' }
# Desechable: se borra sola al apagarse (ella o todo su laboratorio). Siempre enlazada: es rápida.
$desechable = [bool]$P.desechable
if ($desechable) { $tipo = 'linked' }
$ram = [int]$P.ram; $cpu = [int]$P.cpus; $vram = [int]$P.vram
# El usuario de la máquina es el que tiene su base (la máquina es una copia); el de Ajustes solo vale
# para las bases que se creen a partir de ahora
$usuarioVm = [string]$base.Usuario
if (-not $usuarioVm) { $usuarioVm = [string]$Config.Usuario }
# El usuario acaba en el CD de configuración (config.env se lee como órdenes de shell dentro de la máquina, como root):
# solo con la forma de un nombre de usuario, sin comillas ni espacios
if (-not (Usuario-SeguroEnOrden $usuarioVm)) {
    Salir-ConError "El usuario apuntado en la base '$($base.Nombre)' no es válido (solo letras, números, punto, guion y guion bajo). Revisa «Usuario» en Ajustes o vuelve a crear la base."
}
$esWindows = $base.EsWindows
# Las bases nuevas reciben la contraseña real en el CD de cada máquina: sin ella no se puede entrar. Se
# comprueba antes de crear nada.
if ($base.ClaveTemporal -and -not (Obtener-Password -SinPreguntar)) {
    Salir-ConError "Falta la contraseña de las VMs (password.sec) o no se puede leer: $script:motivoPassword`nMáquinas hechas sin ella no tendrían contraseña conocida."
}
# Windows Server exige contraseñas complejas al cambiarlas (el instalador las admitía todas): si la tuya no
# lo es, la máquina se quedaría con la temporal y no se podría entrar. Mejor avisarlo antes de crearla.
if ($base.ClaveTemporal -and $esWindows -and $base.EsServidor) {
    $pwComprobar = Obtener-Password -SinPreguntar
    $tipos = @(($pwComprobar -cmatch '[A-Z]'), ($pwComprobar -cmatch '[a-z]'), ($pwComprobar -match '\d'), ($pwComprobar -match '[^A-Za-z0-9]') | Where-Object { $_ })
    $llevaUsuario = ($usuarioVm.Length -ge 3) -and ($pwComprobar.IndexOf($usuarioVm, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    $pwCorta = $pwComprobar.Length -lt 7
    $pwComprobar = $null
    if ($pwCorta -or $tipos.Count -lt 3 -or $llevaUsuario) {
        Salir-ConError "Windows Server solo admite contraseñas complejas: al menos 7 caracteres, con 3 de estos 4 tipos (mayúsculas, minúsculas, números, símbolos) y sin el nombre del usuario.`nLa contraseña de las VMs de este PC no lo cumple. Cámbiala con full-cowl\cambiar-password.bat y repite."
    }
}
# Lo que va al CD de configuración acaba en un script que se ejecuta como root/SYSTEM dentro de
# la VM: solo extras y paquetes de la lista, e IP, dominio y NetBIOS con formato correcto
# (ficha 20) Extras-Validos deja solo los identificadores del catálogo de ESA base (Windows Server, Windows, apt, dnf o pacman);
# el agente de la máquina los vuelve a comprobar contra su propio catálogo antes de instalar nada.
$extras = @(); $paquetes = @()
if ($base.EsWindows) { $extras = @(Extras-Validos $base $P.extras) } else { $paquetes = @(Extras-Validos $base $P.paquetes) }
# Un controlador de dominio ya instala AD DS y DNS al crear el dominio
if ($P.ad -and [string]$P.ad.modo -eq 'dc') { $extras = @($extras | Where-Object { @('adds', 'dns') -notcontains $_ }) }
if ($P.ip) {
    $pre = 0
    if (-not (Es-IPv4 ([string]$P.ip.addr)) -or -not [int]::TryParse([string]$P.ip.prefix, [ref]$pre) -or $pre -lt 1 -or $pre -gt 32 -or
        ($P.ip.gw -and -not (Es-IPv4 ([string]$P.ip.gw))) -or @($P.ip.dns | Where-Object { $_ -and -not (Es-IPv4 ([string]$_)) }).Count) {
        Salir-ConError "Los datos de IP no son válidos."
    }
}
if ($P.ad) {
    if (-not (Es-Dominio ([string]$P.ad.dominio)) -or [string]$P.ad.netbios -notmatch '^[A-Za-z0-9-]{1,15}$' -or
        @('dc', 'unir') -notcontains [string]$P.ad.modo -or ($P.ad.dcip -and -not (Es-IPv4 ([string]$P.ad.dcip)))) {
        Salir-ConError "Los datos del dominio no son válidos."
    }
}
if (-not $base.ConAgente) { $P.ip = $null; $P.ad = $null; $extras = @(); $paquetes = @(); $P.actualizar = $false }
# Zona horaria (ficha 36): solo si se eligió una de la tabla cerrada Y distinta a la de la base. Si no, no se toca nada.
# La copia no recibe la clave, sino los valores ya resueltos (id de Windows o nombre IANA).
$zonaCopia = $null
if ($base.ConAgente -and $P.PSObject.Properties['zona'] -and [string]$P.zona -and [string]$P.zona -ne [string]$base.Zona) {
    $zonaCopia = @(Obtener-Zonas | Where-Object { $_.Clave -eq [string]$P.zona }) | Select-Object -First 1
    if ($zonaCopia) { Write-Host "  Zona horaria: $($zonaCopia.Nombre)" -ForegroundColor Green }
}

# =====================================================================
#  3. Clonar
# =====================================================================
$carpeta = Join-Path $Config.CarpetaVMs $nombre
$vmx = Join-Path $carpeta "$nombre.vmx"
New-Item -ItemType Directory -Force -Path $carpeta | Out-Null

Escribir-Titulo "Creando '$nombre' a partir de $($base.Nombre)"
Write-Host "Clonando..." -ForegroundColor Cyan
$snaps = & $vmrun -T ws listSnapshots $base.Vmx 2>&1
if (-not ($snaps -match '^base$')) {
    Remove-Item $carpeta -Recurse -Force
    Salir-ConError "La base no tiene la instantánea 'base'. Vuelve a crearla."
}
& $vmrun -T ws clone $base.Vmx $vmx $tipo '-snapshot=base' "-cloneName=$nombre"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $vmx)) {
    Remove-Item $carpeta -Recurse -Force -ErrorAction SilentlyContinue
    Salir-ConError "vmrun no pudo clonar la máquina. ¿Está la base abierta o encendida en VMware? Ciérrala y repite."
}

$valores = @{
    'displayName'           = $nombre
    'memsize'               = [string]$ram
    'numvcpus'              = [string]$cpu
    'cpuid.coresPerSocket'  = [string]$cpu
    # Aceleración 3D (Display > Accelerate 3D graphics) y memoria gráfica
    'mks.enable3d'          = $(if ($vram -gt 0) { 'TRUE' } else { 'FALSE' })
    'svga.graphicsMemoryKB' = [string]([Math]::Max(262144, $vram * 1024))
    'guestinfo.hostname'    = $hostname
    # Para el gestor de máquinas de la ventana
    'guestinfo.vmtareas.base'  = $base.Nombre
    'guestinfo.vmtareas.copia' = $tipo
    'guestinfo.vmtareas.usuario' = $usuarioVm
    # Ficha 36: idioma de la base y zona de esta máquina (la de la base si no se cambió), para su ficha
    'guestinfo.vmtareas.idioma'  = [string]$base.Idioma
    'guestinfo.vmtareas.zona'    = $(if ($zonaCopia) { [string]$zonaCopia.Clave } else { [string]$base.Zona })
}
# Hyper-V, Sandbox o WSL dentro de la VM: activar la virtualización anidada
if (@($extras | Where-Object { $ExtrasAnidados -contains $_ }).Count) { $valores['vhv.enable'] = 'TRUE' }

# --- CD de configuración (lo lee el agente de la base en el primer arranque)
if ($base.ConAgente) {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $tmp = Join-Path $carpeta '_cd'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $utf8 = [Text.UTF8Encoding]::new($false)
    $conClave = $false
    # Las bases hechas con contraseña temporal (agente 3) reciben la real en este CD; el CD se borra solo
    # (Limpiar-CdClave). Las bases anteriores ya la llevan dentro y solo la necesita el dominio.
    $claveReal = $null
    if ($base.ClaveTemporal -or ($esWindows -and $P.ad)) {
        $claveReal = Obtener-Password -SinPreguntar
        if (-not $claveReal) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue; Salir-ConError "Falta la contraseña de las VMs (password.sec): ábrela en Ajustes o en Crear base." }
        $conClave = $true
    }
    try {   # la carpeta _cd puede llevar la contraseña: se borra pase lo que pase
    if ($esWindows) {
        $datos = [ordered]@{ id = $id; hostname = $hostname; usuario = $usuarioVm; ip = $P.ip; ad = $P.ad; extras = $extras }
        if ($zonaCopia) { $datos.zona = [string]$zonaCopia.Win }
        if ($claveReal) { $datos.password = $claveReal }
        [IO.File]::WriteAllText((Join-Path $tmp 'config.json'), ($datos | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($true))
        Copy-Item (Join-Path $PSScriptRoot 'clon\config-windows.ps1') (Join-Path $tmp 'config.ps1')
    } else {
        $textoEnv = @(
            "ID='$id'"
            "HOSTNAME_VM='$hostname'"
            "USUARIO='$usuarioVm'"
            "IP_ADDR='$(if ($P.ip) { $P.ip.addr })'"
            "IP_PREFIX='$(if ($P.ip) { $P.ip.prefix })'"
            "IP_GW='$(if ($P.ip) { $P.ip.gw })'"
            "IP_DNS='$(if ($P.ip) { @($P.ip.dns) -join ',' })'"
            "ACTUALIZAR='$(([string][bool]$P.actualizar).ToLower())'"
            "PAQUETES='$($paquetes -join ' ')'"
            "ZONA='$(if ($zonaCopia) { [string]$zonaCopia.Iana })'"
        ) -join "`n"
        [IO.File]::WriteAllText((Join-Path $tmp 'config.env'), $textoEnv + "`n", $utf8)
        # La contraseña va en su propio archivo (sin comillas ni escapes: la lee temprano.sh tal cual)
        if ($claveReal -and $base.ClaveTemporal) { [IO.File]::WriteAllText((Join-Path $tmp 'clave'), $claveReal, $utf8) }
        foreach ($f in 'temprano.sh', 'config.sh') {
            $t = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "clon\$f")) -replace "`r`n", "`n"
            [IO.File]::WriteAllText((Join-Path $tmp $f), $t, $utf8)
        }
    }
    Crear-Iso -Carpeta $tmp -Destino (Join-Path $carpeta 'vmtareas.iso') -Etiqueta 'VMTAREAS'
    } finally { $claveReal = $null; Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    $valores['sata0.present']          = 'TRUE'
    $valores['sata0:2.present']        = 'TRUE'
    $valores['sata0:2.deviceType']     = 'cdrom-image'
    $valores['sata0:2.fileName']       = 'vmtareas.iso'
    $valores['sata0:2.startConnected'] = 'TRUE'
    $valores['guestinfo.vmtareas.cdclave'] = $(if ($conClave) { '1' } else { '0' })
    if ($P.ip) { $valores['guestinfo.vmtareas.ip'] = $P.ip.addr }
    if ($P.ad -and $P.ad.modo -eq 'dc') {
        $valores['guestinfo.vmtareas.dominio'] = $P.ad.dominio
        $valores['guestinfo.vmtareas.netbios'] = $P.ad.netbios
    }
}
if ($desechable) {
    $valores['guestinfo.vmtareas.desechable'] = $(if ($P.labid) { [string]$P.labid } else { [guid]::NewGuid().ToString('N').Substring(0, 12) })
}
# Marca para «Abrir en el navegador» (ficha 19): lleva un servidor web (Apache, Nginx o IIS)
if (($paquetes -contains 'apache') -or ($paquetes -contains 'nginx') -or ($extras -contains 'iis')) { $valores['guestinfo.vmtareas.web'] = '1' }
# Lo pedido (ficha 20), para enseñar cómo va cada extra y para la ficha del laboratorio. Solo identificadores del catálogo.
# OJO: el agente NO lee esta marca; lo que instala es la lista del CD de configuración, hecha aquí mismo.
$pedidos = @(@($extras) + @($paquetes) | Where-Object { $_ })
if ($pedidos.Count) { $valores['guestinfo.vmtareas.extras'] = ($pedidos -join ',') }
if ($P.lab) { $valores['guestinfo.vmtareas.lab'] = [string]$P.lab }
if ($P.labid) { $valores['guestinfo.vmtareas.labid'] = [string]$P.labid }
# Para el progreso (vigilante.ps1): cuándo se creó, en segundos UTC
$valores['guestinfo.vmtareas.creada'] = [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Fijar-ValoresVmx $vmx $valores
# Etiquetas y nota (ficha 18): una copia NO hereda las de su base. Se limpian y solo se ponen las que se hayan pedido
# ahora (la etiqueta «Lab …» de las máquinas de un laboratorio no se guarda: se calcula al leer)
try { Guardar-EtiquetasNota $vmx @($P.etiquetas) '' } catch { Write-Host "  Aviso: no se han podido poner las etiquetas ($($_.Exception.Message))." -ForegroundColor Yellow }

# Red de la primera tarjeta (la elige el laboratorio: NAT, segmento LAN...)
if ($P.red -and $P.red.tipo) {
    $tj = @(Leer-Tarjetas $vmx)
    if ($tj.Count) {
        $modelo = if ($tj[0].Modelo) { $tj[0].Modelo } elseif ($esWindows) { 'e1000e' } else { 'vmxnet3' }
        $nuevas = @([pscustomobject]@{ Tipo = [string]$P.red.tipo; Vnet = [string]$P.red.vnet; Pvn = [string]$P.red.pvn; Modelo = $modelo; Mac = $tj[0].Mac; MacFija = $tj[0].MacFija })
        $nuevas += @($tj | Select-Object -Skip 1)
        Guardar-Tarjetas $vmx $nuevas
    }
}

& $vmrun -T ws snapshot $vmx 'inicio' | Out-Null
# El vigilante borra las desechables y sigue el progreso de la configuración (aviso al terminar)
if ($desechable -or $base.ConAgente) { Iniciar-Vigilante }

# =====================================================================
#  4. Resumen
# =====================================================================
Escribir-Titulo "Máquina '$nombre' creada"
Write-Host "  Carpeta:   $carpeta"
Write-Host "  Equipo:    $hostname"
Write-Host "  Usuario:   $usuarioVm$(if ($usuarioVm -cne [string]$Config.Usuario) { "  (el de su base; en Ajustes pone '$($Config.Usuario)')" })"
Write-Host "  Recursos:  $ram MB de RAM, $cpu procesadores"
Write-Host "  Gráficos:  $(if ($vram -gt 0) { "aceleración 3D, $vram MB" } else { "sin aceleración 3D" })"
if ($P.ip) { Write-Host "  IP fija:   $($P.ip.addr)/$($P.ip.prefix)  puerta $($P.ip.gw)  DNS $(@($P.ip.dns) -join ', ')" }
if ($P.ad) {
    if ($P.ad.modo -eq 'dc') { Write-Host "  Dominio:   crea $($P.ad.dominio) ($($P.ad.netbios)) - será el controlador" }
    else { Write-Host "  Dominio:   se une a $($P.ad.dominio) (controlador $($P.ad.dcip); enciéndelo antes)" }
}
if ($extras.Count) { Write-Host "  Extras:    $($extras -join ', ')" }
if ($valores['vhv.enable']) { Write-Host "  Virtualización anidada activada (Hyper-V/Sandbox/WSL). Si VMware no arranca la VM, desactiva Hyper-V en tu PC." -ForegroundColor Yellow }
if ($P.actualizar -or $paquetes.Count) {
    $txt = @(); if ($P.actualizar) { $txt += 'actualizar sistema' }; $txt += $paquetes
    Write-Host "  Software:  $($txt -join ', ')"
}
Write-Host ""
Write-Host "  Todo se aplica solo en el primer arranque." -ForegroundColor Cyan
if ($esWindows) {
    Write-Host "  Windows se reiniciará una o varias veces. Mientras, verás en el escritorio" -ForegroundColor Cyan
    Write-Host "  'CONFIGURANDO - NO APAGAR.txt'; al acabar, 'Configuración de la VM.txt'." -ForegroundColor Cyan
} else {
    Write-Host "  El software se instala en segundo plano: puedes entrar mientras." -ForegroundColor Cyan
    Write-Host "  Al acabar aparece ~/configuracion-vm.txt (progreso: sudo tail -f /var/log/vmtareas.log)." -ForegroundColor Cyan
}
Write-Host "  Instantánea 'inicio' creada (volver a ella repite la configuración)."
if ($desechable) {
    $cuando = if ($P.lab) { "cuando estén apagadas todas las máquinas del laboratorio '$($P.lab)'" } else { 'cuando la apagues' }
    Write-Host "  DESECHABLE: se borrará sola $cuando." -ForegroundColor Yellow
}
Write-Host ""
if ($EnLote) { return }   # el laboratorio se encarga de arrancarlas

$arrancar = if ($P.arrancar -eq $null) { Preguntar-SiNo "¿Arrancarla ahora?" $true } else { [bool]$P.arrancar }
if ($arrancar) {
    Write-Host "Arrancando..." -ForegroundColor Cyan
    # vmrun se queda esperando si VMware abre un aviso (o tarda en abrirse): antes la ventana se quedaba en «Arrancando...» sin
    # decir nada más. Ahora se espera como mucho 90 s y siempre se avisa de cómo ha quedado.
    $procArr = $null
    try { $procArr = Start-Process -FilePath $vmrun -ArgumentList @('-T', 'ws', 'start', "`"$vmx`"", 'gui') -PassThru -WindowStyle Hidden } catch {}
    if (-not $procArr) {
        Write-Host "No se ha podido arrancar desde aquí. La máquina '$nombre' ya está creada: arráncala desde Full Cowl o VMware." -ForegroundColor Yellow
    } elseif ($procArr.WaitForExit(90000)) {
        if ($procArr.ExitCode -eq 0) {
            Write-Host ""
            Write-Host "Máquina '$nombre' creada y encendida. Ya puedes usarla en VMware." -ForegroundColor Green
            Write-Host "Full Cowl (Nueva máquina) dice cuándo termina de configurarse: «Lista para usar»." -ForegroundColor Cyan
        } else {
            Write-Host "VMware no ha podido arrancarla (código $($procArr.ExitCode)). La máquina '$nombre' ya está creada: arráncala desde Full Cowl o VMware." -ForegroundColor Yellow
        }
    } else {
        Write-Host "VMware sigue arrancándola (si se ha abierto un aviso en VMware, contéstalo). La máquina '$nombre' ya está creada." -ForegroundColor Yellow
    }
} else {
    Write-Host "Máquina '$nombre' creada (apagada). Arráncala cuando quieras desde Full Cowl o VMware." -ForegroundColor Green
}
if ($Pedido) {
    Write-Host "Esta ventana se cierra sola en 15 segundos."
    Start-Sleep 15
}
