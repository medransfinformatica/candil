@echo off
REM ============================================================
REM   CANDIL OS - Lanzador de la suite local (Windows)
REM   Uso:  start-candil.bat [serve^|build^|static^|stop^|status]
REM   Por defecto: serve  (deja las 7 apps en linea, puertos 8081-8087)
REM ============================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-candil.ps1" %*
if "%~1"=="" (
  echo.
  echo Presiona una tecla para cerrar esta ventana...
  pause >nul
)
endlocal
