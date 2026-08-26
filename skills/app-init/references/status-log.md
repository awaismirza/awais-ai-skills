# STATUS.md — Cross-Session Handoff Log

The piece most repos are missing. Neither of this skill's two reference repos (a mature, well-documented Next.js app and a shipped iOS app) had one — a changelog records what's *done*; a roadmap records what's *planned*; neither records what's *half-done, why it's stuck, and what the next step is*, which is exactly what an agent picking up cold needs first.

## Why this isn't just the changelog again

A changelog entry gets written when something ships. STATUS.md gets updated *during* the work — including work that never finishes in one session. If an agent runs out of context, or a human switches from Claude Code to Codex to a different Claude Code session, this is the one file that should let the next agent answer, without re-deriving anything from git history: **what was I in the middle of, and what's the next concrete step?**

## Format

One entry per active or recently-touched work item. Keep entries short — this is a pointer to context, not the context itself (link to the relevant plan/PR/issue instead of restating it).

```markdown
# Status

Last updated: 2026-08-27 by Claude (Claude Code)

## In Progress

### Mileage export CSV format change
- **State:** in-progress
- **Started:** 2026-08-25
- **What's done:** New column order implemented in `CSVExporter.swift`, unit tests updated and passing.
- **What's left:** PDF export still uses the old column order — needs the same change in `PDFExportService.swift`.
- **Next step:** Update `PDFExportService.MileagePDFData`, re-run `PDFExportServiceTests`.
- **Blocked on:** nothing.

### Stripe webhook signature verification
- **State:** blocked
- **Started:** 2026-08-24
- **What's done:** Handler scaffolded, reads the raw body correctly.
- **What's left:** Verification itself.
- **Blocked on:** Waiting on the user to provide the webhook signing secret for the sandbox account — cannot proceed without it.

## Recently Completed (last 5, then move to CHANGELOG.md and drop from here)

### Update checker background refresh task
- **Completed:** 2026-08-20
- **Where:** `AppUpdateService.swift`, `BGAppRefreshTask` registration in `DriverLogbookApp.swift`.
```

## Rules that keep it from drifting

1. **Every entry needs a concrete next step, or it's not actually "in progress"** — "in progress" with no next step is indistinguishable from abandoned. If there's genuinely no next step known, mark it `blocked` and say what it's blocked on.
2. **Cross-check "done" against reality before writing it, where that's cheap to do.** If a claimed-done item has a test, does the test exist and pass? If it's a new file, does the file exist? Don't let this become a second hand-maintained ledger that quietly goes stale the way even a well-run repo's own docs can (a mature reference repo's own AGENTS.md footer was found to cite a spec version two behind the actual spec, and its README undercounted tests versus the real suite — both harmless-looking drifts that compound). A status log with the same failure mode as the docs it's meant to fix isn't worth having.
3. **Update it as part of the work, not as a separate pass afterward.** The definition of done (in AGENTS.md) should require a STATUS.md update in the same commit/session as any change that leaves something mid-flight — the same way a changelog entry is required for anything that ships.
4. **Prune aggressively.** Completed items move to the changelog and drop out of STATUS.md within a handful of entries — this file's value is in staying short enough that a cold agent reads the whole thing in one pass, not in being a permanent archive.
5. **One `Last updated` line at the top, with who/what updated it** — mirrors the attribution pattern already common in changelog entries, and makes it obvious at a glance whether this file itself might already be stale.

## Where it's referenced from

Add one line near the top of `AGENTS.md`, ideally right after the file's own opening statement of authority: *"Picking up mid-task? Read [STATUS.md](STATUS.md) first."* A file that exists but isn't linked from the one place every agent is told to read first might as well not exist.
