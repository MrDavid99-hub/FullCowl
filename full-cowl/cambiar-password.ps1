# =====================================================================
#  Cambia la contraseña de las máquinas virtuales de este PC (password.sec).
#  Las máquinas nuevas que se creen a partir de bases hechas desde la 2.0 llevarán la nueva.
# =====================================================================
. "$PSScriptRoot\comun.ps1"

$archivoPw = Join-Path $PSScriptRoot 'password.sec'
$copiaPw = "$archivoPw.antes"
Escribir-Titulo "Cambiar la contraseña de las máquinas virtuales"
Write-Host "  - Las máquinas que ya existen conservan la contraseña que tienen."
Write-Host "  - Las máquinas nuevas llevarán la que escribas ahora, si su base es de la 2.0 o posterior."
Write-Host "    Las bases hechas antes conservan la contraseña con la que se instalaron."
Write-Host "  - Windows Server exige contraseñas complejas: 7 o más caracteres, con 3 de estos 4 tipos"
Write-Host "    (mayúsculas, minúsculas, números, símbolos) y sin el nombre del usuario."
Write-Host ""
if (Test-Path -LiteralPath $archivoPw) { Move-Item -LiteralPath $archivoPw -Destination $copiaPw -Force }
try {
    [void](Obtener-Password)
    Remove-Item -LiteralPath $copiaPw -Force -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Contraseña cambiada." -ForegroundColor Green
} catch {
    # Si se cancela a medias, se deja la anterior
    if ((Test-Path -LiteralPath $copiaPw) -and -not (Test-Path -LiteralPath $archivoPw)) { Move-Item -LiteralPath $copiaPw -Destination $archivoPw -Force }
    Write-Host "No se ha cambiado: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""
Read-Host "Pulsa Enter para cerrar"
