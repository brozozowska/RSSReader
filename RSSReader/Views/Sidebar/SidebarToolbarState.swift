import Foundation

struct SidebarToolbarState: Equatable {
    let subtitle: String
    let isSyncing: Bool

    init(
        refreshStatus: SidebarRefreshStatus,
        formatter: SidebarSubtitleFormatter = SidebarSubtitleFormatter()
    ) {
        self.subtitle = formatter.text(for: refreshStatus)
        self.isSyncing = refreshStatus.isSyncing
    }
}

struct SidebarSubtitleFormatter {
    func text(for refreshStatus: SidebarRefreshStatus) -> String {
        switch refreshStatus {
        case .syncing:
            "Syncing..."
        case .idle(let lastUpdatedAt):
            lastUpdatedText(for: lastUpdatedAt)
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

private extension SidebarRefreshStatus {
    var isSyncing: Bool {
        if case .syncing = self {
            return true
        }
        return false
    }
}
