# Phase 1: Process Scaffolding — Full Procedure

Audit first, every time. Never overwrite a file that already has real content without reading it and reconciling first.

## Step 1 — Read what exists

Before writing anything, check for and read in full: `CLAUDE.md`, `AGENTS.md`, any `docs/` folder, any changelog file, any existing spec file(s) at any naming convention, `README.md`'s own description of the project. Build a picture of what's already there before deciding what's missing.

## Step 2 — CLAUDE.md / AGENTS.md

**Target shape:**
- `AGENTS.md` — canonical, cross-agent. Opens with a statement that it's the source of truth for every agent and every human, and that `CLAUDE.md` defers to it. Contains: the definition of done (always-required checklist; what's additionally required for a user-visible/architectural change, i.e. the spec-bump procedure; what's required for a migration; what's required when a *rule* changes), non-negotiable rules, working-style expectations, dev commands, an architecture overview, a testing summary, a "what's built" section (phases/features complete, known gaps stated honestly, remaining work), and a pointer to `STATUS.md` for in-flight work.
- `CLAUDE.md` — a short pointer ("Read AGENTS.md first... where the two overlap, AGENTS.md wins") plus whatever architectural context is genuinely expensive to rediscover by reading code (the "why" behind non-obvious decisions — a war story, a measured constraint, a considered trade-off). Never restates AGENTS.md's process rules; if you find yourself about to write the same rule in both files, it belongs only in AGENTS.md.

**Three starting states, three procedures:**

1. **Neither file exists.** Write both from `templates/AGENTS.md.template` and `templates/CLAUDE.md.template`, filled in from what you've learned about this repo (or by asking the handful of questions the templates leave as placeholders).
2. **Only CLAUDE.md exists, with real content** (common for a solo Claude Code user who never needed cross-agent portability). This is a migration, not a fresh write: read CLAUDE.md in full, sort its content into "process rule" (definition of done, required updates, conventions) vs. "architecture context" (why something is built the way it is). Move the process-rule content into a new AGENTS.md built from the template; leave the architecture context in CLAUDE.md, trimmed down, with a new pointer section at the top. **Show the user the proposed split before committing it** — this is restructuring real, working documentation, not filling a gap.
3. **Both exist already.** Audit only: check AGENTS.md is actually canonical (does CLAUDE.md defer to it, or do the two duplicate/contradict?) and flag drift rather than silently rewriting either file.

## Step 3 — Versioned spec

Target: `docs/product-spec.md` (stable path, always current) + `docs/specs/product-spec-vX.Y.md` (immutable snapshots, one per version bump).

- If a spec already exists at a different convention (e.g. root-level `AppName_Product_Spec_vX.Y.md` files with no stable "current" name), don't force a rename mid-flight if the repo's own docs (like a CLAUDE.md doc-maintenance section) already document that convention and depend on it elsewhere — flag the stable-path pattern as a suggested improvement instead of silently migrating a scheme other docs already reference by name.
- If no spec exists at all, scaffold `docs/product-spec.md` from `templates/product-spec.md.template`, with a version header block (`> **Spec version:** v1.0`, `> **Historical versions:** (none yet)`).
- Every future bump goes through [`scripts/bump-spec.sh`](../scripts/bump-spec.sh) — never hand-edit the version header without also snapshotting, and never snapshot without also bumping the header. The two operations are one atomic step for a reason: a snapshot without a matching header bump just silently duplicates the previous version under a new filename.

## Step 4 — Changelogs

Two real, working patterns exist:

- **Split** (`CHANGELOG.md` for what shipped, Keep a Changelog format, cut at release time; `docs/spec-changelog.md` for spec version bumps specifically, one entry per bump, cross-referenced by "· Spec vX.Y" tags). Use this by default for a new repo, or a repo whose existing changelog is already struggling to serve both purposes.
- **Bundled single-file** (one release-notes file that captures both shipped changes and spec/version bumps together, promoted from an "Unreleased" section at release time). Keep this if the target repo already has a working version of it — don't fragment an established, working pattern into two files just to match a default.

Either way: an `## Unreleased` (or equivalently-named) section is where every in-progress change accumulates until the next cut — this section should already exist and be current even between releases, not just appear at release time.

## Step 5 — Roadmap & release docs

- `docs/roadmap.md` — forward-looking, one row per planned feature/initiative, a `Status` column (`Backlog` / `In Progress` / `Completed`), grouped by rough priority or phase.
- Release/deployment docs, per stack:
  - **iOS**: an App Store metadata doc — bundle ID(s), product IDs (StoreKit), App Store Connect review notes, submission checklist.
  - **Web**: per-concern deployment runbooks (hosting/CDN, database, payments provider, background workers, environment variables) — one file per concern reads better than one giant ops doc once there's more than 2-3 concerns.

## Step 6 — Privacy & Terms

Two legitimate patterns:

- **In-repo/in-site pages** — the app or site renders `/privacy` and `/terms` itself (typical for a web app with its own marketing pages).
- **Sibling marketing-repo pointer** — a native app with no web presence of its own points at a separate marketing-site repo that hosts the legal pages; the app repo's docs note the sibling repo's expected location and which files there need to stay in sync.

Detect which already applies (does the app have its own rendered legal routes? does an existing doc reference a sibling repo?). If genuinely neither exists yet, ask once which pattern this project wants, and record the answer in `STATUS.md` or the relevant doc rather than re-asking on a later run.

## Step 7 — STATUS.md

The cross-session handoff log — see [`status-log.md`](status-log.md) for the full format. Scaffold from `templates/STATUS.md.template`, and add a one-line pointer to it near the top of AGENTS.md ("Read STATUS.md first if picking up mid-task") so it's not just present but actually discoverable by a cold agent.

## Step 8 — Record what happened

Update `.claude/app-init-status.json` (see [`testing-config.md`](testing-config.md) for its schema) with what Phase 1 found and did, so a re-run is an audit against this record, not a blind repeat.
