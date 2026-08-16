import SwiftUI

/// Complete production-grade Settings View combining:
/// 1. Top Update Banner with Upgrade action
/// 2. Support & Links Card (Website, Privacy, Terms, Support, Rate, Share)
/// 3. Version Card (Version metadata, Check for Updates action, Copyright footer)
public struct SettingsView: View {
    @EnvironmentObject private var updateManager: AppUpdateManager
    @EnvironmentObject private var paywallManager: PaywallTriggerManager
    @EnvironmentObject private var reviewManager: ReviewPromptManager

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Top Upgrade Banner (Visible when update available)
                    AppUpdateBanner(updateManager: updateManager)

                    // 2. Settings Grouped List Content
                    VStack(spacing: 20) {
                        // Support & Links Section
                        SettingsSupportCard()

                        // Version & Updates Section
                        SettingsVersionCard(updateManager: updateManager)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Trailing notification indicator if update is available
                ToolbarItem(placement: .topBarTrailing) {
                    if updateManager.isUpdateAvailable {
                        Button(action: { updateManager.openAppStore() }) {
                            ZStack {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)

                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppUpdateManager.shared)
        .environmentObject(PaywallTriggerManager.shared)
        .environmentObject(ReviewPromptManager.shared)
}
