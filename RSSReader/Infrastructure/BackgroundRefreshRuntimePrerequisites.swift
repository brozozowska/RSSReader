import Foundation
import UIKit

enum BackgroundRefreshAvailabilityStatus: String, Equatable, Sendable {
    case available
    case denied
    case restricted

    init(_ status: UIBackgroundRefreshStatus) {
        switch status {
        case .available:
            self = .available
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }
}

enum BackgroundRefreshSchedulingMode: String, Equatable, Sendable {
    case automatic
    case manual
    case unavailable
}

struct BackgroundRefreshRuntimePrerequisitesSnapshot: Equatable, Sendable {
    let backgroundRefreshStatus: BackgroundRefreshAvailabilityStatus
    let isLowPowerModeEnabled: Bool
    let refreshIntervalPreference: RefreshPreference?
    let schedulingMode: BackgroundRefreshSchedulingMode
}

@MainActor
protocol BackgroundRefreshRuntimePrerequisitesSnapshotting {
    func currentSnapshot() -> BackgroundRefreshRuntimePrerequisitesSnapshot
}

@MainActor
protocol BackgroundRefreshStatusProviding {
    var backgroundRefreshStatus: UIBackgroundRefreshStatus { get }
}

extension UIApplication: BackgroundRefreshStatusProviding {}

protocol LowPowerModeStatusProviding {
    var isLowPowerModeEnabled: Bool { get }
}

extension ProcessInfo: LowPowerModeStatusProviding {}

@MainActor
final class DefaultBackgroundRefreshRuntimePrerequisitesSource:
    BackgroundRefreshRuntimePrerequisitesSnapshotting
{
    private let backgroundRefreshService: (any BackgroundRefreshService)?
    private let application: any BackgroundRefreshStatusProviding
    private let processInfo: any LowPowerModeStatusProviding

    init(backgroundRefreshService: (any BackgroundRefreshService)?) {
        self.backgroundRefreshService = backgroundRefreshService
        self.application = UIApplication.shared
        self.processInfo = ProcessInfo.processInfo
    }

    init(
        backgroundRefreshService: (any BackgroundRefreshService)?,
        application: any BackgroundRefreshStatusProviding,
        processInfo: any LowPowerModeStatusProviding
    ) {
        self.backgroundRefreshService = backgroundRefreshService
        self.application = application
        self.processInfo = processInfo
    }

    func currentSnapshot() -> BackgroundRefreshRuntimePrerequisitesSnapshot {
        let configuration = try? backgroundRefreshService.flatMap { service in
            try service.loadConfiguration()
        }

        return BackgroundRefreshRuntimePrerequisitesSnapshot(
            backgroundRefreshStatus: BackgroundRefreshAvailabilityStatus(application.backgroundRefreshStatus),
            isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            refreshIntervalPreference: configuration?.policy.preference,
            schedulingMode: Self.resolveSchedulingMode(from: configuration)
        )
    }

    private static func resolveSchedulingMode(
        from configuration: BackgroundRefreshConfiguration?
    ) -> BackgroundRefreshSchedulingMode {
        guard let configuration else { return .unavailable }
        return configuration.policy.isAutomaticRefreshEnabled ? .automatic : .manual
    }
}
