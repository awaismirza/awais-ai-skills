---
name: test-start
description: >-
  Guided manual UI/UX verification of a MOHR feature against its spec, walking
  each change ONE AT A TIME (top to bottom) with exactly where to look in the UI,
  what to expect, and which code/key backs it — then logging each result to Azure
  DevOps (parent story + mapped child task, attributed to the signed-in user) with
  the tester's screenshot attached. Use this whenever the user wants to test, verify,
  QA, or "go through" UI changes / a UI-changes spec (Excel or DevOps story), verify
  localisation / relabels / hidden buttons, or says "test-start", "start testing",
  "let's test the changes", "verify these on the UI", or pastes a screenshot of a
  screen under test and wants it recorded on the ticket. Trigger even if they don't
  say the word "test" but are clearly walking through changes to confirm them.
---

# test-start — guided spec verification with DevOps logging

Help the user manually verify a feature's UI changes, one item at a time, and
record each result on Azure DevOps with their screenshot. The user does the
clicking; you tell them precisely **where to look, what to expect, and why it
should work**, capture their screenshot, and write it up on the ticket.

Org/project: **dev.azure.com/occhealth/MOHR**. Auth: `AZURE_DEVOPS_PAT` (env) —
comments post as the signed-in user automatically, so everything reads as
"added by them". Never mention Claude/AI in any comment.

## Session defaults (the user's standing choices — don't re-ask unless they change them)

- **Posting cadence: ask before every post.** Draft the comment, show it, post
  only after they say OK. (If a user ever asks to "auto-post", switch to posting
  immediately after each confirmed item.)
- **Comment mode: ONE consolidated comment per target work item (default).**
  Rather than a new comment per item, the first passed/failed item creates a
  single running comment on each target (story / child task / bug); every
  subsequent item **edits that same comment in place**, appending its block.
  This keeps the ticket's comment feed from being flooded with one-liners and
  gives reviewers a single scrollable test log per work item. Ask once, up
  front, if the user wants the alternative instead: "One comment per item?"
  If they say yes, fall back to the old per-item posting behaviour for that
  session. Otherwise assume consolidated and don't re-ask.
- **Log target: BOTH** the parent story **and** the mapped child task for the item**
  (or just the ticket itself if it has no child tasks, e.g. a bug being tested
  directly). Each target gets its own consolidated comment thread.
- **Screenshots: you save them.** When the user pastes/takes a screenshot it sits
  on the macOS clipboard — grab it with the bundled script (below). You cannot
  read bytes out of a chat-pasted image directly; the clipboard is the bridge.

