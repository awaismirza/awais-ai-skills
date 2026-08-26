---
name: ios-common-features
description: Use when developing, reviewing, or auditing iOS apps (Swift / SwiftUI) for standard production features including settings pages (support/links & version cards), update checking & alert prompts with notification badges, smart usage-based paywall prompts (fortnightly frequency), a persistent top-right upgrade entry point with paywall sheet, App Store rating prompts (3-month cooldown), optional/non-blocking OS permissions with a permission-nudge banner, light/dark adaptive appearance with Liquid Glass materials, and first-launch onboarding flows.
---

# iOS Common Features

Production-ready architecture, UI components, and business rules for mandatory iOS app features: Settings support & links, version & update tracking, update alerts & badge indicators, smart usage-based paywalls, a persistent upgrade entry point, respectful App Store rating prompts, non-blocking permission handling, adaptive light/dark appearance, and first-launch onboarding.

---

## When to Use

- Building or refactoring an iOS Settings screen in SwiftUI or UIKit.
- Implementing Support, Legal (Terms & Privacy), Website, Rating, and App Sharing links.
- Adding automatic or manual App Store update checking with alert dialogs, top-of-settings banners, and notification badges (red circle with digit).
- Designing usage-based paywall triggers with fortnightly (14-day) rate-limiting for frequent users.
- Adding a persistent, always-visible "Upgrade" entry point (top-right pill) that opens a paywall sheet on tap — for free users who want to self-serve upgrade rather than wait for a triggered prompt.
- Implementing native App Store rating requests (`StoreKit` / `SKStoreReviewController`) with a 90-day (3-month) cooldown and positive-milestone triggers.
- Requesting camera, microphone, location, or notification permissions without blocking a feature on the grant, and nudging the user with a banner when a permission they need isn't granted.
- Implementing light/dark mode with semantic colors and Liquid Glass / system-material surfaces.
- Building a first-launch onboarding flow.
- Auditing an iOS app codebase for missing production and App Store compliance requirements.

---

## 1. Feature Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                          App Lifecycle Events                          │
│                   (App Launch / Scene Did Foreground)                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
       ┌────────────────────────────┼────────────────────────────┐
       ▼                            ▼                            ▼
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│ AppUpdateManager │      │ PaywallTriggerMgr│      │ ReviewPromptMgr  │
│                  │      │                  │      │                  │
│ • Remote version │      │ • Session count  │      │ • Positive action│
│   lookup (API)   │      │ • Core free uses │      │   milestones     │
│ • Update Alert   │      │ • 14-day cadence │      │ • 90-day cooldown│
│ • Badge count (1)│      │ • Paywall modal  │      │ • StoreKit prompt│
│ • Settings Banner│      └──────────────────┘      └──────────────────┘
└────────┬─────────┘
         ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Primary Screen Header                           │
│  [Permission Nudge Banner] (full-width, shown when a needed permission │
│   is denied/undetermined)              [UPGRADE pill] (hidden if paid) │
└───────────────────────────────────┬────────────────────────────────────┘
                                     ▼ tap
                        ┌──────────────────────┐
                        │   PaywallSheet        │  ← same sheet Feature 4's
                        │  (PremiumEntryPoint)  │    triggered modal also uses
                        └──────────────────────┘
┌────────────────────────────────────────────────────────────────────────┐
│                             SettingsView                               │
│                                                                        │
│  [Top Upgrade Banner] (Shown when update available)                    │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Card 1: Support & Links                                          │  │
│  │ • Website (globe)                • Terms of Use (doc.text.fill)  │  │
│  │ • Privacy Policy (hand.raised)   • Support (envelope.fill)       │  │
│  │ • Rate The App (star.fill)       • Share the app (square.arrow)  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Card 2: Version & Updates                                        │  │
│  │ • Version: 1.2.0 (45) (info.circle.fill)                         │  │
│  │ • Check for Updates Button (arrow.triangle.2.circlepath)         │  │
│  │ • Footer: © 2026 [App Name]. All rights reserved.                │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The 5 Core Feature Specifications

