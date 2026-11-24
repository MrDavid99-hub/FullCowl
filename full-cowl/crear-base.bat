@echo off
set "PATH=%~dp0;%PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0crear-base.ps1"
