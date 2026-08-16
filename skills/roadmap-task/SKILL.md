---
name: roadmap-task
description: Pick up (or close out) one task from the mohr-web performance/modernization roadmap by ID, keeping the roadmap markdown, the work log, and the HTML task explorer in sync across sessions. Usage - /roadmap-task <task-id> (e.g. /roadmap-task MT-14) or /roadmap-task next (pick the next unstarted task in the active phase) or /roadmap-task done <task-id> (close out a task you already finished)
---

# Roadmap Task

Input: `$ARGUMENTS` — one of:
- A task ID from the roadmap (e.g. `MT-14`, `W3`, `9.4`, `C3.5`, `10.6`, `0.2`)
- `next` — pick the next `planned` task in whichever phase is currently marked active
- `done <task-id>` — close out a task that's already been implemented and manually tested (skip straight to Step 7)

If empty, ask the user which task ID, or whether they want `next`.

Three files must stay in sync for every task start/finish — this is the whole point of the skill:
1. **`~/.claude/mohr-plans/mohr-web-performance-refactor-roadmap.md`** — the source of truth (checkboxes, session log, full task-level detail)
2. **`~/.claude/mohr-work-log.json`** — cross-session ticket/branch/PR bookkeeping (per the `work-log` skill's schema)
3. **`~/.claude/mohr-plans/mohr-roadmap-explorer.html`** — the visual task explorer (status pills), updated via its `TASK_STATUS_OVERRIDES` map only — never hand-edit the `PHASES` data array for a status change

## Step 1 — Resolve the task

Read `~/.claude/mohr-plans/mohr-web-performance-refactor-roadmap.md` and find the task by ID (grep is fine — IDs are unique strings like `MT-14`, `W3`, `9.4`, `C3.5`). Extract: phase, title, files, recipe/description, suggested branch, ticket (may be a real `ab#NNNNN` or `TBD`), model recommendation, test/verification criteria, and any coordination notes (e.g. "also a Phase 10 target — coordinate").

For `next`: find the phase currently marked 🔄 active in the dashboard checklist (§0), then find the first task in that phase's worklist with no `[x]` and no `🔄` prefix.

If the ID isn't found, say so and ask the user to check the ID rather than guessing which task they meant.

## Step 2 — Present the task and confirm

Show the user: task ID + title, files, the recipe steps, suggested branch, ticket, model recommendation, and any coordination notes (these matter — e.g. don't independently redo work that's also claimed by a Phase 7/9/10 track on the same file). Ask for explicit confirmation before starting — same bar as `implement-ticket`'s plan-approval step.

## Step 3 — Branch setup

Run `git status` first — if there are unrelated uncommitted changes, stop and ask how to handle them before switching branches.

- If the task's ticket is a **real ticket** (not `TBD`) and its branch already exists locally or on `origin`, check it out. Several tasks share one branch (e.g. every Phase 8 `MT-*`/`MS-*`/`MM-*`/`MO-*` task suggests branching off `ab#20908-phase8-modal-template-elimination` — check with the user whether they want a dedicated sub-branch per task or to batch several onto the existing branch before shipping).
- If the ticket is `TBD`, this phase/chunk has no Azure DevOps ticket yet. Ask the user: create one now (only if they explicitly want that — do not create ADO tickets unprompted), or proceed on a local branch using the roadmap's suggested branch name and link a ticket later.
- Otherwise: `git checkout main && git pull && git checkout -b "<branch-name>"`.

## Step 4 — Mark the task active in all three files

1. **Roadmap md**: find the task's checkbox/line and prefix it with `🔄` (in-progress marker), matching the existing convention already used for Phase 7 chunks 3/3.5.
2. **Work log**: upsert an entry in `~/.claude/mohr-work-log.json` keyed by (ticket, repo) — if the phase already has an entry (e.g. `ab#20908`), append the specific task ID to its note rather than creating a duplicate entry; if this is a brand-new ticket, create a fresh entry per the `work-log` skill's schema.
3. **HTML explorer**: open `~/.claude/mohr-plans/mohr-roadmap-explorer.html`, find the `TASK_STATUS_OVERRIDES` object (search for that literal string), and add or update the line for this task ID to `'active'`. Do not touch anything else in the file.

## Step 5 — Implement

Follow the recipe from Step 1 exactly, plus this repo's `AGENTS.md`/`CLAUDE.md` conventions:
- No `extends`, no new `ViewChild`, no `mohr-modal-template`, no component-state mutation
- Reuse `libs/designs`/`libs/store`/`libs/utils` before writing app-local code
- `mo-*` components and `theme.css` utility classes only
- Do NOT run `nx build`, `yarn designs:build`, `yarn theme:build`, or any proxy regeneration — leave builds to the user
- Run project-scoped lint/tests (`nx lint <project>`, `nx test <project>`) as you go, not full workspace builds

**Do NOT start the dev server, use `preview_start`/browser-automation tooling, or otherwise try to verify this task's behavior yourself.** This overrides the default "start the dev server and check it in a browser" instinct for every task under this skill — the user runs their own serve and tests every roadmap task manually. Your job ends at: code compiles, lint/test pass at the project-scoped level, and you hand over a precise test plan (Step 6). Do not report a task as behaviorally verified — you didn't verify it; the user will.

## Step 6 — Write the full manual test plan

Never hand the user just the roadmap's one-line `test` field verbatim — expand it into a concrete, click-by-click procedure specific to this task, so they can execute it without having to reconstruct what "check the modal still works" actually means. Include:

1. **Setup** — which app to serve (`yarn tenant:serve` / `provider:serve` / etc.), which route/screen to navigate to, any state precondition (logged in as which role, existing data needed).
2. **Steps** — numbered, concrete actions: which button/field, what to type, what to click next. Not "test the modal" — "click **Add Member** → fill Name + Email → click **Save**".
3. **Expected result at each step** — what should visibly happen, not just "it works".
4. **Regression checks** — what could plausibly break from this specific change, based on the recipe (e.g. a modal conversion: does Cancel truly discard changes; does reopening show fresh state, not stale data from the last open; does the close (X) button behave the same as Cancel).
5. **Console/network check** — tell them to keep DevTools open and watch for: new console errors, duplicate network requests, `NG0100` (relevant to any Phase 7/CD task), unhandled promise rejections.
6. **Edge cases specific to the task category:**
   - **Modal conversions (`MT-*`/`MS-*`)**: open → fill/interact → Save (data persists, modal closes) → reopen same record (shows saved data, not defaults) → open again → Cancel (no save, no partial mutation) → open again → close via X/Escape (same as Cancel) → check on a second monitor size / narrow viewport if the modal has responsive layout concerns.
   - **Subscription-leak fixes (`W*`)**: navigate to the screen → trigger whatever fires the `.subscribe()` (load data, open a sub-panel) → navigate away → navigate back → repeat 3-5×; watch Network tab for duplicate requests and console for duplicate toasts/errors; if a heap snapshot is easy to take, compare retained size before/after.
   - **CD/OnPush chunks (`C*`, Phase 7)**: exercise the specific golden journey named in the task (e.g. drill-down click, tab switch, filter change) multiple times in a row rapidly; confirm the view updates on the *first* interaction, not one click late (the classic OnPush regression signature); watch console for `NG0100`.
   - **Base-class decomposition (`9.*`)**: exercise **every** listed subclass/consumer, not just one — the whole point is confirming the extracted service behaves identically across all of them.
   - **God-component splits (`10.*`)**: full end-to-end flow through every extracted child component in sequence, plus the original single-file flow it replaced (booking creation, calendar navigation, etc. — whatever the component's actual job is).
   - **Config/schematic/lint tasks (Phases 0-3, 5, 6, 11)**: usually no visual UI to click — say so plainly, and instead give the exact command or DevTools check that proves the change (e.g. `performance.getEntriesByType('measure')` in console, or "confirm the pre-commit hook blocks a scratch violation").

Present this plan to the user as the deliverable of this step — do not silently skip past it.

## Step 7 — Close out the task in all three files

Only after the **user** tells you they ran the test plan from Step 6 and it passed (never mark done based on your own assumption or on code review alone):

1. **Roadmap md**: replace the `🔄` prefix with `[x]` (checked). If this was the last task in its group/phase, consider whether the phase-level checkbox in §0 should also flip — ask the user rather than assuming a phase is fully done from one task.
2. **Work log**: update the entry's status/notes to reflect completion; if a PR exists, record its URL.
3. **HTML explorer**: update `TASK_STATUS_OVERRIDES[id]` to `'done'`.
4. **Session log**: append one line to the roadmap md's Session Log — date, task ID, what shipped, PR link if any.

## Step 8 — Report and hand off

Summarize what shipped and where all three files were updated. Tell the user to reload the HTML file's browser tab to see the status change (it's a static file — edits don't auto-refresh an already-open tab). If the work is ready to commit/push/PR, point them at `/ship-ticket` — this skill does not commit, push, or open PRs itself.