### Feature 1: Settings Support & Links Card
Group all external, legal, support, and community actions into **one cohesive card**:
1. **Website**: Title `"Website"`, SF Symbol `globe`, direct URL to product site (never show raw URL in subtitle).
2. **Privacy Policy**: Title `"Privacy Policy"`, SF Symbol `hand.raised.fill` or `shield.lefthalf.filled`, direct privacy policy web URL.
3. **Terms of Use**: Title `"Terms of Use"` / `"Terms & Conditions"`, SF Symbol `doc.text.fill`, direct legal terms URL.
4. **Support**: Title `"Support"`, SF Symbol `envelope.fill`, opens `mailto:` email or support portal.
5. **Rate The App**: Title `"Rate The App"`, SF Symbol `star.fill` (tinted with accent color), opens App Store review write URL (`https://apps.apple.com/app/id<APP_ID>?action=write-review`).
6. **Share the app**: Title `"Share the app"`, SF Symbol `square.and.arrow.up.fill`, triggers `UIActivityViewController` share sheet with iPad popover anchor protection.

### Feature 2: Settings Version & Update Card
Display app version and interactive check in a dedicated card:
1. **Version Label**: Title `"Version"`, SF Symbol `info.circle.fill`, accessory value showing `CFBundleShortVersionString` and `CFBundleVersion` (e.g. `1.0.0 (3)`).
2. **Check for Updates**: Title `"Check for Updates"`, SF Symbol `arrow.triangle.2.circlepath`, initiates manual update lookup with live loading feedback.
3. **Footer**: Displays standard copyright text: `© [Year] [App Name]. All rights reserved.`

### Feature 3: Automated Update Checking & Alerts
1. **On Launch / Foreground**: App checks remote version against App Store Lookup API (`https://itunes.apple.com/lookup?bundleId=...`) or custom backend endpoint.
2. **If Newer Version Exists**:
   - **Update Alert**: Native alert displayed on launch asking user to update, with `"Update Now"` (deep-links to App Store) and `"Cancel / Later"`.
   - **Badge Indicator**: Display red circle badge with digit `1` on Settings tab/navigation icon or navigation bar item.
   - **Settings Top Upgrade Banner**: Prominent banner pinned above the cards in `SettingsView` with text `"Update Available"`, version number, and an `"Upgrade"` button styled in the app's theme.
3. **Manual Check**: Tapping "Check for Updates" in the version card performs an immediate check and displays an alert (either `"You're on the latest version"` or the update prompt).

### Feature 4: Smart Usage-Based Paywall Prompting (Fortnightly Limit)
1. **Usage Analysis**: Tracks engagement metrics (session counts, core free action completions).
2. **Frequency Threshold**: When a user becomes a frequent user (e.g., completes 5+ free actions or 10+ sessions), trigger the Paywall.
3. **Fortnightly Rate-Limiting**: Enforce a strict minimum cooldown of **14 days (fortnightly)** between automatic paywall impressions.
4. **Respectful Timing**: Only trigger paywall immediately *after* successful completion of a free action—never interrupt active user workflows or error states.

### Feature 5: App Store Rating Prompt (`StoreKit`)
1. **Milestone Triggers**: Trigger rating review after meaningful positive milestones (e.g., successful project export, 3 completed workflows, streaks).
2. **3-Month (90 Days) Cooldown**: Persist `lastReviewPromptDate` in `UserDefaults`. Suppress review requests if prompted within the past 90 days.
3. **Native API**: Use modern SwiftUI `Environment(\.requestReview)` on iOS 16/17+ or `SKStoreReviewController.requestReview(in:)` with fallback.
4. **App Store Review Link Fallback**: Always maintain manual "Rate The App" link in Settings Support Card.

