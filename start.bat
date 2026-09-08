@echo off
setlocal
cd /d "%~dp0"
echo =================================================================
echo   CHANDIGARH POLICE CYBER CRIME INVESTIGATION PLATFORM (PS3-DWID)
echo =================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo Startup encountered an issue (Exit Code: %ERRORLEVEL%).
    pause
)
