---
name: work-start
description: "Start work on a MOHR Azure DevOps ticket (occhealth org) — and the read-only ticket viewer. Accepts a ticket URL, number, or ab# reference. Fetches title, description, state, assignee, priority, tags, acceptance criteria, comments, and relations, then OFFERS to create a clean ab#{ticket}-desc branch off latest main. Use whenever the user provides an Azure DevOps ticket link / ab# reference, wants to view a ticket, or wants to start working a ticket. Often run right after /work-plan. Commit/PR/Slack are handled later by /work-ship; returning to main by /work-done."
trigger: /work-start
---

# /work-start

The **start of the MOHR ticket lifecycle**, and the read-only ticket viewer. Fetches and displays a MOHR Azure DevOps work item in full, then offers to create the branch so you can begin work. Works with ticket URLs, plain IDs, or `ab#` references.

> Usually run on a **BE/FE child task** number after `/work-plan` has scoped the work — but works standalone on any ticket too.

> Just want to *read* a ticket (e.g. during a PR review)? Run this and decline the branch prompt in Step 6 — viewing-only is the default path.

> ## 🚫 GOLDEN RULE — never commit code by default
> When working a MOHR ticket, **do NOT `git commit` or `git push` code automatically.** Finish the change, report the build result, and **ask** before committing — the user usually needs to test from the UI first. The stash/commit handling in Step 6 below (for *pre-existing* work when starting a new task) must also be confirmed before running.

## Usage

```
/work-start 20479
/work-start ab#20479
/work-start https://dev.azure.com/occhealth/MOHR/_workitems/edit/20479
```

---

## What You Must Do When Invoked

### Step 1 — Extract the work item ID

From the argument provided, extract the numeric ID:
- `20479` → `20479`
- `ab#20479` → `20479`
- `https://dev.azure.com/occhealth/MOHR/_workitems/edit/20479` → `20479`
- `https://dev.azure.com/occhealth/MOHR/_workitems/edit/20479?...` → `20479` (strip query string)

If no argument was provided, ask: "Please provide a ticket number or URL."

Set `TICKET_ID` to the extracted number.

### Step 2 — Fetch the work item

Run this bash command (requires `AZURE_DEVOPS_PAT` env var):

```bash
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${TICKET_ID}?\$expand=all&api-version=7.1"
```

If `AZURE_DEVOPS_PAT` is empty or the command returns `{"$id":"1","innerException":null,"message":"..."`, tell the user:
> `AZURE_DEVOPS_PAT` env var is not set. Add it to `~/.claude/settings.json` under the `"env"` key and restart Claude Code.

### Step 3 — Fetch comments

```bash
curl -s -u ":$AZURE_DEVOPS_PAT" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workitems/${TICKET_ID}/comments?api-version=7.1-preview.3"
```

### Step 4 — Display the ticket

Format the output clearly using these field paths from the JSON response:

| Display Label | JSON Field Path |
|---|---|
| ID | `.id` |
| Title | `.fields["System.Title"]` |
| Type | `.fields["System.WorkItemType"]` |
| State | `.fields["System.State"]` |
| Assigned To | `.fields["System.AssignedTo"].displayName` |
| Priority | `.fields["Microsoft.VSTS.Common.Priority"]` |
| Area Path | `.fields["System.AreaPath"]` |
| Iteration | `.fields["System.IterationPath"]` |
| Tags | `.fields["System.Tags"]` |
| Created By | `.fields["System.CreatedBy"].displayName` |
| Created Date | `.fields["System.CreatedDate"]` (format: `DD MMM YYYY`) |
| Changed Date | `.fields["System.ChangedDate"]` (format: `DD MMM YYYY`) |
| Description | `.fields["System.Description"]` (strip HTML tags) |
| Acceptance Criteria | `.fields["Microsoft.VSTS.Common.AcceptanceCriteria"]` (strip HTML tags) |
| Repro Steps | `.fields["Microsoft.VSTS.Common.ReproSteps"]` (strip HTML tags, if present) |

To strip HTML tags from description/criteria fields, pipe through:
```bash
sed 's/<[^>]*>//g' | sed 's/&nbsp;/ /g' | sed 's/&lt;/</g' | sed 's/&gt;/>/g' | sed 's/&amp;/\&/g' | tr -s ' \n'
```

For **relations** (linked items), check `.relations[]`:
- `rel == "System.LinkTypes.Hierarchy-Reverse"` → Parent
- `rel == "System.LinkTypes.Hierarchy-Forward"` → Child
- `rel == "ArtifactLink"` → PR/commit links

