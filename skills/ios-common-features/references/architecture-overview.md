# iOS Common Features: Architecture & Dependency Management

This document details the architectural standards, state management, and dependency injection patterns for integrating standard production features into iOS apps.

---

## 1. Architectural Pattern (MVVM + Services)

All common features are managed by lightweight, isolated singleton services (or environment objects) to avoid tight coupling with view hierarchies.

```
┌────────────────────────────────────────────────────────┐
│                      SwiftUI App                       │
│  @StateObject / @Observable var updateManager          │
│  @StateObject / @Observable var paywallManager         │
│  @StateObject / @Observable var reviewManager          │
└───────────────────────────┬────────────────────────────┘
                            │ Environment / Injection
                            ▼
┌────────────────────────────────────────────────────────┐
│                      Views                             │
│  • ContentView (Listens to update alert & badges)      │
│  • SettingsView (Renders banners, cards, badges)       │
│  • FeatureViews (Triggers paywall & review milestones) │
└────────────────────────────────────────────────────────┘
```

---

## 2. Shared Configuration: `AppConstants.swift`

Centralize all URLs, App Store IDs, and bundle identifiers in one nonisolated structure:

```swift
import Foundation

public enum AppConstants {
    // MARK: - App Store & Identifiers
    public static let appStoreId = "YOUR_APP_ID" // e.g. "6471234567"
    public static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.awaisjamil.app"

    // MARK: - Web & Legal Links
    public static let websiteURL = URL(string: "https://awaisjamil.com/products/your-app-slug")!
    public static let privacyPolicyURL = URL(string: "https://awaisjamil.com/privacy")!
    public static let termsOfUseURL = URL(string: "https://awaisjamil.com/terms")!
    public static let supportEmail = URL(string: "mailto:support@awaisjamil.com?subject=App%20Support")!
    public static let supportWebURL = URL(string: "https://awaisjamil.com/support")!

    // MARK: - Store Links
    public static var appStoreWriteReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreId)?action=write-review") ?? websiteURL
    }

    public static var appStoreProductURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreId)") ?? websiteURL
    }

    // MARK: - Version Metadata
    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    public static var formattedVersion: String {
        "v\(appVersion) (\(buildNumber))"
    }

    public static var copyrightNotice: String {
        let currentYear = Calendar.current.component(.year, from: Date())
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "App"
        return "© \(currentYear) \(appName). All rights reserved."
    }
}
```

---

## 3. Dependency Injection & Environment Setup

In your main `@main struct YourApp: App`:

```swift
import SwiftUI

@main
struct YourApp: App {
    @StateObject private var updateManager = AppUpdateManager.shared
    @StateObject private var paywallManager = PaywallTriggerManager.shared
    @StateObject private var reviewManager = ReviewPromptManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updateManager)
                .environmentObject(paywallManager)
                .environmentObject(reviewManager)
                .task {
                    // Check for updates on initial cold launch
                    await updateManager.checkForUpdates(isManualCheck: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Re-check on foregrounding if last check was > 24 hours ago
                    Task {
                        await updateManager.checkOnForegroundIfNeeded()
                    }
                }
                .alert(
                    "Update Available",
                    isPresented: $updateManager.showUpdateAlert,
                    presenting: updateManager.availableUpdateInfo
                ) { info in
                    Button("Update Now") {
                        if let url = info.appStoreURL {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Later", role: .cancel) { }
                } message: { info in
                    Text("A new version (\(info.latestVersion)) of \(info.appName) is available. Please update to enjoy the latest features and bug fixes.")
                }
        }
    }
}
```
