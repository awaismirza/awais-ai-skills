<#
.SYNOPSIS
  Deployment-log-triage scorer. Groups ApplicationLog records into error signatures,
  correlates BACKEND signatures against mohr-api commits (sound: C# stack frame -> changed file),
  and correlates FRONTEND signatures only temporally against mohr-web commits in the onset window
  (low-confidence: minified bundles have no source maps -> no file-level mapping).

  Self-contained: runs the git-history steps itself, so no manual `git log` prep is needed.

.PARAMETER LogJson
  Path to the JSON array of log records produced by fetch-logs.sh (its "output" field).
.PARAMETER ApiRepo
  Path to the mohr-api git checkout (backend correlation baseline). Default C:\Source\mohr-api.
.PARAMETER WebRepo
  Path to the mohr-web git checkout (frontend temporal correlation). Default C:\Source\mohr-web.
  If missing, frontend errors are still grouped/reported but without commit context.
.PARAMETER Branch
  Branch to correlate against in both repos. Default 'main'. (Prod triage: use 'release'.)
.PARAMETER LookbackDays
  Window length. Default 7. WindowStart = latest-log-time minus this many days unless -WindowStart is given.
.PARAMETER WindowStart
  ISO-8601 override for the window start (the deploy/novelty boundary). Optional.
.PARAMETER TolHours
  Onset tolerance for candidate commits (accounts for deploy/clock skew). Default 2.
.PARAMETER Top
  How many findings to print per section. Default 10.
.PARAMETER Json
  Optional path to also write the full ranked result set as JSON.

.NOTES
  Scoring rubric (per SKILL.md Step 4), deterministic — same logs + same git state => same scores:
    +40 candidate commit changed the file for a DEFINING class (top MOHR frame / serviceName)
    +25 novelty (onset >= window start; no occurrence in the pre-window baseline)
    +15/+10/+5 onset within 6h/24h/48h of the nearest candidate commit
    +10 error's build version newer than any seen before onset
    +N  volume: min(10, round(3*log10(count)))
  Backend "expected" exceptions (UserFriendlyException / AbpValidation / AbpAuthorization and
  transient DB-cancellations) are pulled into a separate validation bucket, not the bug ranking.
  Frontend signatures are never given a +40 (no source maps) and render in a low-confidence section.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$LogJson,
  [string]$ApiRepo = 'C:\Source\mohr-api',
  [string]$WebRepo = 'C:\Source\mohr-web',
  [string]$Branch = 'main',
  [int]$LookbackDays = 7,
  [string]$WindowStart,
  [double]$TolHours = 2,
  [int]$Top = 10,
  [string]$Json
)
$ErrorActionPreference = 'Stop'