### Feature 6: Persistent Premium Entry Point (Upgrade Pill + Paywall Sheet)
Distinct from Feature 4: Feature 4 is an **interruptive, frequency-gated modal** the app decides to show. Feature 6 is a **persistent, non-interruptive, self-serve entry point** that's simply always there for free users. Both coexist and present the same `PaywallSheet`.
1. **Placement**: Outline-style capsule pill, top-right of the primary/home screen header, ideally visible from every top-level tab (not just one screen).
2. **Visibility rule**: Rendered only when the live entitlement check says non-premium; hidden immediately once purchased/subscribed. Never shown to a paying user, even briefly on a stale cache — check real entitlements, not just a cached tier flag.
3. **Visual style**: 1pt border in accent color, accent-colored label (e.g. `"UPGRADE"`), transparent/matching fill — not solid. Reserve solid fill for the sheet's own primary CTA.
4. **Tap behavior**: Sets a single shared `@Published var isPaywallPresented` on the entitlement manager, presented via `.sheet(isPresented:)`. Every upgrade entry point in the app (this pill, a Settings row, a milestone nudge from Feature 4) should drive the *same* published flag so they all open the identical sheet.
5. **Paywall sheet anatomy**, top to bottom: dismiss `✕` → small-caps product-name eyebrow in accent color → bold benefit-led headline (states the outcome, not the feature list) → card of 2–4 checkmarked feature bullets → price card(s) → primary CTA (`"Buy for $X.XX"` / `"Subscribe"` / `"Start Free Trial"`) → `"Not Now"` secondary text button (dismiss only, no guilt copy) → `"Restore Purchases"` tertiary link → one-line legal fine print stating renewal/expiry terms plainly.
6. **Monetization model — detect or ask once, never assume**: two genuinely different, both-legitimate patterns:
   - **Auto-renewable subscription** (monthly/yearly): StoreKit 2 `Product.products(for:)` + `Transaction.currentEntitlements` + a `Transaction.updates` listener; tier cached optimistically in `UserDefaults`, always reconciled against real entitlements; never a sandbox/debug bypass in a shipped build.
   - **One-time non-consumable "lifetime unlock"**: a single non-consumable product; entitlement = "was this ever purchased and not revoked" — no expiration/renewal concept, no multiple price tiers.
   These need materially different StoreKit code *and* different sheet copy (subscription needs multi-tier price cards + trial messaging; one-time needs exactly one price card + "never expires, never renews" fine print). Search the existing codebase first (`Product.products`, `.autoRenewable`, `.nonConsumable`, an existing entitlement manager) before generating anything new. If neither exists, ask the developer once which model applies and treat the answer as fixed — switching models later is an App Store Connect product-configuration decision, not a code toggle.

### Feature 7: Optional, Non-Blocking Permissions + Permission Nudge Banner
1. **Every OS permission is optional.** Camera, microphone, location, notifications — denying one degrades the dependent feature to a working fallback (e.g. "pick from library" instead of "scan"), it never disables a whole app section. Design the degraded path before writing the permission-request code.
2. **Ask at point of use, never in a batch on launch.** Request the permission the moment the user taps the action that needs it. Batched upfront prompts on first launch get reflexively denied.
3. **Permission Nudge Banner**: full-width, dismissible banner near the top of the screen whose primary action needs a currently denied/undetermined permission — not a corner badge. Leading SF Symbol matching the permission (`bell.slash.fill`, `location.slash.fill`, `mic.slash.fill`, `camera.fill` with a slash overlay), muted warning tint, one plain-language line stating *why* the app needs it (e.g. `"Notifications are off, so alarms can't arrive."`), trailing chevron. Tapping it opens the system Settings deep link (`UIApplication.openSettingsURLString`) once already denied, or the native OS prompt directly if still `.notDetermined`.
4. **Don't nag**: never re-show the banner for a permission already explicitly declined more than once in the same session.

### Feature 8: Adaptive Appearance — Light/Dark Mode + Liquid Glass Materials
1. Every custom color is a semantic asset-catalog color with both Light and Dark appearances defined — never a hardcoded `Color(white:)`/hex value. Don't force `.preferredColorScheme` — follow the system setting.
2. Prefer system materials (`.ultraThinMaterial`, `.regularMaterial`, `.thickMaterial`) and system glass/blur surfaces for cards, sheets, and bars over flat opaque fills — they adapt to light/dark and to content behind them automatically, and match system chrome on Liquid-Glass-era iOS.
3. Verify both appearances explicitly before calling a screen done — check it in both Light and Dark (Simulator or Xcode preview), not just whichever mode the simulator happened to be in.

### Feature 9: First-Launch Onboarding Flow
1. A multi-step, full-screen paged flow (`TabView` page style or equivalent) shown once, before the user's first meaningful action.
2. **Derive the steps from this app's own spec — never copy another app's exact step list.** Standard shape: Welcome/value-prop → optional Sign In with an explicit Skip/guest path (never force account creation to see the app) → one step per piece of setup data the core feature actually needs → Complete/summary. Every step past Welcome is skippable or has a sensible default, except data the core feature genuinely cannot function without.
3. Persist both the completion flag and per-step progress, so a force-quit mid-flow resumes rather than restarts, and so an interrupted first run isn't mistaken for a fresh reinstall (check for partial profile data too, not just the completion flag, before deciding which one happened).

