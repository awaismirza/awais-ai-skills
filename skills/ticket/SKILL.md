---
name: ticket
description: Use when given an Azure DevOps ticket number to fetch, scaffold a local workspace, and generate an implementation plan. Invoke for inputs like "ab#1234", "ticket 1234", or "/ticket 1234".
argument-hint: <ticket-id>
allowed-tools: Bash(powershell*) Bash(git *) Bash(msbuild *) Bash(nx *) Bash(yarn nswag*) mcp__mcp-code-search__search_codebase Read Grep Glob Write
---

## Setting up workspace

!`powershell -File "${CLAUDE_PLUGIN_ROOT}/skills/ticket/run.ps1" "$ARGUMENTS"`

---

Follow these steps in order. **Do NOT write any implementation code until the user confirms the plan.**

### Step 1 — Read all generated files

Use `Read` on every file listed under "Files to read":
- `ticket.md` — start here
- `comments.md` if present — discussion often contains clarifications, QA feedback, and edge cases with screenshots
- All `linked/*.md` — understand parent epic and child relationships
- `prs.md` if present — understand what was already attempted or reviewed

### Step 2 — Read all images

Use `Read` on every image path listed under "Images". Images marked `[comment]` are from discussion — may include bug screenshots, QA findings, or design clarifications. Images marked `[ticket]` are from the ticket body.

### Step 3 — Semantic search

Use `search_codebase` with 2–3 targeted queries based on the ticket title, module, and key terms from Business Rules / Acceptance Criteria. Find existing patterns to follow before planning.

### Step 4 — Scope analysis

Determine:
- **Scope:** FE-only / BE-only / FE+BE
- **FE apps:** auth / tenant / provider / employee / booking
- **BE projects:** specific `MOHR.*` project names
- **API shape changes?** → `yarn nswag` needed
- **DB changes?** → migration needed
- **Linked ticket impact:** does parent context or child ticket change the scope?

### Step 5 — Write plan.md and STOP

Write the implementation plan to the ticket folder as `plan.md`. Structure it as:

```
# Implementation Plan — ab#<id>

## Scope
...

## Execution order
1. [ ] BE: specific file path — what to change
2. [ ] FE: specific file path — what to change
...

## Files to read before starting
- path/to/file — why

## Potential impact areas
- list components/services that may be affected

## Questions / ambiguities
- ...
```

After writing `plan.md`, present a **concise summary** of the plan to the user.

**STOP HERE. Do not write any code or modify any source files.**

End your response with:
> ✅ Plan saved to `plan.md`. Reply **go** to start implementing, or give feedback to revise the plan.

---

## After user says "go" — Implementation + Impact Check

Implement according to `plan.md`. After completing **each logical unit** (e.g. one service, one component), do a quick impact scan before moving to the next.

### Impact check protocol

After implementation is complete, run the following:

**1. Git diff — see what actually changed**

Run `git diff --name-only` in each repo root that was modified.

**2. For each changed BE file (.cs):**
- If a **method signature** changed → `Grep` for all callers across `src/`
- If a **DTO/interface** changed → `Grep` for all usages (serialization, mapping, API consumers)
- If an **entity property** changed → check EF config + any direct property access
- Run: `msbuild src/<Project>/<Project>.csproj -t:rebuild -v:minimal`

**3. For each changed FE file (.ts / .html):**
- If an **@Input() or @Output()** changed → `Grep` for all template usages of that component selector
- If a **service method signature** changed → `Grep` for all `.inject(ServiceName)` + method calls
- If an **interface/type** changed → `Grep` for all type usages
- If a **route** changed → `Grep` for all `routerLink` and `navigate()` references
- Run: `nx build <app> --configuration development`

**4. Search for hidden callers**
Use `search_codebase` to find any callers that Grep might miss (e.g. dynamically referenced services, cross-lib usages).

**5. Report**
Summarise:
- ✅ What was verified safe
- ⚠️ What needs attention (callers found that may break)
- ❌ Any build errors

Only mark implementation complete when build passes and no unhandled breaking callers remain.
