# iOS Common Features: Smart Usage-Based Paywall Rules

This guide explains how to analyze user engagement, track core free action usage, and trigger paywall presentations with a strict **fortnightly (14-day)** rate limit.

---

## 1. Principles of Smart Paywalls

1. **Value First**: Never show a paywall immediately upon first launch before the user has experienced the app's core value.
2. **Frequency Trigger**: Trigger paywalls when the user becomes a frequent, habitual user (e.g. 5+ completed actions or repeated app sessions).
3. **Respectful Fortnightly Cadence (14 Days)**: Once a user dismisses a paywall prompt, do not automatically present another paywall for at least **14 days (a fortnight)**.
4. **Natural Action Milestones**: Only trigger the paywall after the successful completion of a task (e.g., generating a report, completing a workout, saving a project). Never trigger mid-task or on error.

---

## 2. Tracking State Machine

The `PaywallTriggerManager` tracks the following metrics in `UserDefaults`:

| Key | Type | Description |
|-----|------|-------------|
| `paywall_free_action_count` | `Int` | Number of core free actions completed since last paywall prompt |
| `paywall_session_count` | `Int` | Number of active app launches / sessions |
| `paywall_last_prompt_date` | `Date?` | Timestamp when the paywall was last presented |
| `is_user_subscribed` | `Bool` | User's active subscription status (RevenueCat / StoreKit 2) |

---

## 3. Trigger Evaluation Logic

```
User completes free action
           │
           ▼
Is user already Pro / Subscribed? ───► YES ───► Do Nothing
           │ NO
           ▼
Increment `free_action_count`
           │
           ▼
Has it been >= 14 days since `last_prompt_date`? ───► NO ───► Do Nothing
           │ YES (or never prompted)
           ▼
Has user reached action threshold (e.g. >= 5 actions)? ───► NO ───► Do Nothing
           │ YES
           ▼
Present Paywall Sheet
           │
           ▼
Update `last_prompt_date = Date()`
Reset `free_action_count = 0`
```

---

## 4. SwiftUI Integration Example

```swift
struct ActionCompletionView: View {
    @EnvironmentObject private var paywallManager: PaywallTriggerManager
    @State private var isShowingPaywall = false

    var body: some View {
        Button("Save & Export") {
            performExport()
            
            // Increment usage and evaluate paywall trigger
            if paywallManager.recordActionAndEvaluateTrigger() {
                isShowingPaywall = true
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    private func performExport() {
        // Export logic...
    }
}
```
