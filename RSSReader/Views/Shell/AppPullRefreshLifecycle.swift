import Foundation

/// A screen-local presentation lifecycle. Feed refresh tasks and retry policy
/// remain owned by the screen controller.
struct AppPullRefreshLifecycle {
    private(set) var state: AppPullRefreshState = .idle
    private var refreshID: UUID?

    mutating func updatePullProgress(_ progress: Double) {
        guard state.phase != .refreshing else { return }
        state = .pulling(progress: progress)
    }

    @discardableResult
    mutating func begin() -> UUID {
        let id = UUID()
        state = .refreshing
        refreshID = id
        return id
    }

    /// An unguarded end also invalidates completions after a screen reset.
    mutating func end(ifMatching id: UUID? = nil) {
        if let id, id != refreshID { return }
        state = .idle
        refreshID = nil
    }
}

struct AppPullRefreshState: Equatable {
    enum Phase: Equatable {
        case idle
        case pulling
        case ready
        case refreshing
    }

    static let idle = AppPullRefreshState(phase: .idle, pullProgress: 0)
    static let refreshing = AppPullRefreshState(phase: .refreshing, pullProgress: 1)

    let phase: Phase
    let pullProgress: Double

    var showsIndicator: Bool {
        phase != .idle
    }

    var indicatorState: AppRefreshIndicatorState {
        switch phase {
        case .idle:
            .idle
        case .pulling:
            .pulling(progress: pullProgress)
        case .ready:
            .ready
        case .refreshing:
            .refreshing
        }
    }

    static func pulling(progress: Double) -> AppPullRefreshState {
        let normalizedProgress = min(max(progress, 0), 1)

        if normalizedProgress <= 0 {
            return .idle
        }

        if normalizedProgress >= 1 {
            return AppPullRefreshState(phase: .ready, pullProgress: 1)
        }

        return AppPullRefreshState(phase: .pulling, pullProgress: normalizedProgress)
    }
}
