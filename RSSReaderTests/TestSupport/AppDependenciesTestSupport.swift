import CloudKit
import Foundation
import Testing
@testable import RSSReader

final class AppDependenciesTestICloudAccountAvailabilityService: ICloudAccountAvailabilityService, @unchecked Sendable {
    private let initialAvailability: ICloudAccountAvailability
    private let queue = DispatchQueue(label: "RSSReaderTests.AppDependencies.AccountAvailability")
    private var continuations: [UUID: AsyncStream<ICloudAccountAvailability>.Continuation] = [:]

    init(initialAvailability: ICloudAccountAvailability) {
        self.initialAvailability = initialAvailability
    }

    func currentAvailability() async -> ICloudAccountAvailability {
        initialAvailability
    }

    func availabilityChanges() -> AsyncStream<ICloudAccountAvailability> {
        AsyncStream { continuation in
            let id = UUID()
            queue.sync {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var subscriberCount: Int {
        queue.sync {
            continuations.count
        }
    }

    func yield(_ availability: ICloudAccountAvailability) async {
        let activeContinuations = queue.sync {
            Array(continuations.values)
        }
        activeContinuations.forEach { continuation in
            continuation.yield(availability)
        }
    }
}

@MainActor
final class AppDependenciesRecordingBackgroundRefreshForegroundHandoffCoordinator:
    BackgroundRefreshForegroundHandoffCoordinating
{
    private var reloadHandler: (@MainActor () -> Void)?

    func bindReloadHandler(_ handler: @escaping @MainActor () -> Void) {
        reloadHandler = handler
    }

    func unbindReloadHandler() {
        reloadHandler = nil
    }

    func updateRuntimeState(_ runtimeState: AppRuntimeReloadState) {}

    func handleBackgroundRefreshExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {}

    func triggerBoundReloadHandler() {
        reloadHandler?()
    }
}

final class AppDependenciesTestCloudKitRuntimeEventSource: CloudKitRuntimeEventSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RSSReaderTests.AppDependencies.CloudKitRuntimeEvents")
    private var continuations: [UUID: AsyncStream<CloudKitRuntimeEvent>.Continuation] = [:]

    func events() -> AsyncStream<CloudKitRuntimeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            queue.sync {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var subscriberCount: Int {
        queue.sync {
            continuations.count
        }
    }

    func yield(_ event: CloudKitRuntimeEvent) async {
        let activeContinuations = queue.sync {
            Array(continuations.values)
        }
        activeContinuations.forEach { continuation in
            continuation.yield(event)
        }
    }
}

final class AppDependenciesTestPersistentStoreRemoteChangeSource: PersistentStoreRemoteChangeSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RSSReaderTests.AppDependencies.PersistentStoreRemoteChanges")
    private var continuations: [UUID: AsyncStream<PersistentStoreRemoteChangeEvent>.Continuation] = [:]

    func events() -> AsyncStream<PersistentStoreRemoteChangeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            queue.sync {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var subscriberCount: Int {
        queue.sync {
            continuations.count
        }
    }

    func yield(_ event: PersistentStoreRemoteChangeEvent) async {
        let activeContinuations = queue.sync {
            Array(continuations.values)
        }
        activeContinuations.forEach { continuation in
            continuation.yield(event)
        }
    }
}

struct AppDependenciesFixedSyncBootstrapPreferenceStore: AppSyncBootstrapPreferenceStoring {
    let currentPreference: AppSyncBootPreference?

    func currentBootPreference() -> AppSyncBootPreference? {
        currentPreference
    }

    func saveBootPreference(_ preference: AppSyncBootPreference) {}
}

struct AppDependenciesTimedOutError: Error {}

enum AppDependenciesSyncBootstrapAccountStatusScenario: CaseIterable {
    case available
    case temporarilyUnavailable
    case noAccount
    case restricted
    case couldNotDetermine

    var accountStatus: CKAccountStatus {
        switch self {
        case .available:
            .available
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedAccountAvailability: ICloudAccountAvailability {
        DefaultICloudAccountAvailabilityService.mapAccountAvailability(from: accountStatus)
    }

    var expectedModelContainerPolicy: AppPersistenceCloudKitPolicy {
        expectsCloudKitBootstrap
            ? .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
            : .disabled
    }

    var expectsCloudKitBootstrap: Bool {
        self == .available
    }

    var expectsLocalOnlyFallback: Bool {
        expectsCloudKitBootstrap == false
    }
}

func appDependenciesTestSyncBackedStoreReference() -> SyncBackedStoreReference {
    SyncBackedStoreReference(
        runtimeStoreIdentifier: "SyncBackedStore",
        persistentStoreURL: URL(fileURLWithPath: "/tmp/SyncBackedStore.sqlite")
    )
}

func expectAppDependenciesEventually(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))

    while ContinuousClock.now < deadline {
        if await MainActor.run(body: condition) {
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }

    throw AppDependenciesTimedOutError()
}

func expectAppDependenciesRemoteSyncReloadObservationStarted(
    cloudKitRuntimeEventSource: AppDependenciesTestCloudKitRuntimeEventSource,
    remoteChangeSource: AppDependenciesTestPersistentStoreRemoteChangeSource
) async throws {
    try await expectAppDependenciesEventually {
        cloudKitRuntimeEventSource.subscriberCount == 1
            && remoteChangeSource.subscriberCount == 1
    }
}

func expectAppDependenciesNoReload(
    sidebarReloadID: UUID,
    articleListReloadID: UUID,
    articleScreenReloadID: UUID,
    in appState: AppState,
    durationNanoseconds: UInt64 = 200_000_000
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(durationNanoseconds))

    while ContinuousClock.now < deadline {
        let reloadOccurred = await MainActor.run {
            appState.sidebarReloadID != sidebarReloadID
                || appState.articleListReloadID != articleListReloadID
                || appState.articleScreenReloadID != articleScreenReloadID
        }

        #expect(reloadOccurred == false)
        try await Task.sleep(for: .milliseconds(10))
    }
}
