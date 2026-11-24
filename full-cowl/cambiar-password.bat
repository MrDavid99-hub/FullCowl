@echo off
set "PATH=%~dp0;%PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cambiar-password.ps1"
