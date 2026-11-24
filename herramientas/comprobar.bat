@echo off
setlocal
rem Comprobacion automatica de Full Cowl (ficha 31). Se ejecuta con doble clic o desde una consola.
rem Hace falta Python 3.8 o mas nuevo. Si faltara, aqui se explica como instalarlo.
chcp 65001 >nul
set "PYTHONUTF8=1"
cd /d "%~dp0.."

set "PY="
py -3 -c "import sys; sys.exit(0 if sys.version_info[:2] >= (3, 8) else 1)" >nul 2>nul && set "PY=py -3"
if not defined PY python -c "import sys; sys.exit(0 if sys.version_info[:2] >= (3, 8) else 1)" >nul 2>nul && set "PY=python"
if not defined PY goto :sinpython

%PY% "%~dp0comprobar.py" %*
set "RESULTADO=%ERRORLEVEL%"
goto :fin

:sinpython
echo.
echo No encuentro Python 3.8 o mas nuevo en este PC y la comprobacion lo necesita.
echo Para instalarlo:
echo   1. Abre una consola y escribe:  winget install Python.Python.3.12
echo      (o bajalo de https://www.python.org/downloads/ y marca "Add python.exe to PATH").
echo   2. Cierra esta ventana y vuelve a ejecutar comprobar.bat.
set "RESULTADO=1"

:fin
echo.
if "%~1"=="" pause
endlocal & exit /b %RESULTADO%
