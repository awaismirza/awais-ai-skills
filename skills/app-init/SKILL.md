---
name: app-init
description: Use when starting a new app repo, or auditing an existing one, for the process-and-documentation scaffolding a coding agent needs to work autonomously across sessions — CLAUDE.md/AGENTS.md, a versioned product spec with immutable snapshots, a split shipped-changes/spec-bump changelog, a roadmap, release/deployment docs, and a cross-session STATUS log so any agent (Claude Code, Codex, Cursor, or a human) can pick up in-progress work cold. Also runs the platform feature-checklist playbook (iOS today, via the ios-common-features skill) with a configurable manual/simulator/browser/E2E verification mode. Use when the user says "set up this repo for agents", "/app-init", "scaffold CLAUDE.md and AGENTS.md", "add a spec/changelog to this repo", or asks what a repo is missing versus a properly-set-up one.
---

# App Init

Two-phase repo scaffolder: **Phase 1** sets up the agent-coding process infrastructure (docs, spec, changelogs, a cross-session status log); **Phase 2** runs a platform-specific feature-checklist playbook. One invocation, always audit-first — never blind-overwrite a file that already has real content.

---

## Usage

```
/app-init                              # audit + fill gaps in the current repo, reuse persisted config
/app-init --verification=manual        # set/override how Phase 2 verifies its work; persists for future runs
/app-init --verification=simulator     # drive the iOS Simulator tool to build/launch/screenshot
/app-init --verification=browser       # drive a browser against the dev server
/app-init --verification=e2e           # run the project's existing Playwright/XCTest suite
/app-init --phase=1                    # process scaffolding only, skip the feature playbook
/app-init --phase=2                    # feature playbook only, skip process scaffolding
/app-init --reset                      # discard .claude/app-init-status.json and start a genuinely fresh run
```

