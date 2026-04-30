import Foundation

final class AppSyncRuntimeOrchestrator {
    private let logger: Logging
    private let syncCoordinator: SyncCoordinator?
    private let iCloudAccountAvailabilityService: any ICloudAccountAvailabilityService
    private let cloudKitRuntimeEventSource: any CloudKitRuntimeEventSource
    private let persistentStoreRemoteChangeSource: any PersistentStoreRemoteChangeSource
    private let syncBackedStoreReference: SyncBackedStoreReference?
    private let syncBootstrapPreferenceStore: any AppSyncBootstrapPreferenceStoring
    private let syncBootstrapContext: AppSyncBootstrapContext?
    private let appSettingsService: (any AppSettingsService)?

    private var hasStartedSyncCoordinatorAppLifetime = false
    private var hasStartedRemoteSyncReloadAppLifetime = false
    private var remoteSyncReloadObservationTask: Task<Void, Never>?
    private var remoteSyncReloadPendingImportCompletion = false
    private var remoteSyncReloadPendingStoreChange = false

    init(
        logger: Logging,
        syncCoordinator: SyncCoordinator?,
        iCloudAccountAvailabilityService: any ICloudAccountAvailabilityService,
        cloudKitRuntimeEventSource: any CloudKitRuntimeEventSource,
        persistentStoreRemoteChangeSource: any PersistentStoreRemoteChangeSource,
        syncBackedStoreReference: SyncBackedStoreReference?,
        syncBootstrapPreferenceStore: any AppSyncBootstrapPreferenceStoring,
        syncBootstrapContext: AppSyncBootstrapContext?,
        appSettingsService: (any AppSettingsService)?
    ) {
        self.logger = logger
        self.syncCoordinator = syncCoordinator
        self.iCloudAccountAvailabilityService = iCloudAccountAvailabilityService
        self.cloudKitRuntimeEventSource = cloudKitRuntimeEventSource
        self.persistentStoreRemoteChangeSource = persistentStoreRemoteChangeSource
        self.syncBackedStoreReference = syncBackedStoreReference
        self.syncBootstrapPreferenceStore = syncBootstrapPreferenceStore
        self.syncBootstrapContext = syncBootstrapContext
        self.appSettingsService = appSettingsService
    }

    deinit {
        remoteSyncReloadObservationTask?.cancel()
    }

    @MainActor
    func startSyncCoordinatorAppLifetime() {
        guard hasStartedSyncCoordinatorAppLifetime == false else { return }
        hasStartedSyncCoordinatorAppLifetime = true

        guard let syncCoordinator else { return }

        let isSyncEnabled = resolveInitialSyncEnablementForCoordinator()
        logger.info("Starting SyncCoordinator app lifetime: isSyncEnabled=\(isSyncEnabled)")
        syncCoordinator.applySyncEnablement(isEnabled: isSyncEnabled)
        syncCoordinator.connectRuntimeSources(
            accountAvailabilityService: iCloudAccountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )
    }

    @MainActor
    func startRemoteSyncReloadAppLifetime(using appState: AppState) {
        guard hasStartedRemoteSyncReloadAppLifetime == false else { return }
        hasStartedRemoteSyncReloadAppLifetime = true
        logger.info("Starting remote sync reload app lifetime observation")
        let runtimeEvents = cloudKitRuntimeEventSource.events()
        let remoteChangeEvents = persistentStoreRemoteChangeSource.events()

        remoteSyncReloadObservationTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await runtimeEvent in runtimeEvents {
                        guard Task.isCancelled == false else { return }
                        await MainActor.run { [weak self] in
                            self?.handleRemoteSyncReload(runtimeEvent: runtimeEvent, using: appState)
                        }
                    }
                }

                group.addTask { [weak self] in
                    for await remoteChangeEvent in remoteChangeEvents {
                        guard Task.isCancelled == false else { return }
                        await MainActor.run { [weak self] in
                            self?.handleRemoteSyncReload(remoteChangeEvent: remoteChangeEvent, using: appState)
                        }
                    }
                }

