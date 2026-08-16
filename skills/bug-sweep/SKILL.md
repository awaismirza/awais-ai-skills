---
name: bug-sweep
description: 'Sweep a MOHR environment for deployment-caused bugs and drive them to reviewed PRs: runs deployment-log-triage, files AZDO Bug tickets for high-confidence findings (deduped by signature tag), fixes each via /ticket or /feature, pushes branches, opens GitHub PRs via gh, and announces them in Slack #code-review. Checkpointed — prompts before every ticket creation, fix, push/PR, and Slack post. Invoke for "/bug-sweep", "/bug-sweep <hostname>", "sweep QA for deploy bugs", or "triage the logs and fix what broke".'
argument-hint: [hostname]
allowed-tools: Bash(powershell*) Bash(pwsh *) Bash(bash *) Bash(git *) Bash(az *) Bash(gh *) Bash(curl *) Bash(jq *) Read Grep Glob Write AskUserQuestion
---

# /bug-sweep — QA log triage → AZDO Bugs → fixes → PRs → Slack

Orchestrates existing mohr-dev skills into one checkpointed pipeline. You (the model) drive it
in the main session; the user approves every irreversible step. **Never** create a ticket, push,
open a PR, or post to Slack without the user's explicit go-ahead at that step.

Default hostname: `qa-api.myocchealthrecord.dev` (same as deployment-log-triage). Prod sweeps
(`release` branch) are a later phase — decline and explain if asked.

## Preflight

1. **az login + azure-devops extension** (needed for Steps 2 and 4):
   ```
   az account show --output none
   az extension add --name azure-devops --upgrade --only-show-errors
   ```
   If `az account show` fails → STOP: tell the user to run `! az login`.
2. **Slack webhook** — check `$env:SLACK_CODE_REVIEW_WEBHOOK` is set. If not, WARN now
   (one-time setup: create an incoming webhook for `#code-review` in Slack admin, set the env
   var) but continue — Slack never blocks the sweep.
3. Triage's own git preflight (branch/dirty checks on mohr-api and mohr-web) happens inside
   Step 1; don't duplicate it here.

## Step 1 — Triage

Run the **deployment-log-triage** skill exactly per its SKILL.md (git preflight, `fetch-logs.sh`
with `--paste` auth if needed), with one addition: pass `-Json` to `triage.ps1` so you get
machine-readable findings:

```
pwsh ${CLAUDE_PLUGIN_ROOT}/skills/deployment-log-triage/triage.ps1 `
  -LogJson '<output from fetch>' -ApiRepo C:\Source\mohr-api -WebRepo C:\Source\mohr-web `
  -Json '<scratchpad>/triage-findings.json'
```

Present the ranked report per that skill's Step 4. Then `Read` the JSON. The sweep set is:
`Band == 'High'` **and** `Backend == true` **and** `Expected == false`. Frontend and
validation/expected findings are display-only — never ticketed.

If the sweep set is empty: say so, show the report highlights, and stop.

## Step 2 — Ticket loop (checkpoint per finding)

For each finding in the sweep set, in score order:

1. Show the evidence: `Label`, `Score` + `Signals`, `Count`, `Onset`/`Last`, `Suspects`,
   `FileCommits`, and example `ExMsg` / `ExUrl` / `ExVer`.
