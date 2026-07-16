[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$AllowInstall,
  [switch]$Launch,
  [string]$MsixPath
)

$ErrorActionPreference = 'Stop'

function Fail {
  param([string]$Message)
  throw "[codex-gold-safe-install] $Message"
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ([string]::IsNullOrWhiteSpace($MsixPath)) {
  $MsixPath = Get-ChildItem (Join-Path $env:USERPROFILE 'Downloads\codex-msix-repack') -Filter '*_patched.msix' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($MsixPath) -or -not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) {
  Fail "patched MSIX not found: $MsixPath"
}

$package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $package -or $package.Status -ne 'Ok') {
  Fail 'the existing Codex package is not registered and healthy; refusing to update'
}

$signature = Get-AuthenticodeSignature -LiteralPath $MsixPath
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
  Fail "patched MSIX signature is not valid: $($signature.StatusMessage)"
}

$thumbprint = $signature.SignerCertificate.Thumbprint
$trustedRoot = Get-ChildItem Cert:\CurrentUser\Root | Where-Object Thumbprint -eq $thumbprint
$trustedPublisher = Get-ChildItem Cert:\CurrentUser\TrustedPeople | Where-Object Thumbprint -eq $thumbprint
if (-not $trustedRoot -or -not $trustedPublisher) {
  Fail "signing certificate is not trusted for the current user: $thumbprint"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $MsixPath).Hash
Write-Host "[codex-gold-safe-install] existing package: $($package.PackageFullName) ($($package.SignatureKind), $($package.Status))"
Write-Host "[codex-gold-safe-install] patched MSIX sha256: $hash"
Write-Host "[codex-gold-safe-install] signer thumbprint: $thumbprint"
Write-Host '[codex-gold-safe-install] strategy: transactional package update; Remove-AppxPackage is never called'

if (-not $Install) {
  Write-Host '[codex-gold-safe-install] preflight passed; no package was changed'
  exit 0
}
if (-not $AllowInstall) {
  Fail 'refusing to install without -AllowInstall'
}
if (-not (Test-IsAdministrator)) {
  Fail 'transactional installation requires an elevated PowerShell so Windows AppX Deployment can trust the signing root'
}

$tempCertificate = Join-Path $env:TEMP ("codex-gold-signing-$thumbprint.cer")
try {
  Export-Certificate -Cert $signature.SignerCertificate -FilePath $tempCertificate -Force | Out-Null
  Import-Certificate -FilePath $tempCertificate -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
  Import-Certificate -FilePath $tempCertificate -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
  Write-Host "[codex-gold-safe-install] signing certificate trusted for LocalMachine: $thumbprint"
} finally {
  Remove-Item -LiteralPath $tempCertificate -Force -ErrorAction SilentlyContinue
}

try {
  Add-AppxPackage -Path $MsixPath -ForceApplicationShutdown -ForceUpdateFromAnyVersion -RetainFilesOnFailure -ErrorAction Stop
} catch {
  $remaining = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($remaining -and $remaining.Status -eq 'Ok') {
    Write-Host "[codex-gold-safe-install] update failed; existing package remains healthy: $($remaining.PackageFullName) ($($remaining.SignatureKind))"
  }
  throw
}

$installed = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Select-Object -First 1
if ($installed.Status -ne 'Ok' -or $installed.SignatureKind -ne 'Developer') {
  Fail "post-install verification failed: status=$($installed.Status) signature=$($installed.SignatureKind)"
}

Write-Host "[codex-gold-safe-install] installed package verified: $($installed.PackageFullName) ($($installed.SignatureKind), $($installed.Status))"
if ($Launch) {
  $appUserModelId = "$($installed.PackageFamilyName)!App"
  Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$appUserModelId"
  Write-Host "[codex-gold-safe-install] launched package app: $appUserModelId"
} else {
  Write-Host '[codex-gold-safe-install] Codex was not launched automatically'
}
