# Instala Packer en segundo plano (lo lanza el asistente de primer arranque para no congelar la ventana).
# Escribe el resultado en el archivo -Resultado (JSON) y sale con 0 si ha ido bien.
param([string]$Resultado)
. (Join-Path $PSScriptRoot 'packer.ps1')
$r = Instalar-Packer
if ($Resultado) { try { [IO.File]::WriteAllText($Resultado, ($r | ConvertTo-Json -Compress), [Text.Encoding]::UTF8) } catch {} }
if ($r.Ok) { exit 0 } else { exit 1 }
