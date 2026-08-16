---
name: work-e2e
description: >-
  Drive the browser yourself to run and verify a MOHR workflow end-to-end on the
  LOCAL dev environment (localhost) — log in through the auth portal, go to the
  named provider/tenant portal, walk a module workflow (create booking, add note,
  etc.), and report pass/fail per step with screenshots. Attaches to the already-
  running `yarn serve` (never builds). Grows a library of saved workflow recipes:
  first run is freeform, then it saves the successful steps as a named recipe to
  replay next time. Use when the user says "work-e2e", "run an e2e test", "test
  this workflow in the browser", "log in and click through X", "drive the UI and
  check Y", or wants Claude (not the user) to operate the local app. This is the
  Claude-drives-the-browser skill; for user-driven manual QA that logs to a ticket
  use `test-start` instead.
trigger: /work-e2e
---

# work-e2e — Claude drives the local browser to run MOHR workflows

**You** operate the browser (log in, navigate, click, type) against the **local**
running app; the user watches and reads your pass/fail report. This is the inverse
of `test-start` (where the user clicks and you guide). Use it to smoke-test a
workflow you built, or to replay a saved recipe.

## 🔒 Golden rules (never break these)

1. **Localhost only.** This skill targets the local dev app (`localhost:4200/4201/4202`). Never point it at QA/staging/production.
2. **Attach, never build/start.** The dev server is already running via the IDE (`yarn <app>:serve`). Just attach and navigate. **Never run a build or start a server** — the mohr-web `CLAUDE.md` no-build rule applies (builds corrupt the running serve).
3. **Never print or log the password.** Read it from the credentials file at fill-time only. Never echo it, never write it into a recipe, a screenshot description, a run log, or an Azure DevOps comment.
4. **Confirm data-writing actions on the first pass of a new workflow.** Before a step that creates/edits/deletes/submits real data, say what it will do and get an OK. Once that workflow is saved as a recipe and the user has accepted it, replays can run those steps without re-confirming.
5. **No AI mentions in any Azure DevOps comment** (if the user opts into logging). Comments read as written by the user.

## Config & credentials

Everything lives under this skill's folder:

- **Credentials** — `~/.claude/skills/work-e2e/.credentials.json` (gitignored, chmod 600). Shape:
  ```json
  { "local": { "user": "...", "pass": "...", "urls": { "auth": "http://localhost:4200", "provider": "http://localhost:4202", "tenant": "http://localhost:4201" } } }
  ```
  Read `user` / `pass` / `urls` from here. Resolve the target portal URL by name (see below).
- **Recipes** — `~/.claude/skills/work-e2e/recipes/*.json` (one file per recipe). `login.json` is the reusable auth recipe; workflow recipes are named per task (`create-booking.json`, …).
- **Run artifacts** — `~/.claude/skills/work-e2e/runs/<timestamp>/` (gitignored): per-step screenshots + `run-log.md`.

Portal name → URL:

| Name the user gives | URL | Notes |
|---|---|---|
| `auth` (login) | `urls.auth` (`:4200`) | Where login happens; other portals redirect here to authenticate |
| `provider` | `urls.provider` (`:4202`) | Provider portal |
| `tenant` | `urls.tenant` (`:4201`) | Tenant portal |

## Browser engine

Default: the **Preview** tools (`preview_*`), attached to the running server.
(Their schemas are deferred — load with `ToolSearch "select:mcp__Claude_Preview__preview_start,mcp__Claude_Preview__preview_snapshot,mcp__Claude_Preview__preview_click,mcp__Claude_Preview__preview_fill,mcp__Claude_Preview__preview_eval,mcp__Claude_Preview__preview_screenshot"` before first use.)

- **Attach:** `preview_start` against the target URL (e.g. `http://localhost:4200`). If `preview_list` shows a session already, reuse it. Never start a dev server yourself — if nothing is serving, stop and ask the user to start their `yarn <app>:serve`.
- **Navigate:** `preview_eval` with `window.location.href = "<url>"`, or `preview_start` on the new URL.
- **Read the page:** `preview_snapshot` (structure/text) before deciding what to click; `preview_screenshot` for evidence and when the user should see it.
- **Act:** `preview_click` / `preview_fill`. Prefer stable, human-readable targets (label text, placeholder, role, visible button text) over brittle nth-child selectors.
- **Diagnose:** `preview_console_logs` / `preview_network` when a step fails.

If the user says they want to *watch it happen in real Chrome*, switch to the `Claude_in_Chrome` tools instead (same step logic). Preview is the default because deterministic replay of saved recipes is more reliable there.

## Invocation modes

