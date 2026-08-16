---
name: work-log
description: "MOHR work command center across local branches, GitHub PRs, and Azure DevOps ticket state — scoped to the current sprint by default. Use when the user asks what they're working on, what's in code review/QA, their todo or backlog, to resume work, or to sync their work log. Subcommands: last-sprint/next-sprint/sprint N/backlog/all, todo, in-progress/code-review/qa/done, sync, resume <ticket>. Config-driven via ~/.claude/mohr-worklog.config.json; also defines the work-log schema the other lifecycle skills write to."
trigger: /work-log
---

# /work-log — MOHR work command center

One place to see and drive all your MOHR work, reconciled across three sources of truth:

1. **Local** — your git branches + the work log (`~/.claude/mohr-work-log.json`)
2. **GitHub** — open/merged PRs (`gh`)
3. **Azure DevOps** — the ticket's real workflow state (To Do → In Development → Code Review → QA → Deployed)

## Usage

**Default scope is the CURRENT SPRINT.** The dashboard shows current-sprint work from local branches + GitHub + the log, and **prompts before syncing DevOps** — it never auto-writes the log or moves ticket states.

```
/work-log                  — current sprint: active branches + GitHub PRs + local log (prompts to sync DevOps)
/work-log last-sprint      — same view, previous sprint
/work-log next-sprint      — same view, next sprint
/work-log sprint 134       — a specific sprint by number
/work-log backlog          — your assigned items with no sprint (backlog)
/work-log all              — everything assigned, all sprints + backlog (Done collapsed to a count)
/work-log todo             — current-sprint To Do tickets; which already have a branch / local work
/work-log in-progress      — filter to a DevOps state bucket within scope (code-review, qa, done, todo, cancelled)
/work-log sync             — reconcile the local log with PR + DevOps state (the write-back step; always confirmed)
/work-log resume 20553     — resume a ticket (checkout branch in the right repo, re-orient)
/work-log show             — print the raw local log only, no live fetch
```

Any view can take a sprint scope (e.g. `/work-log todo last-sprint`, `/work-log code-review all`). No scope given = **current sprint**.

---

## Configuration — everything is config-driven

Read **`~/.claude/mohr-worklog.config.json`** first (create from the defaults below if missing). All repos, paths, the Azure org/project, the assignee, and the **state→bucket mapping** come from there — never hardcode them. To retarget (new repo, different states, team rollout), the user edits that one file.

Key config fields:
- `azure` — `orgUrl`, `project`, `assignee` (`@Me`), `authEnv` (`AZURE_DEVOPS_PAT`), `ticketUrlTemplate`, `apiVersion`
- `repos[]` — `{name, role (FE/BE), path, gh}`
- `log.path`, `log.plansDir`
- `stateBuckets` — maps a bucket (`todo`, `in-progress`, `code-review`, `qa`, `done`, `cancelled`) to the list of raw DevOps state names that fall in it (states vary by work-item type, e.g. "In Development" vs "In Dev" vs "Work In Progress" all = in-progress)
- `bucketOrder`, `bucketEmoji` — display order + icons
- `codeReviewTarget` — `{field, value}` used when moving a ticket to code review
- `branch.regex` — how to spot a ticket id in a branch name (`[Aa][Bb]#[0-9]+`)

Expand `~` in config paths via `$HOME` in bash. Map a raw DevOps state to a bucket by finding which `stateBuckets` list contains it (case-insensitive); unknown → `other`.

---

## DevOps access

Prefer the **`ado` MCP tools** if connected (`wit_my_work_items`, `wit_query_by_wiql`, `wit_get_work_items_batch_by_ids`, `wit_update_work_item`). Otherwise use **curl + `$AZURE_DEVOPS_PAT`**. Reusable curl pattern (org/project/version from config):

