import Foundation

enum RuntimeFeedbackLocalization {
    static let refreshIdleAccessibilityLabel = String(
        localized: "runtime.refresh.accessibility.idle",
        defaultValue: "Refresh idle",
        comment: "Accessibility label for an idle refresh indicator."
    )
    static let refreshPullingAccessibilityLabel = String(
        localized: "runtime.refresh.accessibility.pulling",
        defaultValue: "Pulling to refresh",
        comment: "Accessibility label while the user is pulling to refresh."
    )
    static let refreshReadyAccessibilityLabel = String(
        localized: "runtime.refresh.accessibility.ready",
        defaultValue: "Release to refresh",
        comment: "Accessibility label when releasing will trigger refresh."
    )
    static let refreshingAccessibilityLabel = String(
        localized: "runtime.refresh.accessibility.refreshing",
        defaultValue: "Refreshing",
        comment: "Accessibility label while refresh is running."
    )
    static let syncingStatusTitle = String(
        localized: "runtime.sync.status.syncing",
        defaultValue: "Syncing...",
        comment: "Short runtime status shown while feeds or iCloud data are syncing."
    )
    static let syncFailedStatusTitle = String(
        localized: "runtime.sync.status.failed",
        defaultValue: "Sync failed",
        comment: "Short runtime status shown when iCloud sync failed."
    )
    static let notUpdatedYetStatusTitle = String(
        localized: "runtime.refresh.status.notUpdatedYet",
        defaultValue: "Not updated yet",
        comment: "Sidebar subtitle shown before feeds have ever refreshed."
    )
    static func todayRefreshStatus(time: String) -> String {
        let format = String(
            localized: "runtime.refresh.status.today.format",
            defaultValue: "Today at %@",
            comment: "Sidebar subtitle for a refresh that happened today. Placeholder is a localized time."
        )
        return CommonLocalization.localizedTemplate(format, time)
    }
    static func yesterdayRefreshStatus(time: String) -> String {
        let format = String(
            localized: "runtime.refresh.status.yesterday.format",
            defaultValue: "Yesterday at %@",
            comment: "Sidebar subtitle for a refresh that happened yesterday. Placeholder is a localized time."
        )
        return CommonLocalization.localizedTemplate(format, time)
    }
}