For **comments**, display each as:
```
[Author] [Date]: [Text (strip HTML)]
```

### Step 5 — Output format

Present the ticket like this:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ab#{ID} — {Title}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Type:       {WorkItemType}
State:      {State}
Assigned:   {AssignedTo}
Priority:   {Priority}
Tags:       {Tags}
Iteration:  {IterationPath}
URL:        https://dev.azure.com/occhealth/MOHR/_workitems/edit/{ID}

DESCRIPTION
{Description (cleaned)}

ACCEPTANCE CRITERIA
{AcceptanceCriteria (cleaned, if present)}

REPRO STEPS
{ReproSteps (cleaned, if present)}

RELATIONS
{Parent / Child / PR links if any}

COMMENTS ({count})
{Each comment: Author · Date · Text}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Omit sections that are empty or null.

### Step 6 — Offer to start the task (branch setup)

After displaying the ticket, **ask the user**: "Do you want to start working on this ticket now (create a branch)?"

If they say no, stop here — this is the read-only / viewing path. If yes, prepare a clean branch off the latest `main`:

**6a. Inspect the current working state**
```bash
git branch --show-current
git status --short
```

**6b. Handle any in-progress work before switching**

If the working tree has uncommitted changes (or you're sitting on an in-progress `ab#…` branch), decide **stash vs commit** based on whether the *current* branch already has an open PR:

```bash
CURRENT=$(git branch --show-current)
gh pr list --head "$CURRENT" --state open --json number,url
```

- **Current branch HAS an open PR** → the work belongs to that already-reviewed PR. **Commit** it (and offer to push) so nothing is lost:
  ```bash
  git add -A
  git commit -m "ab#{currentTicket} {concise message}"
  git push
  ```
- **Current branch has NO PR** → it's unfinished/unreviewed work. **Stash** it so it can be restored later:
  ```bash
  git stash push -u -m "WIP ${CURRENT} before starting ab#{TICKET_ID}"
  ```
- **Working tree is clean** → nothing to do.

Always confirm the chosen action (commit vs stash) with the user before running it.

**6c. Create the new branch off latest main**
```bash
git fetch origin
git checkout -b "ab#{TICKET_ID}-{short-description}" origin/main
```
Derive `{short-description}` from the ticket title — kebab-case, concise, no spaces (e.g. `ab#20032-dfr-waiver-date-pfid`). Confirm the proposed branch name with the user before creating it.

**6d. Record it in the work log.** Once the branch is created, add (upsert) an entry to `~/.claude/mohr-work-log.json` so the work is tracked from the start — `status: "in-progress"`, with the ticket, title, repo (`mohr-web`/`mohr-api`), branch, and parent story if known. Use the "Upsert" jq helper documented in `/work-log`. This entry lives until `/work-done` closes it, so `/work-log` can always show what's in flight and resume it.

> Branch naming must match the MOHR rule: `ab#{ticket}` or `ab#{ticket}-short-description`. From here, **once your change is done and tested locally, run `/work-ship`** — it handles the pre-PR checklist → commit → push → PR → code-review move → #code-review Slack message. When the PR is up, `/work-done` switches you back to `main` and closes the work-log entry.

---

## Lifecycle map

| Stage | Skill |
|---|---|
| **Start** — read ticket + create branch (adds work-log entry) | **`/work-start`** (this skill) |
| **Ship** — checklist → commit → push → PR → code review → Slack | `/work-ship` |
| **Done** — verify PR + (code review) + main + close/park log | `/work-done` |
| **Resume** — list in-progress work, pick up where you left off | `/work-log` |

## Multiple Tickets

If the user passes multiple IDs or URLs (space or comma separated), fetch and display each in sequence.

```
/work-start 20479 20480 20481
```

Fetch them in parallel if possible (run multiple curl commands). When multiple tickets are passed, treat it as view-only — don't offer branch creation until the user picks one.

---

## Quick Reference

| Setting | Value |
|---|---|
| Org | `https://dev.azure.com/occhealth` |
| Project | `MOHR` |
| API Version | `7.1` |
| Auth env var | `AZURE_DEVOPS_PAT` |
| Work Items API | `/_apis/wit/workitems/{id}?$expand=all&api-version=7.1` |
| Comments API | `/_apis/wit/workitems/{id}/comments?api-version=7.1-preview.3` |
| Query API | `/_apis/wit/wiql?api-version=7.1` |
| Branch format | `ab#{ticket}` or `ab#{ticket}-short-description` |
| Next step | `/work-ship` after local testing |
