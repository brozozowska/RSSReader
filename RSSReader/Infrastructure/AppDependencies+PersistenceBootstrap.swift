import CloudKit
import Foundation
import SwiftData

extension AppDependencies {
    static func makeSwiftDataConfigurationPlan(
        modelPartition: AppPersistenceModelPartition,
        isStoredInMemoryOnly: Bool,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy = CloudKitContainerConfiguration.syncBackedDatabasePolicy
    ) -> AppPersistenceConfigurationPlan {
        AppPersistenceConfigurationPlan.make(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
    }

    @MainActor
    static func makeWithSwiftData(
        modelPartition: AppPersistenceModelPartition,
        syncEnablementPolicy: AppSyncEnablementPolicy
    ) -> AppDependencies {
        let syncCoordinator = SyncCoordinator()
        return makeWithSwiftData(
            modelPartition: modelPartition,
            syncEnablementPolicy: syncEnablementPolicy,
            syncCoordinator: syncCoordinator
        )
    }

    @MainActor
    static func makeWithSwiftData(
        modelPartition: AppPersistenceModelPartition,
        syncEnablementPolicy: AppSyncEnablementPolicy,
        syncCoordinator: SyncCoordinator,
        syncBootstrapPreferenceStore: (any AppSyncBootstrapPreferenceStoring)? = nil,
        globalOrphanSweepScheduleStore: (any GlobalOrphanSweepScheduleStoring)? = nil,
        logger: Logging? = nil
    ) -> AppDependencies {
        let logger = logger ?? makeDefaultLogger()

        let resolvedSyncBootstrapPreferenceStore = syncBootstrapPreferenceStore
            ?? AppSyncBootstrapPreferenceStore(logger: logger)
        let bootstrapSettingsSnapshot = makeSyncEnablementBootstrapSettingsSnapshot(
            modelPartition: modelPartition,
            logger: logger
        )
        logger.info(
            "Resolved sync bootstrap settings snapshot: useiCloudSync=\(String(describing: bootstrapSettingsSnapshot?.useiCloudSync))"
        )
        let desiredBootPreference = syncEnablementPolicy.bootPreference(
            from: bootstrapSettingsSnapshot,
            localBootstrapPreference: resolvedSyncBootstrapPreferenceStore.currentBootPreference()
        )
        let desiredSyncBackedCloudKitPolicy = resolveSyncBackedCloudKitPolicy(
            syncEnablementPolicy: syncEnablementPolicy,
            bootstrapSettingsSnapshot: bootstrapSettingsSnapshot,
            localBootstrapPreference: desiredBootPreference
        )
        let syncBootstrapContext = resolveSyncBootstrapContext(
            desiredBootPreference: desiredBootPreference,
            desiredPolicy: desiredSyncBackedCloudKitPolicy,
            logger: logger
        )
        logger.info(
            "Resolved sync bootstrap policy selection: desiredBootPreference=\(desiredBootPreference.rawValue) desiredSyncBackedCloudKitPolicy=\(String(describing: desiredSyncBackedCloudKitPolicy)) effectiveModelContainerCloudKitPolicy=\(String(describing: syncBootstrapContext.modelContainerCloudKitPolicy)) accountAvailabilityAtBootstrap=\(String(describing: syncBootstrapContext.accountAvailabilityAtBootstrap)) localOnlyFallback=\(syncBootstrapContext.isRunningLocalOnlyFallbackForCurrentLaunch)"
        )
        let syncBackedCloudKitPolicy = syncBootstrapContext.modelContainerCloudKitPolicy
        let syncBackedStoreReference = makeSyncBackedStoreReference(
            modelPartition: modelPartition,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
        let modelContainer: ModelContainer?
        let modelContainerBootstrapFailureDescription: String?
        do {
            logger.info(
                "Starting model container setup: syncBackedPolicy=\(String(describing: syncBackedCloudKitPolicy)) syncBackedStoreIdentifier=\(syncBackedStoreReference.runtimeStoreIdentifier) syncBackedStoreURL=\(syncBackedStoreReference.persistentStoreURL.path)"
            )
            modelContainer = try makeModelContainer(
                modelPartition: modelPartition,
                isStoredInMemoryOnly: false,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
            )
            modelContainerBootstrapFailureDescription = nil
            logger.info(
                "Model container setup succeeded: syncBackedPolicy=\(String(describing: syncBackedCloudKitPolicy)) syncBackedStoreIdentifier=\(syncBackedStoreReference.runtimeStoreIdentifier)"
            )
        } catch {
            let persistentStoreProbeFailureDescription = makePersistentStoreProbeFailureDescription(
                modelPartition: modelPartition,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
            )
            logger.error(
                "Model container setup failed: syncBackedPolicy=\(String(describing: syncBackedCloudKitPolicy)) syncBackedStoreIdentifier=\(syncBackedStoreReference.runtimeStoreIdentifier) error=\(error)"
            )
            modelContainer = nil
            modelContainerBootstrapFailureDescription = makeModelContainerBootstrapFailureDescription(
                for: error,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy,
                persistentStoreProbeFailureDescription: persistentStoreProbeFailureDescription
            )
        }
        return AppDependencies(
            logger: logger,
            modelContainer: modelContainer,
            modelContainerBootstrapFailureDescription: modelContainerBootstrapFailureDescription,
            syncBackedStoreReference: syncBackedStoreReference,
            syncBootstrapPreferenceStore: resolvedSyncBootstrapPreferenceStore,
            syncBootstrapContext: syncBootstrapContext,
            globalOrphanSweepScheduleStore: globalOrphanSweepScheduleStore,
            syncCoordinator: syncCoordinator
        )
    }
}

extension AppDependencies {
    static func resolveSyncBackedCloudKitPolicy(
        syncEnablementPolicy: AppSyncEnablementPolicy,
        bootstrapSettingsSnapshot: AppSettingsSnapshot?,
        localBootstrapPreference: AppSyncBootPreference? = nil
    ) -> AppPersistenceCloudKitPolicy {
        syncEnablementPolicy.syncBackedCloudKitPolicy(
            for: bootstrapSettingsSnapshot,
            localBootstrapPreference: localBootstrapPreference
        )
    }

    static func resolveSyncBootstrapContext(
        desiredBootPreference: AppSyncBootPreference,
        desiredPolicy: AppPersistenceCloudKitPolicy,
        logger: Logging,
        resolvedAccountStatus: CKAccountStatus? = nil
    ) -> AppSyncBootstrapContext {
        guard case .privateContainer(let containerIdentifier) = desiredPolicy else {
            logger.info(
                "Using local-only sync bootstrap path because desired policy does not require CloudKit: desiredBootPreference=\(desiredBootPreference.rawValue) desiredPolicy=\(String(describing: desiredPolicy))"
            )
            return AppSyncBootstrapContext(
                desiredBootPreference: desiredBootPreference,
                desiredSyncBackedCloudKitPolicy: desiredPolicy,
                modelContainerCloudKitPolicy: desiredPolicy,
                accountAvailabilityAtBootstrap: nil
            )
        }

        let resolvedContainerIdentifier = containerIdentifier.isEmpty
            ? CloudKitContainerConfiguration.containerIdentifier
            : containerIdentifier
        let accountStatus = resolvedAccountStatus
            ?? CloudKitAccountStatusResolver.currentStatus(for: resolvedContainerIdentifier)
        let accountAvailability = DefaultICloudAccountAvailabilityService.mapAccountAvailability(
            from: accountStatus
        )
        logger.info(
            "Resolved sync bootstrap account status: containerIdentifier=\(resolvedContainerIdentifier) accountStatus=\(String(describing: accountStatus)) availability=\(accountAvailability.rawValue)"
        )

        guard accountStatus == .available else {
            logger.info(
                "Skipped CloudKit-backed model container bootstrap because account status is \(String(describing: accountStatus)); using local-only fallback for current launch"
            )
            return AppSyncBootstrapContext(
                desiredBootPreference: desiredBootPreference,
                desiredSyncBackedCloudKitPolicy: desiredPolicy,
                modelContainerCloudKitPolicy: .disabled,
                accountAvailabilityAtBootstrap: accountAvailability
            )
        }

        return AppSyncBootstrapContext(
            desiredBootPreference: desiredBootPreference,
            desiredSyncBackedCloudKitPolicy: desiredPolicy,
            modelContainerCloudKitPolicy: desiredPolicy,
            accountAvailabilityAtBootstrap: accountAvailability
        )
    }

    @MainActor
    static func fetchSyncEnablementBootstrapSettings(
        from modelContainer: ModelContainer
    ) throws -> AppSettingsSnapshot? {
        let repository = SwiftDataAppSettingsRepository(modelContext: modelContainer.mainContext)
        guard let settings = try repository.fetch() else {
            return nil
        }

        return AppSettingsSnapshot(settings: settings)
    }

    private static func makeModelContainer(
        modelPartition: AppPersistenceModelPartition,
        isStoredInMemoryOnly: Bool,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) throws -> ModelContainer {
        let schema = modelPartition.schema
        let configurationPlan = makeSwiftDataConfigurationPlan(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )

        return try ModelContainer(
            for: schema,
            configurations: configurationPlan.modelContainerConfigurations
        )
    }

    static func makeModelContainerBootstrapFailureDescription(
        for error: Error,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy,
        persistentStoreProbeFailureDescription: String? = nil
    ) -> String {
        let policyDescription = String(describing: syncBackedCloudKitPolicy)
        let errorDescription = CloudKitStoreBootstrapDiagnostics.describeErrorChain(error).joined(separator: "\n")
        let persistentStoreProbeSection: String
        if let persistentStoreProbeFailureDescription {
            persistentStoreProbeSection = "\nPersistent store probe:\n\(persistentStoreProbeFailureDescription)"
        } else {
            persistentStoreProbeSection = ""
        }
        return """
        The app could not initialize its data store for the current sync configuration (\(policyDescription)).
        \(errorDescription)
        \(persistentStoreProbeSection)
        """
    }

    private static func makePersistentStoreProbeFailureDescription(
        modelPartition: AppPersistenceModelPartition,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) -> String? {
        guard let request = makeSyncBackedStoreBootstrapRequest(
            modelPartition: modelPartition,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        ) else {
            return nil
        }

        return CloudKitStoreBootstrapDiagnostics.persistentStoreProbeFailureDescription(using: request)
    }

    @MainActor
    private static func makeSyncEnablementBootstrapSettingsSnapshot(
        modelPartition: AppPersistenceModelPartition,
        logger: Logging
    ) -> AppSettingsSnapshot? {
        do {
            let bootstrapContainer = try makeModelContainer(
                modelPartition: modelPartition,
                isStoredInMemoryOnly: false,
                syncBackedCloudKitPolicy: .disabled
            )
            return try fetchSyncEnablementBootstrapSettings(from: bootstrapContainer)
        } catch {
            logger.error("Failed to resolve sync enablement bootstrap settings: \(error)")
            return nil
        }
    }

    private static func makeSyncBackedStoreBootstrapRequest(
        modelPartition: AppPersistenceModelPartition,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) -> CloudKitStoreBootstrapRequest? {
        guard case .privateContainer(let containerIdentifier) = syncBackedCloudKitPolicy else {
            return nil
        }

        let resolvedContainerIdentifier = containerIdentifier.isEmpty
            ? CloudKitContainerConfiguration.containerIdentifier
            : containerIdentifier
        let configurationPlan = makeSwiftDataConfigurationPlan(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
        let syncBackedStore = configurationPlan.syncBackedStore

        return CloudKitStoreBootstrapRequest(
            containerIdentifier: resolvedContainerIdentifier,
            storeConfigurationName: syncBackedStore.name,
            storeURL: syncBackedStore.modelConfiguration.url,
            modelTypes: syncBackedStore.modelTypes
        )
    }

    private static func makeSyncBackedStoreReference(
        modelPartition: AppPersistenceModelPartition,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) -> SyncBackedStoreReference {
        let configurationPlan = makeSwiftDataConfigurationPlan(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
        let syncBackedStore = configurationPlan.syncBackedStore

        return SyncBackedStoreReference(
            runtimeStoreIdentifier: syncBackedStore.name,
            persistentStoreURL: syncBackedStore.modelConfiguration.url
        )
    }
}