No flags on a repeat run = incremental audit against the persisted status file, not a re-ask of every question.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│  Phase 0 — Detect                                                       │
│  • Stack: SwiftUI iOS project.yml/xcodeproj? Next.js/web package.json? │
│  • Existing run: .claude/app-init-status.json present?                 │
│    - absent  → first run, ask the questions Phase 1/2 need             │
│    - present → incremental audit, reuse persisted answers              │
└───────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Phase 1 — Process scaffolding          (references/process-scaffolding.md) │
│  AGENTS.md (canonical) ← CLAUDE.md (thin pointer + architecture notes) │
│  docs/product-spec.md (stable path) + docs/specs/product-spec-vX.md    │
│  CHANGELOG.md (shipped)  +  docs/spec-changelog.md (spec bumps)        │
│  docs/roadmap.md · release/deployment docs · privacy & terms           │
│  STATUS.md — the cross-session handoff log (references/status-log.md) │
└───────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Phase 2 — Feature playbook               (references/<stack>-playbook.md) │
│  Per checklist item: detect → implement if missing → verify per mode   │
│  iOS today → invokes the ios-common-features skill as the base layer   │
│  (web/Android playbooks slot in here later, same pattern)              │
└────────────────────────────────────────────────────────────────────────┘
```

All persisted decisions (stack, verification mode, monetization model if Phase 2 needs one, per-item done/pending status) live in one file: `.claude/app-init-status.json` in the target repo. This is what makes re-runs incremental instead of a full re-interview.

---

## Phase 1 — Process Scaffolding

Full detail in [`references/process-scaffolding.md`](references/process-scaffolding.md). Summary:

1. **Audit first.** Read what already exists (CLAUDE.md, AGENTS.md, any docs/, any changelog) before writing anything. A repo with real content in CLAUDE.md and no AGENTS.md (common — e.g. a solo Claude Code user who never needed cross-agent portability) gets *migrated*, not overwritten: move the process rules into a new AGENTS.md, slim CLAUDE.md down to a pointer plus the architecture context worth preserving, and confirm the migration with the user before committing it.
2. **AGENTS.md is canonical, CLAUDE.md defers to it.** AGENTS.md is the one file every agent (Claude Code, Codex, Cursor, Gemini, Copilot, a human) reads for the definition of done, non-negotiable rules, and required spec/changelog updates. CLAUDE.md becomes a short pointer ("AGENTS.md is the source of truth... where the two disagree, AGENTS.md wins") plus whatever hard-won architectural context is expensive to rediscover from code — never a second copy of the process rules.
3. **Versioned spec, stable path + immutable snapshots.** `docs/product-spec.md` is the one path every agent always reads; each version bump snapshots it to `docs/specs/product-spec-vX.Y.md` via [`scripts/bump-spec.sh`](scripts/bump-spec.sh) before editing the stable file. Never keep only numbered files with no stable "current" path — a tool shouldn't have to guess which is newest.
4. **Two changelogs, not one**, unless the target repo already has a working single-file convention (e.g. Driver Logbook's `RELEASES.md`) — audit for that first and extend it rather than fragmenting an established pattern. Otherwise: `CHANGELOG.md` (Keep a Changelog format, what shipped, cut at release time) and `docs/spec-changelog.md` (spec version bumps specifically, one entry per bump). Different cadences — a spec can bump several times between changelog cuts.
5. **Roadmap, release/deployment docs.** `docs/roadmap.md` (forward-looking, a Status column per item). Release docs per stack — an App Store metadata doc for iOS (bundle IDs, product IDs, review notes), deployment runbooks per concern for web (hosting, database, payments, worker/queue).
6. **Privacy & terms — ask, don't assume.** Two real patterns exist: rendered in-app/in-site pages (a web app's own `/privacy` route), or a pointer to a separate marketing-site repo (common for a native app with no web presence of its own). Detect which one already applies; if neither, ask once and persist the answer.
7. **STATUS.md — the piece most repos are missing.** A cross-session handoff log so a different agent (or the same agent, out of context) can read one file and know what's done, in-progress, blocked, and next — see [`references/status-log.md`](references/status-log.md). Reference it explicitly from AGENTS.md's "read this first" section.

---

## Phase 2 — Feature Playbook

Full detail in [`references/ios-playbook.md`](references/ios-playbook.md) (the only playbook today; a web/Android playbook slots into the same `references/<stack>-playbook.md` pattern later without touching Phase 1 or this file).

For a SwiftUI iOS target, Phase 2 **invokes the `ios-common-features` skill** as the base layer (Settings support/links, version/update card + native alert + badge + Settings banner, usage-triggered paywall, App Store rating, the persistent upgrade pill + paywall sheet, non-blocking permissions + nudge banner, adaptive appearance, onboarding) — see that skill for the full checklist and templates. `app-init`'s own job in Phase 2 is just: detect the stack, invoke the right playbook, and drive verification per the configured mode (below). It does not re-implement what `ios-common-features` already owns.

### Verification mode

Set once (first run asks; a flag overrides and re-persists), stored in `.claude/app-init-status.json`:

| Mode | What Phase 2 does after implementing/auditing a checklist item |
|---|---|
| `manual` | Prints what to check by hand — no tool drives anything |
| `simulator` | Builds, launches, and screenshots via the iOS Simulator tool |
| `browser` | Drives a browser against the project's dev server |
| `e2e` | Runs the project's existing Playwright/XCTest suite, if present |

See [`references/testing-config.md`](references/testing-config.md) for the exact persisted schema and how a later `--verification=` flag changes it without re-asking anything else.

---

## Templates & Reference Files

### Reference Guides
- [`references/process-scaffolding.md`](references/process-scaffolding.md) — Phase 1 in full, including the CLAUDE.md→AGENTS.md migration procedure for a repo that already has content in CLAUDE.md alone.
- [`references/status-log.md`](references/status-log.md) — STATUS.md format: fields, states, how it stays honest instead of drifting.
- [`references/testing-config.md`](references/testing-config.md) — verification-mode persistence and the `--verification=` flag contract.
- [`references/ios-playbook.md`](references/ios-playbook.md) — Phase 2 for SwiftUI iOS targets.

### Templates
- [`templates/CLAUDE.md.template`](templates/CLAUDE.md.template)
- [`templates/AGENTS.md.template`](templates/AGENTS.md.template)
- [`templates/product-spec.md.template`](templates/product-spec.md.template)
- [`templates/spec-changelog.md.template`](templates/spec-changelog.md.template)
- [`templates/CHANGELOG.md.template`](templates/CHANGELOG.md.template)
- [`templates/STATUS.md.template`](templates/STATUS.md.template)

### Scripts
- [`scripts/bump-spec.sh`](scripts/bump-spec.sh) — clones `docs/product-spec.md` to a version-numbered snapshot and rewrites the stable file's version header. The one purely mechanical step in Phase 1 — run it rather than hand-editing the version bump, so the snapshot and the header can't drift out of sync.

---

## Common Implementation Mistakes & Red Flags

| Mistake | Why it fails | Correct solution |
|---|---|---|
| Overwriting an existing CLAUDE.md that already has real content | Destroys hard-won, undocumented-elsewhere knowledge | Audit first; migrate content into AGENTS.md, slim CLAUDE.md to a pointer, confirm before committing |
| Writing process rules into both CLAUDE.md and AGENTS.md | The two drift the moment one gets updated and the other doesn't | AGENTS.md owns rules; CLAUDE.md only points to it plus "why" context |
| Only numbered spec files, no stable "current" path | A tool (or a human) has to guess which numbered file is newest | Stable `docs/product-spec.md` + immutable `docs/specs/vX.Y.md` snapshots |
| One changelog trying to serve both "what shipped" and "how the spec changed" | The two have different cadences and get confusing once a spec bumps faster than releases cut | Split `CHANGELOG.md` / `docs/spec-changelog.md` — unless the repo already has a working single-file convention; don't fragment an established pattern for its own sake |
| No cross-session status log, or one that's just a changelog with extra steps | A different agent (or the same one, out of context) can't tell "shipped" from "half-built and blocked" | STATUS.md tracks per-item state (done/in-progress/blocked/not-started), cross-checked against real repo state where possible |
| Hardcoding the iOS feature checklist inside `app-init` itself | Duplicates `ios-common-features`, and the two drift | Phase 2 invokes the existing platform skill; `app-init` only sequences and verifies |
| Assuming a monetization model (subscription vs. one-time) when scaffolding premium features | Generates StoreKit code that doesn't match the app's actual App Store Connect product config | Detect an existing pattern first; if none, ask once and persist — see `ios-common-features`'s `references/premium-entry-point.md` |
| Re-asking every question on every run | Turns an incremental audit into a full re-interview, defeats the point of persisting config | Read `.claude/app-init-status.json` first; only ask what isn't already answered, unless `--reset` |

---

## Audit Checklist

When auditing a repo against this skill:

- [ ] **AGENTS.md exists and is canonical** — the definition of done, non-negotiable rules, and spec/changelog update requirements all live there.
- [ ] **CLAUDE.md defers to AGENTS.md** — a short pointer plus architecture context, not a second copy of process rules.
- [ ] **`docs/product-spec.md` is a stable path**, with immutable version snapshots in `docs/specs/`.
- [ ] **Changelog(s) reflect actual cadence** — either a working split (shipped vs. spec-bump) or one established file, not silent drift between what's documented and what shipped.
- [ ] **`docs/roadmap.md` exists** with a per-item status.
- [ ] **Release/deployment docs exist** for the target stack (App Store metadata for iOS; deployment runbooks for web).
- [ ] **Privacy/terms handling is explicit** — in-repo pages or a sibling-repo pointer, not silently missing.
- [ ] **`STATUS.md` exists, is referenced from AGENTS.md, and reflects real repo state** — not stale, not just a restated changelog.
- [ ] **`.claude/app-init-status.json` exists** with stack, verification mode, and (if applicable) monetization model recorded.
- [ ] **Phase 2's platform playbook has actually run**, not just been referenced — check the playbook's own audit checklist (e.g. `ios-common-features`'s) for the real per-feature state.
