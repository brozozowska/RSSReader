import Foundation

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

    func text(
        for refreshStatus: SidebarRefreshStatus,
        iCloudSyncStatus: ICloudSyncStatus = .disabled
    ) -> String {
        if refreshStatus.isSyncing || iCloudSyncStatus == .syncing {
            return "Syncing..."
        }

        if case .failed = iCloudSyncStatus {
            return "Sync failed"
        }

        switch refreshStatus {
        case .idle(let lastUpdatedAt):
            return lastUpdatedText(for: lastUpdatedAt)
        case .syncing:
            return "Syncing..."
        }
    }

    private func lastUpdatedText(for date: Date?) -> String {
        guard let date else {
            return "Not updated yet"
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return "Today at \(timeString(for: date))"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday at \(timeString(for: date))"
        }

        return dateString(for: date)
    }

    private func timeString(for date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: date)
    }
}
