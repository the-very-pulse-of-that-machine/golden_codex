[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
$artifact = Get-ChildItem (Join-Path $env:USERPROFILE 'Downloads\codex-msix-repack') -Filter '*_patched.msix' -File -Recurse -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
$runtimeConfig = Join-Path $env:USERPROFILE '.codex\reasoning-theme\theme-settings.json'
$artifactManifestVersion = $null
if ($artifact) {
  $layoutManifest = Join-Path (Split-Path -Parent (Split-Path -Parent $artifact.FullName)) 'package\AppxManifest.xml'
  if (Test-Path -LiteralPath $layoutManifest -PathType Leaf) {
    [xml]$manifest = Get-Content -Raw -LiteralPath $layoutManifest
    $artifactManifestVersion = $manifest.Package.Identity.Version
  }
}
$dashboard = Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 8002 -State Listen -ErrorAction SilentlyContinue

[pscustomobject]@{
  PackageFullName = $package.PackageFullName
  Version = $package.Version
  SignatureKind = $package.SignatureKind
  Status = $package.Status
  InstallLocation = $package.InstallLocation
  LatestArtifact = $artifact.FullName
  ArtifactManifestVersion = $artifactManifestVersion
  ArtifactSignature = if ($artifact) { (Get-AuthenticodeSignature $artifact.FullName).Status } else { $null }
  RuntimeConfig = $runtimeConfig
  RuntimeConfigExists = Test-Path -LiteralPath $runtimeConfig -PathType Leaf
  DashboardListening = $null -ne $dashboard
} | Format-List
