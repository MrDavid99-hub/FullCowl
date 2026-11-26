# =====================================================================
#  Accesos directos con icono para las herramientas (los .bat no pueden
#  llevar icono propio). Los crea si faltan y los corrige si tienen otro
#  icono o apuntan a otra carpeta; también los del escritorio y los
#  anclados a la barra de tareas que abran estas herramientas.
#  Lo ejecutan Actualizar.bat y Full Cowl al abrirse.
#
#  Si se cambia un icono, cambiar también el nombre del archivo: Windows
#  guarda los iconos en caché por ruta y seguiría mostrando el antiguo.
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
$raiz = $PSScriptRoot
$ws = New-Object -ComObject WScript.Shell
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# Los scripts ocultos se abren con conhost --headless: así no sale ninguna consola (con
# -WindowStyle Hidden, si Windows Terminal es la consola predeterminada, la ventana sale igual)
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'

# Lnk = dónde va el acceso · Bat = lo que abre (o Ps1 = script de PowerShell oculto) · Ventana: 1 normal, 7 minimizada
# Icono = archivo de iconos\ (o IconoRuta = otro .ico del repositorio)
$accesos = @(
    @{ Lnk = 'Actualizar.lnk';                         Bat = 'Actualizar.bat';                 Icono = 'actualizar';     Ventana = 1; Desc = 'Traer la última versión de GitHub' }
    @{ Lnk = 'full-cowl\Full Cowl.lnk'; Ps1 = 'full-cowl\abrir-nueva.ps1'; IconoRuta = 'full-cowl\recursos\full-cowl-icono-4.ico'; Ventana = 1; Desc = 'Full Cowl - máquinas virtuales de VMware' }
)

function Poner($acc, $a) {
    # Deja el acceso $acc (objeto de WScript.Shell) como indica $a. Devuelve $true si cambió algo.
    $icono = $(if ($a.IconoRuta) { Join-Path $raiz $a.IconoRuta } else { Join-Path $raiz "iconos\$($a.Icono).ico" }) + ',0'
    if ($a.Ps1) {
        $destino = $conhost
        $args2 = "--headless `"$powershell`" -NoProfile -ExecutionPolicy Bypass -STA -File `"$(Join-Path $raiz $a.Ps1)`""
        $dir = Split-Path (Join-Path $raiz $a.Ps1)
    } else {
        $destino = Join-Path $raiz $a.Bat
        $args2 = ''
        $dir = Split-Path $destino
    }
    if ($acc.TargetPath -eq $destino -and $acc.Arguments -eq $args2 -and $acc.IconLocation -eq $icono -and $acc.WorkingDirectory -eq $dir) { return $false }
    $acc.TargetPath = $destino; $acc.Arguments = $args2; $acc.WorkingDirectory = $dir
    $acc.IconLocation = $icono; $acc.WindowStyle = $a.Ventana; $acc.Description = $a.Desc
    $acc.Save()
    return $true
}

$cambiado = $false
# 1. Los de las carpetas del repositorio
foreach ($a in $accesos) {
    $acc = $ws.CreateShortcut((Join-Path $raiz $a.Lnk))
    if (Poner $acc $a) { $cambiado = $true }
}
# 2.0: «Full Cowl (interfaz nueva)» pasa a ser «Full Cowl» (la ventana de siempre se quitó)
# y «Instalar Packer» desaparece (Packer lo instalan el instalador y el asistente, ficha 33)
Remove-Item -LiteralPath (Join-Path $raiz 'full-cowl\Instalar Packer.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $raiz 'full-cowl\Full Cowl (interfaz nueva).lnk') -Force -ErrorAction SilentlyContinue

# 2. Los del escritorio y la barra de tareas que abran estas herramientas: se les pone el icono y la ruta actuales
$carpetasAntiguas = @()
foreach ($dirLnk in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
                      (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))) {
    if (-not $dirLnk -or -not (Test-Path $dirLnk)) { continue }
    foreach ($archivo in @(Get-ChildItem -LiteralPath $dirLnk -Filter *.lnk)) {
        $acc = $ws.CreateShortcut($archivo.FullName)
        $elegido = $null
        foreach ($a in $accesos) {
            if ($a.Ps1) {
                if ($acc.Arguments -like "*$(Split-Path $a.Ps1 -Leaf)*") { $elegido = $a }
                # Accesos de antes de la 2.0 que abrían la ventana de siempre (abrir-ventana.ps1): ahora abren Full Cowl
                elseif ($a.Ps1 -like '*abrir-nueva.ps1' -and $acc.Arguments -like '*abrir-ventana.ps1*') { $elegido = $a }
            } elseif ($acc.TargetPath) {
                $hoja = Split-Path $acc.TargetPath -Leaf
                $padre = Split-Path (Split-Path $acc.TargetPath) -Leaf
                $padreA = Split-Path (Split-Path (Join-Path $raiz $a.Bat)) -Leaf
                $esAntigua = $carpetasAntiguas -contains $padre -and $carpetasAntiguas -contains $padreA
                if ($hoja -eq (Split-Path $a.Bat -Leaf) -and ($padre -eq $padreA -or $esAntigua)) { $elegido = $a }
            }
            if ($elegido) { break }
        }
        if ($elegido -and (Poner $acc $elegido)) { $cambiado = $true }
    }
}

# Que Windows refresque su caché de iconos
if ($cambiado) { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\ie4uinit.exe') -ArgumentList '-show' -WindowStyle Hidden }