Confirm these once at the start of a session ("I'll keep one running comment per
target, updating it as we go — or would you rather have a separate comment per
item? I'll post to both the story and the child task, asking you before each
update, and save your screenshots from the clipboard — good?"), then proceed
without re-asking.

## Step 1 — Identify the spec and the tickets

Resolve, asking only for what's missing:
1. **Story** — `ab#NNNNN` (the parent). Read it with the DevOps tools to get its
   child tasks and titles.
2. **Spec source** — an Excel file path (preferred, has the row-by-row items) and/or
   the story description. Read the Excel with `openpyxl` (install quietly if absent:
   `pip3 install --quiet openpyxl`). Dump every row across all sheets so you have the
   full ordered item list before you start.
3. **Build the item → child-task map.** Match each item's *Type/module* column to the
   child task whose title covers that module. Confirm the map with the user once.
   For the **DFR Drop 2 story `ab#19851`** the map is:

   | Spec Type | Child task |
   |---|---|
   | Global Changes | ab#20419 |
   | Booking Dashboard (+ Hide Buttons sheet) | ab#20553 |
   | Clinical Dashboard | ab#20554 |
   | Document Type | ab#20556 |
   | PDF Report | ab#20552 (Org-Unit-Psych hide item → ab#20557) |
   | Admin Centre | ab#20555 (deferred) |

## Step 2 — State preconditions once

Before walking items, remind the user of what must be running, because most items
won't render otherwise and you'll waste their time:
- **Front end:** run mohr-web from the **integration branch** that has all the FE
  changes (for DFR Drop 2 that's `dfr-drop2-all`), not a single task branch. FE-only
  items (badges, hidden buttons, tab relabels) only appear there.
- **Localisation active:** the relabels are an `en-MS` overlay. The provider portal
  switches to it via the FE appconfig `defaultUserLanguage:en-MS` (or the
  `Abp.Localization.CultureName=en-MS` cookie). No DB seed drives this — if labels
  don't change, the culture cookie is the thing to check.
- **Right login:** e.g. provider portal as the Sonic Health Plus provider for
  provider-side items.

For each item, tag which kind it is so expectations are right:
- **BE/en-MS** (text overlay) → renders on any FE build once en-MS is active.
- **FE-only** (logic/visibility/badges) → needs the integration FE branch.
- **PDF** → needs a generated report, gated by `IsDfrTenant` (not the overlay,
  because PDFs render under a fixed culture).
- **Deferred/blocked** → note it and skip (don't send the user hunting).

## Step 3 — The per-item loop (the core)

Go strictly top to bottom, **one item per turn**. For each item present this compact
block, then stop and wait:

```
### Item N of TOTAL — <Type / Page>
Change: "<old>" → "<new>"   (or: Hide <X> / behaviour change)
🧭 Steps to reproduce:
   1. <first concrete click/nav>
   2. <next> …  (start from a known entry point: login → menu → screen → control)
✅ Expect: <what they should see after the steps>
🔎 Look here: <the exact control/text on screen to eyeball>
🧩 Backed by: <en-MS key / component / file>  ·  <BE-en-MS | FE-only | PDF | deferred>
⚠️ <any caveat: needs integration branch, needs a Psychology booking, etc.>
```

The **Steps to reproduce** are the point — write them so a QA person who has never
seen the change can follow them cold and land on the exact spot. Start from a known
entry point (login, which portal/tenant), then each click. These same steps get
written into the ticket comment, so QA can re-run the test without you.

Then prompt: verify it, and **paste a screenshot** (or say "skip image"), or tell you
what they actually saw. Don't advance to N+1 until they confirm or say **next**.

Be specific in 🔎 Where — name the menu, tab, dropdown, modal, button. Ground 🧩
Backed-by in the real code (grep the en-MS XML key or the component) so you can tell
them whether it's even wired on the branch they're running — if it isn't, say so
instead of letting them search for something that can't appear.

**Keep momentum:** answer the current item fully and stop. Don't pre-process all
items before responding. You can map/look-up the rest between turns while they test.

## Step 4 — Capture the screenshot

When the user indicates a screenshot is ready (they just took/pasted it → it's on
the clipboard), save it immediately:

```bash
~/.claude/skills/test-start/scripts/save-clipboard-image.sh \
  ~/dfr-tests/<story>/item-<NN>-<short-slug>.png
```

- Success → it prints the saved path; remember it for the post.
- `NO_IMAGE_ON_CLIPBOARD` → the paste didn't put an image on the clipboard (dragging
  a file into chat often doesn't). Ask them to take the shot with **Cmd+Ctrl+Shift+4**
  (copies to clipboard) or **Cmd+Shift+4** (saves to Desktop) and tell you "saved";
  for the Desktop case, grab the newest file: `ls -t ~/Desktop/*.png | head -1`.
- If they said "skip image", proceed text-only.

**Multiple locations = multiple screenshots, captured one at a time.** The clipboard
only holds the **last** copied image, so if an item was verified in 2+ places, save
them individually: copy location 1 → save as `item-NN-<loc1>.png`, copy location 2 →
save as `item-NN-<loc2>.png`. Name each file by its location so you can label it in
the comment. If the user already pasted several images into chat at once, you only
have bytes for the last one — ask them to re-copy the others individually.

## Step 5 — Draft, confirm, and post the result

Build the item's result as a clean **HTML block** — result badge, item/type/spec-ref,
steps to reproduce, expected, verified locations (one labelled screenshot per place
tested), environment, and date. The exact block template, the full field list ("what
to add"), colours, and the consolidated-wrapper anatomy live in
**`references/comment-format.md`** — read it and fill the template. Don't fall back to
a plain `<pre>` blob; the HTML version is what makes results scannable for QA.

### Consolidated mode (default)

Maintain **one running HTML file per target work item** at
`~/dfr-tests/<story>/consolidated-<workItemId>.html` — this is the full, current body
of that target's comment. Also keep `~/dfr-tests/<story>/comment-ids.json` mapping
`{ "<workItemId>": <commentId> }` so you know whether a comment already exists there.

For each verified item, per target:
1. Read the target's current `consolidated-<workItemId>.html` (empty/wrapper-only if
   this is the first item for that target).
2. Insert the new item's HTML block before the closing `</div>` (separated by `<hr/>`
   from the previous block), producing the new full body.
3. Show the user **just the new block** (not the whole accumulated comment — that
   would be noisy) and get their OK per the ask-before-post default.
4. Write the full updated body to the local file, then post:
   - **No comment yet for this target** (not in `comment-ids.json`) → create it:
     ```bash
     URL=$(~/.claude/skills/test-start/scripts/upload-attachment.sh ~/dfr-tests/<story>/item-NN-<loc>.png)
     # write the full wrapper (header + this one item block) to consolidated-<id>.html
     ~/.claude/skills/test-start/scripts/post-comment.sh <workItemId> ~/dfr-tests/<story>/consolidated-<workItemId>.html
     # record the returned comment id in comment-ids.json
     ```
   - **Comment already exists for this target** → edit it in place with the full
     accumulated body (this REPLACES the comment text, so always send the complete
     file, not a diff):
     ```bash
     URL=$(~/.claude/skills/test-start/scripts/upload-attachment.sh ~/dfr-tests/<story>/item-NN-<loc>.png)
     # append the new item block to consolidated-<workItemId>.html
     ~/.claude/skills/test-start/scripts/post-comment.sh <workItemId> ~/dfr-tests/<story>/consolidated-<workItemId>.html <existingCommentId>
     ```
5. Do this once per target (story + child task, or just the ticket if no children) —
   each target has its own independent running comment/file/id.

Report the comment id(s) back after each update.

### Failed items do NOT go on the ticket (important)

The consolidated ticket comment is a record of **verified-passing** items only.
When an item **fails**:
- **Do NOT append it to the consolidated comment / do NOT post it to the ticket.**
- Record it in the local `test-log.md` as `FAIL` with the root cause, and state
  plainly to the user what was wrong (and severity) — then fix it.
- Only once it **passes on retest** do you add its (passing) block to the
  consolidated comment.
- If you already posted/appended a failing item before it was fixed, **remove that
  block** from the `consolidated-<id>.html` file and PATCH the comment so the fail
  disappears from the ticket; re-add it as a pass after the retest.

This keeps the ticket clean for reviewers (no transient red that's already fixed)
while the local log still captures the full fail→fix→pass history.

### Per-item mode (opt-in)

If the user asked for a separate comment per item instead, post fresh comments as
before (no accumulation, no `comment-ids.json`):

```bash
URL=$(~/.claude/skills/test-start/scripts/upload-attachment.sh ~/dfr-tests/<story>/item-NN-<loc>.png)
~/.claude/skills/test-start/scripts/post-comment.sh <storyId> /tmp/item-NN.html
~/.claude/skills/test-start/scripts/post-comment.sh <taskId>  /tmp/item-NN.html
```

To fix or extend a comment already posted this way (e.g. add a missed screenshot),
pass its existing comment id as the 3rd arg to `post-comment.sh` — edit in place,
don't post a duplicate.

## Step 6 — Track progress and allow resume

Maintain a local log at `~/dfr-tests/<story>/test-log.md` (append one line per item:
number, change, Pass/Fail/Skip, screenshot path, comment IDs). In consolidated mode,
also keep `~/dfr-tests/<story>/comment-ids.json` and the per-target
`consolidated-<workItemId>.html` files current — together these let a fresh
`/test-start` on the same story resume exactly where it left off: read the log for
the next unverified item, and read `comment-ids.json` to know which target comments
already exist (so new items get appended via PATCH instead of accidentally creating
a second comment). Also keep the MOHR work-log current if the session conventions
call for it.

## Notes & guardrails

- One item per turn; never batch the whole list onto the user.
- Verify the change is actually present on the running branch before asserting where
  to find it — grep the en-MS key or component. Saying "this won't show on your build"
  saves more time than a confident wrong location.
- **Never reuse a screenshot captured for a different item as evidence.** Each embedded
  screenshot must actually show the item under test. If the user doesn't provide a
  dedicated screenshot for an item, log it **text-only** with an honest note (e.g.
  "verified visually; no dedicated screenshot this pass") rather than repurposing
  another item's image — passing off a reused image as fresh evidence misrepresents
  the verification on a shared ticket.
- Comments must read as written by the user — no Claude/AI mentions, no "Co-Authored-By".
- The DevOps PAT change is consequential/outward-facing: honour the ask-before-post
  default unless the user explicitly opts into auto-posting.
- This skill is MOHR-shaped but general: for a non-DFR story, derive the item→task
  map from that story's own child tasks and skip the DFR-specific branch/en-MS notes.
