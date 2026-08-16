---
name: work-plan
description: "Plan a MOHR feature from an Azure DevOps story (occhealth org). Reads the full story + any linked Figma designs, decides whether the work is FE, BE, or both, finds (or creates, with confirmation) the BE/FE child tasks, grounds a concrete implementation plan in the actual mohr-web (FE) and mohr-api (BE) code, and hands the task number(s) to /work-start. Accepts a story URL/number (preferred) or a task URL/number. Use when starting a new piece of feature work, when given a story link, or when the user says plan this ticket / work-plan."
trigger: /work-plan
---

# /work-plan

Turns an Azure DevOps **story** into a grounded, actionable implementation plan split by repo, and sets up the BE/FE child tasks the rest of the workflow keys off.

Pipeline: **read story → read Figma → decide FE/BE/both → find or create BE/FE child tasks → ground a plan in real code → hand off to `/work-start`.**

> ## Scope rule
> Plan **only what the work needs.** If the story is FE-only → only the FE plan + FE task. BE-only → only BE. If it spans both → both. Never invent the other side just to be symmetric.

> ## ✋ Writes are confirmed
> Creating Azure DevOps tasks is a write. **Always confirm before creating** any work item (titles + assignee shown first). This skill plans and sets up tasks. It does **not** write code (that's the implementation itself) — but when the user **accepts the plan and picks auto mode** (Step 8), it *will* create the fresh feature branch(es) off latest `main`, exactly the way `/work-start` does. Branch creation is safe (no commits/pushes); pre-existing uncommitted work is still stash/commit-confirmed first.

## Usage

```
/work-plan https://dev.azure.com/occhealth/MOHR/_workitems/edit/20300   — plan from a story URL
/work-plan 20300                                                        — plan from a story number
/work-plan ab#20300                                                     — ab# prefix optional
/work-plan <task URL/number>                                            — task link: resolve its parent story for context
```

## Key facts

| Thing | Value |
|---|---|
| Org / Project | `https://dev.azure.com/occhealth` / `MOHR` |
| Auth env var | `AZURE_DEVOPS_PAT` |
| FE repo (mohr-web) | `/Users/mohr/code/mohr-web` — Angular 21 / Nx (see its `AGENTS.md` + `CLAUDE.md`) |
| BE repo (mohr-api) | `/Users/mohr/code/mohr-api` — .NET / CQRS (apply `/work-patterns`) |
| Assign new tasks to | `awais@myocchealthrecord.com` (the user) |
| Task title convention | `BE - {story title}` / `FE - {story title}` |
| BE marker | task title prefixed or postfixed with `BE` |
| FE marker | task title prefixed or postfixed with `FE` |
| Branch (FE) | `ab#{FE task}-{desc}` created in **mohr-web** by `/work-start` |
| Branch (BE) | `ab#{BE task}-{desc}` created in **mohr-api** by `/work-start` |

---

## What You Must Do When Invoked

### Step 1 — Resolve the input to a story

Extract the numeric ID from the argument (URL → strip to digits; `ab#NNNNN` → digits). Requires `AZURE_DEVOPS_PAT` (if unset, tell the user to add it to `~/.claude/settings.json` under `"env"` and restart).

Fetch the work item:
```bash
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${ID}?\$expand=all&api-version=7.1"
```

Determine what was passed via `.fields["System.WorkItemType"]`:
- **Story / Feature / Bug / PBI** → this is the planning root. Set `STORY_ID = ID`.
- **Task** → find its parent story from `.relations[]` where `rel == "System.LinkTypes.Hierarchy-Reverse"`, set `STORY_ID` to the parent, fetch it too, and remember that the passed task is one of the BE/FE tasks (detect which from its title marker). If a Task has no parent, treat the Task itself as the planning root.

### Step 2 — Read the story in full

From the story JSON, gather: Title, Description, Acceptance Criteria, Repro Steps, Tags, Area Path, Iteration Path. Strip HTML:
```bash
sed 's/<[^>]*>//g; s/&nbsp;/ /g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' | tr -s ' \n'
```
Also fetch comments for extra context:
```bash
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${STORY_ID}/comments?api-version=7.1-preview.3"
```

### Step 3 — Read the linked Figma designs

Scan the description, AC, and comments for Figma URLs (`figma.com/design/…`, `figma.com/file/…`, `figma.com/proto/…`, including `?node-id=`). For each:
- Use the **Figma MCP** tools (access is already granted): `get_design_context` for layout/specs/tokens, `get_screenshot` for the visual, `get_metadata` for structure. (Load the `figma-use` skill if you need to drive the tools.)
- Extract what matters for implementation: screens/components, states, fields, validation, copy, spacing/tokens, and any interaction notes.

If there are no Figma links, note that and continue (FE plan will be based on the written AC).

### Step 4 — Decide the scope: FE, BE, or both

From the story + AC + Figma, judge what's actually required:
- **FE signals** — new/changed screens, components, forms, navigation, client validation, report/table UI.
- **BE signals** — new/changed endpoints, CQRS commands/queries, entities/migrations, seeding, permissions, integrations, business rules.

State the verdict explicitly (FE-only / BE-only / both) with a one-line justification before proceeding.

### Step 5 — Find or create the BE/FE child tasks

List the story's children — `.relations[]` where `rel == "System.LinkTypes.Hierarchy-Forward"` — and fetch each child's title + type:
```bash
# child id is the trailing segment of relation.url
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${CHILD_ID}?api-version=7.1"
```

Match by marker (case-insensitive, prefix **or** postfix): a title containing `BE` → backend task; containing `FE` → frontend task.

Branch the logic:

- **Found the task(s) for the needed scope(s)** → use those task numbers. (If scope is "both" but only one marked task exists, treat the missing side as Step 5c.)
- **Children exist but none clearly marked BE/FE** → **don't guess.** List every child task (`ab#{id} — {title}`) and **ask the user** which is backend and which is frontend (only for the scopes needed).
- **No suitable task exists for a needed scope (5c)** → propose creating it, **confirm**, then create as a child of the story assigned to the user:
  ```bash
  curl -s -u ":$AZURE_DEVOPS_PAT" -X POST \
    -H "Content-Type: application/json-patch+json" \
    "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/\$Task?api-version=7.1" \
    -d "$(jq -nc \
      --arg title "FE - {story title}" \
      --arg assignee "awais@myocchealthrecord.com" \
      --arg area "{story System.AreaPath}" \
      --arg iter "{story System.IterationPath}" \
      --arg parent "https://dev.azure.com/occhealth/MOHR/_apis/wit/workItems/${STORY_ID}" \
      '[{op:"add",path:"/fields/System.Title",value:$title},
        {op:"add",path:"/fields/System.AssignedTo",value:$assignee},
        {op:"add",path:"/fields/System.AreaPath",value:$area},
        {op:"add",path:"/fields/System.IterationPath",value:$iter},
        {op:"add",path:"/relations/-",value:{rel:"System.LinkTypes.Hierarchy-Reverse",url:$parent}}]')"
  ```
  Use `BE - {story title}` for the backend task. Create **only the side(s) the scope needs**. Capture the new task `id`(s) from the response. If the POST errors, report the message and don't claim success.

End this step with a clear mapping, e.g.:
> FE task: `ab#20301` (mohr-web) · BE task: `ab#20302` (mohr-api)

### Step 6 — Ground the plan in real code

For each applicable side, explore the actual repo so the plan names real files/symbols — **graphify first, then read the specific files it surfaces** (cheaper than broad grep):

- **FE (mohr-web)** — `cd /Users/mohr/code/mohr-web` then `graphify query "<feature/area>"`. Respect `AGENTS.md` + `CLAUDE.md`: reuse `libs/designs` (`mo-*`), `libs/store`, `libs/utils`; Angular 21 rules (no `extends`/`ViewChild`, signals/`computed`, reactive forms, `theme.css` classes). Identify the components/services/proxies to touch or add.
- **BE (mohr-api)** — `cd /Users/mohr/code/mohr-api` then `graphify query "<feature/area>"` (or explore if no graph). Apply `/work-patterns`: CQRS split (reads in `MOHR.Application` AppServices, writes via `IHandler<TCommand>` in `MOHR.Core`), SmartEnum, Mapperly, migrations/seeding. Identify handlers/AppServices/entities/DTOs to touch or add, and whether a migration/seed is needed.

### Step 7 — Produce the plan

Output a structured plan. Include only the applicable sections:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PLAN — ab#{STORY_ID} {story title}
Scope: {FE-only | BE-only | both}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONTEXT
{2–4 lines: what the story asks for, key AC, what the Figma shows}

BACKEND — ab#{BE task} (mohr-api)
- {step, citing real handlers/AppServices/entities/files}
- Migration: {needed? which entity} · Seeding: {needed? RunOnce/Seed}
- API surface: {endpoints / commands / queries}
- Suggested branch: ab#{BE task}-{kebab-desc}

FRONTEND — ab#{FE task} (mohr-web)
- {step, citing real components/services/libs/proxies}
- Reuse: {mo-* components, libs/store, libs/utils}
- Suggested branch: ab#{FE task}-{kebab-desc}

DEPENDENCIES / ORDER
{e.g. BE endpoint before FE wiring; proxy regen handled by user}

OPEN QUESTIONS
{anything ambiguous in the ticket/Figma worth confirming}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Persist the plan and seed the work log** (so it survives across sessions and `/work-log` can resume it):

1. **Save the plan** to `~/.claude/mohr-plans/ab#{STORY_ID}.md`:
   ```bash
   mkdir -p ~/.claude/mohr-plans
   cat > ~/.claude/mohr-plans/ab#${STORY_ID}.md   # write the full plan markdown
   ```
2. **Seed a `planned` work-log entry per task** the plan covers (FE task, BE task, or just one) — see the "Seed a planned entry" jq helper in `/work-log`. Set `repo` (`mohr-web`/`mohr-api`), `story`, and `plan` (the saved path); leave `branch` empty. When `/work-start` later runs on that task, it flips the entry to `in-progress` and records the branch.

This means a planned-but-not-started ticket already shows up in `/work-log`.

### Step 8 — Accept the plan, then hand off (manual or auto)

After the plan, **prompt** for acceptance and how to proceed:
> "Plan ready. Do you want to start now, and how?
> • **Auto** — I'll cut a fresh branch off the latest `main` for the task(s) below and set the work log to in-progress, then you start coding.
> • **Manual** — you run `/work-start {task}` yourself when ready.
> • **Later** — just save the plan; nothing else."
>
> Auto targets: FE → `ab#{FE task}-{desc}` in mohr-web · BE → `ab#{BE task}-{desc}` in mohr-api.

Do nothing branch-related until the user **accepts the plan**. Then branch on their choice:

- **Manual** → proceed with `/work-start {task}` on the chosen task number (in the matching repo). Stop here.
- **Later** → stop; the plan is saved and logged `planned`, they'll trigger `/work-start` themselves.
- **Auto** → for **each in-scope task** (FE in mohr-web, BE in mohr-api), create the branch **the same way `/work-start` does** — always off the *latest* `main`, one branch per repo:

  **8a. `cd` into the correct repo for the task** (`/Users/mohr/code/mohr-web` for FE, `/Users/mohr/code/mohr-api` for BE) and inspect the working state:
  ```bash
  git branch --show-current
  git status --short
  ```

  **8b. Handle any pre-existing work first (confirm before running).** If the tree is dirty or you're on another `ab#…` branch, use `/work-start`'s rule: if the current branch has an open PR (`gh pr list --head "$CURRENT" --state open`), **commit** (offer to push) so nothing is lost; otherwise **stash** (`git stash push -u -m "WIP $CURRENT before ab#{task}"`). Clean tree → nothing to do. **Always confirm the stash/commit choice before running it.**

  **8c. Cut the fresh branch off latest `main`:**
  ```bash
  git fetch origin
  git checkout -b "ab#{task}-{kebab-desc}" origin/main
  ```
  `{kebab-desc}` = the concise kebab-case description from the plan's "Suggested branch" line. Branching off `origin/main` guarantees it starts from the up-to-date `main`, not whatever branch was checked out. (Confirm the branch name if it differs from the plan's suggestion.)

  **8d. Flip the work-log entry to `in-progress`** for that (task, repo) — record the branch — using the "Upsert → in-progress" jq helper in `/work-log`. This converts the `planned` entry Step 7 seeded.

  Repeat 8a–8d per in-scope repo. When done, report each new branch and that the log is in-progress, so the user can start coding immediately.

