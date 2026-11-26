@echo off
REM Consola clasica minimizada y sin -ExecutionPolicy Bypass: oculta y con Bypass, el antivirus Check Point
REM de los institutos lo tomaba por malware (regla MuddyWater). Esa consola no hay que cerrarla.
start "" /min "%SystemRoot%\System32\conhost.exe" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -File "%~dp0full-cowl\abrir-nueva.ps1"
