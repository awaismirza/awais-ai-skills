import SwiftUI
import UIKit

/// Reusable card component grouping Website, Privacy Policy, Terms of Use,
/// Support, Rate The App, and Share The App links.
public struct SettingsSupportCard: View {
    @Environment(\.openURL) private var openURL

    // App-specific URLs (override or inject as needed)
    public var websiteURL: URL
    public var privacyPolicyURL: URL
    public var termsOfUseURL: URL
    public var supportEmailOrURL: URL
    public var rateAppURL: URL
    public var shareMessage: String

    public init(
        websiteURL: URL = URL(string: "https://awaisjamil.com/products/your-app")!,
        privacyPolicyURL: URL = URL(string: "https://awaisjamil.com/privacy")!,
        termsOfUseURL: URL = URL(string: "https://awaisjamil.com/terms")!,
        supportEmailOrURL: URL = URL(string: "mailto:support@awaisjamil.com")!,
        rateAppURL: URL = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID?action=write-review")!,
        shareMessage: String = "Check out this app on the App Store!"
    ) {
        self.websiteURL = websiteURL
        self.privacyPolicyURL = privacyPolicyURL
        self.termsOfUseURL = termsOfUseURL
        self.supportEmailOrURL = supportEmailOrURL
        self.rateAppURL = rateAppURL
        self.shareMessage = shareMessage
    }

    public var body: some View {
        Section {
            // 1. Website
            Button(action: { openURL(websiteURL) }) {
                SettingsRowContent(
                    title: "Website",
                    systemImage: "globe",
                    iconColor: .blue,
                    accessibilityHint: "Opens product website"
                )
            }

            // 2. Privacy Policy
            Button(action: { openURL(privacyPolicyURL) }) {
                SettingsRowContent(
                    title: "Privacy Policy",
                    systemImage: "hand.raised.fill",
                    iconColor: .green,
                    accessibilityHint: "Opens privacy policy in browser"
                )
            }

            // 3. Terms of Use
            Button(action: { openURL(termsOfUseURL) }) {
                SettingsRowContent(
                    title: "Terms of Use",
                    systemImage: "doc.text.fill",
                    iconColor: .indigo,
                    accessibilityHint: "Opens terms and conditions"
                )
            }

            // 4. Support
            Button(action: { openURL(supportEmailOrURL) }) {
                SettingsRowContent(
                    title: "Support",
                    systemImage: "envelope.fill",
                    iconColor: .orange,
                    accessibilityHint: "Opens support contact email or page"
                )
            }

            // 5. Rate The App
            Button(action: { openURL(rateAppURL) }) {
                SettingsRowContent(
                    title: "Rate The App",
                    systemImage: "star.fill",
                    iconColor: .yellow,
                    accessibilityHint: "Opens App Store to write a review"
                )
            }

            // 6. Share The App
            Button(action: { shareApp() }) {
                SettingsRowContent(
                    title: "Share the app",
                    systemImage: "square.and.arrow.up.fill",
                    iconColor: .purple,
                    accessibilityHint: "Shares app link with friends"
                )
            }
        } header: {
            Text("Support & Links")
        } footer: {
            Text("Questions, feedback, or need help? We'd love to hear from you.")
        }
    }

    // MARK: - iPad-Safe Share Presentation
    private func shareApp() {
        let items: [Any] = [shareMessage, websiteURL]
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        // iPad popover anchor to prevent crash
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
}

/// Generic row item layout with icon and chevron
public struct SettingsRowContent: View {
    public let title: String
    public let systemImage: String
    public let iconColor: Color
    public let accessibilityHint: String

    public init(title: String, systemImage: String, iconColor: Color = .accentColor, accessibilityHint: String = "") {
        self.title = title
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.accessibilityHint = accessibilityHint
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessibilityHint)
    }
}
