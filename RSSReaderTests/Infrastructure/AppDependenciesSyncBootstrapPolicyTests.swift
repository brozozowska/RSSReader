import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Sync Bootstrap Policy")
@MainActor
struct AppDependenciesSyncBootstrapPolicyTests {
    @Test
    func appDependenciesResolveSyncBackedCloudKitPolicyFromPersistedSyncPreference() {
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: false)
            ) == .disabled
        )
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: true)
            ) == .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
        )
    }

    @Test
    func appDependenciesResolveSyncBackedCloudKitPolicyPrefersLocalBootstrapPreferenceWhenAvailable() {
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: false),
                localBootstrapPreference: .enabled
            ) == .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
        )
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: true),
                localBootstrapPreference: .disabled
            ) == .disabled
        )
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextKeepsDesiredSyncIntentWhenCloudKitBootstrapFallsBackToLocalOnly() {
        let context = AppDependencies.resolveSyncBootstrapContext(
            desiredBootPreference: .enabled,
            desiredPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
            logger: TestLogger(),
            resolvedAccountStatus: .temporarilyUnavailable
        )

        #expect(context.desiredBootPreference == .enabled)
        #expect(context.desiredSyncBackedCloudKitPolicy == .privateContainer(CloudKitContainerConfiguration.containerIdentifier))
        #expect(context.modelContainerCloudKitPolicy == .disabled)
        #expect(context.accountAvailabilityAtBootstrap == .temporarilyUnavailable)
        #expect(context.isSyncRequested)
        #expect(context.isUsingCloudKitForCurrentLaunch == false)
        #expect(context.isRunningLocalOnlyFallbackForCurrentLaunch)
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextGatesCloudKitBootstrapForEachAccountStatus() {
        for scenario in AppDependenciesSyncBootstrapAccountStatusScenario.allCases {
            let context = AppDependencies.resolveSyncBootstrapContext(
                desiredBootPreference: .enabled,
                desiredPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
                logger: TestLogger(),
                resolvedAccountStatus: scenario.accountStatus
            )

            #expect(context.desiredBootPreference == .enabled)
            #expect(context.desiredSyncBackedCloudKitPolicy == .privateContainer(CloudKitContainerConfiguration.containerIdentifier))
            #expect(context.modelContainerCloudKitPolicy == scenario.expectedModelContainerPolicy)
            #expect(context.accountAvailabilityAtBootstrap == scenario.expectedAccountAvailability)
            #expect(context.isSyncRequested)
            #expect(context.isUsingCloudKitForCurrentLaunch == scenario.expectsCloudKitBootstrap)
            #expect(context.isRunningLocalOnlyFallbackForCurrentLaunch == scenario.expectsLocalOnlyFallback)
        }
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextLogsAccountResolutionAndFallbackSelection() {
        let logger = RecordingLogger()

        _ = AppDependencies.resolveSyncBootstrapContext(
            desiredBootPreference: .enabled,
            desiredPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
            logger: logger,
            resolvedAccountStatus: .noAccount
        )

        #expect(logger.contains("Resolved sync bootstrap account status"))
        #expect(logger.contains("availability=noAccount"))
        #expect(logger.contains("Skipped CloudKit-backed model container bootstrap because account status is"))
        #expect(logger.contains("noAccount"))
        #expect(logger.contains("using local-only fallback for current launch"))
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextLogsLocalOnlyBootstrapPolicyWithoutCloudKit() {
        let logger = RecordingLogger()

        _ = AppDependencies.resolveSyncBootstrapContext(
            desiredBootPreference: .disabled,
            desiredPolicy: .disabled,
            logger: logger
        )

        #expect(logger.contains("Using local-only sync bootstrap path because desired policy does not require CloudKit"))
        #expect(logger.contains("desiredBootPreference=disabled"))
    }

    @Test
    func appDependenciesFetchSyncEnablementBootstrapSettingsFromModelContainer() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                useiCloudSync: true,
                updatedAt: .distantPast
            )
        )

        let bootstrapSettings = try AppDependencies.fetchSyncEnablementBootstrapSettings(
            from: harness.modelContainer
        )

        #expect(bootstrapSettings?.useiCloudSync == true)
    }

    @Test
    func appDependenciesBootstrapFailureDescriptionIncludesNSErrorContext() {
        let underlyingError = NSError(
            domain: "NSCocoaErrorDomain",
            code: 134060,
            userInfo: [
                NSLocalizedDescriptionKey: "Persistent store failed to load."
            ]
        )
        let topLevelError = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [
                NSUnderlyingErrorKey: underlyingError
            ]
        )

        let description = AppDependencies.makeModelContainerBootstrapFailureDescription(
            for: topLevelError,
            syncBackedCloudKitPolicy: .privateContainer("iCloud.ru.brozozowska.RSSReader")
        )

        #expect(description.contains("privateContainer(\"iCloud.ru.brozozowska.RSSReader\")"))
        #expect(description.contains("Error: domain=SwiftData.SwiftDataError code=1"))
        #expect(description.contains("Underlying error 1: domain=NSCocoaErrorDomain code=134060"))
        #expect(description.contains("Persistent store failed to load."))
    }

    @Test
    func appDependenciesBootstrapFailureDescriptionAppendsPersistentStoreProbeDetails() {
        let error = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [:]
        )

        let description = AppDependencies.makeModelContainerBootstrapFailureDescription(
            for: error,
            syncBackedCloudKitPolicy: .privateContainer("iCloud.ru.brozozowska.RSSReader"),
            persistentStoreProbeFailureDescription: "Error: domain=NSCocoaErrorDomain code=134060 localizedDescription=Persistent store probe failed. userInfo={}"
        )

        #expect(description.contains("Persistent store probe:"))
        #expect(description.contains("domain=NSCocoaErrorDomain code=134060"))
        #expect(description.contains("Persistent store probe failed."))
    }
}
