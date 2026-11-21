@echo off
rem Reclaim launcher: double-click for the menu, or pass options, e.g.  reclaim -Scan -Preset Dev
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
where pwsh >nul 2>nul && if /i "%RECLAIM_PWSH%"=="1" set "PS=pwsh"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reclaim.ps1" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
