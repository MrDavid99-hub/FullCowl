@echo off
REM Instala Full Cowl desde esta carpeta (el ZIP descomprimido). No pide administrador.
REM Si Windows avisa (SmartScreen), pulsa "Mas informacion" y "Ejecutar de todas formas".
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0full-cowl\instalacion\instalar-completo.ps1" -Origen "%~dp0."
if errorlevel 1 pause
