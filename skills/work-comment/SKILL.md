---
name: work-comment
description: "Draft and post a comment to a MOHR Azure DevOps work item (occhealth org). Summarizes the work done / current logic from the git diff, commits, and session context into a comment, shows it for confirmation, and only posts after you approve. Resolves the ticket number from the branch (ab#NNNNN) or an argument. Use to add a progress note, implementation summary, or status update to a ticket."
trigger: /work-comment
---

# /work-comment

Drafts a comment summarizing the current work (implementation logic, what changed, status) and — **only after you confirm** — posts it to the Azure DevOps work item.

> ## ✋ Always confirm before posting
> Never post to the ticket without explicit approval. Generate the draft, show it in a copyable block, and wait for the user to approve (or edit) it first.

## Usage

```
/work-comment                 — draft a comment from current work, confirm, then post
/work-comment 20253           — same, ticket number pre-filled
/work-comment ab#20253        — same, ab# prefix optional
/work-comment "free text"     — post a specific message (still confirm first)
```

---

## What You Must Do When Invoked

### Step 0 — Resolve the ticket number

Stop at the first match:
1. **Command argument** — a number / `ab#NNNNN` (strip the prefix for the raw digits).
2. **Current branch name** — `git branch --show-current`; if it starts with `ab#`, extract the number.
3. **Ask** the user.

Requires `AZURE_DEVOPS_PAT`. If it's empty, tell the user to add it to `~/.claude/settings.json` under `"env"` and restart Claude Code.

### Step 1 — Build the comment draft

- **If the user passed free text** → use that as the draft (lightly clean it up).
- **Otherwise generate it** from the actual work. Pull context from:
  ```bash
  git log origin/main..HEAD --oneline        # commits on this branch
  git diff origin/main --stat                # files touched
  ```
  plus what was done in this session. Summarize **what changed and the logic/approach**, not a file-by-file dump. Keep it concise and factual — a developer's progress/implementation note.

**Voice — read `~/.claude/mohr-voice.md` before drafting** and write the comment in that voice: lead with what was done, plain short sentences, no headers, no bold labels, no emoji. A single short paragraph is often enough; use a few plain bullets only when the changes are genuinely list-shaped.

Suggested shape (adapt to the work):
```
{What was done and the approach, in 1–3 plain sentences.}

- {key change / decision 1}   ← only if genuinely list-shaped
- {key change / decision 2}

{Optional, plain sentence: testing done / what's next / anything reviewers should know.}
```

- Azure DevOps comments render basic HTML. Keep formatting simple; line breaks are fine.
- **Never mention Claude, AI, or any AI assistance** — it must read as a human developer's note.

### Step 2 — Show the draft and confirm

Output the draft in a fenced, copyable code block, then **ask:** "Post this comment to ab#{ticket}? (yes / edit / no)"

- **yes** → proceed to Step 3.
- **edit** → revise per the user's instructions and re-confirm.
- **no** → stop; leave the draft for them to copy manually.

### Step 3 — Post the comment

Only after approval:
```bash
curl -s -u ":$AZURE_DEVOPS_PAT" -X POST \
  -H "Content-Type: application/json" \
  "https://dev.azure.com/occhealth/MOHR/_apis/wit/workItems/${TICKET_ID}/comments?api-version=7.1-preview.3" \
  -d "$(jq -nc --arg t "$COMMENT_TEXT" '{text:$t}')"
```

Use `jq -nc --arg` (or an equivalent safe JSON encoder) so quotes/newlines/HTML in the comment are escaped correctly — do **not** hand-concatenate the JSON body.

Confirm success (the response contains the new comment `id` and `createdDate`) and return the ticket URL:
`https://dev.azure.com/occhealth/MOHR/_workitems/edit/{TICKET_ID}`

If the response is an error object (`{"$id":"1",...,"message":"..."}`), report the message and do not claim success.

---

## Quick Reference

| Setting | Value |
|---|---|
| Org / Project | `https://dev.azure.com/occhealth` / `MOHR` |
| Auth env var | `AZURE_DEVOPS_PAT` |
| Post comment API | `POST /_apis/wit/workItems/{id}/comments?api-version=7.1-preview.3` |
| Body | `{"text": "..."}` (Content-Type `application/json`, JSON-escaped via `jq`) |
| Ticket source | Argument → `ab#` branch name → ask |
| Confirm | **Always** show draft and get approval before posting |
| Wording | Never mention Claude/AI — reads as human-authored |
| Voice | Follow `~/.claude/mohr-voice.md` — plain short sentences, no headers/bold/emoji |
