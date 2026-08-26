import SwiftUI

/// Full-width, dismissible banner shown near the top of a screen whose primary
/// action needs a permission that is currently denied or not-determined.
///
/// Not a corner badge — a full-width bar, matching the real-world pattern:
/// "🔕 Notifications are off, so alarms can't arrive. ›"
///
/// Suppress re-showing this for a permission the user has already explicitly
/// declined once this session — one nudge, not a nag.
public struct PermissionNudgeBanner: View {
    let systemImage: String       // e.g. "bell.slash.fill", "location.slash.fill"
    let message: String           // plain language, states *why* it's needed
    let action: () -> Void        // opens Settings deep link, or the native prompt if .notDetermined

    public init(systemImage: String, message: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.message = message
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens permission settings")
    }
}

/// Opens the system Settings deep link for this app — use once a permission has
/// already been denied (a repeat request through the OS API is a silent no-op).
public enum SystemSettingsLink {
    public static func open() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif

#Preview {
    PermissionNudgeBanner(
        systemImage: "bell.slash.fill",
        message: "Notifications are off, so alarms can't arrive.",
        action: { SystemSettingsLink.open() }
    )
    .padding()
}
