# Abre Full Cowl (ventana-nueva.ps1). Antes revisa que no haya errores de escritura en sus
# scripts ni en sus pantallas (.xaml): si los hay, los muestra en un aviso y los apunta en
# estado\interfaz.log (si no, la ventana simplemente no aparecería, porque se abre sin consola).
# La consola de PowerShell queda minimizada en la barra de tareas mientras Full Cowl está abierto: que diga qué es
try { $Host.UI.RawUI.WindowTitle = 'Full Cowl (no cierres esta ventana: cierra Full Cowl)' } catch {}
$errores = @()
$scripts = @((Join-Path $PSScriptRoot 'ventana-nueva.ps1'), (Join-Path $PSScriptRoot 'comun.ps1'), (Join-Path $PSScriptRoot 'config.ps1'))
$scripts += @(Get-ChildItem (Join-Path $PSScriptRoot 'interfaz') -Filter *.ps1 | ForEach-Object { $_.FullName })
$pantallas = @(Get-ChildItem (Join-Path $PSScriptRoot 'interfaz') -Filter *.xaml)
# Si nada ha cambiado desde la última revisión buena, no se repite (la ventana se abre antes)
$firma = (@($scripts | ForEach-Object { Get-Item -LiteralPath $_ }) + $pantallas | ForEach-Object { "$($_.Name)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }) -join ';'
$archivoFirma = Join-Path ([IO.Path]::GetTempPath()) 'FullCowl\revision-interfaz.txt'
$yaRevisado = $false
try { $yaRevisado = (Test-Path $archivoFirma) -and ([IO.File]::ReadAllText($archivoFirma) -eq $firma) } catch {}
if ($yaRevisado) { $scripts = @(); $pantallas = @() }
foreach ($archivo in $scripts) {
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($archivo, [ref]$tokens, [ref]$errs)
    foreach ($fallo in $errs) { $errores += "$(Split-Path $archivo -Leaf), línea $($fallo.Extent.StartLineNumber): $($fallo.Message)" }
}
foreach ($pantalla in $pantallas) {
    try { $doc = New-Object System.Xml.XmlDocument; $doc.Load($pantalla.FullName) }
    catch { $errores += "$($pantalla.Name): $($_.Exception.InnerException.Message)$($_.Exception.Message)" }
}
if ($errores) {
    Add-Type -AssemblyName System.Windows.Forms
    $texto = "Full Cowl no puede abrirse porque hay errores en sus archivos:`n`n" + (($errores | Select-Object -First 15) -join "`n") + "`n`nPrueba «Actualizar.bat» (vuelve a traer los archivos buenos). Si sigue igual, copia este mensaje al informar del problema."
    try {
        $dirLog = Join-Path $PSScriptRoot 'estado'
        if (-not (Test-Path $dirLog)) { [void](New-Item -ItemType Directory -Path $dirLog) }
        Add-Content -LiteralPath (Join-Path $dirLog 'interfaz.log') -Value ("[{0:dd/MM/yyyy HH:mm:ss}] {1}" -f (Get-Date), $texto) -Encoding UTF8
    } catch {}
    [void][System.Windows.Forms.MessageBox]::Show($texto, 'Full Cowl', 'OK', 'Error')
    exit 1
}
if (-not $yaRevisado) {
    try {
        $dirFirma = Split-Path $archivoFirma
        if (-not (Test-Path $dirFirma)) { [void](New-Item -ItemType Directory -Path $dirFirma) }
        [IO.File]::WriteAllText($archivoFirma, $firma)
    } catch {}
}
# «Actualizar solo al abrir» (Ajustes): antes de cargar la interfaz, con 10 s de margen y sin molestar si falla
try {
    $cfgLocal = Join-Path $PSScriptRoot 'config.local.json'
    if (Test-Path $cfgLocal) {
        $modoAct = [string]([IO.File]::ReadAllText($cfgLocal, [Text.Encoding]::UTF8) | ConvertFrom-Json).Actualizaciones
        if ($modoAct -eq 'Solo') {
            $psi = New-Object System.Diagnostics.ProcessStartInfo((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path (Split-Path $PSScriptRoot) 'actualizar.ps1')`" -Automatico")
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $pa = [System.Diagnostics.Process]::Start($psi)
            if (-not $pa.WaitForExit(40000)) { try { $pa.Kill() } catch {} }
        }
    }
} catch {}
& (Join-Path $PSScriptRoot 'ventana-nueva.ps1')
