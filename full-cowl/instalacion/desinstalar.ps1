# =====================================================================
#  Desinstalar Full Cowl (ficha 33). Lo lanza «Desinstalar Full Cowl.bat».
#  Quita la carpeta del programa y sus accesos directos. NUNCA toca las
#  máquinas, las bases ni las ISO (dice dónde están). Pregunta antes de
#  borrar Packer y los ajustes de este PC. No pide administrador.
#  En una copia del repositorio (con carpeta .git) no hace nada.
# =====================================================================
param([switch]$Si)
$ErrorActionPreference = 'Continue'
$raiz = Split-Path (Split-Path $PSScriptRoot)
try { $Host.UI.RawUI.WindowTitle = 'Desinstalar Full Cowl' } catch {}
function Preguntar([string]$t, [string]$porDefecto) { if ($Si) { return $porDefecto }; $r = Read-Host $t; if (-not $r) { return $porDefecto }; return $r.Trim().ToLower() }
function Salir([int]$c) { if (-not $Si) { [void](Read-Host 'Pulsa Enter para cerrar') }; exit $c }

Write-Host ''
Write-Host "Desinstalar Full Cowl de «$raiz»" -ForegroundColor Cyan
if (Test-Path -LiteralPath (Join-Path $raiz '.git')) {
    Write-Host 'Esta carpeta es una copia del repositorio (tiene .git): no la borro desde aquí.' -ForegroundColor Yellow
    Write-Host 'Si de verdad quieres quitarla, bórrala a mano.' -ForegroundColor Yellow
    Salir 1
}
if (-not (Test-Path -LiteralPath (Join-Path $raiz 'full-cowl\abrir-nueva.ps1'))) { Write-Host 'Aquí no parece haber una instalación de Full Cowl.' -ForegroundColor Red; Salir 1 }

# Dónde están las máquinas (no se tocan): se dice para que el usuario decida
$cfg = $null
try { $cfg = [IO.File]::ReadAllText((Join-Path $raiz 'full-cowl\config.local.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}
Write-Host ''
Write-Host 'No se borra NINGUNA máquina, base ni ISO. Están en:' -ForegroundColor Green
if ($cfg) {
    foreach ($par in @(@('Máquinas', $cfg.CarpetaVMs), @('Bases', $cfg.CarpetaBases), @('ISO', $cfg.CarpetaISOs))) {
        if ($par[1]) { Write-Host "  $($par[0]): $($par[1])" }
    }
    Write-Host '  (Si quieres liberar espacio antes, usa Ajustes → Espacio y limpieza, o bórralas a mano después.)' -ForegroundColor DarkGray
} else { Write-Host '  (las carpetas que elegiste en el asistente)' }
Write-Host ''
if ((Preguntar '¿Quitar Full Cowl de este PC? [s/N]' 'n') -notlike 's*') { Write-Host 'Cancelado: no se ha cambiado nada.'; Salir 0 }

# Full Cowl abierto: hay que cerrarlo
try {
    $patron = [regex]::Escape((Join-Path $raiz 'full-cowl'))
    $abiertos = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $patron })
    if ($abiertos.Count) { Write-Host 'Full Cowl (o una de sus tareas) está abierto: ciérralo y vuelve a ejecutar esto.' -ForegroundColor Red; Salir 1 }
} catch {}

$guardarPacker = (Preguntar '¿Quitar también Packer (herramientas\packer)? [S/n]' 's') -like 'n*'
$guardarAjustes = (Preguntar '¿Borrar también tus ajustes de este PC (carpetas, contraseña cifrada, registros)? [s/N]' 'n') -notlike 's*'

# Accesos directos que abren esta instalación (escritorio, menú Inicio, barra de tareas)
$ws = New-Object -ComObject WScript.Shell
$quitados = 0
foreach ($dirLnk in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'),
                      (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))) {
    if (-not $dirLnk -or -not (Test-Path -LiteralPath $dirLnk)) { continue }
    foreach ($a in @(Get-ChildItem -LiteralPath $dirLnk -Filter *.lnk -ErrorAction SilentlyContinue)) {
        try {
            $acc = $ws.CreateShortcut($a.FullName)
            if ("$($acc.TargetPath) $($acc.Arguments)" -like "*$raiz*") { Remove-Item -LiteralPath $a.FullName -Force; $quitados++ }
        } catch {}
    }
}
Write-Host "Accesos directos quitados: $quitados"

# Archivos del programa (fuera de la carpeta no se borra nada)
Set-Location ([IO.Path]::GetTempPath())
$conservar = @()
if ($guardarPacker) { $conservar += (Join-Path $raiz 'herramientas\packer') }
if ($guardarAjustes) {
    foreach ($n in 'config.local.json', 'password.sec', 'preferencias.json', 'segmentos.json', 'plantillas-laboratorio.json', 'estado') { $conservar += (Join-Path $raiz "full-cowl\$n") }
}
function Se-Conserva([string]$ruta) { foreach ($c in $conservar) { if ($ruta -eq $c -or $ruta.StartsWith("$c\", [StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith("$ruta\", [StringComparison]::OrdinalIgnoreCase)) { return $true } }; return $false }
$fallos = 0
foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -Force -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)) {
    if (Se-Conserva $f.FullName) { continue }
    try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $fallos++ }
}
foreach ($d in @(Get-ChildItem -LiteralPath $raiz -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
    if (Se-Conserva $d.FullName) { continue }
    try { if (-not (Get-ChildItem -LiteralPath $d.FullName -Force)) { Remove-Item -LiteralPath $d.FullName -Force } } catch {}
}
try { if (-not (Get-ChildItem -LiteralPath $raiz -Force)) { Remove-Item -LiteralPath $raiz -Force } } catch {}
Write-Host ''
if ($fallos) { Write-Host "Hecho, pero $fallos archivos no se han podido borrar (en uso): bórralos a mano en «$raiz»." -ForegroundColor Yellow }
else { Write-Host 'Full Cowl se ha quitado de este PC.' -ForegroundColor Green }
if ($conservar.Count) { Write-Host "Se ha conservado en «$raiz» lo que pediste guardar." -ForegroundColor DarkGray }
Salir 0
