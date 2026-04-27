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

        if Calendar.current.isDateInToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }

        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday at \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