```
/work-e2e                              → list saved recipes + offer a freeform run
/work-e2e <portal> "<goal>"            → freeform run, e.g. /work-e2e provider "create a booking"
/work-e2e <recipe-name>                → replay a saved recipe (e.g. /work-e2e create-booking)
/work-e2e <recipe-name> --record       → re-record/update an existing recipe
```

`<portal>` is `provider` or `tenant` (login is always via `auth`).

## The run loop

### 1. Resolve target + preconditions
- Parse the portal (`provider`/`tenant`) and the goal or recipe name from the args.
- Load `.credentials.json`. Load the matching recipe from `recipes/` if a name was given.
- `preview_list` / `preview_start` to attach to the portal URL. If nothing is serving that port, **stop** and ask the user to start their serve (don't build).

### 2. Ensure logged in (login recipe)
- Navigate to the target portal URL. If it redirects to the auth portal (`:4200`) or shows a login screen, run **`login.json`**:
  1. On the auth page, `preview_snapshot` to find the username/password fields.
  2. `preview_fill` username = `user`, password = `pass` (read at fill-time; never printed).
  3. Click the sign-in control; wait for redirect back to the portal (`preview_snapshot` until the app shell/dashboard is present).
- If already authenticated (dashboard visible), skip login.
- If `login.json` doesn't exist yet, drive login freeform, then **save it** as `login.json` (step 5) so it's a one-time cost.

### 3. Run the workflow
- **Replay (recipe given):** execute each step in order — navigate / click / fill / assert `expect`. `preview_screenshot` after meaningful steps (and always at the end). If a target isn't found, `preview_snapshot`, try to self-heal to the equivalent control, and note the drift so the recipe can be updated.
- **Freeform (goal given):** `preview_snapshot` to see the current screen, decide the next action toward the goal, act, re-snapshot, repeat. Narrate each step briefly. Honour rule 4 (confirm data-writing steps).

### 4. Report
- Per step: ✅/❌ with what happened. On ❌, include the console/network clue and a screenshot.
- End with a summary: steps passed/failed, screenshot paths under `runs/<timestamp>/`, and the final screen.
- Then **offer** Azure DevOps logging (opt-in): if the user says yes, reuse `test-start`'s scripts —
  `~/.claude/skills/test-start/scripts/upload-attachment.sh <png>` → URL, then
  `~/.claude/skills/test-start/scripts/post-comment.sh <workItemId> <html>` — building an HTML result block (badge + steps + screenshots). Comments must not mention AI.

### 5. Record-then-save (grow the library)
After a **successful freeform run** (or a healed replay), propose saving it:
- Show the captured recipe (name + ordered steps + the actual targets used) and ask for a name + OK.
- Write `recipes/<name>.json`. On accept, next time `/work-e2e <name>` replays it.
- If it was a login flow, save/update `login.json`.

## Recipe schema

```json
{
  "name": "create-booking",
  "portal": "provider",
  "description": "Create a standard booking for an employee",
  "requiresLogin": true,
  "steps": [
    { "action": "navigate", "url": "{provider}/#/bookings", "expect": "Bookings list visible" },
    { "action": "click",    "target": "New Booking button",   "expect": "Booking form opens" },
    { "action": "fill",     "target": "Employee search input", "value": "<sample>", "expect": "employee suggestions appear" },
    { "action": "click",    "target": "Save",                  "writesData": true, "expect": "success toast + booking in list" },
    { "action": "screenshot","label": "final" }
  ]
}
```

- `action` ∈ `navigate | click | fill | select | assert | screenshot | wait`.
- `target` = human-readable description (label/placeholder/role/button text) — the driver resolves it live, so it survives minor DOM changes.
- `url` may use `{auth}`/`{provider}`/`{tenant}` placeholders (filled from `urls`).
- `writesData: true` marks a step that mutates data → gate it per rule 4 on first pass.
- Never store credentials in a recipe — `login.json` references `user`/`pass` from the credentials file by intent, not value.

## Resume & notes
- Keep `runs/<timestamp>/run-log.md`: one line per step (n, action, target, pass/fail, screenshot).
- On a fresh run of the same recipe, you may reference the last run's log to compare.
- Keep the MOHR work-log current if session conventions call for it (this is verification, not a branch change — usually nothing to log).

## Relationship to other skills
- **`test-start`** — user-driven manual QA that logs each item to a ticket. Use that when the *user* is clicking. `work-e2e` is when *you* click.
- **Preview verification workflow** (built into the repo) — `work-e2e` is a structured, credential-aware, recipe-saving layer on top of the same `preview_*` tools.
