import SwiftUI

/// Top-of-Settings banner shown when a newer app version is available.
/// Displays an intuitive update indicator with an "Upgrade" action button.
public struct AppUpdateBanner: View {
    @ObservedObject var updateManager: AppUpdateManager

    public var accentColor: Color

    public init(
        updateManager: AppUpdateManager = .shared,
        accentColor: Color = .blue
    ) {
        self.updateManager = updateManager
        self.accentColor = accentColor
    }

    public var body: some View {
        if updateManager.isUpdateAvailable, let info = updateManager.availableUpdateInfo {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    // Update Icon with pulsating badge dot
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(accentColor)

                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Available")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Version \(info.latestVersion) is now available on the App Store.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Upgrade Button in top right
                    Button(action: {
                        updateManager.openAppStore()
                    }) {
                        Text("Upgrade")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accentColor)
                            .clipShape(Capsule())
                    }
                }

                if let notes = info.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accentColor.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
        }
    }
}
