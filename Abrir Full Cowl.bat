@echo off
REM Abre Full Cowl (sin ninguna consola: conhost --headless)
start "" "%SystemRoot%\System32\conhost.exe" --headless "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0full-cowl\abrir-nueva.ps1"