```bash
ORG="https://dev.azure.com/occhealth"; PROJ="MOHR"; V="7.1"
# (1) WIQL → ids (filter as needed; @Me resolves to the PAT owner)
IDS=$(curl -s -u ":$AZURE_DEVOPS_PAT" -H "Content-Type: application/json" \
  "$ORG/$PROJ/_apis/wit/wiql?api-version=$V" \
  -d '{"query":"SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo]=@Me AND [System.TeamProject]='"'"'MOHR'"'"' ORDER BY [System.ChangedDate] DESC"}' \
  | jq -r '[.workItems[].id]|.[0:100]|join(",")')
# (2) batch fetch fields
curl -s -u ":$AZURE_DEVOPS_PAT" -H "Content-Type: application/json" \
  "$ORG/$PROJ/_apis/wit/workitemsbatch?api-version=$V" \
  -d "{\"ids\":[$IDS],\"fields\":[\"System.Id\",\"System.WorkItemType\",\"System.State\",\"System.BoardColumn\",\"System.Title\"]}" \
  | jq -r '.value[].fields | "ab#\(.["System.Id"]) [\(.["System.WorkItemType"])] \(.["System.State"]) — \(.["System.Title"])"'
```

If `$AZURE_DEVOPS_PAT` is unset and the MCP isn't connected, say so and fall back to **local-only** views (log + git + `gh`), noting DevOps state is unavailable.

---

## Sprint scope (default = current sprint)

Sprints are project-wide iteration paths: `MOHR\Sprint NNN` (config `sprints.iterationPrefix`). Every view is **scoped to the current sprint by default**; a scope keyword changes it.

| Scope arg | Iteration |
|---|---|
| *(none)* / `current` | current sprint |
| `last-sprint` | current − 1 |
| `next-sprint` | current + 1 |
| `sprint <N>` | `MOHR\Sprint <N>` |
| `backlog` | items with **no** sprint (IterationPath == `sprints.backlogIterationPath`, i.e. project root `MOHR`) |
| `all` | no iteration filter (every sprint + backlog) |

**Resolve the current sprint** (config `sprints.resolveCurrentBy`):
- **`date`** (default, team-agnostic): read the iteration tree and pick the sprint whose `[startDate, finishDate]` contains today; if today is in a gap between sprints, use `sprints.gapFallback` (`next` → the upcoming sprint).
  ```bash
  ORG="https://dev.azure.com/occhealth"; PROJ="MOHR"; V="7.1"; TODAY=$(date +%F)
  curl -s -u ":$AZURE_DEVOPS_PAT" "$ORG/$PROJ/_apis/wit/classificationnodes/iterations?\$depth=2&api-version=$V" \
    | jq -r --arg today "$TODAY" '[..|objects|select(.attributes.startDate?!=null)
        |{name,start:.attributes.startDate[0:10],finish:.attributes.finishDate[0:10]}]|sort_by(.start)
        | (map(select(.start<=$today and .finish>=$today))|first) // (map(select(.start>$today))|first) // last
        | .name'
  ```
  `last-sprint`/`next-sprint` = the entry before/after the current one in that sorted list; `sprint N` = `Sprint N`.
- **`team-macro`** (if `sprints.team` is set): use the WIQL macro instead — `[System.IterationPath] = @CurrentIteration('[MOHR]\<team>')`, with `- 1` / `+ 1` for last/next. Azure handles gaps/rollover.

**Apply the scope** in every WIQL by adding the iteration clause:
- specific sprint → `AND [System.IterationPath] = 'MOHR\Sprint NNN'`
- backlog → `AND [System.IterationPath] = 'MOHR'`
- all → (omit the iteration clause)

Always tell the user which sprint is in view (e.g. "Sprint 135 · 15–26 Jun").

---

## The log file

- **Path:** `~/.claude/mohr-work-log.json` (from config) — JSON array, managed with `jq` (never hand-concatenate).
- **Unique key = (`ticket`, `repo`)** — the same `ab#NNNNN` is often worked in **both** repos, so two entries can share a ticket (one per repo). All helpers match on ticket **and** repo.

**Entry schema:**
```json
{
  "ticket": "ab#20553",
  "title": "Localisation - Booking Dashboard",
  "repo": "mohr-web",
  "branch": "ab#20553-booking-dashboard-localisation",
  "story": "",
  "status": "in-progress",        // local: planned | in-progress | pr-created | paused
  "prs": [],
  "plan": "",
  "devopsState": "To Do",         // last-synced Azure DevOps state (optional; refreshed by sync)
  "devopsType": "Task",
  "notes": "",
  "updated": "2026-06-28T10:00:00Z"
}
```

`status` (your local code stage): **planned** (`/work-plan`, no branch) · **in-progress** (branch, coding) · **pr-created** (PR open) · **paused** (parked by `/work-done`, no PR). `devopsState` is the **ticket's** workflow stage — they can disagree (that's a signal, see Sync).

