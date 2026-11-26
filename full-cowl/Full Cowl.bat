@echo off
REM Full Cowl: crear bases, maquinas y laboratorios de VMware
REM Sin ninguna consola: conhost --headless (con -WindowStyle Hidden, Windows Terminal la ensena igual)
start "" "%SystemRoot%\System32\conhost.exe" --headless "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0abrir-nueva.ps1"
