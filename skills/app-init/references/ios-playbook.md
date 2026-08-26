# Phase 2 Playbook: SwiftUI iOS

## Detection

A repo is `ios-swiftui` for Phase 2 purposes if it has a `project.yml` (XcodeGen) or `.xcodeproj`/`.xcworkspace`, and SwiftUI is the primary UI framework (check the app entry point for `import SwiftUI` / `@main ... App`). If it's UIKit-primary, note that in `.claude/app-init-status.json` and flag to the user that this playbook's templates assume SwiftUI — most of the underlying rules (non-blocking permissions, versioned update checks, monetization-model detection) still apply, but the ready-to-paste templates will need UIKit adaptation.

## What this playbook does

Everything in this playbook is owned by the **`ios-common-features` skill** — this file's job is to sequence and verify, not duplicate its content.

1. **Invoke `ios-common-features`.** Give it the repo context (existing Settings screen if any, existing update/paywall/rating code if any) and let it run its own audit checklist (see that skill's §6) against the repo.
2. **For each of its checklist items**, record the result in `.claude/app-init-status.json` under `phase2.items` (see [`testing-config.md`](testing-config.md) for the exact keys), using the item names in that skill's Quick Reference table:
   - Settings support/links card
   - Version & update card
   - Automated update checking & alerts (badge + Settings banner)
   - Smart usage-based paywall (14-day cooldown)
   - **Upgrade pill + paywall sheet** (Feature 6) — this is the one most likely to need real implementation work rather than just an audit pass, since it's a newer addition to that skill; confirm the monetization model (subscription vs. one-time) before generating any StoreKit code, per that skill's `references/premium-entry-point.md`, and persist the answer to `.claude/app-init-status.json`'s `monetizationModel` field so it's never re-asked.
   - App Store rating prompt
   - **Optional permissions + permission nudge banner** (Feature 7)
   - **Adaptive appearance** (Feature 8)
   - **Onboarding** (Feature 9) — the one item that needs *this app's own spec*, not just the generic skill: read `docs/product-spec.md` (scaffolded or found in Phase 1) to derive the actual onboarding steps this app needs, rather than defaulting to another app's exact step list. If Phase 1 hasn't run yet in this session, read whatever spec/README content exists instead.
3. **Verify each implemented/audited item per the configured mode** — see [`testing-config.md`](testing-config.md). A `done` status in the config file should mean "verified," not just "code was written."

## When `ios-common-features` isn't installed

If the skill isn't available in this environment, say so explicitly rather than silently reimplementing its checklist inline — the whole point of Phase 2 delegating to it is that its templates and reference docs stay the single source of truth. Point the user at installing it (same repo, `skills/ios-common-features/`) rather than duplicating its content into this playbook.
