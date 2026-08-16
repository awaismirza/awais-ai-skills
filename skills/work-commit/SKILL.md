---
name: work-commit
description: "Mid/after work on a MOHR ticket: validate the branch name, commit the current repo's changes with a proper ab#{ticket} message, and push — then offer to do the same in the sibling repo (mohr-web ↔ mohr-api) if it has uncommitted changes. The lightweight commit step; for the full checklist → commit → PR → Slack flow use /work-ship."
trigger: /work-commit
---

# /work-commit

The lightweight **commit + push** step. Validates the branch name, commits the current repo's work with a proper `ab#{ticket}` message and pushes, then — because MOHR changes often span both repos — offers to do the same in the sibling repo (`mohr-web` ↔ `mohr-api`).

> Triggering this is your explicit signal to commit & push. Still **show the proposed message and the file list first**, and **never silently stage changes unrelated to this ticket**. Never mention Claude/AI in the commit message. For the full pre-PR checklist + PR + Slack flow, use `/work-ship` instead.

## Usage

```
/work-commit              — commit & push the current repo, then prompt for the sibling repo
/work-commit 20253        — same, ticket number pre-filled
/work-commit ab#20253     — same, ab# prefix optional
```

---

## What You Must Do When Invoked

### Step 0 — Resolve the ticket number

Stop at the first match:
1. **Command argument** — strip any `ab#` prefix for the raw digits.
2. **Current branch name** — `git branch --show-current`; if it starts with `ab#`, extract the number.
3. **Ask** the user.

Store both the full form (`ab#20253`) and the raw digits.

### Step 1 — Identify the current repo and its sibling

```bash
ROOT=$(git rev-parse --show-toplevel)
NAME=$(basename "$ROOT")
PARENT=$(dirname "$ROOT")
if [ "$NAME" = "mohr-web" ]; then OTHER="$PARENT/mohr-api"; else OTHER="$PARENT/mohr-web"; fi
```

### Step 2 — Validate the branch name (current repo)

```bash
git branch --show-current
```

Valid: `ab#1234` or `ab#1234-short-description` (kebab-case, no spaces). If the branch doesn't start with `ab#NNNNN`, stop and advise:
> Branch name must start with `ab#{ticket}`. Example: `ab#1234-fix-employee-webhook`

Offer to rename/create a correctly named branch if needed.

### Step 3 — Commit & push (current repo)

Inspect what will be committed so it's deliberate:
```bash
git status --short
git diff origin/main --stat
```

Generate a **proper commit message** from the actual change — `ab#{ticket} {concise, specific description}` (imperative; what changed and why). Don't use a vague placeholder.

**Show the user the proposed message and the file list, then:**
```bash
git add {changed files}
git commit -m "ab#{ticket} {concise message}"
git push -u origin HEAD
```

- If the working tree has changes unrelated to this ticket, confirm before staging them.
- If there's nothing to commit, say so and skip to Step 4.
- Pushing a branch does **not** open a PR — it's a safe remote backup.

### Step 4 — Offer to commit & push the sibling repo (only if it has changes)

```bash
git -C "$OTHER" rev-parse --is-inside-work-tree 2>/dev/null
git -C "$OTHER" branch --show-current
git -C "$OTHER" status --short
```

- **No sibling repo found** → skip silently (note briefly).
- **Sibling working tree clean** → nothing to do; say so.
- **Sibling has uncommitted changes** → **ask:** "`{sibling}` is on `{branch}` and has uncommitted changes. Do you want me to commit & push there too?"
  - **yes** → run the same Step 2 + Step 3 flow against `$OTHER` using `git -C "$OTHER" …`. Validate that branch name too; use the same `ab#{ticket}` message convention (the sibling should be on a matching `ab#{ticket}` branch for the same work).
  - **no** → leave it untouched.

### Step 5 — Report

Per repo: branch, commit message used, and push result (or "nothing to commit"). If you're ready to open the PR next, point to `/work-ship pr`.

---

## Quick Reference

| Rule | Value |
|---|---|
| Action | Validate branch → `git add` → `git commit -m "ab#{ticket} …"` → `git push -u origin HEAD` |
| Commit message | `ab#{ticket} {concise message}` — never mention Claude/AI |
| Branch format | `ab#{ticket}` or `ab#{ticket}-description` |
| Sibling repos | `mohr-web` ↔ `mohr-api` (siblings under the same parent dir) |
| Sibling prompt | Only when the sibling has uncommitted changes |
| Confirm first | Show message + file list; never stage unrelated changes silently |
| Full flow | `/work-ship` (checklist → commit → push → PR → Slack) |