function AsUtc($v) {
  # ConvertFrom-Json already yields [datetime]; re-parsing a DateTime via local culture corrupts m/d order.
  if ($v -is [datetime]) { return $v.ToUniversalTime() }
  return [datetime]::Parse([string]$v, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}
function Normalize([string]$s) {
  if (-not $s) { return '' }
  $s = $s -replace '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{guid}'
  $s = $s -replace ':\d+:\d+', ':{n}:{n}'
  $s = $s -replace '\.js:\d+', '.js:{n}'
  $s = $s -replace 'main\.[0-9a-f]{8,}\.js', 'main.{hash}.js'
  $s = $s -replace ':line \d+', ':line {n}'
  $s = $s -replace '\d{10,}', '{num}'
  $s = $s -replace '\d+', 'N'
  return $s.Trim()
}
# top application (MOHR.*) frame -> "Class.Method"; also returns the set of MOHR classes on the stack
function StackInfo([string]$stack) {
  $classes = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  $topFrame = $null
  if ($stack) {
    foreach ($m in [regex]::Matches($stack, 'at\s+(MOHR(?:\.[A-Za-z0-9_]+)+)\.([A-Za-z0-9_<>]+)\s*\(')) {
      $cls = ($m.Groups[1].Value -split '\.')[-1]
      [void]$classes.Add($cls)
      if (-not $topFrame) { $topFrame = "$cls.$($m.Groups[2].Value)" }
    }
  }
  return [pscustomobject]@{ Top = $topFrame; Classes = $classes }
}

# ---- git: load commits (hash/date/subject/changed .cs classes) for a repo, one call ----
function Load-Commits([string]$repo, [string]$branch, [string]$since) {
  $commits = @()
  if (-not (Test-Path (Join-Path $repo '.git'))) {
    Write-Warning "repo not found or not a git checkout: $repo (skipping its correlation)"
    return ,$commits
  }
  # one `git log --name-only` gives marker(hash/date/subject) + file paths per commit
  $raw = & git -C $repo log $branch --since=$since --date=iso-strict --name-only --pretty="COMMIT%x09%H%x09%ad%x09%s" 2>$null
  $cur = $null
  foreach ($line in $raw) {
    if ($line -match '^COMMIT\t') {           # regex tab, NOT -like 'COMMIT`t' (that matches a literal, never the tab)
      $p = $line -split "`t"
      $cur = [pscustomobject]@{
        Hash=$p[1]; Short=$p[1].Substring(0,10)
        Date=[datetime]::Parse($p[2], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        Subject=$p[3]
        Classes = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
      }
      $commits += $cur
      continue
    }
    if (-not $cur -or [string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -match '\.cs$') {
      $b = [System.IO.Path]::GetFileNameWithoutExtension($line)
      if ($b) { [void]$cur.Classes.Add($b) }
    }
  }
  return ,$commits
}

# generic infra that appears in nearly every stack / is touched by unrelated migrations -> not causal
$INFRA = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
'MOHRDbContext','MOHRDbContextModelSnapshot','Program','Startup','MOHRCoreModule','MOHRApplicationModule','MOHRWebHostModule','MOHREntityFrameworkModule','DbContextFactory' | ForEach-Object { [void]$INFRA.Add($_) }
function DefiningMinusInfra($set) { $out=@(); foreach($c in $set){ if(-not $INFRA.Contains($c)){ $out+=$c } }; ,$out }

# backend exceptions that are deliberate user-facing validation / benign transients, not deploy bugs
$EXPECTED_ERR = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
'UserFriendlyException','AbpValidationException','AbpAuthorizationException','AbpException' | ForEach-Object { [void]$EXPECTED_ERR.Add($_) }
function IsExpected([string]$errType, [string]$msg) {
  if ($EXPECTED_ERR.Contains($errType)) { return $true }
  if ($msg -match 'Report is not available yet') { return $true }               # transient "try again"
  if ($msg -match 'Operation cancelled by user|severe error occurred on the current command') { return $true } # query cancel
  return $false
}

# ---- load + group logs ----
$logs = Get-Content $LogJson -Raw | ConvertFrom-Json
if (-not $logs) { throw "no log records in $LogJson" }
$times = @(); foreach ($r in $logs) { try { $times += (AsUtc $r.creationTime) } catch {} }
$latestLog = ($times | Measure-Object -Maximum).Maximum
$earliestLog = ($times | Measure-Object -Minimum).Minimum
$winStart = if ($WindowStart) { AsUtc $WindowStart } else { $latestLog.AddDays(-$LookbackDays) }
$gitSince = (@($winStart, $earliestLog) | Measure-Object -Minimum).Minimum.AddDays(-1).ToString('yyyy-MM-dd')
$baselineDays = [math]::Round(($winStart - $earliestLog).TotalDays, 1)

$apiCommits = Load-Commits $ApiRepo $Branch $gitSince
$webCommits = Load-Commits $WebRepo $Branch $gitSince

$groups = @{}
foreach ($r in $logs) {
  try { $ct = AsUtc $r.creationTime } catch { continue }
  $isBackend = ($r.logType.value -eq 1)
  $si = StackInfo $r.stackTrace
  $sigClasses = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($c in $si.Classes) { [void]$sigClasses.Add($c) }
  $defining = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

  if ($isBackend) {
    $svc = [string]$r.serviceName
    if ($svc) { [void]$sigClasses.Add(($svc -split '\.')[-1]) }
    if ($si.Top) { $key = "BE|$($r.errorType)|$($si.Top)"; $label = "$($r.errorType) @ $($si.Top)" }
    else { $sn = if ($svc) { ($svc -split '\.')[-1] } else { 'Unknown' }; $key = "BE|$($r.errorType)|$sn.$($r.methodName)"; $label = "$($r.errorType) @ $sn.$($r.methodName)" }
    if ($si.Top) { [void]$defining.Add(($si.Top -split '\.')[0]) }
    if ($svc)    { [void]$defining.Add(($svc -split '\.')[-1]) }
  } else {
    $msg = Normalize ([string]$r.exception); if ($msg.Length -gt 90) { $msg = $msg.Substring(0,90) }
    $fe = if ($r.frontendErrorType) { $r.frontendErrorType.name } else { 'FE' }
    $key = "FE|$fe|$($r.errorType)|$msg"; $label = "[FE $fe] $($r.errorType): $msg"
  }

  if (-not $groups.ContainsKey($key)) {
    $groups[$key] = [pscustomobject]@{
      Key=$key; Label=$label; Backend=$isBackend; ErrType=[string]$r.errorType
      Count=0; Onset=$ct; Last=$ct
      Defining = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
      MaxVer=$null; Example=$r
    }
  }
  $g = $groups[$key]; $g.Count++
  if ($ct -lt $g.Onset) { $g.Onset = $ct; $g.Example = $r }
  if ($ct -gt $g.Last)  { $g.Last  = $ct }
  foreach ($c in $defining) { [void]$g.Defining.Add($c) }
  $vn = 0L; if ([long]::TryParse([string]$r.version, [ref]$vn) -and $vn -gt 0) { if ($null -eq $g.MaxVer -or $vn -gt $g.MaxVer) { $g.MaxVer = $vn } }
}

# version events (for "newer build than seen before onset")
$verEvents = @()
foreach ($r in $logs) { $vn=0L; if ([long]::TryParse([string]$r.version, [ref]$vn) -and $vn -gt 0) { try { $verEvents += [pscustomobject]@{ T=(AsUtc $r.creationTime); V=$vn } } catch {} } }

# ---- score ----
$results = @()
foreach ($g in $groups.Values) {
  $commitPool = if ($g.Backend) { $apiCommits } else { $webCommits }
  $defClasses = DefiningMinusInfra $g.Defining
  $signals = @(); $score = 0

  # candidate commits: within [windowStart, onset + tolerance]  (tolerance covers deploy/clock skew)
  $candHi = $g.Onset.AddHours($TolHours)
  $cands  = $commitPool | Where-Object { $_.Date -ge $winStart -and $_.Date -le $candHi }

  # +40 code overlap — BACKEND ONLY (frontend has no reliable file mapping)
  $matchCommits = @()
  if ($g.Backend) {
    foreach ($c in $cands) { foreach ($cls in $defClasses) { if ($c.Classes.Contains($cls)) { $matchCommits += $c; break } } }
    if ($matchCommits.Count -gt 0) { $score += 40; $signals += "code-overlap(+40)" }
  }
  # same-defining-file commits, either direction, nearest-to-onset (report-only)
  $fileCommits = @()
  if ($g.Backend) {
    foreach ($c in $commitPool) { foreach ($cls in $defClasses) { if ($c.Classes.Contains($cls)) { $fileCommits += [pscustomobject]@{ Short=$c.Short; Subject=$c.Subject; H=[math]::Round(($g.Onset-$c.Date).TotalHours,1) }; break } } }
    $fileCommits = $fileCommits | Sort-Object { [math]::Abs($_.H) } | Select-Object -First 3
  }
  # +25 novelty
  if ($g.Onset -ge $winStart) { $score += 25; $signals += "new(+25)" }
  # temporal proximity to nearest candidate (abs distance, so a just-after-onset deploy still counts)
  $nearest = $cands | Sort-Object { [math]::Abs(($g.Onset-$_.Date).TotalHours) } | Select-Object -First 1
  if ($nearest) {
    $h = [math]::Abs(($g.Onset - $nearest.Date).TotalHours)
    if ($h -le 6) { $score += 15; $signals += "onset~6h(+15)" }
    elseif ($h -le 24) { $score += 10; $signals += "onset~24h(+10)" }
    elseif ($h -le 48) { $score += 5; $signals += "onset~48h(+5)" }
  }
  # +10 newer build version than any before onset
  if ($g.MaxVer) {
    $priorMax = ($verEvents | Where-Object { $_.T -lt $g.Onset } | Measure-Object -Property V -Maximum).Maximum
    if (-not $priorMax -or $g.MaxVer -gt $priorMax) { $score += 10; $signals += "newer-version(+10)" }
  }
  # volume
  $vol = [math]::Min(10, [math]::Round(3 * [math]::Log10([math]::Max(1,$g.Count))))
  if ($vol -gt 0) { $score += $vol; $signals += "volume(+$vol)" }
  if ($score -gt 100) { $score = 100 }
  $band = if ($score -ge 80) {'High'} elseif ($score -ge 50) {'Medium'} else {'Low'}
  $expected = ($g.Backend -and (IsExpected $g.ErrType ([string]$g.Example.exception)))

  $results += [pscustomobject]@{
    Score=$score; Band=$band; Backend=$g.Backend; Expected=$expected; ErrType=$g.ErrType
    Label=$g.Label; Count=$g.Count
    Onset=$g.Onset.ToString('yyyy-MM-ddTHH:mmZ'); Last=$g.Last.ToString('yyyy-MM-ddTHH:mmZ')
    Signals=($signals -join ', ')
    Suspects=(($matchCommits | ForEach-Object { "$($_.Short) $($_.Subject)" }) -join ' || ')
    FileCommits=(($fileCommits | ForEach-Object { "$($_.Short) [$($_.H)h] $($_.Subject)" }) -join ' || ')
    NearWeb=$(if(-not $g.Backend -and $nearest){"$($nearest.Short) [$([math]::Round(($g.Onset-$nearest.Date).TotalHours,1))h] $($nearest.Subject)"}else{''})
    Defining=(@($defClasses) -join ',')
    ExMsg=([string]$g.Example.exception -replace "`n",' '); ExUrl=[string]$g.Example.url; ExVer=[string]$g.Example.version
  }
}

if ($Json) { $results | Sort-Object Score -Descending | ConvertTo-Json -Depth 4 | Out-File $Json -Encoding utf8 }

# ---- report ----
$env = [System.IO.Path]::GetFileNameWithoutExtension($LogJson) -replace '^logs_',''
$genuine    = $results | Where-Object { $_.Backend -and -not $_.Expected } | Sort-Object @{e='Score';d=$true},@{e='Count';d=$true},@{e='Last';d=$true}
$validation = $results | Where-Object { $_.Backend -and $_.Expected }      | Sort-Object @{e='Score';d=$true},@{e='Count';d=$true}
$frontend   = $results | Where-Object { -not $_.Backend }                  | Sort-Object @{e='Count';d=$true},@{e='Last';d=$true}

"# Deployment Log Triage"
"environment : $env"
"repos       : api=$ApiRepo  web=$WebRepo  branch=$Branch"
"window      : $($winStart.ToString('yyyy-MM-ddTHH:mmZ')) -> $($latestLog.ToString('yyyy-MM-ddTHH:mmZ'))  (${LookbackDays}d, tol +/-${TolHours}h)"
"logs        : $($logs.Count) records, span $($earliestLog.ToString('yyyy-MM-dd')) -> $($latestLog.ToString('yyyy-MM-dd'))"
"commits     : api=$($apiCommits.Count)  web=$($webCommits.Count) (since $gitSince)"
"signatures  : $($results.Count)  (backend $(($results|?{$_.Backend}).Count), frontend $(($results|?{-not $_.Backend}).Count))"
if ($baselineDays -lt 2) { "CAVEAT      : only ${baselineDays}d of pre-window baseline -> novelty (+25) is weak; recent errors may look 'new' when they are pre-existing." }
""

function Show([object[]]$rows, [string]$title, [int]$n) {
  "==== $title ===="
  if (-not $rows -or $rows.Count -eq 0) { "  (none)"; ""; return }
  $i = 0
  foreach ($r in ($rows | Select-Object -First $n)) {
    $i++
    "$i) [$($r.Score) $($r.Band)] $($r.Label)   x$($r.Count)"
    "    onset=$($r.Onset) last=$($r.Last)  signals: $($r.Signals)"
    if ($r.Suspects)    { "    suspect commit(s): $($r.Suspects)" }
    if ($r.FileCommits) { "    same-file commits (+/-onset): $($r.FileCommits)" }
    if ($r.NearWeb)     { "    nearest web commit (low-confidence): $($r.NearWeb)" }
    if ($r.Defining)    { "    defining: $($r.Defining)" }
    $m = $r.ExMsg; if ($m.Length -gt 150) { $m = $m.Substring(0,150) }
    "    ex: $m"
    "    url=$($r.ExUrl)  ver=$($r.ExVer)"
    ""
  }
}

Show $genuine    "GENUINE BACKEND BUGS (ranked)" $Top
Show $validation "VALIDATION / EXPECTED CLUSTERS (surfaced only if bursting near a suspect)" ([math]::Min($Top,8))
Show $frontend   "FRONTEND ERRORS (low-confidence: no source maps; web commits are temporal only)" $Top
