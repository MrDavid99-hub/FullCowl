param([string]$Pedido)   # lo crea la ventana (Mis máquinas > Exportar...)
# =====================================================================
#  Exporta una máquina a un único archivo .ova (se abre en cualquier
#  VMware o VirtualBox). Los clones enlazados salen completos.
# =====================================================================
. "$PSScriptRoot\comun.ps1"
if (-not $Pedido) { Salir-ConError "Ábrelo desde la ventana: Mis máquinas > Exportar..." }
$vmrun = Buscar-Vmrun
$P = Leer-Pedido $Pedido
$vmx = [string]$P.vmx
$destino = [string]$P.destino

Escribir-Titulo "Exportar '$($P.nombre)'"
$ovf = Join-Path (Split-Path $vmrun) 'OVFTool\ovftool.exe'
if (-not (Test-Path $ovf)) { Salir-ConError "No encuentro OVF Tool (viene con VMware Workstation):`n  $ovf" }
$estadoEnc = Leer-Encendidas $vmrun
if (-not $estadoEnc.Sabido) { Salir-ConError "VMware no contesta y no puedo saber si la máquina está apagada. Espera un poco (o cierra VMware y ábrelo de nuevo) y vuelve a exportar." }
if (@($estadoEnc.Lista) -contains $vmx.ToLower()) { Salir-ConError "La máquina está encendida. Apágala y vuelve a exportar." }
if (Get-ChildItem -LiteralPath (Split-Path $vmx) -Filter *.vmss -ErrorAction SilentlyContinue) {
    Salir-ConError "La máquina está suspendida. Enciéndela, apágala del todo y vuelve a exportar."
}
# El CD de configuración de las máquinas con dominio lleva la contraseña: no puede viajar en el .ova
if ((Leer-ValorVmx $vmx 'guestinfo.vmtareas.cdclave') -eq '1') {
    Limpiar-CdClave ([pscustomobject]@{ Carpeta = (Split-Path $vmx); Vmx = $vmx })
    if ((Leer-ValorVmx $vmx 'guestinfo.vmtareas.cdclave') -eq '1') {
        # Se espera 30 minutos desde que se creó para estar seguros de que terminó de configurarse. Si la persona
        # ya la encendió, la comprobó y la apagó (lo normal al exportar justo después de probarla), puede confirmarlo.
        Write-Host ""
        Write-Host "Esta máquina todavía lleva su CD de configuración (con la contraseña) porque se creó hace poco." -ForegroundColor Yellow
        Write-Host "Ese CD no puede viajar en el .ova. Si ya la has encendido, ha terminado de configurarse (tiene su IP," -ForegroundColor Yellow
        Write-Host "usuarios o dominio) y la has apagado, se puede quitar ahora." -ForegroundColor Yellow
        if ((Preguntar-SiNo "¿Ya terminó de configurarse y quieres quitar el CD para exportar?" $false) -and -not (Get-ChildItem -LiteralPath (Split-Path $vmx) -Filter '*.lck' -ErrorAction SilentlyContinue)) {
            Limpiar-CdClave ([pscustomobject]@{ Carpeta = (Split-Path $vmx); Vmx = $vmx }) -Forzar
        }
        if ((Leer-ValorVmx $vmx 'guestinfo.vmtareas.cdclave') -eq '1') {
            Salir-ConError "Esta máquina todavía lleva su CD de configuración (con la contraseña).`nEnciéndela, deja que termine de configurarse, apágala del todo (y ciérrala en VMware) y vuelve a exportar."
        }
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
Write-Host "  Origen:  $vmx"
Write-Host "  Destino: $destino"
Write-Host ""
Write-Host "Exportando... (puede tardar varios minutos según el tamaño del disco)" -ForegroundColor Cyan
# Con las marcas de Full Cowl (usuario, IP, agente...) para que «Importar» las recupere en el otro PC;
# si esta versión de OVF Tool no admite la opción, se exporta sin ellas
& $ovf --acceptAllEulas --overwrite --exportFlags=extraconfig "--name=$($P.nombre)" $vmx $destino
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destino)) {
    Write-Host "  Reintentando sin las marcas de Full Cowl..." -ForegroundColor Yellow
    & $ovf --acceptAllEulas --overwrite "--name=$($P.nombre)" $vmx $destino
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destino)) { Salir-ConError "OVF Tool no pudo exportar la máquina (mira los mensajes de arriba)." }

Escribir-Titulo "Exportada"
Write-Host "  $destino  ($(Formato-Tamano (Get-Item -LiteralPath $destino).Length))"
Write-Host ""
Write-Host "  Para abrirla en otro PC: VMware > File > Open > el archivo .ova"
Write-Host ""
Start-Process explorer.exe -ArgumentList "/select,`"$destino`""
Read-Host "Pulsa Enter para cerrar"
