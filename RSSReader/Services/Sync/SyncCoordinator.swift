import Foundation
import Observation

enum SyncRuntimePhase: Equatable, Sendable {
    case disabled
    case statusUnavailable
    case idle
    case accountProblem(ICloudAccountAvailability)
    case syncing(CloudKitRuntimeActivity)
    case failed(SyncRuntimeFailure)
}

struct SyncRuntimeFailure: Equatable, Sendable {
    let activity: CloudKitRuntimeActivity?
    let message: String?

    var resolvedMessage: String {
        if let message, message.isEmpty == false {
            return message
        }

        guard let activity else {
            return "iCloud sync failed."
        }

        switch activity {
        case .setup:
            return "iCloud sync setup failed."
        case .import:
            return "Importing changes from iCloud failed."
        case .export:
            return "Exporting changes to iCloud failed."
        }
    }
}

struct SyncRuntimeState: Equatable, Sendable {
    let phase: SyncRuntimePhase
    let isSyncEnabled: Bool
    let accountAvailability: ICloudAccountAvailability?
    let activeActivity: CloudKitRuntimeActivity?
    let lastEventContext: CloudKitRuntimeEventContext?

    static let disabled = SyncRuntimeState(
        phase: .disabled,
        isSyncEnabled: false,
        accountAvailability: nil,
        activeActivity: nil,
        lastEventContext: nil
    )

    var iCloudSyncStatus: ICloudSyncStatus {
        switch phase {
        case .disabled:
            return .disabled
        case .statusUnavailable:
            return .statusUnavailable
        case .idle:
            return .idle
        case .accountProblem:
            return .statusUnavailable
        case .syncing:
            return .syncing
        case .failed(let failure):
            return .failed(failure.resolvedMessage)
        }
    }
}

@MainActor
@Observable
final class SyncCoordinator {
    private(set) var runtimeState: SyncRuntimeState

    private let logger: Logging
    private var isSyncEnabled: Bool
    private var accountAvailability: ICloudAccountAvailability?
    private var activeActivity: CloudKitRuntimeActivity?
    private var lastFailure: SyncRuntimeFailure?
    private var lastEventContext: CloudKitRuntimeEventContext?
    private var accountAvailabilityObservationTask: Task<Void, Never>?
    private var cloudKitRuntimeEventObservationTask: Task<Void, Never>?

    init(
        isSyncEnabled: Bool = false,
        logger: Logging? = nil
    ) {
        self.logger = logger ?? ConsoleLogger()
        self.isSyncEnabled = isSyncEnabled
        self.accountAvailability = nil
        self.activeActivity = nil
        self.lastFailure = nil
        self.lastEventContext = nil
        self.runtimeState = isSyncEnabled
            ? SyncRuntimeState(
                phase: .statusUnavailable,
                isSyncEnabled: true,
                accountAvailability: nil,
                activeActivity: nil,
                lastEventContext: nil
            )
            : .disabled
    }

    var iCloudSyncStatus: ICloudSyncStatus {
        runtimeState.iCloudSyncStatus
    }

    func connectRuntimeSources(
        accountAvailabilityService: any ICloudAccountAvailabilityService,
        cloudKitRuntimeEventSource: any CloudKitRuntimeEventSource
            ) {
        disconnectRuntimeSources()
        guard isSyncEnabled else {
            logger.info("Skipped SyncCoordinator runtime source connection because sync is disabled")
            recomputeRuntimeState()
            return
        }

        logger.info("Connecting SyncCoordinator runtime sources")

        accountAvailabilityObservationTask = Task { [weak self] in
            let initialAvailability = await accountAvailabilityService.currentAvailability()
            await MainActor.run {
                self?.logger.info(
                    "SyncCoordinator received initial iCloud account availability: \(String(describing: initialAvailability))"
                )
                self?.applyAccountAvailability(initialAvailability)
            }

            for await availability in accountAvailabilityService.availabilityChanges() {
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    self?.logger.info(
                        "SyncCoordinator received iCloud account availability update: \(String(describing: availability))"
                    )
                    self?.applyAccountAvailability(availability)
                }
            }
        }

