---
name: work-ship
description: "Ship a tested MOHR change (mohr-api / mohr-web): runs the pre-PR checklist (build, tests, migration, seeding, plugin, changelog), commits with a proper ab#{ticket} message and pushes, then PROMPTS to create the PR (gh pr create) and ALWAYS outputs the ready-to-paste #code-review Slack message once the PR exists (user pastes it manually; only posts via Slack MCP if explicitly asked). Use AFTER local manual testing, when the work is ready to go up. Returning to main afterward is /work-done."
trigger: /work-ship
---

# /work-ship

The **commit → push → PR → notify** step of the MOHR ticket lifecycle. Run this **after** the code is finished and manually tested locally. It runs the pre-PR checklist, commits with a proper message and pushes, prompts to open the PR, and — once the PR exists — **always outputs the ready-to-paste `#code-review` Slack message** (manual paste is the default; posting via Slack MCP happens only if the user explicitly asks).

> ## 🚫 GOLDEN RULE — committing here is intentional, but confirm the message
> Triggering `/work-ship` is your explicit signal to commit & push — so this skill *does* commit (unlike `/work-start`, which never commits by default). But **always show the proposed commit message and PR text first and let the user adjust**, and **never silently commit unrelated changes** — confirm what's being staged. PR creation is a separate opt-in prompt; the Slack message is always emitted after the PR exists (but never auto-posted). Never mention Claude/AI in commits, PRs, or messages.

## Usage

```
/work-ship              — checklist → commit & push → prompt PR → output Slack message
/work-ship 20253        — same, ticket number pre-filled
/work-ship ab#20253     — same, ab# prefix optional
/work-ship checklist    — run the pre-PR checklist only
/work-ship pr           — skip to PR creation (already committed & pushed)
```

---

## What You Must Do When Invoked

### Step 0 — Identify the ticket

Resolve the ticket number — stop at the first match:

1. **Command argument** — e.g. `/work-ship 20253` or `/work-ship ab#20253` → strip `ab#` for the raw digits.
2. **Current branch name** — `git branch --show-current`; if it starts with `ab#`, extract the number.
3. **Ask** — "What is the Azure DevOps ticket number for this work?"

Store both the full form (`ab#20253`) and the raw digits (`20253`) — both are needed later.

### Step 1 — Validate the branch & sync with main

```bash
git branch --show-current
git fetch origin
git log --oneline HEAD..origin/main
```

**Valid branch name formats:** `ab#1234` or `ab#1234-short-description` (kebab-case, no spaces). If the branch does not start with `ab#NNNNN`, stop and advise:
> Branch name must start with `ab#{ticket}`. Example: `ab#1234-fix-employee-webhook`

If `origin/main` has commits not in the current branch, advise merging and resolving conflicts before continuing:
```bash
git merge origin/main
```

### Step 2 — Pre-PR checklist

