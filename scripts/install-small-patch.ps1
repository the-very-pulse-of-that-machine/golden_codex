[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$AllowInstall,
  [switch]$Launch,
  [switch]$KeepBuild,
  [switch]$TrustedCurrentUserInstall,
  [switch]$SkipAutoRegistration,
  [switch]$RegisterAutoRepatchOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build-patch.ps1'
$installScript = Join-Path $PSScriptRoot 'install-patch.ps1'
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('ctp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

function Fail {
  param([string]$Message)
  throw "[codex-theme-small-patch] $Message"
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Clear-TemporaryBuild {
  param([string]$Path)
  $resolvedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolvedPath.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Fail "refusing to clean a build path outside the temporary directory: $resolvedPath"
  }
  if ([IO.Path]::GetFileName($resolvedPath) -notlike 'ctp-*') {
    Fail "refusing to clean an unexpected build directory: $resolvedPath"
  }
  if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
  }
}

function Install-AutoRepatchRuntime {
  $runtimeRoot = Join-Path $env:LOCALAPPDATA 'CodexThemePatch\current'
  New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
  foreach ($fileName in @('README.md', 'RELEASE_NOTES.md', 'install-small-patch.cmd', 'uninstall-patch.cmd', 'unified_config_loader.py')) {
    $source = Join-Path $projectRoot $fileName
    if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $runtimeRoot -Force }
  }
  foreach ($directoryName in @('scripts', 'vendor', 'config')) {
    $source = Join-Path $projectRoot $directoryName
    $destination = Join-Path $runtimeRoot $directoryName
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Name -ne 'dashboard.pid' } |
      Copy-Item -Destination $destination -Force
  }
  $startupDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
  New-Item -ItemType Directory -Force -Path $startupDirectory | Out-Null
  $startupPath = Join-Path $startupDirectory 'CodexThemePatchAutoReapply.cmd'
  $startupLines = @(
    '@echo off',
    'start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\CodexThemePatch\current\scripts\dashboard-service.ps1" -Action Start',
    'start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\CodexThemePatch\current\scripts\auto-repatch.ps1"'
  )
  [IO.File]::WriteAllLines($startupPath, $startupLines, [Text.Encoding]::ASCII)
  Write-Host "[codex-theme-small-patch] dashboard and automatic reapply registered: $startupPath"
  $dashboardService = Join-Path $runtimeRoot 'scripts\dashboard-service.ps1'
  & powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $dashboardService -Action Start
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "dashboard could not be started; run: $dashboardService"
  }
}

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf) -or -not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
  Fail 'small patch package is incomplete'
}

if ($RegisterAutoRepatchOnly) {
  Install-AutoRepatchRuntime
  exit 0
}

$packageBefore = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $packageBefore -or $packageBefore.Status -ne 'Ok') {
  Fail 'a healthy Codex installation is required'
}
if ($packageBefore.SignatureKind -eq 'Developer') {
  if (-not $SkipAutoRegistration) { Install-AutoRepatchRuntime }
  Write-Host "[codex-theme-small-patch] already patched: $($packageBefore.PackageFullName)"
  exit 0
}

$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($buildRoot).TrimEnd(':\'))
if ($drive.Free -lt 6GB) {
  Fail "at least 6 GB of temporary free space is required; available: $([Math]::Round($drive.Free / 1GB, 2)) GB"
}

Write-Host "[codex-theme-small-patch] source Codex: $($packageBefore.PackageFullName)"
Write-Host "[codex-theme-small-patch] temporary build: $buildRoot"
Write-Host '[codex-theme-small-patch] running compatibility dry run'
& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -DryRun -StableConfigOnly -OutputRoot $buildRoot
if ($LASTEXITCODE -ne 0) { Fail "compatibility dry run failed: $LASTEXITCODE" }

if (-not $Install) {
  Write-Host '[codex-theme-small-patch] preflight passed; no package was built or installed'
  if (-not $KeepBuild) { Clear-TemporaryBuild -Path $buildRoot }
  exit 0
}
if (-not $AllowInstall) { Fail 'refusing to install without -AllowInstall' }

Write-Host '[codex-theme-small-patch] building a temporary signed MSIX from the installed Codex package'
& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -BuildPackage -StableConfigOnly -InstallPrerequisites -OutputRoot $buildRoot
if ($LASTEXITCODE -ne 0) { Fail "temporary package build failed: $LASTEXITCODE" }

$msix = Get-ChildItem -LiteralPath $buildRoot -Filter '*_patched.msix' -File -Recurse |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $msix) { Fail 'temporary patched MSIX was not produced' }

$installArguments = @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installScript,
  '-Install', '-AllowInstall', '-MsixPath', $msix.FullName
)
if ($Launch) { $installArguments += '-Launch' }

if ($TrustedCurrentUserInstall) {
  $signature = Get-AuthenticodeSignature -LiteralPath $msix.FullName
  if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { Fail 'temporary MSIX signature is invalid' }
  $thumbprint = $signature.SignerCertificate.Thumbprint
  $trustedRoot = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $thumbprint
  $trustedPublisher = Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Thumbprint -eq $thumbprint
  if (-not $trustedRoot -or -not $trustedPublisher) { Fail 'automatic reapply certificate is not trusted for LocalMachine' }
  Add-AppxPackage -Path $msix.FullName -ForceApplicationShutdown -ForceUpdateFromAnyVersion -RetainFilesOnFailure
  $installExitCode = 0
  if ($Launch) {
    Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($packageBefore.PackageFamilyName)!App"
  }
} elseif (Test-IsAdministrator) {
  & powershell @installArguments
  $installExitCode = $LASTEXITCODE
} else {
  Write-Host '[codex-theme-small-patch] requesting administrator approval for the AppX transaction'
  $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $installArguments -Wait -PassThru
  $installExitCode = $process.ExitCode
}
if ($installExitCode -ne 0) { Fail "transactional install failed: $installExitCode" }

$packageAfter = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1
if (-not $packageAfter -or $packageAfter.Status -ne 'Ok' -or $packageAfter.Version -le $packageBefore.Version) {
  Fail 'post-install package verification failed'
}

Write-Host "[codex-theme-small-patch] installed and verified: $($packageAfter.PackageFullName)"
if (-not $SkipAutoRegistration) { Install-AutoRepatchRuntime }
if ($KeepBuild) {
  Write-Host "[codex-theme-small-patch] temporary build retained: $buildRoot"
} else {
  Clear-TemporaryBuild -Path $buildRoot
  Write-Host '[codex-theme-small-patch] temporary package and build files removed'
}
