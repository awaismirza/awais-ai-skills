import Foundation
import StoreKit
import SwiftUI
import Combine

/// Manages App Store rating requests, enforcing positive milestone triggers
/// and a mandatory 90-day (3-month) minimum cooldown between prompts.
@MainActor
public final class ReviewPromptManager: ObservableObject {
    public static let shared = ReviewPromptManager()

    // MARK: - Configuration Constants
    public let minimumPositiveEvents: Int
    public let minimumCooldownDays: Int // 90 days = 3 months

    // MARK: - UserDefaults Keys
    private let keyPositiveEventsCount = "ReviewPrompt_positiveEventsCount"
    private let keyLastPromptDate = "ReviewPrompt_lastPromptDate"
    private let keyHasRated = "ReviewPrompt_hasRated"

    public init(
        minimumPositiveEvents: Int = 3,
        minimumCooldownDays: Int = 90
    ) {
        self.minimumPositiveEvents = minimumPositiveEvents
        self.minimumCooldownDays = minimumCooldownDays
    }

    // MARK: - Event Recording & Evaluation

    /// Records that the user reached a positive moment of delight.
    /// Returns `true` if the app should trigger the native StoreKit review prompt.
    @discardableResult
    public func recordPositiveEventAndEvaluatePrompt() -> Bool {
        let count = UserDefaults.standard.integer(forKey: keyPositiveEventsCount) + 1
        UserDefaults.standard.set(count, forKey: keyPositiveEventsCount)

        guard isEligibleForPrompt(currentEventCount: count) else {
            return false
        }

        markReviewPrompted()
        return true
    }

    /// Explicitly marks that the user was prompted for a review.
    public func markReviewPrompted() {
        UserDefaults.standard.set(Date(), forKey: keyLastPromptDate)
    }

    /// Marks that the user completed an explicit rating or tapped "Rate The App" in Settings.
    public func markUserRated() {
        UserDefaults.standard.set(true, forKey: keyHasRated)
        UserDefaults.standard.set(Date(), forKey: keyLastPromptDate)
    }

    // MARK: - Private Eligibility Check

    private func isEligibleForPrompt(currentEventCount: Int) -> Bool {
        // Must have completed enough positive events
        guard currentEventCount >= minimumPositiveEvents else {
            return false
        }

        // Must respect 90-day cooldown
        if let lastDate = UserDefaults.standard.object(forKey: keyLastPromptDate) as? Date {
            let daysPassed = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            if daysPassed < minimumCooldownDays {
                return false
            }
        }

        return true
    }
}
