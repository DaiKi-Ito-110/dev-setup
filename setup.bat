@echo off
rem Set up a GitHub project on this PC (double-click, or: setup.bat owner/repo).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
pause
