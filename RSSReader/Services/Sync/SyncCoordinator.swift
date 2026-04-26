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

    private var isSyncEnabled: Bool
    private var accountAvailability: ICloudAccountAvailability?
    private var activeActivity: CloudKitRuntimeActivity?
    private var lastFailure: SyncRuntimeFailure?
    private var lastEventContext: CloudKitRuntimeEventContext?

    init(isSyncEnabled: Bool = false) {
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

    func applySyncEnablement(isEnabled: Bool) {
        isSyncEnabled = isEnabled

        if isEnabled == false {
            accountAvailability = nil
            activeActivity = nil
            lastFailure = nil
            lastEventContext = nil
        }

        recomputeRuntimeState()
    }

    func applyAccountAvailability(_ availability: ICloudAccountAvailability?) {
        accountAvailability = availability
        recomputeRuntimeState()
    }

    func applyCloudKitRuntimeEvent(_ event: CloudKitRuntimeEvent) {
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
        lastFailure = nil
        recomputeRuntimeState()
    }

    private func recomputeRuntimeState() {
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

        runtimeState = SyncRuntimeState(
            phase: phase,
            isSyncEnabled: isSyncEnabled,
            accountAvailability: accountAvailability,
            activeActivity: activeActivity,
            lastEventContext: lastEventContext
        )
    }
}
