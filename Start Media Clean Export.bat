@echo off
set "SCRIPT=%~dp0MediaCleanExport.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
