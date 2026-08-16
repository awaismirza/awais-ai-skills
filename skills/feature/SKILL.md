---
name: feature
description: Use for an Azure DevOps ticket that spans BOTH the .NET backend (mohr-api) and the Angular frontend (mohr-web). Fetches the ticket once, plans coordinated FE+BE changes around the backend→NSwag→frontend contract flow, implements with two human gates (plan approval, and pre-git), and smoke-tests the running stack. Invoke for inputs like "feature ab#1234", "/feature 1234". For single-repo work, use /ticket instead.
argument-hint: <ticket-id>
allowed-tools: Bash(powershell*) Bash(git *) Bash(msbuild *) Bash(dotnet test*) Bash(nx *) Bash(yarn nswag*) Bash(yarn *) mcp__mcp-code-search__search_codebase mcp__mcp-code-search__search_code_graph mcp__mcp-code-search__get_code_neighborhood mcp__mcp-code-search-web__search_codebase mcp__mcp-code-search-web__search_code_graph mcp__mcp-code-search-web__get_code_neighborhood Read Grep Glob Write
---

# /feature — cross-repo ticket orchestrator (mohr-api + mohr-web)

Coordinates one AZDO ticket across the backend and frontend. The backend is the
**contract source**: API changes flow to the frontend through NSwag-generated proxies
(`libs/service-proxies`), so the execution order is always
**BE change → build BE → `yarn nswag` → FE change → build/test FE**.

## Repos
- **Backend:** `C:\Source\mohr-api` — .NET 10 / ABP, Aspire `MOHR.AppHost`, API on `:22742`.
- **Frontend:** `C:\Source\mohr-web` — Angular/Nx/Yarn. Apps: auth `:4200`, tenant `:4201`,
  provider `:4202`, employee `:4204`, booking. Reads `appconfig.json` →
  `remoteServiceBaseUrl: http://localhost:22742`.

## Session prerequisite — CHECK FIRST
This skill edits files in **both** repos, so the session needs both as working
directories and both MCP servers enabled.

1. Confirm `C:\Source\mohr-web` is reachable: `Glob` for `C:\Source\mohr-web\package.json`.
   - If it is **not** accessible, STOP and tell the user:
     > This session can't reach `mohr-web`. Run `/add-dir C:\Source\mohr-web` (or restart
     > Claude with both repos), then re-run `/feature <id>`.
2. The backend tools are `mcp__mcp-code-search__*` (scoped to mohr-api); the frontend tools
   are `mcp__mcp-code-search-web__*` (scoped to mohr-web). Use the matching server per repo.

---

## Setting up the workspace (fetch ONCE)

