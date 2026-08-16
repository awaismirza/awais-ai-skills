param([string]$TicketId)

$script = Join-Path $PSScriptRoot "fetch-ticket.py"

# fetch-ticket.py shells out to the Azure CLI (`az`), so Python AND az must live on
# the SAME OS. We prefer Windows when both are present, else WSL, else fail loudly.

# --- Detect a REAL Windows Python (ignore the Microsoft Store alias stub) ---
function Get-WindowsPython {
    foreach ($candidate in @("py", "python", "python3")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $src = $cmd.Source
        # The Store alias stub lives under ...\WindowsApps\ and only prints a nag.
        if ($src -and $src -match '\\WindowsApps\\') { continue }
        try {
            $ver = & $src --version 2>&1
            if ($LASTEXITCODE -eq 0 -and "$ver" -match 'Python') { return $src }
        } catch { }
    }
    return $null
}

$winPy = Get-WindowsPython
$winAz = [bool](Get-Command az -ErrorAction SilentlyContinue)

# --- Probe WSL for python3 + az (only if wsl exists) ---
# Use two separate, quote-free probes and check exit codes. Do NOT combine them into a
# single `echo "...;..."` string: Windows PowerShell 5.1 (which the `!`-prefixed command
# substitution uses via `powershell -File`) has a native-argument quoting bug that strips
# embedded double-quotes, so the `;`-separated payload gets truncated at the first token
# and `az` is silently reported missing even when installed. pwsh 7 is unaffected, but the
# skill runs under 5.1, so keep each probe a single unquoted token.
$hasWsl = [bool](Get-Command wsl -ErrorAction SilentlyContinue)
$wslPy = $false
$wslAz = $false
if ($hasWsl) {
    wsl bash -lc 'command -v python3 >/dev/null 2>&1' 2>$null; $wslPy = ($LASTEXITCODE -eq 0)
    wsl bash -lc 'command -v az      >/dev/null 2>&1' 2>$null; $wslAz = ($LASTEXITCODE -eq 0)
}

# --- Run on whichever OS has BOTH python and az ---
if ($winPy -and $winAz) {
    & $winPy @($script, $TicketId)
    exit $LASTEXITCODE
}

if ($wslPy -and $wslAz) {
    # Convert the Windows script path to a WSL /mnt path. Do NOT use a scriptblock
    # replacement (`-replace '...', { ... }`): that is a pwsh 7+ feature, and under
    # Windows PowerShell 5.1 (which the skill runs under) the scriptblock is stringified
    # literally, producing a garbage path. This two-step form works in both editions.
    $wslScript = $script -replace '\\', '/'
    if ($wslScript -match '^([A-Za-z]):/(.*)$') {
        $wslScript = "/mnt/$($matches[1].ToLower())/$($matches[2])"
    }
    wsl bash -lc "python3 '$wslScript' '$TicketId'"
    exit $LASTEXITCODE
}

# --- Neither OS has both: explain exactly what's missing and how to fix it ---
$winPyState = if ($winPy) { "yes ($winPy)" } else { "no (Store-alias stub ignored)" }
$wslState   = if ($hasWsl) { "python3=$(if($wslPy){'yes'}else{'no'})  az=$(if($wslAz){'yes'}else{'no'})" } else { "wsl not installed" }

$msg = @"
Cannot fetch the ticket: Python and the Azure CLI (az) must be available on the SAME OS.
fetch-ticket.py runs Python and shells out to 'az', so both have to be on one side.

Detected:
  Windows : python=$winPyState  az=$(if($winAz){'yes'}else{'no'})
  WSL     : $wslState

Fix ONE side, then re-run:
  - WSL (recommended here): install az ->  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
                            (python3 is already present in WSL)
  - Windows:                winget install Microsoft.AzureCLI  and  winget install Python.Python.3.12
                            (disable the Store alias: Settings > Apps > Advanced app settings > App execution aliases)
"@
Write-Error $msg
exit 1
