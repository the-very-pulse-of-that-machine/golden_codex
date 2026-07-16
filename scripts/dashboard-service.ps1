[CmdletBinding()]
param(
  [ValidateSet('Start', 'Stop', 'Status')]
  [string]$Action = 'Start',
  [int]$Port = 8002
)

$ErrorActionPreference = 'Stop'
$runtimeRoot = Split-Path -Parent $PSScriptRoot
$dashboardScript = Join-Path $runtimeRoot 'config\ui_bridge.py'
$stateDirectory = Join-Path $env:LOCALAPPDATA 'CodexThemePatch'
$pidPath = Join-Path $stateDirectory 'dashboard.pid'
$stdoutPath = Join-Path $stateDirectory 'dashboard.stdout.log'
$stderrPath = Join-Path $stateDirectory 'dashboard.stderr.log'
$healthUrl = "http://127.0.0.1:$Port/api/health"

function Test-DashboardHealth {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 1
    return $response.StatusCode -eq 200
  } catch {
    return $false
  }
}

function Get-DashboardProcess {
  if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return $null }
  $processId = 0
  if (-not [int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$processId)) { return $null }
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
  if (-not $process -or -not $process.CommandLine) { return $null }
  if (-not $process.CommandLine.Contains('ui_bridge.py')) { return $null }
  return $process
}

function Find-Python {
  $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
  if ($launcher) { return @{ FilePath = $launcher.Source; Prefix = @('-3') } }
  $python = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($python) { return @{ FilePath = $python.Source; Prefix = @() } }
  throw '[codex-theme-dashboard] Python 3 was not found in PATH'
}

New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null

switch ($Action) {
  'Start' {
    if (Test-DashboardHealth) {
      Write-Host "[codex-theme-dashboard] already running: $healthUrl"
      exit 0
    }
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
      throw "[codex-theme-dashboard] port $Port is occupied by process $($listener.OwningProcess)"
    }
    if (-not (Test-Path -LiteralPath $dashboardScript -PathType Leaf)) {
      throw "[codex-theme-dashboard] dashboard entry not found: $dashboardScript"
    }
    $python = Find-Python
    $arguments = @($python.Prefix) + @("`"$dashboardScript`"", '--host', '127.0.0.1', '--port', [string]$Port)
    $process = Start-Process -FilePath $python.FilePath -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    [IO.File]::WriteAllText($pidPath, [string]$process.Id, [Text.Encoding]::ASCII)
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
      Start-Sleep -Milliseconds 250
      if (Test-DashboardHealth) {
        $listener = Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) {
          [IO.File]::WriteAllText($pidPath, [string]$listener.OwningProcess, [Text.Encoding]::ASCII)
        }
        Write-Host "[codex-theme-dashboard] started: http://127.0.0.1:$Port"
        exit 0
      }
      if ($process.HasExited) { break }
    }
    throw "[codex-theme-dashboard] failed to start; see $stderrPath"
  }
  'Stop' {
    $process = Get-DashboardProcess
    if ($process) {
      Stop-Process -Id $process.ProcessId -Force
      Write-Host "[codex-theme-dashboard] stopped process $($process.ProcessId)"
    } else {
      Write-Host '[codex-theme-dashboard] no managed dashboard process is running'
    }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
  }
  'Status' {
    [pscustomobject]@{
      Listening = Test-DashboardHealth
      Url = "http://127.0.0.1:$Port"
      ProcessId = (Get-DashboardProcess).ProcessId
      PidFile = $pidPath
    } | Format-List
  }
}
