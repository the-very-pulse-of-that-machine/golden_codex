@echo off
setlocal
set "SCRIPT=%~dp0scripts\uninstall-patch.ps1"

if not exist "%SCRIPT%" (
  echo Uninstall script not found: %SCRIPT%
  exit /b 1
)

if "%~1"=="" (
  echo Disabling all Codex reasoning themes safely...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -DisableThemes -AllowDisable
  if errorlevel 1 exit /b %errorlevel%
  echo.
  echo Themes are disabled. Codex itself remains installed.
  echo To remove the patch completely, drag an official Codex MSIX onto this file.
  exit /b 0
)

echo Restoring official Codex package from: %~1
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -OfficialMsixPath "%~1" -AllowPackageRestore -Launch
exit /b %errorlevel%