Work through each item and report pass/fail. (Build/test commands below are for **mohr-api**; for **mohr-web**, follow the repo's build policy — do not auto-build, leave builds to the user and just confirm the change is tested.)

#### 2a. Build verification (mohr-api)
Build the narrowest project covering the changes:
```bash
msbuild src/MOHR.Core/MOHR.Core.csproj -t:rebuild -v:minimal
```
Replace the project path with whichever project(s) were modified. Must report **0 errors** before proceeding.

#### 2b. Run tests (mohr-api)
```bash
dotnet test
```
All tests must pass. If failures exist, stop and fix them.

#### 2c. Migration check
```bash
git diff origin/main --name-only | grep -i "EntityFrameworkCore"
```
If any entity files in `MOHR.EntityFrameworkCore` changed, check whether a migration was added:
```bash
git diff origin/main --name-only | grep -i "Migrations"
```
- Entity changed but no migration → **BLOCK**: "EF entity changed — a migration in `MOHR.EntityFrameworkCore.Migrations` is required."
- Migration present → ✅ pass

#### 2d. Seeding check
```bash
git diff origin/main --name-only | grep -i "Seeding"
```
Ask: "Does this change require new or corrective data?"
- One-time data fix → `RunOnceSeed` in `MOHR.Seeding`
- Repeatable reference data → `Seed` in `MOHR.Seeding`
- Not needed → mark N/A

#### 2e. Plugin deployment check
```bash
git diff origin/main --name-only | grep -i "Plugin"
```
If plugin files changed, verify registration in **both**:
1. `deploy/azure-pipelines-plugins.yaml` — plugin entry present
2. `deploy/MOHR.Deployment.Plugins/lib/mohr-plugins-stack.ts` — plugin name in `PLUGIN_NAMES` array

#### 2f. CLAUDE_CHANGELOG.md update
Remind the user:
> Update `CLAUDE_CHANGELOG.md` at the root of the repo with a summary of what changed in this session before the PR goes up.

### Step 3 — Commit with a proper message & push

Inspect what's staged/unstaged so the commit is deliberate:
```bash
git status --short
git diff origin/main --stat
```

Generate a **proper commit message** from the actual change — format `ab#{ticket} {concise, specific description}` (imperative, what changed and why it matters). Derive it from the diff, not a vague placeholder.

**Show the user the proposed message and the file list, then commit & push:**
```bash
git add {changed files}
git commit -m "ab#{ticket} {concise message}"
git push -u origin HEAD
```
- Never mention Claude/AI in the message — it must read as human-authored.
- If the working tree contains changes unrelated to this ticket, confirm with the user before staging them.
- Pushing a branch does **not** open a PR — it's a safe remote backup.

Then **ensure a work-log entry exists** for this ticket (so in-progress work is tracked even if `/work-start` wasn't used). Upsert it as `in-progress` — see `/work-log` for the schema and the exact `jq` upsert helper. Use the current repo (`mohr-web`/`mohr-api`) and branch.

### Step 4 — Prompt to create the PR

**Ask:** "Code is committed and pushed. Do you want me to create the PR now?"

If the user says **no / still testing** (or anything ambiguous) → stop here: "👍 Run `/work-ship pr` when you're ready and I'll open the PR and prepare the #code-review message."

If **yes**:

**4a. Duplicate guard** — check first to avoid a second PR:
```bash
gh pr list --head "$(git branch --show-current)" --state open --json number,url
```
If one already exists, return its URL and skip to Step 4d (still update the log + offer the code-review move).

**4b. Generate the PR title + description.**

PR Title: `ab#{ticket} Short description` (max 70 characters).
Example: `ab#20253 Fix employee webhook publisher for DFR tenant`

Fill **every** section from the actual change (use "Not required" / "Not applicable", never blank). Derive Summary / Reason / Validation from `git log origin/main..HEAD` and `git diff origin/main --stat`.

The section headings below are the team's fixed PR template — keep them. But the **prose inside each section follows `~/.claude/mohr-voice.md`**: plain short sentences, no filler ("Additionally", "It's worth noting"), no emoji, no extra bolding, bullets that read like a developer's notes rather than polished parallel phrases.

```markdown
## ab#{ticket} {Short description}

### Summary
- {bullet 1}
- {bullet 2}

### Reason for Changes
{Why this change was needed}

### Validation Performed
- [ ] Build: 0 errors
- [ ] Tests: {all passing | no relevant automated tests}
- [ ] Manual testing: {describe what was tested locally from the UI}

### Migration
{Included | Not required | TODO}

### Seeding
{Included (RunOnceSeed / Seed) | Not required | TODO}

### Documentation
{Updated | Not applicable}
```

**4c. Create the PR:**
```bash
gh pr create --title "ab#{ticket} {description}" --body "$(cat <<'EOF'
{filled-in PR description}
EOF
)"
```
Capture the PR URL returned by `gh pr create`.

**4d. Update the work log** — mark this ticket `pr-created` and record the PR URL (see `/work-log` for the "Mark PR created" jq helper). This is what keeps `/work-log` and `/work-done` aware that the PR exists.

### Step 4e — Move the ticket to code review (PR created)

Because the PR now exists, **offer to move the work item to the code-review column:**
> "PR is up. Move ab#{ticket} to the code-review column on the board?"

If **no** → continue to Step 5. If **yes** (requires `AZURE_DEVOPS_PAT`), discover the right field at runtime — don't hardcode:

1. Read the work item's current `System.State`, `System.BoardColumn`, its `Microsoft.VSTS.Common.CompletedWork` field, and the allowed states for its type:
   ```bash
   curl -s -u ":$AZURE_DEVOPS_PAT" \
     "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${TICKET_ID}?\$expand=all&api-version=7.1"
   TYPE="..."   # url-encode spaces, e.g. User%20Story
   curl -s -u ":$AZURE_DEVOPS_PAT" \
     "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitemtypes/${TYPE}/states?api-version=7.1"
   ```
   - If a **State** like "Code Review" exists → target `System.State`. Otherwise it's a **board column** → target `System.BoardColumn`.
   - If it's already in code review, say so and skip (idempotent — `/work-done` may also offer this).
   - **🐞 Bugs need `Completed Work` set before `Code Review`.** The transition isn't actually blocked for Bugs — it's gated by a rule requiring `Microsoft.VSTS.Common.CompletedWork` to be populated first (`TF401320: Completed Work — Required`):
     - Field already has a non-zero value (visible in the GET above) → proceed straight to the normal Code Review PATCH below, same as any other type.
     - Field is missing/zero → **ask the user**: "ab#{ticket} is a Bug — Code Review requires 'Completed Work' to be set. How many hours should I log?" Carry their answer into step 2.
2. **Confirm** the exact `current → target` change (let the user correct the wording). For a Bug with no `Completed Work` yet, PATCH that field first with the value from the question above, **then** PATCH the state — for every type (Bug included), the target is `Code Review`:
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

### Step 5 — ALWAYS output the #code-review Slack message (never auto-post, never ask)

The moment a PR URL is available (newly created **or** already existing via the duplicate guard), **ALWAYS output the ready-to-paste message** — every time, no exceptions — in a fenced, copyable code block, with all placeholders filled in (no `{…}` left).

- **Do NOT ask** whether to post it — the standing default is **manual paste by the user**. Just emit the block and move on.
- **Do NOT auto-post.** Only post via the `slack_send_message` MCP tool (channel `#code-review`) if the user **explicitly asks** ("post it", "send to slack") — in the same message or afterwards.

> **IMPORTANT:** Never mention Claude, AI, or any AI assistance in the message. It must read as if written by a human developer. (Posting via the Slack MCP adds an automatic "Sent using @Claude" app attribution that cannot be removed from the message body — which is why manual paste is the default.)

- **Channel (only if user explicitly asks to post):** `#code-review`
- **⚠️ Link format — this is the thing that's easy to get wrong.** Slack's `<url|label>` link syntax **only renders when a message is sent via the API**. When a **human pastes** it manually, Slack shows it literally as `<https://…|text>` and the links don't work. Because the default flow here is **manual paste**, the ready-to-paste message MUST use **plain URLs** (Slack auto-links them on paste). Never put `<url|label>` in the paste version.
- **Message — paste-friendly (DEFAULT, plain URLs):**

```
*PR ready for review* 👀

*ab#{ticket} — {short description}*

• *Ticket:* https://dev.azure.com/occhealth/MOHR/_workitems/edit/{N}
• *PR:* {PR_URL}
• *Branch:* `{branch-name}`
• *Repo:* {repo-name}
```

For a ticket with **multiple PRs** (e.g. mohr-api + mohr-web), give each its own line:
`• *mohr-api PR:* {API_PR_URL}` / `• *mohr-web PR:* {WEB_PR_URL}` (still plain URLs).

The block above is the channel's established format — keep it. `{short description}` and any extra line the user asks to add follow `~/.claude/mohr-voice.md`: plain everyday phrasing, no extra emoji beyond the template's, no filler. Any **other** Slack message drafted in this flow (a follow-up, a reply, an FYI to a teammate) is free text and must follow the voice guide fully — short, casual-professional, like asking someone across the desk.

Only when the user opts into **auto-posting via the `slack_send_message` MCP tool** may you switch to Slack's `<{PR_URL}|label>` mrkdwn links — they render correctly when sent through the API.

Where `{N}` is the raw ticket number (digits only) and `{repo-name}` is `mohr-web` or `mohr-api` based on the current directory.

Return the PR URL and confirm whether the message was posted or left for manual paste.

> **PR is up.** When you're ready to start the next piece of work, run **`/work-done`** to switch back to `main` and pull the latest.

---

## Lifecycle map

| Stage | Skill |
|---|---|
| **Start** — read ticket + create branch | `/work-start` |
| **Ship** — checklist → commit → push → PR → Slack | **`/work-ship`** (this skill) |
| **Done** — switch back to `main` and pull | `/work-done` |

## Quick Reference

| Rule | Value |
|---|---|
| Run when | After the change is done and **manually tested locally** |
| Commit here | Intentional (you triggered ship) — but confirm message & files first |
| Branch format | `ab#{ticket}` or `ab#{ticket}-description` |
| Commit message | `ab#{ticket} {concise message}` — never mention Claude/AI |
| PR title format | `ab#{ticket} Short description` (≤70 chars) |
| Build command (api) | `msbuild src/Project.csproj -t:rebuild -v:minimal` |
| Test command (api) | `dotnet test` |
| mohr-web builds | Don't auto-build — leave to the user per repo policy |
| Entity changed | Migration required in `MOHR.EntityFrameworkCore.Migrations` |
| One-time data fix | `RunOnceSeed` in `MOHR.Seeding` |
| Repeatable data | `Seed` in `MOHR.Seeding` |
| New plugin | Register in `azure-pipelines-plugins.yaml` + `mohr-plugins-stack.ts` |
| Changelog | Update `CLAUDE_CHANGELOG.md` before PR |
| Duplicate guard | `gh pr list --head <branch>` before creating |
| After PR created | Mark work log `pr-created` (+ PR url) → offer to move ticket to code review |
| Code-review move | Discover State vs BoardColumn from API → confirm → PATCH (idempotent) |
| Work log | `~/.claude/mohr-work-log.json` — see `/work-log` |
| Slack message | ALWAYS output for manual paste once PR exists — don't ask; post only if user explicitly asks. Never mention Claude/AI |
| Voice | PR prose + free-text Slack wording follow `~/.claude/mohr-voice.md` (template structures stay) |
| After PR | Run `/work-done` to return to `main` |
