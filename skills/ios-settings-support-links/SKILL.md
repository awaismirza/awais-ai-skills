---
name: ios-settings-support-links
description: Use when building, standardizing, or refactoring the Support & Links, Legal, App Rating, Sharing, and Version cards in iOS Settings screens.
---

# iOS Settings: Support, Links, & Version Pattern

Standardized SwiftUI pattern for structuring the **Support & Links** and **Version / App Info** cards across iOS applications.

---

## 1. Structure & Visual Hierarchy

Settings screens should separate navigational/legal links from build/version metadata into two distinct grouped cards.

### Card 1: Support & Links
Contains clean, uncluttered rows with standard SF Symbols:

1. **Website**: Title `"Website"`, icon `globe`, opens product webpage (no cluttered URL subtitle).
2. **Privacy Policy**: Title `"Privacy Policy"`, icon `hand.raised.fill` (or `shield.lefthalf.filled`), opens privacy URL.
3. **Terms of Use**: Title `"Terms of Use"`, icon `doc.text.fill`, opens terms URL.
4. **Support**: Title `"Support"` (not `"Contact Support"`), icon `envelope.fill`, opens `mailto:` email or support page.
5. **Rate The App**: Title `"Rate The App"`, icon `star.fill` (tinted with accent color), opens App Store review URL.
6. **Share the app**: Title `"Share the app"`, icon `square.and.arrow.up.fill`, presents system share sheet (`UIActivityViewController`).

### Card 2: Version & Updates
1. **Version**: Title `"Version"`, icon `info.circle.fill`, trailing accessory with version & build number (e.g. `1.0.0 (3)`).
2. **Check for Updates**: Title `"Check for Updates"`, icon `arrow.triangle.2.circlepath`, live progress indicator and update button.
3. **Footer**: Displays copyright: `© [Year] [App Name]. All rights reserved.`

---

## 2. SwiftUI Implementation Template

### `AboutLinks` Enum Pattern

```swift
import Foundation

nonisolated enum AboutLinks {
    // Replace with app-specific product URLs
    static let profile = URL(string: "https://awaisjamil.com/products/your-app-slug")!
    static let support = URL(string: "https://awaisjamil.com/products/your-app-slug/support")!
    static let supportEmail = URL(string: "mailto:support@awaisjamil.com")!
    static let privacyPolicy = URL(string: "https://awaisjamil.com/products/your-app-slug/privacy")!
    static let termsOfUse = URL(string: "https://awaisjamil.com/products/your-app-slug/terms")!
    
    // App Store review URL (add app ID upon App Store Connect setup)
    static let rateApp = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID?action=write-review") ?? profile
    
    static let copyright = "© 2026 Your App Name. All rights reserved."

    /// Dynamically reads CFBundleShortVersionString and CFBundleVersion
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
```

---

### `AboutSettingsSection` View Pattern

```swift
import SwiftUI
import UIKit

struct AboutSettingsSection: View {
    @Environment(\.openURL) private var openURL
    // Optional update service dependency
    var updateService: AppUpdateService?

    var body: some View {
        // Card 1: Support & Links
        SettingsGroup(title: "Support & Links") {
            SettingsRow(
                title: "Website",
                systemImage: "globe",
                accessory: .chevron,
                hint: "Opens product website",
                action: { openURL(AboutLinks.profile) }
            )
            SettingsDivider()
            SettingsRow(
                title: "Privacy Policy",
                systemImage: "hand.raised.fill",
                accessory: .chevron,
                hint: "Opens privacy policy",
                action: { openURL(AboutLinks.privacyPolicy) }
            )
            SettingsDivider()
            SettingsRow(
                title: "Terms of Use",
                systemImage: "doc.text.fill",
                accessory: .chevron,
                hint: "Opens terms of use",
                action: { openURL(AboutLinks.termsOfUse) }
            )
            SettingsDivider()
            SettingsRow(
                title: "Support",
                systemImage: "envelope.fill",
                accessory: .chevron,
                hint: "Opens Mail to support",
                action: { openURL(AboutLinks.supportEmail) }
            )
            SettingsDivider()
            SettingsRow(
                title: "Rate The App",
                systemImage: "star.fill",
                iconColor: .accentColor,
                accessory: .chevron,
                hint: "Opens App Store to rate this app",
                action: { openURL(AboutLinks.rateApp) }
            )
            SettingsDivider()
            SettingsRow(
                title: "Share the app",
                systemImage: "square.and.arrow.up.fill",
                accessory: .chevron,
                hint: "Share app with friends",
                action: { shareApp() }
            )
        } footer: {
            SettingsFootnote(text: "Need help or have feedback? Reach out to our support team.")
        }

        // Card 2: Version
        SettingsGroup(title: "Version") {
            SettingsRow(
                title: "Version",
                systemImage: "info.circle.fill",
                accessory: .value(AboutLinks.versionDescription)
            )
            SettingsDivider()
            updateCheckRow
        } footer: {
            SettingsFootnote(text: AboutLinks.copyright)
        }
    }

    /// iPad-safe system share sheet presentation
    private func shareApp() {
        let text = "Check out Your App Name on iOS"
        let url = AboutLinks.profile
        let activityVC = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        // iPad Popover anchor safety to prevent crash
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(activityVC, animated: true)
    }

    @ViewBuilder
    private var updateCheckRow: some View {
        SettingsRow(
            title: "Check for Updates",
            systemImage: "arrow.triangle.2.circlepath",
            accessory: .chevron,
            hint: "Checks for the latest app update",
            action: {
                Task { await updateService?.checkForUpdates() }
            }
        )
    }
}
```

---

## 3. Best Practices & Rules

1. **Clean Labeling**: Never display full raw URLs in row subtitles (e.g. avoid displaying `https://domain.com/path...`). Use clean labels like `"Website"` or `"Support"`.
2. **iPad Popover Anchor**: Always configure `popoverPresentationController.sourceView` when presenting `UIActivityViewController` on iOS, or iPad builds will crash on tap.
3. **App Store Review Link**: Use `?action=write-review` appended to the App Store URL to take the user directly to the rating modal.
4. **Accessibility**: Combine the row elements with `.accessibilityElement(children: .combine)` and add descriptive accessibility hints for VoiceOver.