2. Ask the user: **create Bug / skip / stop sweep**.
3. On create:
   - **Signature slug** from `Label`: lowercase, replace every run of non-alphanumerics with
     `-`, trim leading/trailing `-`, truncate to 120 chars.
   - Write TWO plain-text files to the scratchpad. **No markdown syntax** (`##`, `-`, backticks)
     — both land in AZDO rich-text fields rendered as text with line breaks, so markdown would
     show literally. Blank lines and `Label: value` lines are the formatting.

     `sysinfo-<slug>.txt` → the System Info field (triage/environment metadata):
     ```
     Deployment log triage evidence (automated)

     Environment: <hostname>    Branch: main
     Triage window: <window start> to <fetch time>
     Signature: <Label>    (dedupe tag sig:<slug>)
     Score: <Score> (<Band>) — <Signals>
     Occurrences: <Count>    Onset: <Onset>    Last seen: <Last>
     Build version: <ExVer>
     Suspect commit(s): <Suspects>
     Same-file commits near onset: <FileCommits>

     Caveats: <truncation / thin-baseline caveats from the triage run, if any>
     ```

     `repro-<slug>.txt` → the Repro Steps field. Best-effort and honest: this comes from log
     telemetry, not a reproduced session — say so, then give the closest thing to steps the
     evidence supports:
     ```
     Not reproduced directly — derived from QA ApplicationLog telemetry.

     Best-effort reproduction:
     1. Go to <ExUrl>
     2. <the user action the URL/route implies, e.g. "Open the employee's pre-employments tab">
     3. Error is thrown in <Class.Method>:

     <ExMsg>

     Seen <Count> times between <Onset> and <Last>. If it does not reproduce, correlate via
     the ApplicationLog signature above (System Info).
     ```
   - Run the helper:
     ```
     pwsh ${CLAUDE_PLUGIN_ROOT}/skills/bug-sweep/create-bug.ps1 `
       -Title '[QA deploy] <ErrType> in <Class.Method>' `
       -Signature '<slug>' `
       -SystemInfoFile '<scratchpad>/sysinfo-<slug>.txt' -ReproFile '<scratchpad>/repro-<slug>.txt' `
       -Application <pick> -Module '<pick>'
     ```
     (`<Class.Method>` is the part of `Label` after the ` @ ` separator. The Bug is created
     under the `MOHR\Engineering` area.)
   - `-Application`, `-Module`, and `-Discovered` fill the MOHR Bug type's required fields.
     Valid values are ValidateSet-enforced in `create-bug.ps1` (a bad value fails fast with
     the allowed list). **Choose from the finding's context:**
     - **Application** — from the example URL host: `qa-provider.*` → `Provider`,
       `qa-tenant.*` → `Client`, `qa-employee.*` → `Employee`, bare `qa.*` (host admin
       routes like `#/app/admin/...`) → `Host`. No URL → judge from the defining
       class/service; default `Client`.
     - **Module** — from the URL route / feature area, e.g. `/pre-employment*` → `PE`,
       `/ehm/*` → `EHM`, `/administration*` or `/admin/*` → `Admin Centre`,
       `/assessment*` or workflow-builder → `Assessment`, booking routes → `Bookings`,
       `/injury*` → `ICM`, `/injury-prevention*` → `IP`, reporting routes → `Reporting`,
       tenant settings/branding → `Tenant`, notifications/auth/infrastructure → `Platform-wide`.
       Unclear → `N/A`.
     - **Discovered** — omit; defaults to `QA` (this skill's scope until the prod phase).
   - Parse the JSON result. `duplicate:true` → report the existing Bug id/url, don't re-add to
     the fix list unless the user asks. Otherwise report the new id + url and add it to the
     fix list.

## Step 3 — Fix loop (checkpoint per ticket)

For each created ticket, ask: **fix now / skip / stop**. Route by scope:

- **Backend-only** (the normal case — High-band findings are C# stack traces and the fix does
  not change any API contract surface the frontend consumes) → run the **ticket** skill
  (`/ticket <id>`).
- **FE-contract involvement** (fix changes a DTO/AppService signature, or evidence implicates
  frontend behavior) → run the **feature** skill (`/feature <id>`).

The invoked skill's own gates apply unchanged (plan approval "go"; feature's pre-git "commit").
Do not shortcut them.

## Step 4 — Commit + push + PR (checkpoint)

The two fix skills end differently:
- `/feature` creates branch + commit itself at its "commit" gate.
- `/ticket` ends at the impact-check report with **no git steps** — after the user confirms,
  create the branch yourself: `bugs/AB#<id>-short-desc` off latest `main` (matches the repos'
  existing `bugs/AB#...` / `features/AB#...` convention), commit message starting `AB#<id> `
  and ending with the repo's Co-Authored-By convention.

The tickets live in AZDO but **the code is on GitHub** (`github.com/myocchealthrecord/*`), so
PRs go through `gh`, not `az repos`. Confirm with the user, then per modified repo:

```
git -C <repo> push -u origin <branch>
cd <repo> && gh pr create --base main `
  --title 'AB#<id> <short description>' `
  --body '<ticket ref + AZDO work-item URL, summary, validation performed, migration status, seeding status>'
```

- Preflight (once): `gh auth status` — if not logged in, STOP and have the user run `! gh auth login`.
- The `AB#<id>` prefix in the branch name, commit subject, and PR title is what links the work
  item (AZDO↔GitHub integration); there is no `--work-items` equivalent — do not drop the prefix.
- PR body follows mohr-api CLAUDE.md requirements (ticket reference, summary, validation
  performed, migration status, seeding status) — the fix skill already prepared this content at
  its report gate; reuse it. End the body with the 🤖 Claude Code attribution line.
- If `gh pr create` fails: report the error; the branch and commit are intact — the user can
  retry or open the PR manually. Do not roll anything back.

## Step 5 — Slack

Confirm with the user, then post one message (bash tool):

```bash
curl -sf -X POST -H 'Content-type: application/json' \
  -d "$(jq -n --arg t "AB#<id> <title> — PR: <url(s)> — <one-line summary>" '{text:$t}')" \
  "$SLACK_CODE_REVIEW_WEBHOOK"
```

If the env var is unset or curl fails: WARN, print the exact message text so the user can post
it manually, and continue. Slack never blocks or rolls back anything.

## Step 6 — Continue

Ask: **next ticket / stop**. There is no state file — AZDO is the state. An interrupted sweep
resumes naturally later: re-running `/bug-sweep` dedupes already-filed Bugs (reporting their
ids instead of re-filing), and individual tickets can be fixed directly via `/ticket <id>`.
