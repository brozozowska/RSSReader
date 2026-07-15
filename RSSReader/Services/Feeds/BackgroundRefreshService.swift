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

enum BackgroundRefreshServiceExecutionFailure: Sendable, Equatable {
    case configurationLoadFailed
    case feedRefreshServiceUnavailable
}

enum BackgroundRefreshServiceExecutionResult: Sendable {
    case skippedManual(BackgroundRefreshConfiguration)
    case executed(BackgroundFeedRefreshResult)
    case failedToStart(BackgroundRefreshServiceExecutionFailure)
}

@MainActor
protocol BackgroundRefreshService {
    func loadConfiguration() throws -> BackgroundRefreshConfiguration

    @discardableResult
    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult
}

@MainActor
final class DefaultBackgroundRefreshService: BackgroundRefreshService {
    private let logger: Logging
    private let appSettingsService: any AppSettingsService
    private let feedRefreshService: (any FeedRefreshCoordinating)?
    private let articleRetentionCleanupService: (any ArticleRetentionCleanupServicing)?

    init(
        logger: Logging,
        appSettingsService: any AppSettingsService,
        feedRefreshService: (any FeedRefreshCoordinating)?,
        articleRetentionCleanupService: (any ArticleRetentionCleanupServicing)? = nil
    ) {
        self.logger = logger
        self.appSettingsService = appSettingsService
        self.feedRefreshService = feedRefreshService
        self.articleRetentionCleanupService = articleRetentionCleanupService
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

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        let configuration: BackgroundRefreshConfiguration
        do {
            configuration = try loadConfiguration()
        } catch {
            logger.debug("Background refresh service trace outcome=configurationLoadFailed error=\(error)")
            return .failedToStart(.configurationLoadFailed)
        }

        guard configuration.policy.isAutomaticRefreshEnabled else {
            logger.debug("Background refresh service trace outcome=skippedManual")
            return .skippedManual(configuration)
        }

        guard let feedRefreshService else {
            logger.debug("Background refresh service trace outcome=feedRefreshServiceUnavailable")
            return .failedToStart(.feedRefreshServiceUnavailable)
        }

        let refreshResult = await feedRefreshService.refreshAllActiveFeedsForBackground()
        cleanupArticles(policy: configuration.settingsSnapshot.articleRetentionPolicy)
        return .executed(refreshResult)
    }

    private func cleanupArticles(policy: ArticleRetentionPolicy) {
        guard let articleRetentionCleanupService else {
            return
        }

        do {
            try articleRetentionCleanupService.cleanupArticles(policy: policy, now: .now)
        } catch {
            logger.error("Failed to apply article retention after background refresh: \(error)")
        }
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
