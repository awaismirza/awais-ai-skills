<#
.SYNOPSIS
  Match-verifier for deployment-log-triage. Answers "which commits touched class X, and when?"
  so you can sanity-check a triage.ps1 suspect (or find a culprit that landed just outside the
  candidate window). Also lists every changed .cs basename in the window, and flags generic-infra
  classes (MOHRDbContext etc.) that pollute the +40 code-overlap signal if matched naively.

.PARAMETER Repo
  Git checkout to inspect. Default C:\Source\mohr-api.
.PARAMETER Class
  A class/basename to reverse-look-up (e.g. RetrievePlanTasksHandler). Omit to list all changed .cs.
.PARAMETER Branch
  Default 'main'.
.PARAMETER Since
  git --since date. Default '10 days ago'.
.PARAMETER Onset
  Optional ISO onset time; when given, prints hours-from-onset for each matching commit
  (negative = commit landed AFTER onset, i.e. a deploy/clock-skew culprit).

.EXAMPLE
  debug.ps1 -Class RetrievePlanTasksHandler -Onset 2026-07-02T09:28Z
  debug.ps1                      # dump all changed .cs basenames + infra warnings
#>
[CmdletBinding()]
param(
  [string]$Repo = 'C:\Source\mohr-api',
  [string]$Class,
  [string]$Branch = 'main',
  [string]$Since = '10 days ago',
  [string]$Onset
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $Repo '.git'))) { throw "not a git checkout: $Repo" }

$INFRA = 'MOHRDbContext','MOHRDbContextModelSnapshot','Program','Startup','MOHRCoreModule','MOHRApplicationModule','MOHRWebHostModule','MOHREntityFrameworkModule','DbContextFactory'
$onsetT = $null
if ($Onset) { $onsetT = [datetime]::Parse($Onset, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }

$raw = & git -C $Repo log $Branch --since=$Since --date=iso-strict --name-only --pretty="COMMIT%x09%H%x09%ad%x09%s" 2>$null
$commits = @(); $cur = $null; $allCs = @{}
foreach ($line in $raw) {
  if ($line -match '^COMMIT\t') {
    $p = $line -split "`t"
    $cur = [pscustomobject]@{ Short=$p[1].Substring(0,10); Date=[datetime]::Parse($p[2],[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime(); Subject=$p[3]; Classes=New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase) }
    $commits += $cur; continue
  }
  if (-not $cur -or [string]::IsNullOrWhiteSpace($line)) { continue }
  if ($line -match '\.cs$') { $b=[System.IO.Path]::GetFileNameWithoutExtension($line); if($b){[void]$cur.Classes.Add($b); $allCs[$b]=($allCs[$b]+1)} }
}
"repo=$Repo branch=$Branch since='$Since'  commits=$($commits.Count)  distinct changed .cs=$($allCs.Count)"
""

if ($Class) {
  "commits that changed '$Class.cs':"
  $hits = $commits | Where-Object { $_.Classes.Contains($Class) }
  if (-not $hits) { "  (none)" }
  foreach ($c in ($hits | Sort-Object Date -Descending)) {
    $h = if ($onsetT) { "  [{0}h from onset]" -f [math]::Round(($onsetT-$c.Date).TotalHours,1) } else { '' }
    "  $($c.Short)  $($c.Date.ToString('yyyy-MM-ddTHH:mmZ'))$h  $($c.Subject)"
  }
  if ($INFRA -contains $Class) { ""; "WARNING: '$Class' is generic infra — matching it inflates code-overlap; triage.ps1 excludes it." }
} else {
  "all changed .cs basenames (count = # commits touching it), infra flagged:"
  foreach ($k in ($allCs.Keys | Sort-Object)) {
    $flag = if ($INFRA -contains $k) { '  <-- INFRA (excluded from +40)' } else { '' }
    "  {0,-55} x{1}{2}" -f $k, $allCs[$k], $flag
  }
}
