@echo off
chcp 65001 >nul
cd /d "%~dp0"
REM Deja esta carpeta igual que la ultima version de GitHub (con Git o, si se instalo por descarga, sin el).
REM Toda la logica esta en actualizar.ps1 (la usa tambien el boton de Full Cowl).
REM Lo propio de este PC (config.local.json, password.sec, preferencias...) no se toca.
REM OJO: si cambias a mano algun script, ese cambio se pierde al actualizar.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0actualizar.ps1"
if errorlevel 1 (
  echo.
  echo Full Cowl se cierra solo si esta abierto. Si dice que hay archivos en uso, cierra las
  echo consolas abiertas, espera un minuto y repite. El detalle queda en full-cowl\estado\actualizar.log
  pause
  exit /b 1
)
timeout /t 5 >nul
