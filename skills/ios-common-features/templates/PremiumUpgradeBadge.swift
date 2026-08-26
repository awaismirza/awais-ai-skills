import SwiftUI

/// Persistent, always-visible "Upgrade" entry point for the primary screen header.
///
/// Rendered only while the live entitlement check says non-premium — hidden the
/// instant a purchase/subscription is verified. Tapping it sets the shared
/// `isPaywallPresented` flag on the entitlement manager so it opens the exact
/// same `PaywallSheet` any other upgrade entry point in the app would.
public struct PremiumUpgradeBadge: View {
    @ObservedObject var entitlement: EntitlementManager

    public init(entitlement: EntitlementManager) {
        self.entitlement = entitlement
    }

    public var body: some View {
        if !entitlement.isPremium {
            Button {
                entitlement.isPaywallPresented = true
            } label: {
                Text("Upgrade")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule().strokeBorder(Color.accentColor, lineWidth: 1)
                    )
            }
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Upgrade to Premium")
            .accessibilityHint("Opens the upgrade options")
        }
    }
}

/// Minimal shape a screen's toolbar needs — replace with your real entitlement
/// manager (see PaywallSheet.swift + references/premium-entry-point.md for the
/// subscription-vs-one-time-purchase StoreKit 2 implementation this drives).
@MainActor
public protocol EntitlementManagerProtocol: ObservableObject {
    var isPremium: Bool { get }
    var isPaywallPresented: Bool { get set }
}

// Placeholder concrete type so this file compiles standalone when copied in.
// Replace with your app's real StoreKit-2-backed manager.
@MainActor
public final class EntitlementManager: ObservableObject, EntitlementManagerProtocol {
    @Published public var isPremium: Bool = false
    @Published public var isPaywallPresented: Bool = false
    public init() {}
}

#Preview {
    HStack {
        Spacer()
        PremiumUpgradeBadge(entitlement: EntitlementManager())
            .padding()
    }
}
