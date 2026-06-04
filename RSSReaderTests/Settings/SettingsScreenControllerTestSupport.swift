import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@MainActor
final class SettingsRecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private(set) var lastReplacedConfiguration: BackgroundRefreshConfiguration?
    private let replaceError: Error?

    init(replaceError: Error? = nil) {
        self.replaceError = replaceError
    }

    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshSchedulePlan? {
        lastReplacedConfiguration = configuration
        return DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now)
    }

    func cancel() {}

    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshScheduleResult {
        lastReplacedConfiguration = configuration

        if let replaceError {
            throw replaceError
        }

        if let plan = DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now) {
            return .scheduled(plan)
        }

        return .cancelled
    }
}

enum SettingsRuntimeAccountAvailabilityScenario: CaseIterable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var availability: ICloudAccountAvailability {
        switch self {
        case .available:
            .available
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedPresentation: SettingsSyncStatusPresentation {
        SettingsSyncStatusPresentation(accountAvailability: availability)
    }

    var expectedICloudSyncStatus: ICloudSyncStatus {
        expectedPresentation.iCloudSyncStatus
    }
}

enum SettingsBootstrapFallbackScenario: CaseIterable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var availability: ICloudAccountAvailability {
        switch self {
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedPresentation: SettingsSyncStatusPresentation {
        SettingsSyncStatusPresentation(accountAvailability: availability)
    }
}