        cloudKitRuntimeEventObservationTask = Task { [weak self] in
            for await runtimeEvent in cloudKitRuntimeEventSource.events() {
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    self?.logger.debug(
                        "SyncCoordinator received CloudKit runtime event: \(Self.describe(runtimeEvent: runtimeEvent))"
                    )
                    self?.applyCloudKitRuntimeEvent(runtimeEvent)
                }
            }
        }
    }

    func disconnectRuntimeSources() {
        logger.debug("Disconnecting SyncCoordinator runtime sources")
        accountAvailabilityObservationTask?.cancel()
        cloudKitRuntimeEventObservationTask?.cancel()
        accountAvailabilityObservationTask = nil
        cloudKitRuntimeEventObservationTask = nil
    }

    func applySyncEnablement(isEnabled: Bool) {
        logger.info("Applying SyncCoordinator sync enablement: isEnabled=\(isEnabled)")
        isSyncEnabled = isEnabled

        if isEnabled == false {
            disconnectRuntimeSources()
            accountAvailability = nil
            activeActivity = nil
            lastFailure = nil
            lastEventContext = nil
        }

        recomputeRuntimeState()
    }

    func applyAccountAvailability(_ availability: ICloudAccountAvailability?) {
        logger.debug("Applying SyncCoordinator account availability: \(String(describing: availability))")
        accountAvailability = availability
        recomputeRuntimeState()
    }

    func applyCloudKitRuntimeEvent(_ event: CloudKitRuntimeEvent) {
        switch event {
        case .started:
            logger.info("SyncCoordinator handling CloudKit runtime activity start: \(Self.describe(runtimeEvent: event))")
        case .finished:
            logger.info("SyncCoordinator handling CloudKit runtime activity finish: \(Self.describe(runtimeEvent: event))")
        case .failed:
            logger.error("SyncCoordinator handling CloudKit runtime failure: \(Self.describe(runtimeEvent: event))")
        }

        switch event {
        case .started(let activity, let context):
            activeActivity = activity
            lastFailure = nil
            lastEventContext = context
        case .finished(_, let context):
            activeActivity = nil
            lastFailure = nil
            lastEventContext = context
        case .failed(let activity, let context, let message):
            activeActivity = nil
            lastFailure = SyncRuntimeFailure(activity: activity, message: message)
            lastEventContext = context
        }

        recomputeRuntimeState()
    }

    func clearRuntimeFailure() {
        logger.info("Clearing SyncCoordinator runtime failure")
        lastFailure = nil
        recomputeRuntimeState()
    }

    private func recomputeRuntimeState() {
        let previousRuntimeState = runtimeState
        let phase: SyncRuntimePhase

        if isSyncEnabled == false {
            phase = .disabled
        } else if let lastFailure {
            phase = .failed(lastFailure)
        } else if let activeActivity {
            phase = .syncing(activeActivity)
        } else if let accountAvailability {
            switch accountAvailability {
            case .available:
                phase = .idle
            case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
                phase = .accountProblem(accountAvailability)
            }
        } else {
            phase = .statusUnavailable
        }

        let nextRuntimeState = SyncRuntimeState(
            phase: phase,
            isSyncEnabled: isSyncEnabled,
            accountAvailability: accountAvailability,
            activeActivity: activeActivity,
            lastEventContext: lastEventContext
        )

        runtimeState = nextRuntimeState
        if previousRuntimeState != nextRuntimeState {
            logger.info(
                "SyncCoordinator runtime state changed from \(Self.describe(runtimeState: previousRuntimeState)) to \(Self.describe(runtimeState: nextRuntimeState))"
            )
        }
    }
}

private extension SyncCoordinator {
    static func describe(runtimeState: SyncRuntimeState) -> String {
        "phase=\(describe(phase: runtimeState.phase)) isSyncEnabled=\(runtimeState.isSyncEnabled) accountAvailability=\(String(describing: runtimeState.accountAvailability)) activeActivity=\(String(describing: runtimeState.activeActivity)) storeIdentifier=\(runtimeState.lastEventContext?.storeIdentifier ?? "nil")"
    }

    static func describe(phase: SyncRuntimePhase) -> String {
        switch phase {
        case .disabled:
            return "disabled"
        case .statusUnavailable:
            return "statusUnavailable"
        case .idle:
            return "idle"
        case .accountProblem(let availability):
            return "accountProblem(\(availability.rawValue))"
        case .syncing(let activity):
            return "syncing(\(activity.rawValue))"
        case .failed(let failure):
            return "failed(activity=\(failure.activity?.rawValue ?? "nil"), message=\(failure.resolvedMessage))"
        }
    }

    static func describe(runtimeEvent: CloudKitRuntimeEvent) -> String {
        switch runtimeEvent {
        case .started(let activity, let context):
            return "started(activity=\(activity.rawValue), storeIdentifier=\(context.storeIdentifier), eventIdentifier=\(context.identifier.uuidString))"
        case .finished(let activity, let context):
            return "finished(activity=\(activity.rawValue), storeIdentifier=\(context.storeIdentifier), eventIdentifier=\(context.identifier.uuidString))"
        case .failed(let activity, let context, let message):
            return "failed(activity=\(activity.rawValue), storeIdentifier=\(context.storeIdentifier), eventIdentifier=\(context.identifier.uuidString), message=\(message ?? "nil"))"
        }
    }
}
