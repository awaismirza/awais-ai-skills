import Foundation
import SwiftUI
import Combine

/// Model representing remote update information
public struct UpdateInfo: Sendable, Equatable {
    public let appName: String
    public let currentVersion: String
    public let latestVersion: String
    public let releaseNotes: String?
    public let appStoreURL: URL?

    public init(
        appName: String,
        currentVersion: String,
        latestVersion: String,
        releaseNotes: String? = nil,
        appStoreURL: URL? = nil
    ) {
        self.appName = appName
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseNotes = releaseNotes
        self.appStoreURL = appStoreURL
    }
}

/// Service managing remote update detection, semantic version comparisons,
/// alerts, notification badges, and settings update banners.
@MainActor
public final class AppUpdateManager: ObservableObject {
    public static let shared = AppUpdateManager()

    // MARK: - Published State
    @Published public var isChecking: Bool = false
    @Published public var isUpdateAvailable: Bool = false
    @Published public var showUpdateAlert: Bool = false
    @Published public var availableUpdateInfo: UpdateInfo?
    @Published public var lastCheckMessage: String?

    // MARK: - Constants & Keys
    private let lastCheckDateKey = "AppUpdateManager_lastCheckDate"
    private let appStoreId: String
    private let bundleIdentifier: String

    public init(
        appStoreId: String = "YOUR_APP_ID",
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.example.app"
    ) {
        self.appStoreId = appStoreId
        self.bundleIdentifier = bundleIdentifier
    }

    // MARK: - Public Actions

    /// Checks for updates immediately.
    /// - Parameter isManualCheck: If true, will present confirmation message or alert even if no update is found.
    public func checkForUpdates(isManualCheck: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        lastCheckMessage = nil

        defer {
            isChecking = false
            UserDefaults.standard.set(Date(), forKey: lastCheckDateKey)
        }

        do {
            let info = try await fetchLatestVersionFromAppStore()
            let current = SemanticVersion(info.currentVersion)
            let latest = SemanticVersion(info.latestVersion)

            if latest > current {
                self.isUpdateAvailable = true
                self.availableUpdateInfo = info
                self.showUpdateAlert = true
                self.lastCheckMessage = "Update available: v\(info.latestVersion)"
            } else {
                self.isUpdateAvailable = false
                self.availableUpdateInfo = nil
                if isManualCheck {
                    self.lastCheckMessage = "You're on the latest version (\(info.currentVersion))"
                }
            }
        } catch {
            if isManualCheck {
                self.lastCheckMessage = "Could not check for updates. Please try again."
            }
        }
    }

    /// Checks for updates when the app foregrounds if at least 24 hours have passed since the last check.
    public func checkOnForegroundIfNeeded() async {
        if let lastDate = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date {
            let hoursPassed = Date().timeIntervalSince(lastDate) / 3600
            guard hoursPassed >= 24 else { return }
        }
        await checkForUpdates(isManualCheck: false)
    }

    /// Opens the App Store product page to update.
    public func openAppStore() {
        let url = availableUpdateInfo?.appStoreURL
            ?? URL(string: "https://apps.apple.com/app/id\(appStoreId)")
        if let url {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Internal Network Lookup

    private func fetchLatestVersionFromAppStore() async throws -> UpdateInfo {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "App"

        // iTunes Lookup API endpoint
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleIdentifier)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let firstResult = results.first,
              let latestVersion = firstResult["version"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let releaseNotes = firstResult["releaseNotes"] as? String
        let trackViewUrlString = firstResult["trackViewUrl"] as? String
        let storeURL = trackViewUrlString.flatMap { URL(string: $0) }
            ?? URL(string: "https://apps.apple.com/app/id\(appStoreId)")

        return UpdateInfo(
            appName: appName,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseNotes: releaseNotes,
            appStoreURL: storeURL
        )
    }
}

// MARK: - Semantic Version Parsing
public struct SemanticVersion: Comparable, Equatable {
    public let components: [Int]

    public init(_ versionString: String) {
        let clean = versionString.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        self.components = clean.split(separator: ".").compactMap { Int($0) }
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left < right { return true }
            if left > right { return false }
        }
        return false
    }
}
