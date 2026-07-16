[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runtimeRoot = Split-Path -Parent $PSScriptRoot
$logDirectory = Join-Path $env:LOCALAPPDATA 'CodexThemePatch'
$logPath = Join-Path $logDirectory 'auto-repatch.log'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

function Write-AutoLog {
  param([string]$Message)
  Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ("{0} {1}" -f (Get-Date -Format o), $Message)
}

$mutex = [Threading.Mutex]::new($false, 'Local\CodexThemePatchAutoRepatch')
if (-not $mutex.WaitOne(0)) { exit 0 }
try {
  Start-Sleep -Seconds 20
  $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $package -or $package.Status -ne 'Ok') {
    Write-AutoLog 'skip: Codex package is unavailable or unhealthy'
    exit 0
  }
  if ($package.SignatureKind -ne 'Store') {
    Write-AutoLog "skip: package already patched ($($package.Version), $($package.SignatureKind))"
    exit 0
  }
  Write-AutoLog "detected Store update: $($package.PackageFullName)"
  $installer = Join-Path $PSScriptRoot 'install-small-patch.ps1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Install -AllowInstall -Launch -TrustedCurrentUserInstall -SkipAutoRegistration
  if ($LASTEXITCODE -ne 0) { throw "small patch installer failed: $LASTEXITCODE" }
  $installed = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1
  Write-AutoLog "success: $($installed.PackageFullName)"
} catch {
  Write-AutoLog "failure: $($_.Exception.Message)"
} finally {
  $mutex.ReleaseMutex()
  $mutex.Dispose()
}
