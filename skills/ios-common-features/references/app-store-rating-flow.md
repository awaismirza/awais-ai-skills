# iOS Common Features: App Store Rating & Review Flow

This reference guide details the App Store review prompt rules, Apple HIG requirements, StoreKit integration, and the mandatory **3-month (90-day)** cooldown.

---

## 1. Apple Human Interface Guidelines (HIG) Rules

- **Do Not Interrupt**: Never interrupt a user when they are in the middle of performing a task or immediately upon app opening.
- **Do Not Prompt on Failure**: Never prompt for a review after a crash, network error, or failed transaction.
- **Prompt at Moments of Delight**: Trigger the review request after a user completes a meaningful, positive milestone (e.g. achieving a goal, exporting a file, completing a 5-day streak).
- **Enforce Cooldowns**: Apple limits StoreKit prompts to 3 times per 365 days. If prompted too often, Apple will silently ignore the request. Therefore, maintaining an internal **90-day (3-month)** minimum cooldown ensures every prompt is meaningful.

---

## 2. StoreKit Review Implementation

### Modern SwiftUI (iOS 16+)
Use the `@Environment(\.requestReview)` action:

```swift
import SwiftUI
import StoreKit

struct MilestoneView: View {
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var reviewManager: ReviewPromptManager

    var body: some View {
        Button("Complete Goal") {
            completeGoal()

            if reviewManager.recordPositiveEventAndEvaluatePrompt() {
                // Request StoreKit review on main actor
                Task { @MainActor in
                    requestReview()
                }
            }
        }
    }
}
```

### Fallback for iOS 14/15 or UIKit
```swift
import StoreKit

func promptReviewIfEligible() {
    guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
        return
    }
    SKStoreReviewController.requestReview(in: scene)
}
```

---

## 3. Cooldown & Tracking Model

The `ReviewPromptManager` enforces the 90-day cooldown via `UserDefaults`:

```
User completes positive milestone
               │
               ▼
Has user completed at least 3 positive milestones? ───► NO ───► Do Nothing
               │ YES
               ▼
Has it been >= 90 days (3 months) since last review prompt? ───► NO ───► Do Nothing
               │ YES (or never prompted)
               ▼
Call `requestReview()`
               │
               ▼
Record `lastReviewPromptDate = Date()`
```

---

## 4. Manual Review Link in Settings

Always provide a permanent "Rate The App" row in Settings (`SettingsSupportCard.swift`):
- Deep-links directly to the App Store review page:
  `https://apps.apple.com/app/id<APP_ID>?action=write-review`
- Does not affect the StoreKit 3-times-per-year rate limit.
