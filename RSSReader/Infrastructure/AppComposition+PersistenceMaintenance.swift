import Foundation
import SwiftUI

extension AppComposition {
    @MainActor
    @discardableResult
    static func runGlobalOrphanSweepLifecycleIfNeeded(
        from scenePhase: ScenePhase,
        using dependencies: AppDependencies,
        now: Date = .now
    ) async -> GlobalOrphanSweepTriggerResult? {
        guard scenePhase == .active else { return nil }
        return await dependencies.appActions.runScheduledGlobalOrphanSweepIfDue(now: now)
    }
}
