# Test-result comment format (Azure DevOps work-item comments)

DevOps comments render a useful subset of HTML (`<b>`, `<i>`, `<ul>/<ol>/<li>`,
`<table>`, `<span style="color:…">`, `<hr>`, `<br>`, `<img>`, `<a>`). Use it to make
each result a clean, scannable QA test case rather than a wall of text.

## Fields to include (the "what we can add")

| Field | Why it earns its place |
|---|---|
| Result badge | ✅ PASS (green) / ❌ FAIL (red) / ⚠️ ISSUE (amber) — instantly scannable |
| Item N of TOTAL | progress through the spec |
| Type / Page | from the spec's columns — orients the reader |
| Spec ref | sheet name + row number — traceable back to the source of truth |
| Change | "old" → "new" (the acceptance criterion) |
| Steps to reproduce | numbered, from a known entry point — so QA can re-run cold |
| Expected | the pass condition |
| Result / Verified locations | what was actually seen; one labelled screenshot per place tested |
| Environment | FE branch · tenant/provider · URL · en-MS on/off |
| Tested by / date | provenance (author is automatic, but the date helps) |
| Severity (fail only) | how bad — helps triage |

## Item block template (one per verified item)

This is the reusable unit — one per item, whether you're running consolidated mode
(where several of these get concatenated inside one wrapper comment) or per-item mode
(where this whole block, alone, becomes one comment). Keep it tidy; omit rows that
don't apply. Colours: pass `#107c10`, fail `#d13438`, issue `#ca5010`.

```html
<div>
  <span style="color:{{RESULT_COLOR}};"><b>{{RESULT_BADGE}}</b></span>
  &nbsp;·&nbsp; Item {{N}} of {{TOTAL}} &nbsp;·&nbsp; {{TYPE}}
  <table>
    <tr><td><b>Change</b></td><td>"{{OLD}}" → "{{NEW}}"</td></tr>
    <tr><td><b>Page</b></td><td>{{PAGE}}</td></tr>
    <tr><td><b>Spec ref</b></td><td>{{SHEET}}, row {{ROW}}</td></tr>
    <tr><td><b>Environment</b></td><td>{{BRANCH}} · {{TENANT}} · en-MS {{ENMS}}</td></tr>
    <tr><td><b>Tested</b></td><td>{{DATE}}</td></tr>
  </table>
  <b>Steps to reproduce</b>
  <ol>
    <li>{{STEP_1}}</li>
    <li>{{STEP_2}}</li>
  </ol>
  <b>Expected:</b> {{EXPECTED}}<br/>
  <b>Result:</b> {{RESULT_SENTENCE}}
  <ol>
    <li>{{LOCATION_1}}<br/><img src="{{IMG_URL_1}}" width="820"/></li>
    <li>{{LOCATION_2}}<br/><img src="{{IMG_URL_2}}" width="820"/></li>
  </ol>
</div>
```

## Consolidated wrapper template (default mode)

One wrapper per **target work item** (story / child task / bug). It holds a header
plus every item block appended so far, each separated by `<hr/>`. This is the file
you keep at `~/dfr-tests/<story>/consolidated-<workItemId>.html` and grow over time —
always send the FULL file on every PATCH, never a diff.

```html
<div>
  <b>🧪 Manual Test Log — {{SPEC_NAME}}</b><br/>
  <span style="color:#6d6d6d;">Consolidated results — updated as each item is verified.</span>
  <hr/>
  {{ITEM_BLOCK_1}}
  <hr/>
  {{ITEM_BLOCK_2}}
  <hr/>
  {{ITEM_BLOCK_N}}
</div>
```

To add a new item: take the current file's content, insert a new `<hr/>` + item block
right before the final closing `</div>`, and write the result back out before posting.

## Posting flow

**Consolidated (default) — per target work item:**
1. For each saved screenshot, get its attachment URL:
   `URL=$(scripts/upload-attachment.sh ~/dfr-tests/<story>/item-NN-<loc>.png)`
2. Build the item block (above) with the URL(s) embedded under labelled locations.
   One `<img>` per place the user tested — never collapse two locations into one.
3. Append the block to `~/dfr-tests/<story>/consolidated-<workItemId>.html` (creating
   the wrapper if this is the first item for that target).
4. Post the **full** updated file:
   - First item for this target → `scripts/post-comment.sh <workItemId> consolidated-<workItemId>.html`,
     then save the returned comment id into `comment-ids.json`.
   - Every item after → `scripts/post-comment.sh <workItemId> consolidated-<workItemId>.html <existingCommentId>`
     (PATCH — replaces the comment text with the full accumulated body).
5. Repeat per target (story, child task, or just the ticket if no children).

**Per-item (opt-in) — one comment per item, both targets:**
1. Get the screenshot URL(s) as above.
2. Write the item block to `/tmp/item-NN.html`.
3. Post fresh to both targets (per the ask-before-post rule, show the rendered intent
   first):
   - new:  `scripts/post-comment.sh <storyId>  /tmp/item-NN.html`
   - new:  `scripts/post-comment.sh <taskId>   /tmp/item-NN.html`
   - edit: pass the existing `<commentId>` as the 3rd arg to update in place
     (use this to add a missed screenshot instead of posting a duplicate).

## Multiple screenshots / multiple locations

The macOS clipboard holds only the **last** copied image, so capture multi-location
items **one screenshot at a time**: ask the user to copy location 1 → save it →
copy location 2 → save it. Save each to a distinct, location-named file
(`item-NN-module-dropdown.png`, `item-NN-booking-modal.png`) and label each `<img>`
by where it was taken. If the user already pasted several into chat, you only have
bytes for the last one — ask them to re-copy the others individually.