---

## 3. Quick Reference

| Feature | Primary Class / Component | Key Configuration / API | Cooldown / Trigger Rule |
|---------|---------------------------|-------------------------|-------------------------|
| **Support Card** | `SettingsSupportCard.swift` | `AboutLinks` Enum | Always accessible |
| **Version Card** | `SettingsVersionCard.swift` | `Bundle.main.infoDictionary` | Always accessible |
| **Update Check** | `AppUpdateManager.swift` | iTunes Lookup API / Backend | On app start + manual tap |
| **Update Badge** | `AppUpdateBadge.swift` | Red circle with digit `1` | Active when `isUpdateAvailable == true` |
| **Upgrade Banner**| `AppUpdateBanner.swift` | Top of Settings view | Active when `isUpdateAvailable == true` |
| **Paywall Prompt**| `PaywallTriggerManager.swift` | `UserDefaults` persistence | Fortnightly (14 days) + High usage |
| **Upgrade Pill** | `PremiumUpgradeBadge.swift` | Same `PaywallSheet`, drives `isPaywallPresented` | Always visible while non-premium |
| **Paywall Sheet** | `PaywallSheet.swift` | StoreKit 2 (subscription or non-consumable) | Presented by pill, Settings row, or Feature 4 |
| **Rating Prompt** | `ReviewPromptManager.swift` | `requestReview` (StoreKit) | 90 days (3 months) + Milestone |
| **Permission Banner**| `PermissionNudgeBanner.swift` | `UIApplication.openSettingsURLString` | Shown while a needed permission is denied/undetermined |
| **Optional Permissions**| `OptionalPermissionManager.swift` | `AVCaptureDevice`, `CLLocationManager`, `UNUserNotificationCenter` | Requested at point of use, never blocking |

---

## 4. Templates & Reference Files

Detailed implementation files are located in `templates/` and `references/`:

### Reference Guides:
- [`references/architecture-overview.md`](references/architecture-overview.md) — Architectural pattern and dependency injection.
- [`references/update-check-system.md`](references/update-check-system.md) — Remote version lookup, semantic version parsing, and alert flows.
- [`references/smart-paywall-rules.md`](references/smart-paywall-rules.md) — Usage counters, state persistence, and fortnightly rate-limiting.
- [`references/premium-entry-point.md`](references/premium-entry-point.md) — Upgrade pill placement, paywall sheet anatomy, and the subscription-vs-one-time-purchase decision.
- [`references/app-store-rating-flow.md`](references/app-store-rating-flow.md) — StoreKit review guidelines, 90-day cooldown, and milestone hooks.
- [`references/permission-handling.md`](references/permission-handling.md) — Non-blocking permission requests and the permission nudge banner.
- [`references/appearance-and-onboarding.md`](references/appearance-and-onboarding.md) — Light/dark semantic color rules, Liquid Glass materials, and first-launch onboarding structure.

### Ready-to-Use SwiftUI Templates:
- [`templates/SettingsView.swift`](templates/SettingsView.swift) — Full settings screen with banner, support card, and version card.
- [`templates/SettingsSupportCard.swift`](templates/SettingsSupportCard.swift) — Support & links card component.
- [`templates/SettingsVersionCard.swift`](templates/SettingsVersionCard.swift) — Version card component with check button.
- [`templates/AppUpdateBanner.swift`](templates/AppUpdateBanner.swift) — Update notification banner for Settings.
- [`templates/AppUpdateManager.swift`](templates/AppUpdateManager.swift) — Update service with remote checking and badge management.
- [`templates/PaywallTriggerManager.swift`](templates/PaywallTriggerManager.swift) — Paywall rate-limiter and usage tracking.
- [`templates/PremiumUpgradeBadge.swift`](templates/PremiumUpgradeBadge.swift) — Persistent top-right upgrade pill.
- [`templates/PaywallSheet.swift`](templates/PaywallSheet.swift) — Paywall sheet UI, supporting both subscription and one-time-purchase models.
- [`templates/ReviewPromptManager.swift`](templates/ReviewPromptManager.swift) — Review prompt manager with 90-day cooldown.
- [`templates/PermissionNudgeBanner.swift`](templates/PermissionNudgeBanner.swift) — Full-width permission-needed banner.
- [`templates/OptionalPermissionManager.swift`](templates/OptionalPermissionManager.swift) — Non-blocking permission request wrapper for camera/mic/location/notifications.