Plans live in `~/.claude/mohr-plans/` (`ab#{story}.md`); entries point to theirs via `plan`.

### Shared jq helpers (used by all writer skills)

Ensure the file exists: `LOG=~/.claude/mohr-work-log.json; [ -f "$LOG" ] || echo '[]' > "$LOG"`. Use `NOW=$(date -u +%FT%TZ)`; write through a temp file.

**Seed a planned entry (`/work-plan`):**
```bash
tmp=$(mktemp); jq --arg t "ab#20253" --arg title "..." --arg repo "mohr-web" --arg story "ab#20300" \
  --arg plan "$HOME/.claude/mohr-plans/ab#20300.md" --arg now "$NOW" '
  (map(.ticket==$t and .repo==$repo)|index(true)) as $i
  | if $i==null then . + [{ticket:$t,title:$title,repo:$repo,branch:"",story:$story,status:"planned",prs:[],plan:$plan,devopsState:"",devopsType:"",notes:"",updated:$now}]
    else .[$i] |= (.title=$title|.story=$story|.plan=$plan|.updated=$now) end' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
```

**Upsert → in-progress (`/work-start`):**
```bash
tmp=$(mktemp); jq --arg t "ab#20253" --arg title "..." --arg repo "mohr-web" --arg branch "ab#20253-x" --arg story "" --arg now "$NOW" '
  (map(.ticket==$t and .repo==$repo)|index(true)) as $i
  | if $i==null then . + [{ticket:$t,title:$title,repo:$repo,branch:$branch,story:$story,status:"in-progress",prs:[],plan:"",devopsState:"",devopsType:"",notes:"",updated:$now}]
    else .[$i] |= (.title=$title|.branch=$branch|.story=$story|.status="in-progress"|.updated=$now) end' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
```

**Mark PR created (`/work-ship`):**
```bash
tmp=$(mktemp); jq --arg t "ab#20253" --arg repo "mohr-web" --arg pr "$PR_URL" --arg now "$NOW" '
  map(if .ticket==$t and .repo==$repo then .status="pr-created"|.prs=((.prs+[$pr])|unique)|.updated=$now else . end)' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
```

**Set DevOps state (sync):**
```bash
tmp=$(mktemp); jq --arg t "ab#20253" --arg repo "mohr-web" --arg st "Code Review" --arg ty "Task" --arg now "$NOW" '
  map(if .ticket==$t and .repo==$repo then .devopsState=$st|.devopsType=$ty|.updated=$now else . end)' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
```

**Pause with notes (`/work-done`, no PR):**
```bash
tmp=$(mktemp); jq --arg t "ab#20253" --arg repo "mohr-web" --arg notes "$NOTES" --arg now "$NOW" '
  map(if .ticket==$t and .repo==$repo then .status="paused"|.notes=$notes|.updated=$now else . end)' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
```

**Close/remove (`/work-done`, complete):**
```bash
tmp=$(mktemp); jq --arg t "ab#20253" --arg repo "mohr-web" 'map(select((.ticket==$t and .repo==$repo)|not))' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
```

---

## What You Must Do When Invoked

**Step 0 — Load config** (`~/.claude/mohr-worklog.config.json`; create from defaults if missing).

**Step 0a — Parse args into (view, scope).** Args can combine a view word and a scope word in any order:
- **scope words:** `current` (default), `last-sprint`, `next-sprint`, `sprint <N>`, `backlog`, `all`
- **view words:** *(none → Dashboard)*, `todo`, `in-progress`/`code-review`/`qa`/`done`/`cancelled`, `sync`, `resume <ticket>`/number, `show`

Resolve the scope to a concrete iteration clause (see **Sprint scope**) and state which sprint is in view. Then dispatch:

| View | Run |
|---|---|
| *(none)* | **Dashboard** (scoped) |
| `sync` | **Sync** |
| `todo` | **Todo view** (scoped) |
| `in-progress`/`code-review`/`qa`/`done`/`cancelled` | **Bucket view** (scoped) |
| `backlog` (alone) | Dashboard with backlog scope |
| `all` (alone) | **All view** |
| `resume <ticket>` / number | **Resume** |
| `show` | print raw log (`jq '.' "$LOG"`), no live fetch |

Keep all live fetching to the minimum needed (one WIQL + one batch per view; one `gh pr list` per repo). Present results, then offer the next action.

