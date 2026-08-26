# Adaptive Appearance & First-Launch Onboarding

Reference for Features 8 and 9.

## Light/Dark Mode & Liquid Glass (Feature 8)

**Every custom color is a semantic asset-catalog color, never a hardcoded value.** `Color("BackgroundPrimary")` with both a Light and a Dark appearance defined in Assets.xcassets — not `Color(white: 0.98)`, not a raw hex literal. A hardcoded color is a Dark Mode bug waiting to be filed.

Don't force `.preferredColorScheme(.light)` or `.dark)` anywhere in the app unless the user explicitly chose that override in Settings — the default is to follow the system setting, full stop.

Prefer system materials over flat opaque fills for cards, sheets, and bars:

- `.ultraThinMaterial` / `.regularMaterial` / `.thickMaterial` as background fills.
- System-provided glass/blur surfaces (the Liquid Glass family on iOS 18+/26-generation targets) for tab bars, toolbars, and floating controls.

These adapt to light/dark and to whatever content sits behind them automatically — a flat `Color(...)` fill has to be hand-tuned for both appearances and will drift out of sync with system chrome over time.

**Verification is not optional**: before calling any new screen done, check it in both Light and Dark — Simulator toggle (`⌘⇧A` in Interactive Previews, or "Interface Style" in the Simulator's Features menu) or an Xcode preview with both `.preferredColorScheme` traits. A color that "looks fine" is only verified in the one mode you happened to be looking at.

## First-Launch Onboarding (Feature 9)

A multi-step, full-screen paged flow, shown once, before the user's first meaningful action in the app.

**The steps come from this app's own spec — never copy another app's exact sequence.** The question to ask for each candidate step: does the app's core loop actually need this before it can work? If not, it's a step to cut or make optional.

Standard shape, adapt as needed:

1. **Welcome** — one-screen value proposition, no data collection.
2. **Sign In** (optional) — always pair with an explicit Skip/guest path. Never force account creation before the user has seen any value; a guest mode with sane limits beats a forced signup wall.
3. **One step per essential setup input** — only what the core feature genuinely can't function without. Everything else belongs in Settings, editable later, not gating first launch.
4. **Complete** — a short summary/confirmation screen, then into the app.

Every step past Welcome should be skippable or carry a sensible default, with one exception: data the core feature cannot compute anything meaningful without (e.g. a tax-region setting for a tax estimate feature, a starting weight for a weight-tracking feature).

### Resumability

Persist both a completion flag and per-step progress. A force-quit mid-flow should resume where the user left off, not restart from Welcome. This also matters for correctly distinguishing an interrupted first run from a genuine reinstall: don't treat "onboarding completion flag not set" as proof of a fresh install on its own — check for partial profile/setup data too. An app that gets this wrong will re-onboard a user who force-quit once during setup, discarding whatever they'd already entered.