---

## 5. Common Implementation Mistakes & Red Flags

| Mistake | Why It Fails | Correct Solution |
|---------|--------------|------------------|
| Displaying raw URLs in Settings rows | Cluttered UI, bad UX | Use clean titles (`"Website"`, `"Privacy Policy"`) without URL subtitles |
| Missing iPad anchor on `UIActivityViewController` | App crashes on iPad when tapping "Share the app" | Set `popoverPresentationController.sourceView` and `sourceRect` |
| Prompting paywall on every launch | High user churn & negative reviews | Enforce 14-day (fortnightly) cooldown via `UserDefaults` |
| Prompting rating on cold launch or error | Violates Apple HIG and triggers negative reviews | Prompt only after a successful user milestone |
| Prompting rating repeatedly | Apple limits review prompts to 3 times per 365 days | Enforce a local 90-day cooldown before even calling StoreKit |
| Hardcoded version strings | Out of sync upon new release | Dynamically extract from `Bundle.main.infoDictionary` |
| Using string comparison for versions (`"1.10.0"` < `"1.2.0"`) | False update alerts due to lexicographical sort | Parse versions into integer components `[Int]` for comparison |
| Upgrade pill still visible to a paying user | Looks broken, invites a support ticket ("I already paid") | Gate on live entitlement check, not a stale cached tier flag |
| One `PaywallTriggerManager`-style paywall UI hardcoded to subscriptions | Breaks for an app using a one-time non-consumable purchase | Detect or ask the monetization model once; branch the sheet's price-card section on it |
| Gating a feature's availability on permission grant | App looks broken/dead to users who decline | Ship a working degraded path for every permission-dependent feature |
| Requesting all permissions in a batch on first launch | Reflexive denial, worse grant rates | Request at the point of use, one at a time |
| Permission banner re-shown every time the denied screen is revisited | Reads as nagging | Suppress after the permission has been explicitly declined once already this session |
| Hardcoded light-only colors (`Color(white:)`, raw hex) | Broken or illegible in Dark Mode | Use semantic asset-catalog colors with both appearances defined |
| Onboarding steps copied verbatim from another app | Collects data this app doesn't need, or skips setup it does | Derive steps from this app's own spec/core-loop requirements |

---

## 6. Audit Checklist for Any iOS Codebase

When auditing an iOS application for production readiness, verify:

- [ ] **Settings Support Card**: Are Website, Privacy Policy, Terms of Use, Support, Rate, and Share links present in a unified card?
- [ ] **iPad Share Sheet Safety**: Does the share action configure `popoverPresentationController`?
- [ ] **Version Card**: Does the version card dynamically display `CFBundleShortVersionString (CFBundleVersion)`?
- [ ] **Check for Updates**: Is there a functional "Check for Updates" action with feedback?
- [ ] **Update Notification**: Is there an update check on launch, an alert dialog, an update badge (`1`), and a top Settings banner?
- [ ] **Semantic Versioning**: Does version checking compare numerical components rather than raw strings?
- [ ] **Paywall Cadence**: Is automatic paywall presentation rate-limited to at most once per 14 days?
- [ ] **Persistent Upgrade Entry Point**: Is there an always-visible (while non-premium) top-right upgrade pill that opens the same paywall sheet as other entry points?
- [ ] **Monetization Model Consistency**: Does the paywall sheet's code match the app's actual StoreKit product type (subscription vs. one-time non-consumable), rather than assuming one?
- [ ] **Rating Prompt Cooldown**: Is `SKStoreReviewController` protected by a minimum 90-day cooldown and positive milestone trigger?
- [ ] **Non-Blocking Permissions**: Does every permission-dependent feature have a working degraded path when the permission is denied?
- [ ] **Permission Nudge Banner**: Is there a full-width banner explaining, in plain language, why a denied/undetermined permission is needed — shown only where relevant, not nagging?
- [ ] **Adaptive Appearance**: Are all custom colors semantic (Light + Dark defined), and has every screen been checked in both appearances?
- [ ] **Onboarding Resumability**: Does a force-quit mid-onboarding resume instead of restart, and is an interrupted first run told apart from a genuine reinstall?