Reuse the `/ticket` fetcher — do not duplicate AZDO logic. Run from the mohr-api session
so the workspace lands in `C:\Source\mohr-api\.claude\tickets\<id>-<slug>\`:

!`powershell -File "${CLAUDE_PLUGIN_ROOT}/skills/ticket/run.ps1" "$ARGUMENTS"`

The one workspace serves both repos. The cross-repo plan is written there as
`feature-plan.md` (distinct from `/ticket`'s `plan.md`).

---

Follow these steps in order. **Do NOT write any implementation code until the user
approves the plan (Gate 1).**

### Step 1 — Read all generated files
`Read` every file the fetch step listed: `ticket.md` first, then `comments.md`,
all `linked/*.md`, and `prs.md` if present.

### Step 2 — Read all images
`Read` every image path listed (ticket body screenshots, QA findings, design clarifications).

### Step 3 — Scoped semantic search (both repos)
- **Backend patterns:** `mcp__mcp-code-search__search_codebase` /
  `...__search_code_graph` with 2–3 queries from the ticket title, module, and rules.
- **Frontend patterns:** `mcp__mcp-code-search-web__search_codebase` /
  `...__search_code_graph` for the relevant Angular components, libs, and services.
Find existing patterns to reuse before planning new code.

### Step 4 — Cross-repo scope analysis
Determine and record:
- **Scope:** FE-only / BE-only / FE+BE. (If it's truly single-repo, say so and suggest
  `/ticket` — but continue if the user wants the coordinated flow.)
- **BE projects:** specific `MOHR.*` project names.
- **FE apps + libs:** which of auth / tenant / provider / employee / booking, and which
  `libs/*` (designs, store, utils, service-proxies).
- **API contract change?** → `yarn nswag` required (regenerates `libs/service-proxies`).
- **DB migration?** → migration in `MOHR.EntityFrameworkCore.Migrations`.
- **Seeding?** → `RunOnceSeed` (one-time) or `Seed` (repeatable) in `MOHR.Seeding`.

### Step 5 — Write `feature-plan.md` and STOP (GATE 1)
Write the plan to the workspace folder using `feature-plan-template.md` as the structure.
The **execution order** MUST follow the contract flow:
1. BE entity/command/AppService changes
2. Migration (if any) + seeding (if any)
3. Build BE: `msbuild src/<Project>/<Project>.csproj -t:rebuild -v:minimal`
4. `cd C:\Source\mohr-web && yarn nswag` (only if the API contract changed; needs the
   backend running on `:22742`)
5. FE changes (reuse `libs/designs` `mo-*` components, `libs/store`, `libs/utils`)
6. Build/test FE: `nx build <app> --configuration development`, `nx test <app>`

Present a concise summary, then end with:
> ✅ Plan saved to `feature-plan.md`. Reply **go** to implement, or give feedback to revise.

**STOP HERE. Do not modify any source files until the user replies "go".**

---

## After user says "go" — implement autonomously

Implement per `feature-plan.md` in dependency order. After each logical unit, run the
impact check. Do **not** touch git yet.

### Impact check (per repo, reused from /ticket)
**Backend (.cs):**
- Method signature changed → `Grep` all callers across `src/`.
- DTO/interface changed → `Grep` all usages (serialization, mapping, API consumers).
- Entity property changed → check EF config + direct access.
- Build: `msbuild src/<Project>/<Project>.csproj -t:rebuild -v:minimal` (expect 0 errors).

**Contract bridge:**
- If any API surface changed, with the backend running on `:22742`:
  `cd C:\Source\mohr-web && yarn nswag`. Confirm `libs/service-proxies` regenerated and
  the FE build picks up the new types.

**Frontend (.ts / .html):**
- `@Input()`/`@Output()` changed → `Grep` template usages of the component selector.
- Service method signature changed → `Grep` `.inject(ServiceName)` + call sites.
- Interface/type changed → `Grep` type usages. Route changed → `Grep` `routerLink` /
  `navigate()`.
- Build: `nx build <app> --configuration development`. Tests: `nx test <app>`.

**Hidden callers:** use the scoped `search_codebase` per repo to catch dynamic/cross-lib
usages Grep misses.

### Verify the running stack (smoke)
Run the smoke probe against the user-started stack, passing the apps from scope analysis:
```
powershell -File "${CLAUDE_PLUGIN_ROOT}/skills/feature/smoke.ps1" -Apps <app1>,<app2>
```
Report the PASS/WARN/FAIL table. WARN means a probe target isn't running — surface the
start command; it is not a failure of the changes.

### Report + STOP (GATE 2 — before any git operation)
Summarize:
- ✅ Verified safe (builds, tests, smoke).
- ⚠️ Callers/areas needing attention.
- ❌ Any build/test errors.
- Proposed branches (`ab#<id>-short-desc` in each repo) and changed files per repo.

End with:
> ✅ Implementation complete and verified. Reply **commit** to create branches + commits
> in each repo, or give feedback.

**STOP. Do not create branches, commit, or push until the user replies "commit".**

### After user says "commit"
For each modified repo:
- Branch `ab#<id>-short-desc` off latest `main`.
- Commit with a clear message (end with the Co-Authored-By line per repo conventions).
- Per-repo PR description: ticket ref, summary, validation performed, migration status,
  seeding status (`mohr-api/CLAUDE.md` requirements).
**Do NOT open or push PRs until the user explicitly confirms** — branch + commit only,
then ask whether to push and open PRs.
