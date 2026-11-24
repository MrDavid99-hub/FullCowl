@echo off
REM Quita Full Cowl de este PC (programa y accesos directos). No toca las maquinas, las bases ni las ISO.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0full-cowl\instalacion\desinstalar.ps1"