### Dashboard (`/work-log`, default — current sprint)

The "what am I working on right now" view. It is **local-first** and **does not write the log or move ticket states** — DevOps writes happen only via the prompted Sync.

1. Resolve the scope sprint (default current) and announce it: "Sprint 135 · 15–26 Jun".
2. **Local + GitHub first** (no DevOps writes):
   - Read the local log.
   - For each repo: list `ab#` branches + commits ahead of main; `gh -R <gh> pr list --state all --author '@me' --json number,title,headRefName,url,state`.
3. **Scope to the sprint:** one read-only WIQL for ticket ids in the scope sprint assigned to `@Me` (`AND [System.IterationPath]=...`); keep only rows whose ticket is in that set. (For `all` scope, skip the filter.) This read is for scoping/labels only — it doesn't modify the log.
4. Render rows grouped by the freshest signal available (DevOps bucket if just read, else local status), each: `ab#ticket` · title · local status · repo/branch · PR · DevOps state (if known, e.g. from the log's last sync).
5. **Flag mismatches** (the payoff of cross-referencing):
   - local `in-progress`/`pr-created` but DevOps `To Do` → "⚠ ticket still To Do — move to In Development / Code Review?"
   - PR merged but local `pr-created` → "✅ PR merged — run `/work-done` to close it out"
   - DevOps `QA`/`In QA` with a local branch ahead → "⚠ in QA but you have local commits — fix coming back?"
   - DevOps `Deployed` but still in the log → "done — remove from log?"
6. **Prompt before syncing DevOps** (config `devopsSync.auto` is false): end with — "Sync DevOps state into the log now? (writes `devopsState` + reconciles statuses) · or resume one (number/ticket) · `todo` for the backlog." Only run **Sync** (which reads + writes) if the user says yes.

### All view (`/work-log all`)

Everything assigned to you in DevOps, every active bucket, cross-referenced with local branches / log / PRs — the "full workload" picture.

1. WIQL: `[System.AssignedTo]=@Me AND [System.TeamProject]=<project> AND [System.State] NOT IN ('Removed','Cancelled')` → batch-fetch `Id, State, Type, Title`.
2. Build the local signal sets once: per repo, the ticket ids that have a branch (`for-each-ref … | grep -oiE 'ab#?[0-9]+'`); the ids in the log (+ their status); the ids with an open PR (`gh pr list`).
3. Group by bucket in `config.bucketOrder`. For each ticket show: `ab#id` · title · type · local signals (`branch:FE/BE`, `log:<status>`, `PR✓`, or `— nothing local`).
4. **Collapse `done`** (and any `cancelled`) to a one-line count with maybe the 3 most recent — never list 100+ deployed items. Keep the actionable buckets (code-review, qa, in-progress, todo) full.
5. Call out the signal: tickets with **local work but a non-active DevOps state** (e.g. To Do/QA with a branch), and **active DevOps state but nothing local** (likely stale assignment or parent epics).
6. Offer next actions (resume, sync, move states, plan a fresh todo).

### Bucket view (`/work-log <state>`)

Filter to one DevOps bucket (`in-progress`, `code-review`, `qa`, `done`, `cancelled`, or `todo` → use the Todo view).

1. Resolve the bucket's raw state names from `config.stateBuckets[bucket]`.
2. WIQL: assigned `@Me`, `[System.State] IN (<those states>)`, project from config, **+ the scope iteration clause** (current sprint by default); batch-fetch titles/types/state. State the sprint in view.
3. Cross-reference each with local: is there a log entry and/or a branch matching `ab#{id}` in either repo (`git -C <path> branch --list "*{id}*"`)? Is there a PR?
4. Present a compact table: `ab#ticket` · title · type · DevOps state · local (branch? / log status / PR) · ticket URL.
5. Offer relevant next actions (e.g. for `code-review`: open the PRs; for `qa`: nothing local needed; for `in-progress`: resume).

### Todo view (`/work-log todo`)

Your actionable backlog — assigned tickets in a `todo` bucket state, with local readiness.

1. WIQL: `[System.AssignedTo]=@Me AND [System.State] IN (<config todo states>) AND [System.TeamProject]=<project>` **+ the scope iteration clause** (current sprint by default; see Sprint scope) → ids; batch-fetch `Id, Title, WorkItemType, State, Parent`. State the sprint in view.
2. For each ticket, determine local readiness across **both** repos:
   - **branch exists?** `git -C <repo.path> for-each-ref --format='%(refname:short)' refs/heads/ | grep -iE 'ab#?{id}([^0-9]|$)'`
   - **log entry?** look it up in the log by ticket
   - **plan?** `~/.claude/mohr-plans/ab#{id}.md` exists
3. Present nicely, grouped by readiness so the easy wins are obvious:
   ```
   📋 TODO — assigned to you (DevOps: To Do/New)

   ▶ Has local work (continue):
     ab#20553  Localisation - Booking Dashboard        FE+BE branches · in log (in-progress)
     ab#20520  FE - Add Book Appointment to Dashboard  FE branch · in log

   ◇ Planned (not started):
     ab#20300  Hearing trends report                   plan saved · no branch

   ○ Fresh (nothing local yet):
     ab#20427  DS - Checkbox Update (Disabled/Selected) Task · no branch · no plan
     ab#20454  Add line breaks to notes                User Story
   ```
   Show ticket, title, type, and the local signals (which repos have a branch, log status, plan). Link ticket URLs.
4. Offer next actions: `/work-plan {ticket}` (scope it), `/work-start {ticket}` (branch + begin), or `resume` if a branch already exists.

### Sync (`/work-log sync`)

Reconcile the local log with live PR + DevOps state. **Reconcile, don't clobber** — preserve human `notes`/`plan`/`story`.

1. For each repo: `git fetch -q origin`; list `ab#` branches + commits ahead of main (0 ⇒ merged/stale); `gh pr list --state all --author '@me' --json number,title,headRefName,url,state`.
2. Batch-fetch DevOps state for: all tickets in the log + all tickets found on branches.
3. For each (ticket, repo):
   - branch with **open PR** → `status=pr-created` (+ PR url); branch **no PR**, ahead>0 → `in-progress`; branch merged/gone → candidate to remove (ask).
   - write `devopsState`/`devopsType` from DevOps (use the "Set DevOps state" helper).
   - upsert via the (ticket, repo) helpers; keep notes/plan/story.
4. **Report a reconciliation summary** and flag mismatches (same list as Dashboard step 6) — e.g. "ab#20553 local in-progress but DevOps To Do → move to In Development?" Offer to action each (move DevOps state via `wit_update_work_item` / PATCH, run `/work-done`, remove stale entry) — **confirm before any DevOps write or log removal.**
5. Finish by showing the refreshed Dashboard.

### Resume (`/work-log resume <ticket>` or a number from a list)

1. Find the entry (by ticket; if it spans both repos, ask which repo, or default to the one with the freshest `updated`).
2. **Planned, no branch** → show the plan (`cat` the `plan` file) and offer `/work-start {ticket}` in `{repo}`.
3. **Has a branch** → in `{repo.path}`: `git fetch origin` → `git checkout {branch}` (warn, don't force, if the current tree is dirty) → `git log origin/main..HEAD --oneline`. Re-orient with title, `devopsState`, local `status`, PR, `notes`, recent commits. Suggest: keep coding · `/work-ship` if ready · `/work-done` if the PR's merged.
4. Resuming does not change the entry (status only changes via ship/done).

---

## Quick Reference

| Thing | Value |
|---|---|
| Config | `~/.claude/mohr-worklog.config.json` (repos, states, assignee — edit to retarget) |
| Log | `~/.claude/mohr-work-log.json` · key **(ticket, repo)** · plans `~/.claude/mohr-plans/` |
| Sources | local git + log · GitHub PRs (`gh`) · Azure DevOps state (ado MCP or curl+PAT) |
| Local status | planned · in-progress · pr-created · paused |
| DevOps buckets | todo · in-progress · code-review · qa · done · cancelled (mapping in config) |
| **Default scope** | **current sprint** (`MOHR\Sprint NNN`, resolved by date) |
| Scopes | `current` · `last-sprint` · `next-sprint` · `sprint <N>` · `backlog` · `all` |
| Views | (dashboard) · `sync` · `todo` · `<bucket>` · `resume <ticket>` · `show` — combine with a scope |
| DevOps sync | **prompted, not automatic** — dashboard is local-first; sync reads+writes only on confirm |
| Writers | `/work-plan` · `/work-start` · `/work-ship` · `/work-done` (via the jq helpers above) |
| Writes | DevOps state changes + log removals always **confirmed** first |
