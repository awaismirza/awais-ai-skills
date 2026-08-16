import Foundation
import SwiftUI
import Combine

/// Manages smart usage tracking, free action counts, and strictly enforces
/// a fortnightly (14-day) rate-limiting cadence for paywall impressions.
@MainActor
public final class PaywallTriggerManager: ObservableObject {
    public static let shared = PaywallTriggerManager()

    // MARK: - Published State
    @Published public var shouldShowPaywallModal: Bool = false
    @Published public var isUserSubscribed: Bool = false

    // MARK: - Configuration Constants
    public let requiredFreeActionsThreshold: Int
    public let minimumDaysBetweenPrompts: Int // 14 days = fortnightly

    // MARK: - UserDefaults Keys
    private let keyFreeActionCount = "PaywallTrigger_freeActionCount"
    private let keySessionCount = "PaywallTrigger_sessionCount"
    private let keyLastPromptDate = "PaywallTrigger_lastPromptDate"
    private let keyIsSubscribed = "PaywallTrigger_isSubscribed"

    public init(
        requiredFreeActionsThreshold: Int = 5,
        minimumDaysBetweenPrompts: Int = 14
    ) {
        self.requiredFreeActionsThreshold = requiredFreeActionsThreshold
        self.minimumDaysBetweenPrompts = minimumDaysBetweenPrompts
        self.isUserSubscribed = UserDefaults.standard.bool(forKey: keyIsSubscribed)
    }

    // MARK: - Usage Tracking & Evaluation

    /// Records that the user performed a core free action.
    /// Returns `true` if the app should now present the paywall.
    @discardableResult
    public func recordActionAndEvaluateTrigger() -> Bool {
        guard !isUserSubscribed else { return false }

        let currentCount = UserDefaults.standard.integer(forKey: keyFreeActionCount) + 1
        UserDefaults.standard.set(currentCount, forKey: keyFreeActionCount)

        // Check if cooldown has elapsed
        guard isCooldownElapsed() else { return false }

        // Check if usage threshold is met
        if currentCount >= requiredFreeActionsThreshold {
            markPaywallPresented()
            self.shouldShowPaywallModal = true
            return true
        }

        return false
    }

    /// Records an app session/launch.
    public func recordSession() {
        let count = UserDefaults.standard.integer(forKey: keySessionCount) + 1
        UserDefaults.standard.set(count, forKey: keySessionCount)
    }

    /// Updates subscription status when purchased or restored.
    public func updateSubscriptionStatus(isSubscribed: Bool) {
        self.isUserSubscribed = isSubscribed
        UserDefaults.standard.set(isSubscribed, forKey: keyIsSubscribed)
        if isSubscribed {
            self.shouldShowPaywallModal = false
        }
    }

    /// Manually marks that a paywall was shown (resets cooldown timer and action counter).
    public func markPaywallPresented() {
        UserDefaults.standard.set(Date(), forKey: keyLastPromptDate)
        UserDefaults.standard.set(0, forKey: keyFreeActionCount)
    }

    // MARK: - Helper Logic

    private func isCooldownElapsed() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: keyLastPromptDate) as? Date else {
            return true // Never shown before
        }
        let daysPassed = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return daysPassed >= minimumDaysBetweenPrompts
    }
}
