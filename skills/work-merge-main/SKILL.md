---
name: work-merge-main
description: "Fetch and pull the latest main and merge it into the current working branch (the current MOHR repo), then offer to do the same in the sibling repo (mohr-web ↔ mohr-api) if there's active work there. Use to bring a feature branch up to date with main before continuing work or before shipping. Keeps both repos in sync when a change spans frontend + backend."
trigger: /work-merge-main
---

# /work-merge-main

Fetches and pulls the latest `main` and merges it into your **current working branch** for this repo — then, because MOHR changes often span both repos, offers to do the same in the sibling repo (`mohr-web` ↔ `mohr-api`) when there's active work there.

## Usage

```
/work-merge-main          — fetch + pull main, merge it into the current branch, then prompt for the sibling repo
```

---

## What You Must Do When Invoked

### Step 1 — Identify the current repo and its sibling

```bash
ROOT=$(git rev-parse --show-toplevel)
NAME=$(basename "$ROOT")
PARENT=$(dirname "$ROOT")
if [ "$NAME" = "mohr-web" ]; then OTHER="$PARENT/mohr-api"; else OTHER="$PARENT/mohr-web"; fi
echo "Current: $NAME ($ROOT)"
echo "Sibling: $OTHER"
```

(MOHR repos are siblings: `/Users/mohr/code/mohr-web` and `/Users/mohr/code/mohr-api`.)

### Step 2 — Fetch + pull main, merge into the current branch (current repo)

```bash
git branch --show-current
git status --short
```

- If the working tree is **dirty**, warn the user: merging on top of uncommitted changes can be messy. Ask whether to proceed, stash first, or commit first (`/work-commit`). Don't force it.
- If on `main` itself, just `git pull` and report — there's nothing to merge into.

Otherwise fetch + pull the latest `main` and merge it into the current branch (no need to switch branches):
```bash
git fetch origin                              # get the latest refs
git fetch origin main:main                    # fast-forward local main to origin/main (no checkout)
git log --oneline HEAD..origin/main           # what's new on main
git merge origin/main                          # merge latest main into the current branch
```
> `git fetch origin main:main` updates your local `main` without leaving the feature branch. If it fails (e.g. local `main` has diverged), fall back to just `git merge origin/main` — the current branch still gets the latest main.

- **Clean merge** → report the result and the new commits pulled in.
- **Conflicts** → stop, list the conflicted files (`git status --short`), and hand back to the user to resolve. Do not auto-resolve.

### Step 3 — Offer to merge in the sibling repo (only if active work)

Check whether the sibling repo has active work worth syncing:
```bash
git -C "$OTHER" rev-parse --is-inside-work-tree 2>/dev/null   # confirm it exists
git -C "$OTHER" branch --show-current
git -C "$OTHER" status --short
```

"Active work" = the sibling is **on a feature branch** (not `main`) **and/or** has **uncommitted changes**.

- **No sibling repo found** → skip silently (note it briefly).
- **Sibling is clean and on `main`** → nothing to do; say so.
- **Sibling has active work** → **ask:** "`{sibling}` is on `{branch}`{ and has uncommitted changes}. Do you want me to merge the latest main into it too?"
  - **yes** → run the same Step 2 flow against `$OTHER` using `git -C "$OTHER" …`. Apply the same dirty-tree / conflict caution.
  - **no** → leave it untouched.

### Step 4 — Report

Summarize per repo: which branch, how many commits merged in (or "already up to date"), and any conflicts left for the user.

---

## Quick Reference

| Rule | Value |
|---|---|
| Action | `git fetch origin` → `git merge origin/main` on the current branch |
| Sibling repos | `mohr-web` ↔ `mohr-api` (siblings under the same parent dir) |
| Sibling prompt | Only when sibling is on a feature branch and/or has uncommitted changes |
| Dirty tree | Warn / ask before merging — never force |
| Conflicts | Stop and hand back to the user; never auto-resolve |
