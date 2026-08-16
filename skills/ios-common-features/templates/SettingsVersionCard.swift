import SwiftUI

/// Reusable Version card displaying the current build metadata,
/// interactive "Check for Updates" action with feedback, and copyright footer.
public struct SettingsVersionCard: View {
    @ObservedObject var updateManager: AppUpdateManager

    public var copyrightNotice: String

    public init(
        updateManager: AppUpdateManager = .shared,
        copyrightNotice: String? = nil
    ) {
        self.updateManager = updateManager
        if let copyrightNotice {
            self.copyrightNotice = copyrightNotice
        } else {
            let year = Calendar.current.component(.year, from: Date())
            let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
                ?? "App"
            self.copyrightNotice = "© \(year) \(name). All rights reserved."
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    public var body: some View {
        Section {
            // Version Row
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Version")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text(versionDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Check for Updates Row
            Button(action: {
                Task {
                    await updateManager.checkForUpdates(isManualCheck: true)
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Check for Updates")
                        .font(.body)
                        .foregroundColor(.primary)

                    Spacer()

                    if updateManager.isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if updateManager.isUpdateAvailable {
                        Text("Update Available")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            .disabled(updateManager.isChecking)

            // Inline Feedback Message
            if let message = updateManager.lastCheckMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(updateManager.isUpdateAvailable ? .orange : .secondary)
                    .transition(.opacity)
            }
        } header: {
            Text("Version")
        } footer: {
            Text(copyrightNotice)
        }
    }
}
