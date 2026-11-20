@echo off
rem Lokal: holt aktuelle Preise (Billa, Penny, Spar) und oeffnet die Seite.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0abrufen.ps1"
if errorlevel 1 (
  echo.
  echo Abruf fehlgeschlagen - siehe Meldung oben.
  pause
  exit /b 1
)
start "" "%~dp0site\index.html"