                await group.waitForAll()
            }
        }
    }

    @MainActor
    func stopAppLifetime() {
        logger.info("Stopping app-level sync runtime orchestration")
        cancelRemoteSyncReloadObservation()
        syncCoordinator?.disconnectRuntimeSources()
        hasStartedSyncCoordinatorAppLifetime = false
    }

    @MainActor
    private func resolveInitialSyncEnablementForCoordinator() -> Bool {
        if let syncBootstrapContext {
            logger.info(
                "Resolved initial sync enablement from bootstrap context: isUsingCloudKitForCurrentLaunch=\(syncBootstrapContext.isUsingCloudKitForCurrentLaunch) desiredBootPreference=\(syncBootstrapContext.desiredBootPreference.rawValue)"
            )
            return syncBootstrapContext.isUsingCloudKitForCurrentLaunch
        }

        if let localBootstrapPreference = syncBootstrapPreferenceStore.currentBootPreference() {
            logger.info(
                "Resolved initial sync enablement from local bootstrap preference: \(localBootstrapPreference.rawValue)"
            )
            return localBootstrapPreference.usesCloudKit
        }

        guard let appSettingsService else {
            logger.info("Resolved initial sync enablement with default disabled value because app settings service is unavailable")
            return false
        }

        do {
            let isEnabled = try appSettingsService.fetchSettings().useiCloudSync
            logger.info("Resolved initial sync enablement from persisted app settings: \(isEnabled)")
            return isEnabled
        } catch {
            logger.error("Failed to resolve initial sync enablement for SyncCoordinator: \(error)")
            return false
        }
    }

    @MainActor
    private func handleRemoteSyncReload(
        runtimeEvent: CloudKitRuntimeEvent,
        using appState: AppState
    ) {
        guard syncCoordinator?.runtimeState.isSyncEnabled == true else {
            logger.debug("Ignored CloudKit runtime event for remote reload correlation because sync is disabled")
            return
        }

        switch runtimeEvent {
        case .started(.import, let context):
            guard matchesSyncBackedStore(runtimeEventContext: context) else {
                logger.debug(
                    "Ignored CloudKit import start for remote reload correlation because storeIdentifier does not match sync-backed store: \(context.storeIdentifier)"
                )
                return
            }
            remoteSyncReloadPendingImportCompletion = false
            logger.info("Observed CloudKit import start; cleared pending remote reload import completion")
        case .finished(.import, let context):
            guard matchesSyncBackedStore(runtimeEventContext: context) else {
                logger.debug(
                    "Ignored CloudKit import completion for remote reload correlation because storeIdentifier does not match sync-backed store: \(context.storeIdentifier)"
                )
                return
            }
            remoteSyncReloadPendingImportCompletion = true
            logger.info("Observed CloudKit import completion; marked import completion pending for remote reload correlation")
            flushPendingRemoteSyncReloadIfNeeded(using: appState)
        case .failed(.import, let context, let message):
            guard matchesSyncBackedStore(runtimeEventContext: context) else {
                logger.debug(
                    "Ignored CloudKit import failure for remote reload correlation because storeIdentifier does not match sync-backed store: \(context.storeIdentifier)"
                )
                return
            }
            remoteSyncReloadPendingImportCompletion = false
            remoteSyncReloadPendingStoreChange = false
            logger.error(
                "Observed CloudKit import failure; cleared pending remote reload correlation storeIdentifier=\(context.storeIdentifier) message=\(message ?? "nil")"
            )
        case .started, .finished, .failed:
            return
        }
    }

    @MainActor
    private func handleRemoteSyncReload(
        remoteChangeEvent: PersistentStoreRemoteChangeEvent,
        using appState: AppState
    ) {
        guard syncCoordinator?.runtimeState.isSyncEnabled == true else {
            logger.debug("Ignored persistent store remote change because sync is disabled")
            return
        }

        guard matchesSyncBackedStore(remoteChangeEvent: remoteChangeEvent) else {
            logger.debug(
                "Ignored persistent store remote change for remote reload correlation because it does not match sync-backed store storeUUID=\(remoteChangeEvent.storeUUID ?? "nil") storeURL=\(remoteChangeEvent.storeURL?.absoluteString ?? "nil")"
            )
            return
        }

        remoteSyncReloadPendingStoreChange = true
        logger.info(
            "Observed persistent store remote change; marked store change pending for remote reload correlation storeUUID=\(remoteChangeEvent.storeUUID ?? "nil") storeURL=\(remoteChangeEvent.storeURL?.absoluteString ?? "nil")"
        )
        flushPendingRemoteSyncReloadIfNeeded(using: appState)
    }

    @MainActor
    private func flushPendingRemoteSyncReloadIfNeeded(using appState: AppState) {
        guard remoteSyncReloadPendingImportCompletion, remoteSyncReloadPendingStoreChange else {
            logger.debug(
                "Remote sync reload correlation is waiting for pair completion: pendingImportCompletion=\(remoteSyncReloadPendingImportCompletion) pendingStoreChange=\(remoteSyncReloadPendingStoreChange)"
            )
            return
        }

        remoteSyncReloadPendingImportCompletion = false
        remoteSyncReloadPendingStoreChange = false
        logger.info(
            "Requesting app-level remote sync reload after matching import completion and persistent store remote change for sync-backed storeIdentifier=\(syncBackedStoreReference?.runtimeStoreIdentifier ?? "nil")"
        )
        appState.requestRemoteSyncReload()
    }

    private func matchesSyncBackedStore(runtimeEventContext: CloudKitRuntimeEventContext) -> Bool {
        guard let syncBackedStoreReference else { return false }
        return syncBackedStoreReference.matches(runtimeEventContext: runtimeEventContext)
    }

    private func matchesSyncBackedStore(remoteChangeEvent: PersistentStoreRemoteChangeEvent) -> Bool {
        guard let syncBackedStoreReference else { return false }
        return syncBackedStoreReference.matches(remoteChangeEvent: remoteChangeEvent)
    }

    private func cancelRemoteSyncReloadObservation() {
        remoteSyncReloadObservationTask?.cancel()
        remoteSyncReloadObservationTask = nil
        hasStartedRemoteSyncReloadAppLifetime = false
        remoteSyncReloadPendingImportCompletion = false
        remoteSyncReloadPendingStoreChange = false
    }
}

struct SyncBackedStoreReference: Equatable, Sendable {
    let runtimeStoreIdentifier: String
    let persistentStoreURL: URL

    func matches(runtimeEventContext: CloudKitRuntimeEventContext) -> Bool {
        runtimeEventContext.storeIdentifier == runtimeStoreIdentifier
    }

    func matches(remoteChangeEvent: PersistentStoreRemoteChangeEvent) -> Bool {
        guard let storeURL = remoteChangeEvent.storeURL else { return false }
        return storeURL.standardizedFileURL == persistentStoreURL.standardizedFileURL
    }
}
