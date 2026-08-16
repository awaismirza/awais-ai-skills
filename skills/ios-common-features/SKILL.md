---
name: ios-common-features
description: Use when developing, reviewing, or auditing iOS apps (Swift / SwiftUI) for standard production features including settings pages (support/links & version cards), update checking & alert prompts with notification badges, smart usage-based paywall prompts (fortnightly frequency), and App Store rating prompts (3-month cooldown).
---

# iOS Common Features

Production-ready architecture, UI components, and business rules for mandatory iOS app features: Settings support & links, version & update tracking, update alerts & badge indicators, smart usage-based paywalls, and respectful App Store rating prompts.

---

## When to Use

- Building or refactoring an iOS Settings screen in SwiftUI or UIKit.
- Implementing Support, Legal (Terms & Privacy), Website, Rating, and App Sharing links.
- Adding automatic or manual App Store update checking with alert dialogs, top-of-settings banners, and notification badges (red circle with digit).
- Designing usage-based paywall triggers with fortnightly (14-day) rate-limiting for frequent users.
- Implementing native App Store rating requests (`StoreKit` / `SKStoreReviewController`) with a 90-day (3-month) cooldown and positive-milestone triggers.
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
| **Rating Prompt** | `ReviewPromptManager.swift` | `requestReview` (StoreKit) | 90 days (3 months) + Milestone |

---

## 4. Templates & Reference Files

Detailed implementation files are located in `templates/` and `references/`:

### Reference Guides:
- [`references/architecture-overview.md`](references/architecture-overview.md) — Architectural pattern and dependency injection.
- [`references/update-check-system.md`](references/update-check-system.md) — Remote version lookup, semantic version parsing, and alert flows.
- [`references/smart-paywall-rules.md`](references/smart-paywall-rules.md) — Usage counters, state persistence, and fortnightly rate-limiting.
- [`references/app-store-rating-flow.md`](references/app-store-rating-flow.md) — StoreKit review guidelines, 90-day cooldown, and milestone hooks.

### Ready-to-Use SwiftUI Templates:
- [`templates/SettingsView.swift`](templates/SettingsView.swift) — Full settings screen with banner, support card, and version card.
- [`templates/SettingsSupportCard.swift`](templates/SettingsSupportCard.swift) — Support & links card component.
- [`templates/SettingsVersionCard.swift`](templates/SettingsVersionCard.swift) — Version card component with check button.
- [`templates/AppUpdateBanner.swift`](templates/AppUpdateBanner.swift) — Update notification banner for Settings.
- [`templates/AppUpdateManager.swift`](templates/AppUpdateManager.swift) — Update service with remote checking and badge management.
- [`templates/PaywallTriggerManager.swift`](templates/PaywallTriggerManager.swift) — Paywall rate-limiter and usage tracking.
- [`templates/ReviewPromptManager.swift`](templates/ReviewPromptManager.swift) — Review prompt manager with 90-day cooldown.

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
- [ ] **Rating Prompt Cooldown**: Is `SKStoreReviewController` protected by a minimum 90-day cooldown and positive milestone trigger?
