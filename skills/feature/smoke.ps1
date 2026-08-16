<#
.SYNOPSIS
  Smoke-probe the locally running MOHR full stack (backend + selected frontend apps).

.DESCRIPTION
  Assumes the user has already started the stack:
    - Backend  : MOHR.AppHost (e.g. preset "default")  -> http://localhost:22742
    - Frontend : yarn <app>:serve                       -> http://localhost:420x

  Probes wiring only (HTTP reachability). No auth, no DB writes. Auth-protected API
  calls are intentionally out of scope. A target that isn't running is reported as
  WARN (not FAIL) with the exact command to start it.

.PARAMETER Apps
  Comma-separated frontend apps to probe: auth, tenant, provider, employee, booking.
  Defaults to all four port-mapped apps.

.PARAMETER ApiBase
  Backend base URL. Default http://localhost:22742

.PARAMETER AppPortMap
  Optional hashtable override of app->port, e.g. @{ booking = 4203 }

.EXAMPLE
  powershell -File smoke.ps1 -Apps auth,tenant
#>
param(
  [string[]] $Apps = @('auth','tenant','provider','employee'),
  [string]   $ApiBase = 'http://localhost:22742',
  [hashtable] $AppPortMap = @{}
)

$ErrorActionPreference = 'Stop'

# Confirmed dev ports (see mohr-web package.json serve scripts).
$ports = @{
  auth     = 4200
  tenant   = 4201
  provider = 4202
  employee = 4204
  # booking has no fixed serve port in package.json; pass -AppPortMap @{ booking = <port> }
}
foreach ($k in $AppPortMap.Keys) { $ports[$k] = $AppPortMap[$k] }

$serveCmd = @{
  auth     = 'yarn auth:serve'
  tenant   = 'yarn tenant:serve'
  provider = 'yarn provider:serve'
  employee = 'yarn employee:serve'
  booking  = 'yarn booking:serve'
}

$results = New-Object System.Collections.Generic.List[object]

function Test-Endpoint {
  param([string]$Name, [string]$Url, [string]$StartHint)
  $row = [ordered]@{ Target = $Name; Url = $Url; Status = ''; Detail = '' }
  try {
    $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -UseBasicParsing -MaximumRedirection 3
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) {
      $row.Status = 'PASS'; $row.Detail = "HTTP $($resp.StatusCode)"
    } else {
      $row.Status = 'FAIL'; $row.Detail = "HTTP $($resp.StatusCode)"
    }
  } catch {
    $msg = $_.Exception.Message
    # Connection refused / no listener => not running => WARN with start hint.
    if ($msg -match 'Unable to connect|actively refused|No connection|timed out|name resolution') {
      $row.Status = 'WARN'; $row.Detail = "not running — start with: $StartHint"
    } else {
      # Reachable but returned an HTTP error status.
      $code = $null
      try { $code = [int]$_.Exception.Response.StatusCode } catch {}
      if ($code) { $row.Status = 'FAIL'; $row.Detail = "HTTP $code" }
      else { $row.Status = 'WARN'; $row.Detail = "not running — start with: $StartHint" }
    }
  }
  $results.Add([pscustomobject]$row)
}

Write-Host "MOHR stack smoke probe" -ForegroundColor Cyan
Write-Host "(wiring only — no auth, no DB writes)`n"

# --- Backend ---
Test-Endpoint -Name 'backend: swagger' -Url "$ApiBase/swagger/index.html" `
  -StartHint 'MOHR.AppHost preset "default" (dotnet run -- --MOHRAppHost:Preset "default")'

# --- Frontend apps ---
foreach ($app in $Apps) {
  $app = $app.Trim()
  if (-not $ports.ContainsKey($app)) {
    $results.Add([pscustomobject]@{
      Target = "frontend: $app"; Url = '(unknown port)'; Status = 'WARN'
      Detail = "no default port for '$app' — pass -AppPortMap @{ $app = <port> }"
    })
    continue
  }
  $port = $ports[$app]
  $hint = if ($serveCmd.ContainsKey($app)) { "$($serveCmd[$app]) (port $port)" } else { "serve $app on port $port" }
  Test-Endpoint -Name "frontend: $app" -Url "http://localhost:$port/" -StartHint $hint
}

# --- Report ---
$results | Format-Table -AutoSize Target, Status, Detail, Url | Out-String | Write-Host

$fail = ($results | Where-Object Status -eq 'FAIL').Count
$warn = ($results | Where-Object Status -eq 'WARN').Count
$pass = ($results | Where-Object Status -eq 'PASS').Count

Write-Host ("Summary: {0} PASS, {1} WARN, {2} FAIL" -f $pass, $warn, $fail) -ForegroundColor Cyan
if ($warn -gt 0) {
  Write-Host "WARN targets are simply not running — start them and re-run. Not a code failure." -ForegroundColor Yellow
}
# Exit non-zero only on a genuine FAIL (reachable but broken), so callers can gate on it.
if ($fail -gt 0) { exit 1 } else { exit 0 }
