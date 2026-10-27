@echo off
rem Undo setup.bat before returning the PC. Runs from a temp copy so this folder can be deleted too.
copy /y "%~dp0cleanup.ps1" "%TEMP%\dev-setup-cleanup.ps1" >nul
cd /d "%TEMP%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\dev-setup-cleanup.ps1" %* & pause & exit /b
