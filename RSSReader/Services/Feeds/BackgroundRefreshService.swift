import Foundation

struct BackgroundRefreshPolicy: Equatable, Sendable {
    let preference: RefreshPreference
    let minimumInterval: TimeInterval?

    var isAutomaticRefreshEnabled: Bool {
        minimumInterval != nil
    }

    init(preference: RefreshPreference) {
        self.preference = preference
        self.minimumInterval = preference.minimumBackgroundRefreshInterval
    }
}

struct BackgroundRefreshConfiguration: Equatable, Sendable {
    let settingsSnapshot: AppSettingsSnapshot
    let policy: BackgroundRefreshPolicy
}

@MainActor
protocol BackgroundRefreshService {
    func loadConfiguration() throws -> BackgroundRefreshConfiguration

    @discardableResult
    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration

    func performScheduledRefresh() async -> BackgroundFeedRefreshResult?
}

@MainActor
final class DefaultBackgroundRefreshService: BackgroundRefreshService {
    private let logger: Logging
    private let appSettingsService: any AppSettingsService
    private let feedRefreshService: (any FeedRefreshCoordinating)?

    init(
        logger: Logging,
        appSettingsService: any AppSettingsService,
        feedRefreshService: (any FeedRefreshCoordinating)?
    ) {
        self.logger = logger
        self.appSettingsService = appSettingsService
        self.feedRefreshService = feedRefreshService
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        let snapshot = try appSettingsService.fetchSettings()
        return BackgroundRefreshConfiguration(
            settingsSnapshot: snapshot,
            policy: BackgroundRefreshPolicy(preference: snapshot.refreshIntervalPreference)
        )
    }

    @discardableResult
    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date = .now
    ) throws -> BackgroundRefreshConfiguration {
        let updatedSnapshot = try appSettingsService.updateSettings(
            AppSettingsPatch(
                refreshIntervalPreference: preference,
                updatedAt: updatedAt
            )
        )

        return BackgroundRefreshConfiguration(
            settingsSnapshot: updatedSnapshot,
            policy: BackgroundRefreshPolicy(preference: updatedSnapshot.refreshIntervalPreference)
        )
    }

    func performScheduledRefresh() async -> BackgroundFeedRefreshResult? {
        let configuration: BackgroundRefreshConfiguration
        do {
            configuration = try loadConfiguration()
        } catch {
            logger.error("Failed to load background refresh configuration: \(error)")
            return nil
        }

        guard configuration.policy.isAutomaticRefreshEnabled else {
            logger.info("Skipped background refresh because refreshIntervalPreference is manual")
            return nil
        }

        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable for background refresh execution")
            return nil
        }

        return await feedRefreshService.refreshAllActiveFeedsForBackground()
    }
}

private extension RefreshPreference {
    var minimumBackgroundRefreshInterval: TimeInterval? {
        switch self {
        case .manual:
            nil
        case .every15Minutes:
            15 * 60
        case .hourly:
            60 * 60
        case .every6Hours:
            6 * 60 * 60
        case .daily:
            24 * 60 * 60
        }
    }
}
