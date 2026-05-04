import Foundation
import UIKit
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Runtime Prerequisites Source")
@MainActor
struct BackgroundRefreshRuntimePrerequisitesSourceTests {
    @Test
    func runtimePrerequisitesSourceBuildsAutomaticSnapshotFromSystemAndConfigurationState() {
        let source = DefaultBackgroundRefreshRuntimePrerequisitesSource(
            backgroundRefreshService: RuntimePrerequisitesBackgroundRefreshServiceSpy(
                configuration: BackgroundRefreshConfiguration(
                    settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
                    policy: BackgroundRefreshPolicy(preference: .hourly)
                )
            ),
            application: BackgroundRefreshStatusProviderStub(status: .available),
            processInfo: LowPowerModeStatusProviderStub(isLowPowerModeEnabled: false)
        )

        let snapshot = source.currentSnapshot()

        #expect(snapshot.backgroundRefreshStatus == .available)
        #expect(snapshot.isLowPowerModeEnabled == false)
        #expect(snapshot.refreshIntervalPreference == .hourly)
        #expect(snapshot.schedulingMode == .automatic)
    }

    @Test
    func runtimePrerequisitesSourceBuildsManualSnapshotWhenRefreshPreferenceIsManual() {
        let source = DefaultBackgroundRefreshRuntimePrerequisitesSource(
            backgroundRefreshService: RuntimePrerequisitesBackgroundRefreshServiceSpy(
                configuration: BackgroundRefreshConfiguration(
                    settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
                    policy: BackgroundRefreshPolicy(preference: .manual)
                )
            ),
            application: BackgroundRefreshStatusProviderStub(status: .denied),
            processInfo: LowPowerModeStatusProviderStub(isLowPowerModeEnabled: true)
        )

        let snapshot = source.currentSnapshot()

        #expect(snapshot.backgroundRefreshStatus == .denied)
        #expect(snapshot.isLowPowerModeEnabled)
        #expect(snapshot.refreshIntervalPreference == .manual)
        #expect(snapshot.schedulingMode == .manual)
    }

    @Test
    func runtimePrerequisitesSourceBuildsUnavailableSnapshotWhenConfigurationCannotBeResolved() {
        let source = DefaultBackgroundRefreshRuntimePrerequisitesSource(
            backgroundRefreshService: nil,
            application: BackgroundRefreshStatusProviderStub(status: .restricted),
            processInfo: LowPowerModeStatusProviderStub(isLowPowerModeEnabled: false)
        )

        let snapshot = source.currentSnapshot()

        #expect(snapshot.backgroundRefreshStatus == .restricted)
        #expect(snapshot.isLowPowerModeEnabled == false)
        #expect(snapshot.refreshIntervalPreference == nil)
        #expect(snapshot.schedulingMode == .unavailable)
    }
}

@MainActor
private final class RuntimePrerequisitesBackgroundRefreshServiceSpy: BackgroundRefreshService {
    private let configuration: BackgroundRefreshConfiguration

    init(configuration: BackgroundRefreshConfiguration) {
        self.configuration = configuration
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        configuration
    }

    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration {
        configuration
    }

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        .skippedManual(configuration)
    }
}

@MainActor
private struct BackgroundRefreshStatusProviderStub: BackgroundRefreshStatusProviding {
    let status: UIBackgroundRefreshStatus

    var backgroundRefreshStatus: UIBackgroundRefreshStatus {
        status
    }
}

private struct LowPowerModeStatusProviderStub: LowPowerModeStatusProviding {
    let isLowPowerModeEnabled: Bool
}
