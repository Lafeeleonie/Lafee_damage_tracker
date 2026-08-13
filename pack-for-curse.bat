@echo off
setlocal
set "CURSE_SOURCE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\.pack-for-curse.ps1"
if errorlevel 1 (echo Echec de la creation de l'archive.& exit /b 1)
pause