> Auto mode stops at branch creation — it never commits or pushes code (the golden rule from `/work-start` still applies: finish + test the change, then `/work-ship`).

---

## Lifecycle map

| Stage | Skill |
|---|---|
| **Plan** — story + Figma → scope → tasks → grounded plan (saved + logged `planned`) | **`/work-plan`** (this skill) |
| **Start** — create branch for a task (log → `in-progress`) | `/work-start` |
| **Ship** — checklist → commit → push → PR → code review → Slack | `/work-ship` |
| **Done** — move to code review + back to `main` + close/park log | `/work-done` |
| **Resume** — list in-progress/planned work, pick up where you left off | `/work-log` |

Related: `/work-patterns` (BE rules), `/work-merge-main`, `/work-commit`, `/work-comment`.

## Quick Reference

| Rule | Value |
|---|---|
| Input | Story URL/number (preferred); task link resolves to its parent story |
| Reads | Story + AC + comments + linked Figma (Figma MCP) |
| Scope | FE / BE / both — plan only what's needed |
| Tasks | Find by BE/FE marker; if unmarked, ask; if missing, confirm → create child + assign |
| New task title | `BE - {title}` / `FE - {title}` |
| Plan grounding | graphify → files in mohr-web (FE) / mohr-api (BE) |
| DevOps writes | Only task creation, and only after confirmation |
| Local writes | Plan saved to `~/.claude/mohr-plans/ab#{story}.md` + `planned` work-log entries |
| Branch creation | Only in **auto mode** after plan acceptance: fresh `ab#{task}-{desc}` off latest `main` per repo, log → `in-progress` (never commits/pushes) |
| Next | **Auto** → branch cut, start coding · **Manual** → `/work-start {task}` in the matching repo |
