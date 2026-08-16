---
name: deployment-log-triage
description: 'Retrieve application logs from a MOHR API environment, cross-reference errors against recent commits, and rank the bugs most likely caused by a recent deployment. Backend (C#) errors correlate against mohr-api; frontend (JS) errors get a low-confidence temporal correlation against mohr-web. Use when errors spike after a release, when asked "did the last deploy break something?", or to triage production/QA log noise against code changes.'
---

# Deployment Log Triage

## Overview

Pulls `ApplicationLog` records from a MOHR environment and correlates them with recent commits to
surface bugs a deployment likely introduced.

**Core principle:** a *new* error whose onset is near a commit that touched the *same code* the
error's stack trace names is a likely deployment-caused bug. Rank by that.

**Two arms, different confidence:**
- **Backend** (C# errors, `logType=Backend`) → correlated against **mohr-api** commits. Stack traces
  name real files/classes, so file→commit matching is sound. This is the trustworthy arm.
- **Frontend** (JS errors, `logType=Frontend`) → **low-confidence, temporal only** against
  **mohr-web** commits. Deployed bundles are minified (`main.<hash>.js`) with no source maps and a
  `Date.now()` build version, so a JS frame can't be mapped to a source file. We can only say "these
  mohr-web commits landed around when the error started." Reported in a separate section, never scored
  like backend. (Unlock: emit `sourceMap:{hidden:true}` + archive `.js.map` in mohr-web.)

This skill ships in the **mohr-dev plugin** (`${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/`) so both `mohr-api`
and `mohr-web` can be open in one session. It contains:

| File | Role |
|---|---|
| `fetch-logs.sh` | Auth + paginated log fetch → one JSON file. |
| `triage.ps1` | **Self-contained** scorer: runs git history itself, groups signatures, scores, prints the ranked report. |
| `debug.ps1` | On-demand match-verifier: "which commits touched class X, when?" |

## Prerequisites

- `curl`, `jq`, `git` on PATH; PowerShell 7 (`pwsh`) for the analysis scripts.
- Local checkouts of **mohr-api** (default `C:\Source\mohr-api`) and, for the frontend arm,
  **mohr-web** (default `C:\Source\mohr-web`).

## Auth — browser token is the reliable path

**Both `az` and device-code auth currently FAIL** at the Entra app-registration layer
(AADSTS65001 / 650057 / 90008): the Azure CLI app (`04b07795-8ddb-461a-bbee-02f9e1bf7b46`) has no
consent for the MOHR SSO app (`73416665-cf8c-4d13-babf-aa483f8ba35e`). Until an Entra admin grants
that, use the **browser-token paste** method — it bypasses Entra entirely because the script caches
and reuses the *already-exchanged MOHR token*:

1. Log into the target web app in your browser (e.g. `https://qa.myocchealthrecord.dev`).
2. DevTools → Network → any `api/services/app/...` request → **copy** the `Authorization` header
   value to the clipboard (`Bearer ` prefix, quotes, whitespace are all fine — the script strips them).
3. Run the fetch with `--paste` — it reads the clipboard, validates `exp`, caches the token
   (~30–60 min reuse), and proceeds straight into the log fetch:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/fetch-logs.sh --paste
```

The cache filename is `$SCRATCH/token_<safehost>.jwt` (`<safehost>` = hostname, non-alphanumerics →
`_`) — you can still write it manually if clipboard access isn't available. On non-Windows, `--paste`
prompts on stdin instead of reading the clipboard. Subsequent runs reuse a valid cached token
without `--paste`.

**Fallbacks (only if consent gets fixed):** `--az` forces the Azure CLI path; `--device-code` forces
device-code. Both are kept in the script but non-functional today.

## Step 1 — Git preflight (guard, do this first)

The **mohr-api** `main` branch is the backend correlation baseline (and **mohr-web** `main` for the
frontend arm). Don't proceed on the wrong or a stale branch. Run against each repo you'll correlate:

```bash
git -C /c/Source/mohr-api rev-parse --abbrev-ref HEAD   # expect: main
git -C /c/Source/mohr-api status --porcelain            # tracked changes should be empty
git -C /c/Source/mohr-web rev-parse --abbrev-ref HEAD   # expect: main (frontend arm)
```

**If HEAD is not `main`, or tracked source is dirty, STOP and alert the user.** Suggest as
appropriate: `git switch main`; `git stash` uncommitted work; `git fetch origin && git pull --ff-only`
if stale. Untracked docs/tooling don't affect `git log` correlation — note them but they're not
blocking. (Prod triage uses the `release` branch — pass `-Branch release` to `triage.ps1`; still a
later phase.)

## Step 2 — Fetch logs

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/fetch-logs.sh   # defaults to qa-api.myocchealthrecord.dev
```

Pass a hostname as the first arg to target another env. `--fresh` forces re-auth. The script pages
the log endpoint until it covers the lookback window (default 7 days), then prints a JSON summary:

```json
{"output":"/c/.../mohr-log-triage/logs_qa_api_myocchealthrecord_dev.json",
 "fetched":842,"totalCount":842,"window_start":"...","earliest_seen":"...","truncated":false}
```

Note the `output` path — that's the input to `triage.ps1`. `totalCount` is the **all-time**
ApplicationLog count, not the window; ignore it for coverage. If `truncated` is true the `MAX_ROWS`
cap (5000) was hit before covering the window — raise it or narrow it via env vars
(`MAX_ROWS=20000 bash fetch-logs.sh` or `LOOKBACK_DAYS=3 ...`), and note it in the
report.

## Step 3 — Correlate, score, report (one command)

`triage.ps1` runs the git-history steps itself — no manual `git log` prep needed. Point it at the
fetched JSON and the repos:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/triage.ps1 `
  -LogJson '<output path from Step 2>' `
  -ApiRepo C:\Source\mohr-api -WebRepo C:\Source\mohr-web
```

Params: `-Branch` (default `main`; `release` for prod), `-LookbackDays` (7), `-WindowStart` (ISO
override), `-TolHours` (±2h onset tolerance for deploy/clock skew), `-Top` (10), `-Json <path>` to
also dump the full ranked set. It prints three sections: **genuine backend bugs** (ranked),
**validation/expected clusters** (de-ranked), and **frontend errors** (low-confidence).

### Scoring rubric (the documented contract; `triage.ps1` is the source of truth)

Signatures = `normalize(ErrorType + top MOHR stack frame Class.Method`; fall back to
`ServiceName.MethodName)`. Onset = earliest `creationTime`. Candidate commits = commits in
`[windowStart, onset + TolHours]`. Score (cap 100):

| Signal | Points |
|---|---|
| Candidate commit changed the file for a **defining** class (top frame / serviceName) — **backend only** | +40 |
| New — onset ≥ window start (no pre-window occurrence) | +25 |
| Onset within 6h / 24h / 48h of nearest candidate commit | +15 / +10 / +5 |
| Build `version` newer than any seen before onset | +10 |
| Volume: `min(10, round(3*log10(count)))` | +10 max |

Bands: High 80–100 · Medium 50–79 · Low <50. Tie-break by volume, then recency.

**What the script does beyond the raw rubric (learned from the trial run):**
- **Defining-class match only** — the +40 matches the class the error *names* (top frame +
  serviceName), and **excludes generic infra** (`MOHRDbContext`, `*Module`, `Program`, snapshots)
  that appears in nearly every EF stack and gets touched by unrelated migrations.
- **Validation bucketing** — `UserFriendlyException` / `AbpValidationException` /
  `AbpAuthorizationException` and benign transients ("Report is not available yet", query
  cancellations) are pulled out of the bug ranking into a separate section (surfaced only when they
  burst near a suspect commit). These are deliberate user-facing messages, not deploy breakage.
- **Onset tolerance** — candidate commits include those landing up to `TolHours` *after* onset, so a
  culprit deployed minutes before the first error (or seen during pre-merge testing) still scores.
  The report's "same-file commits (+/-onset)" line shows same-file commits in both directions.
- **Thin-baseline caveat** — novelty (+25) is only meaningful with enough pre-window baseline; the
  header prints a caveat when that baseline is < ~2 days.

## Step 4 — Present

Relay the top findings from the **genuine backend** section first (score + band, signature, count,
onset/last, suspect commit(s), signals, one example `exception`/`url`/`version`, and a recommended
next action). Summarize the validation clusters briefly. Present frontend findings separately and
explicitly labeled low-confidence. State up front: environment, repos/branch, window, total logs
scanned, and any truncation or thin-baseline caveat.

### Verifying a suspect (optional)

To sanity-check a match or hunt a culprit just outside the candidate window:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/debug.ps1 -Class RetrievePlanTasksHandler -Onset <iso>
pwsh ${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/debug.ps1     # dump all changed .cs + infra flags
```

## Later phases (not yet built)

- **Environment/baseurl selection.** `fetch-logs.sh` defaults to `qa-api.myocchealthrecord.dev`
  (pass a hostname arg). Prod pairs with the `release` branch (`-Branch release`).
- **Frontend correlation unlock.** Make it real by emitting hidden source maps in mohr-web
  (`sourceMap:{scripts:true,hidden:true}`) + archiving `.js.map` per build, or adopting an error
  tracker that ingests them. Until then the frontend arm stays temporal/low-confidence.

## Reference files (resolve from a mohr-api checkout)

- Auth exchange: `src/MOHR.Web.Host/Controllers/TokenAuthController.cs` — `ExternalAuthenticate` (~:369),
  `GetMSExternalUserInfo` (~:812; Entra token `aud` == WsFederation client id, `upn` == MOHR user, `sub` → providerKey).
- Logs endpoint + DTOs: `src/MOHR.Application/Logging/ApplicationLogAppService.cs` (~:97),
  `src/MOHR.Application/Logging/Dto/ApplicationLogDto.cs`, `RetrieveApplicationLogInput.cs`.
- Responses are ABP-wrapped (`.result…`); `fetch-logs.sh` unwraps. API JSON is **camelCase**
  (`creationTime`), though the server-side `sorting` param uses the C# property name (`CreationTime`).
