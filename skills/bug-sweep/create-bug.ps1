<#
.SYNOPSIS
  Create an AZDO Bug work item from a deployment-log-triage finding, with signature-tag dedupe.
.DESCRIPTION
  Dedupe first: if an open Bug already carries tag "sig:<Signature>", prints its id/url with
  duplicate=true and creates nothing. Otherwise creates the Bug in the MOHR\Engineering area
  with SystemInfoFile -> System Info and ReproFile -> Repro Steps (both plain text, rendered
  with line breaks) and tags "deployment-log-triage; sig:<Signature>".
.PARAMETER Title
  Work item title, e.g. "[QA deploy] NullReferenceException in PlanTasksHandler.Handle".
.PARAMETER Signature
  Signature slug (lowercase a-z0-9 and dashes) — the dedupe key.
.PARAMETER SystemInfoFile
  Plain-text file with the triage/environment metadata for the System Info field.
.PARAMETER ReproFile
  Plain-text file with best-effort reproduction steps for the Repro Steps field.
.PARAMETER Application
  MOHR project's required Custom.ApplicationName field. Pick-list enforced. Default Client.
.PARAMETER Module
  MOHR project's required Custom.ModuleName field. Pick-list enforced. Default N/A.
.PARAMETER Discovered
  MOHR project's required Custom.discovered field. Pick-list enforced. Default QA.
.PARAMETER WhatIf
  Print the az commands that would run, execute nothing, exit 0.
.OUTPUTS
  Single-line JSON: {"id":123,"url":"https://dev.azure.com/<org>/<proj>/_workitems/edit/123","duplicate":false}
#>
param(
  [Parameter(Mandatory)][string]$Title,
  [Parameter(Mandatory)][string]$Signature,
  [Parameter(Mandatory)][string]$SystemInfoFile,
  [Parameter(Mandatory)][string]$ReproFile,
  [ValidateSet('Client','Employee','Host','Provider')]
  [string]$Application = 'Client',
  [ValidateSet('Admin Centre','Assessment','Booking Dashboard','Bookings','Clinical Dashboard',
    'Config Centre','Data fix','EHM','Employee Booking System','HS','ICM','IP','N/A',
    'Occupational Hygiene','Patient File','PE','Platform-wide','PSR','Reporting','Tenant','WB')]
  [string]$Module = 'N/A',
  [ValidateSet('Demo','Dev','DFR Non-Production','DFR Production','Production','QA','Staging')]
  [string]$Discovered = 'QA',
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'

if ($Signature -notmatch '^[a-z0-9][a-z0-9-]{0,119}$') {
  throw "Signature must be a lowercase slug (a-z0-9, dashes): '$Signature'"
}
if (-not (Test-Path $SystemInfoFile)) { throw "SystemInfoFile not found: $SystemInfoFile" }
if (-not (Test-Path $ReproFile))      { throw "ReproFile not found: $ReproFile" }

# Org/project single source of truth lives in the ticket skill's fetcher — parse, don't duplicate.
$fetcher = Join-Path $PSScriptRoot '..\ticket\fetch-ticket.py'
$src     = Get-Content $fetcher -Raw
$org     = [regex]::Match($src, 'AZDO_ORG\s*=\s*"([^"]+)"').Groups[1].Value
$project = [regex]::Match($src, 'AZDO_PROJECT\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $org -or -not $project) { throw "Could not parse AZDO_ORG/AZDO_PROJECT from $fetcher" }
$orgUrl = "https://dev.azure.com/$org"

# System Info / Repro Steps are HTML fields. Render plain text as normal text with line
# breaks (no <pre> — the AZDO UI shows that as a code block). Both encoded values ride the
# same az.cmd command line (~8191-char cmd limit), so cap each ENCODED string: entity-dense
# text inflates unpredictably, so shrink the raw text until it fits.
function ConvertTo-AzdoHtml([string]$Path, [int]$Cap) {
  $raw    = Get-Content $Path -Raw
  $marker = "`n[truncated for CLI arg limit - full detail in the triage report]"
  $keep   = $raw.Length
  do {
    $body = if ($keep -lt $raw.Length) { $raw.Substring(0, $keep) + $marker } else { $raw }
    $html = [System.Net.WebUtility]::HtmlEncode($body) -replace "`r?`n", '<br/>'
    $keep = [int]($keep * 0.75)
  } while ($html.Length -gt $Cap -and $keep -gt 0)
  return $html
}
$sysHtml   = ConvertTo-AzdoHtml $SystemInfoFile 3500
$reproHtml = ConvertTo-AzdoHtml $ReproFile 3500

$tag  = "sig:$Signature"
$wiql = "SELECT [System.Id], [System.Tags] FROM WorkItems WHERE [System.TeamProject] = '$project' AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed' AND [System.Tags] CONTAINS '$tag'"

# Custom.discovered / ApplicationName / ModuleName are alwaysRequired in the MOHR Bug process;
# values are ValidateSet-enforced above to match the project's pick-lists.
$createArgs = @('boards','work-item','create','--type','Bug','--title',$Title,
  '--organization',$orgUrl,'--project',$project,'--output','json',
  '--area',"$project\Engineering",
  '--fields',"Microsoft.VSTS.TCM.SystemInfo=$sysHtml","Microsoft.VSTS.TCM.ReproSteps=$reproHtml",
  "System.Tags=deployment-log-triage; $tag",
  "Custom.discovered=$Discovered","Custom.ApplicationName=$Application","Custom.ModuleName=$Module")

if ($WhatIf) {
  Write-Host "WOULD RUN (dedupe): az boards query --wiql `"$wiql`" --organization $orgUrl --output json"
  Write-Host "WOULD RUN (create): az $($createArgs -join ' ')"
  exit 0
}

$existing = az boards query --wiql $wiql --organization $orgUrl --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "az boards query failed (is the azure-devops extension installed and are you logged in?)" }
# CONTAINS is a substring match ('sig:foo' matches 'sig:foo-bar'), so verify the exact tag here.
$dup = @($existing) | Where-Object { ($_.fields.'System.Tags' -split ';').Trim() -contains $tag } | Select-Object -First 1
if ($dup) {
  $id = if ($dup.id) { $dup.id } else { $dup.fields.'System.Id' }
  [pscustomobject]@{ id = $id; url = "$orgUrl/$project/_workitems/edit/$id"; duplicate = $true } | ConvertTo-Json -Compress
  exit 0
}

$created = az @createArgs | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $created.id) { throw "az boards work-item create failed" }
[pscustomobject]@{ id = $created.id; url = "$orgUrl/$project/_workitems/edit/$($created.id)"; duplicate = $false } | ConvertTo-Json -Compress
