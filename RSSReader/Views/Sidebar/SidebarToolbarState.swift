import Foundation
import SwiftUI

enum SidebarToolbarPlacement {
    static let settings: ToolbarItemPlacement = .topBarLeading
    static let title: ToolbarItemPlacement = .title
    static let subtitle: ToolbarItemPlacement = .subtitle
    static let addFeed: ToolbarItemPlacement = .topBarTrailing
    static let filter: ToolbarItemPlacement = .topBarTrailing
}

struct SidebarToolbarState: Equatable {
    let subtitle: String
    let isSyncing: Bool

    init(
        refreshStatus: SidebarRefreshStatus,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        formatter: SidebarSubtitleFormatter = SidebarSubtitleFormatter()
    ) {
        self.subtitle = formatter.text(
            for: refreshStatus,
            iCloudSyncStatus: iCloudSyncStatus
        )
        self.isSyncing = refreshStatus.isSyncing || iCloudSyncStatus == .syncing
    }
}

struct SidebarSubtitleFormatter {
    var now: Date = .now
    var calendar: Calendar = .current
    var locale: Locale = .current

    func text(
        for refreshStatus: SidebarRefreshStatus,
        iCloudSyncStatus: ICloudSyncStatus = .disabled
    ) -> String {
        if refreshStatus.isSyncing || iCloudSyncStatus == .syncing {
            return RuntimeFeedbackLocalization.syncingStatusTitle
        }

        if case .failed = iCloudSyncStatus {
            return RuntimeFeedbackLocalization.syncFailedStatusTitle
        }

        switch refreshStatus {
        case .idle(let lastUpdatedAt):
            return lastUpdatedText(for: lastUpdatedAt)
        case .syncing:
            return RuntimeFeedbackLocalization.syncingStatusTitle
        }
    }

    private func lastUpdatedText(for date: Date?) -> String {
        guard let date else {
            return RuntimeFeedbackLocalization.notUpdatedYetStatusTitle
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return RuntimeFeedbackLocalization.todayRefreshStatus(time: timeString(for: date))
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return RuntimeFeedbackLocalization.yesterdayRefreshStatus(time: timeString(for: date))
        }

        return dateString(for: date)
    }

    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
