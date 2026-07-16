@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install-small-patch.ps1" -Install -AllowInstall -Launch
if errorlevel 1 (
  echo.
  echo Small patch installation failed. Existing Codex should remain installed.
  pause
  exit /b %errorlevel%
)
echo.
echo Small patch installation completed successfully.
pause
