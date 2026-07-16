[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
  [Parameter(ParameterSetName = 'Disable')]
  [switch]$DisableThemes,
  [Parameter(ParameterSetName = 'Disable')]
  [switch]$AllowDisable,
  [Parameter(ParameterSetName = 'RestoreConfig')]
  [switch]$RestoreThemeConfig,
  [Parameter(ParameterSetName = 'RestoreConfig')]
  [switch]$AllowConfigRestore,
  [Parameter(ParameterSetName = 'RestorePackage', Mandatory = $true)]
  [string]$OfficialMsixPath,
  [Parameter(ParameterSetName = 'RestorePackage')]
  [switch]$AllowPackageRestore,
  [Parameter(ParameterSetName = 'RestorePackage')]
  [switch]$Launch
)

$ErrorActionPreference = 'Stop'
$runtimeDir = Join-Path $env:USERPROFILE '.codex\reasoning-theme'
$configPath = Join-Path $runtimeDir 'theme-settings.json'
$mirrorPath = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\reasoning-theme\theme-settings.json'
$backupDir = Join-Path $runtimeDir 'backups'

function Fail {
  param([string]$Message)
  throw "[codex-theme-safe-uninstall] $Message"
}

function Write-JsonAtomically {
  param([string]$Path, $Value)
  $directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $temporaryPath = "$Path.tmp"
  $json = $Value | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($temporaryPath, $json + "`n", [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Copy-FileAtomically {
  param([string]$Source, [string]$Destination)
  $directory = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $temporaryPath = "$Destination.tmp"
  [IO.File]::WriteAllBytes($temporaryPath, [IO.File]::ReadAllBytes($Source))
  Move-Item -LiteralPath $temporaryPath -Destination $Destination -Force
}

function Backup-ThemeConfig {
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Fail "theme config not found: $configPath"
  }
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  $backupPath = Join-Path $backupDir ('theme-settings.' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
  Copy-Item -LiteralPath $configPath -Destination $backupPath
  return $backupPath
}

function Wake-Codex {
  param($Package)
  Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($Package.PackageFamilyName)!App"
}

function Disable-AutoRepatch {
  $startupPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\CodexThemePatchAutoReapply.cmd'
  if (Test-Path -LiteralPath $startupPath -PathType Leaf) {
    Remove-Item -LiteralPath $startupPath -Force
  }
  $dashboardService = Join-Path $env:LOCALAPPDATA 'CodexThemePatch\current\scripts\dashboard-service.ps1'
  if (Test-Path -LiteralPath $dashboardService -PathType Leaf) {
    & powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $dashboardService -Action Stop
  }
}

$package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $package -or $package.Status -ne 'Ok') {
  Fail 'the existing Codex package is not registered and healthy; refusing to continue'
}

switch ($PSCmdlet.ParameterSetName) {
  'Disable' {
    if (-not $AllowDisable) { Fail 'refusing to disable themes without -AllowDisable' }
    $backupPath = Backup-ThemeConfig
    $settings = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($effort in @('minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')) {
      $settings.efforts.$effort = 'none'
    }
    Write-JsonAtomically -Path $configPath -Value $settings
    Write-JsonAtomically -Path $mirrorPath -Value $settings
    Wake-Codex -Package $package
    Write-Host "[codex-theme-safe-uninstall] all themes disabled; backup: $backupPath"
    Write-Host '[codex-theme-safe-uninstall] Codex will update automatically; no restart is required'
  }
  'RestoreConfig' {
    if (-not $AllowConfigRestore) { Fail 'refusing to restore theme config without -AllowConfigRestore' }
    $backup = Get-ChildItem -LiteralPath $backupDir -Filter 'theme-settings.*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if (-not $backup) { Fail "no theme config backup found under: $backupDir" }
    Get-Content -LiteralPath $backup.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    Copy-FileAtomically -Source $backup.FullName -Destination $configPath
    Copy-FileAtomically -Source $backup.FullName -Destination $mirrorPath
    Wake-Codex -Package $package
    Write-Host "[codex-theme-safe-uninstall] theme config restored: $($backup.FullName)"
  }
  'RestorePackage' {
    if (-not $AllowPackageRestore) { Fail 'refusing to restore the package without -AllowPackageRestore' }
    if (-not (Test-Path -LiteralPath $OfficialMsixPath -PathType Leaf)) { Fail "MSIX not found: $OfficialMsixPath" }
    $signature = Get-AuthenticodeSignature -LiteralPath $OfficialMsixPath
    if ($signature.Status -ne 'Valid') { Fail "MSIX signature is invalid: $($signature.StatusMessage)" }
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::OpenRead($OfficialMsixPath)
    try {
      $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
      $entry = $archive.GetEntry('AppxManifest.xml')
      if (-not $entry) { Fail 'MSIX manifest is missing' }
      $reader = [IO.StreamReader]::new($entry.Open())
      try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
      if ($archive) { $archive.Dispose() }
      $stream.Dispose()
    }
    if ($manifest.Package.Identity.Name -ne 'OpenAI.Codex') { Fail 'MSIX identity is not OpenAI.Codex' }
    Write-Host "[codex-theme-safe-uninstall] restoring package version: $($manifest.Package.Identity.Version)"
    Write-Host '[codex-theme-safe-uninstall] strategy: transactional update; Remove-AppxPackage is never called'
    Add-AppxPackage -Path $OfficialMsixPath -ForceApplicationShutdown -ForceUpdateFromAnyVersion -RetainFilesOnFailure
    $installed = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1
    if (-not $installed -or $installed.Status -ne 'Ok') { Fail 'package restore did not leave Codex healthy' }
    Write-Host "[codex-theme-safe-uninstall] package restored: $($installed.PackageFullName)"
    Disable-AutoRepatch
    Write-Host '[codex-theme-safe-uninstall] automatic reapply startup entry removed'
    if ($Launch) {
      Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($installed.PackageFamilyName)!App"
    }
  }
  default {
    Write-Host "[codex-theme-safe-uninstall] installed package: $($package.PackageFullName) ($($package.Status))"
    Write-Host '[codex-theme-safe-uninstall] no changes made'
    Write-Host '  Disable appearance: -DisableThemes -AllowDisable'
    Write-Host '  Restore appearance: -RestoreThemeConfig -AllowConfigRestore'
    Write-Host '  Restore official MSIX: -OfficialMsixPath <path> -AllowPackageRestore [-Launch]'
  }
}
