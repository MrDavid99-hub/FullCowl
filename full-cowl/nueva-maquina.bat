@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nueva-maquina.ps1"
if errorlevel 1 pause
