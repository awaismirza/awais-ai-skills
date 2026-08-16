---
name: work-done
description: "Finish a MOHR ticket — verify the PR exists (if not, note where you left off into the work log so you can resume), optionally move the work item to the code-review column, then switch back to main and pull. Closes the ticket's work-log entry when shipped, or keeps it paused-with-notes when not. Use after /work-ship when the user says they're done with the ticket, wants to go back to main, or wants to start something new. Safe by default: confirms board moves and never force-switches over a dirty working tree."
trigger: /work-done
---

# /work-done

The **end of the MOHR ticket lifecycle.** Makes sure the work is actually shipped (or properly parked), optionally moves the work item to code review, switches you back to `main`, and updates your in-progress work log.

> Normally run after `/work-ship` has opened the PR. If there's no PR yet, this skill makes sure the work isn't lost — it captures where you left off into `~/.claude/mohr-work-log.json` so `/work-log` can resume it later.

## Usage

```
/work-done            — verify PR → (move to code review) → switch to main → update work log
/work-done 20253      — same, ticket number pre-filled
/work-done ab#20253   — same, ab# prefix optional
```

---

## What You Must Do When Invoked

### Step 0 — Resolve the ticket number (before switching away)

Resolve it **now**, while still on the feature branch — stop at the first match:
1. **Command argument** — strip any `ab#` prefix for the raw digits.
2. **Current branch name** — `git branch --show-current`; if it starts with `ab#`, extract the number.
3. **Ask** — if neither has it. (If the user only wants to switch to main and there's no ticket, that's fine — skip to Step 3.)

Note the current repo (`mohr-web`/`mohr-api`) and branch — needed for the work-log update.

### Step 1 — Make sure a PR exists

```bash
gh pr list --head "$(git branch --show-current)" --state all --json number,url,state
```

- **PR exists** → capture its URL and continue to Step 2.
- **No PR** → the work isn't shipped. **Do not silently finish.** Tell the user and offer three choices:
  > "No PR found for ab#{ticket}. What would you like to do?
  > 1. Run `/work-ship` now to create it,
  > 2. Note where you left off and keep it in your work log to resume later,
  > 3. Just switch to main (I'll keep it in the log as paused)."

  - **(1)** → hand off to `/work-ship` (don't continue closing here).
  - **(2) or (3)** → ask for a short "where I left off / next steps" note, then **pause the entry in the work log** (write `status: "paused"` + `notes`, keep the entry) using the "Pause with notes" jq helper in `/work-log`. The entry is *kept* so `/work-log` can resume it. Continue to Step 3 (skip the code-review move — there's nothing in review yet).

If a work-log entry doesn't yet exist for this ticket, upsert one first (see `/work-log`) so the note isn't lost.

### Step 2 — Offer to move the ticket to the code-review column (PR exists)

**Ask:** "Move ab#{ticket} to the code-review column on the board?" (`/work-ship` may already have done this — this is the safety net.)

If **no** → Step 3. If **yes** (requires `AZURE_DEVOPS_PAT`):

**2a.** Read the work item's current `System.State` / `System.BoardColumn`, its `Microsoft.VSTS.Common.CompletedWork` field, and the allowed states (don't hardcode):
```bash
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${TICKET_ID}?\$expand=all&api-version=7.1"
TYPE="..."   # url-encode spaces, e.g. User%20Story
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitemtypes/${TYPE}/states?api-version=7.1"
```
- State named like "Code Review" → target `System.State`; otherwise target `System.BoardColumn`.
- **Already in code review** → say so and skip (idempotent).
- **🐞 Bugs need `Completed Work` set before `Code Review`.** The transition isn't actually blocked for Bugs — it's gated by a rule requiring `Microsoft.VSTS.Common.CompletedWork` to be populated (`TF401320: Completed Work — Required`):
  - Field already has a non-zero value (visible in the GET above) → skip straight to the normal Code Review PATCH in 2b, same as any other type.
  - Field is missing/zero → **ask the user**: "ab#{ticket} is a Bug — Code Review requires 'Completed Work' to be set. How many hours should I log?" Take their answer into 2b.

**2b. Confirm** the exact `current → target` change (let the user correct the wording). For a Bug with no `Completed Work` yet, PATCH that field first with the value from the question above, **then** PATCH the state — for every type (Bug included), the target is `Code Review`:
```bash
# Bug only, first — if Completed Work is missing/zero:
curl -s -u ":$AZURE_DEVOPS_PAT" -X PATCH \
  -H "Content-Type: application/json-patch+json" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${TICKET_ID}?api-version=7.1" \
  -d '[{"op":"add","path":"/fields/Microsoft.VSTS.Common.CompletedWork","value":"{hours}"}]'

# Then, for all types:
curl -s -u ":$AZURE_DEVOPS_PAT" -X PATCH \
  -H "Content-Type: application/json-patch+json" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${TICKET_ID}?api-version=7.1" \
  -d '[{"op":"add","path":"/fields/System.State","value":"Code Review"}]'
```
Verify the response. If the Code Review PATCH still fails after `Completed Work` is set (a different blocking rule), report the exact error + allowed values, fall back to PATCHing `System.State` to `In Dev` instead, and tell the user why — don't claim success.

### Step 3 — Check the working tree is clean

```bash
git branch --show-current
git status --short
```

- **Clean** → continue to Step 4.
- **Dirty (uncommitted changes)** → **stop.** Do not force-switch or stash silently:
  > You have uncommitted changes on `{branch}`. Commit/push them with `/work-commit` (or `/work-ship`), or tell me to stash them, before switching to `main`.

  Wait for the user to decide.

### Step 4 — Switch to main and pull

```bash
git checkout main
git pull
```
Report the result (confirm on `main`, up to date). If `git pull` reports conflicts / non-fast-forward, surface it instead of forcing.

### Step 5 — Update the work log

Close out the ticket's entry in `~/.claude/mohr-work-log.json` (see `/work-log` for the jq helpers):

- **PR exists (shipped / handed to review)** → **remove** the entry — it's no longer in-progress work.
- **No PR (paused in Step 1)** → the entry was already kept with `status: "paused"` + notes; leave it so `/work-log` can resume it.

Confirm to the user what happened to the entry (removed, or kept as paused with the note).

---

## Lifecycle map

| Stage | Skill |
|---|---|
| **Start** — read ticket + create branch (adds work-log entry) | `/work-start` |
| **Ship** — checklist → commit → push → PR → code review → Slack | `/work-ship` |
| **Done** — verify PR + (code review) + main + close/park log | **`/work-done`** (this skill) |
| **Resume** — list in-progress work, pick up where you left off | `/work-log` |

Related atomic skills: `/work-merge-main`, `/work-commit`, `/work-comment`.

## Quick Reference

| Rule | Value |
|---|---|
| Run when | Wrapping up a ticket / returning to main |
| PR check | `gh pr list --head <branch> --state all` — if none, note it down & keep in work log |
| Code-review move | Opt-in (only if PR exists) → discover State vs BoardColumn → confirm → PATCH (idempotent) |
| Move/Read API | `/_apis/wit/workitems/{id}?api-version=7.1` · auth `AZURE_DEVOPS_PAT` |
| Dirty tree | **Stop and ask** — never force-switch or stash silently |
| Switch commands | `git checkout main` → `git pull` |
| Work log | PR shipped → remove entry · no PR → keep as `paused` + notes (`~/.claude/mohr-work-log.json`) |
| Next | `/work-start {ticket}` for the next piece, or `/work-log` to resume a parked one |
