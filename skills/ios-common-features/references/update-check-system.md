# iOS Common Features: Update Check & Notification System

This reference guide explains the end-to-end mechanism for checking app updates, comparing semantic versions, showing native alerts, rendering the settings banner, and managing badge indicators.

---

## 1. How Update Checking Works

Apple provides the **iTunes Lookup API** which does not require an API key and returns public metadata for any published app:

```
https://itunes.apple.com/lookup?bundleId=com.yourcompany.yourapp
```

Alternatively, if your app is connected to a custom backend or Firebase Remote Config, you can fetch `minimum_supported_version` and `latest_version` JSON payloads.

---

## 2. Robust Semantic Version Comparison

Never compare versions using plain string comparison (e.g. `"1.10.0" > "1.2.0"` evaluates to `false` with string sorting).

Use integer component comparison:

```swift
public struct SemanticVersion: Comparable, Equatable {
    public let components: [Int]

    public init(_ versionString: String) {
        // Strip out any non-numeric prefixes like 'v'
        let clean = versionString.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        self.components = clean.split(separator: ".").compactMap { Int($0) }
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left < right { return true }
            if left > right { return false }
        }
        return false
    }
}
```

---

## 3. The 3 Update Touchpoints

### 1. Alert Prompt (Cold Start / Foreground)
- Displayed when `isUpdateAvailable` is `true`.
- Gives users an immediate path to the App Store with `"Update Now"`.
- Offers a `"Later"` or `"Cancel"` option without breaking their workflow.

### 2. Badge Indicator (Red Circle with Digit `1`)
- Displayed on the Settings icon / Tab item whenever `updateManager.isUpdateAvailable == true`.
- Example SwiftUI badge:
```swift
TabView {
    MainFeatureView()
        .tabItem { Label("Main", systemImage: "sparkles") }
    
    SettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .badge(updateManager.isUpdateAvailable ? 1 : 0)
}
```

### 3. Top of Settings Upgrade Banner
- Placed directly at the top of `SettingsView`.
- Follows the app's visual theme (accent gradient, rounded corner card, contrast text).
- Contains an **"Upgrade"** button that directly opens the App Store product page.

---

## 4. Manual "Check for Update" in Version Card

When user taps "Check for Updates":
1. State changes to `.checking` (displays `ProgressView`).
2. Asynchronous network request queries the Lookup API.
3. If new version found: updates `isUpdateAvailable = true` and shows update prompt.
4. If already on latest: displays temporary inline message or toast `"You're on the latest version (\(AppConstants.appVersion))"`.
