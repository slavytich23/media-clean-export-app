@echo off
set "SCRIPT=%~dp0MediaCleanExport.ps1"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%"
