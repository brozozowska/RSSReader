import Foundation

enum SidebarContentPhase: Equatable {
    case loading
    case loaded
    case empty
    case failed(String)
}

enum SidebarRefreshStatus: Equatable {
    case idle(lastUpdatedAt: Date?)
    case syncing

    var isSyncing: Bool {
        if case .syncing = self {
            return true
        }
        return false
    }
}

struct SidebarScreenPrimaryLoadingState: Equatable {
    let title: String
}

struct SidebarScreenPlaceholderState: Equatable {
    let title: String
    let systemImage: String
    let description: String?
}

struct SidebarScreenDerivedViewState {
    let smartRows: [SidebarSmartRowState]
    let folderRows: [SidebarFolderSectionRowState]
    let ungroupedFeedRows: [SidebarFeedRowState]
    let shouldDisableScrolling: Bool
    let primaryLoadingState: SidebarScreenPrimaryLoadingState?
    let placeholder: SidebarScreenPlaceholderState?
    let toolbarState: SidebarToolbarState
}

struct SidebarSmartRowState: Identifiable, Equatable {
    let item: SmartSidebarItem
    let count: Int?

    var id: String { item.id }
    var title: String { item.title }
    var iconSystemName: String { item.iconSystemName }
    var selection: SidebarSelection { item.selection }
}

struct SidebarFeedRowState: Identifiable, Equatable {
    let id: UUID
    let title: String
    let iconURL: String?
    let count: Int
    let selection: SidebarSelection
    let isIndented: Bool

    init(feed: FeedSidebarItem, count: Int, isIndented: Bool) {
        self.id = feed.id
        self.title = feed.title
        self.iconURL = feed.iconURL
        self.count = count
        self.selection = .feed(feed.id)
        self.isIndented = isIndented
    }
}

struct SidebarFolderRowState: Identifiable, Equatable {
    let name: String
    let count: Int
    let isExpanded: Bool
    let selection: SidebarSelection

    var id: String { name }
}

enum SidebarFolderSectionRowState: Identifiable, Equatable {
    case folder(SidebarFolderRowState)
    case feed(SidebarFeedRowState)

    var id: String {
        switch self {
        case .folder(let row):
            "folder-\(row.id)"
        case .feed(let row):
            "feed-\(row.id.uuidString)"
        }
    }
}

enum SmartSidebarItem: CaseIterable, Identifiable, Equatable {
    case allItems
    case unread
    case starred

    var id: String { title }

    var title: String {
        switch self {
        case .allItems:
            "All Items"
        case .unread:
            "Unread"
        case .starred:
            "Starred"
        }
    }

    var iconSystemName: String {
        switch self {
        case .allItems:
            "tray.full"
        case .unread:
            "circle"
        case .starred:
            "star"
        }
    }

    var selection: SidebarSelection {
        switch self {
        case .allItems:
            .inbox
        case .unread:
            .unread
        case .starred:
            .starred
        }
    }

    static func visibleItems(for filter: SourcesFilter, hasFeeds: Bool) -> [SmartSidebarItem] {
        guard hasFeeds else { return [] }

        return switch filter {
        case .allItems:
            [SmartSidebarItem.allItems]
        case .unread:
            [SmartSidebarItem.unread]
        case .starred:
            [SmartSidebarItem.starred]
        }
    }

    static func selection(for filter: SourcesFilter) -> SidebarSelection {
        switch filter {
        case .allItems:
            .inbox
        case .unread:
            .unread
        case .starred:
            .starred
        }
    }
}

enum SidebarFeedVisibility {
    static func filteredFeeds(
        feeds: [FeedSidebarItem],
        filter: SourcesFilter,
        starredFeedIDs: Set<UUID>
    ) -> [FeedSidebarItem] {
        switch filter {
        case .starred:
            feeds.filter { starredFeedIDs.contains($0.id) }
        case .unread:
            feeds.filter { $0.unreadCount > 0 }
        case .allItems:
            feeds
        }
    }
}

enum SidebarUngroupedFeeds {
    static func visibleFeeds(from feeds: [FeedSidebarItem]) -> [FeedSidebarItem] {
        feeds
            .filter { $0.folderName == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

enum SidebarSelectionBehavior {
    static func resolvedSelection(
        currentSelection: SidebarSelection?,
        filter: SourcesFilter,
        visibleFeedIDs: Set<UUID>,
        visibleFolderNames: Set<String>
    ) -> SidebarSelection? {
        let fallbackSelection = SmartSidebarItem.selection(for: filter)

        guard let currentSelection else {
            return nil
        }

        switch currentSelection {
        case .feed(let feedID):
            return visibleFeedIDs.contains(feedID) ? currentSelection : fallbackSelection
        case .folder(let folderName):
            return visibleFolderNames.contains(folderName) ? currentSelection : fallbackSelection
        case .inbox, .unread, .starred:
            return currentSelection == fallbackSelection ? currentSelection : fallbackSelection
        }
    }
}

struct FolderSidebarGroup: Identifiable {
    let name: String
    let feeds: [FeedSidebarItem]

    var id: String { name }
    var unreadCount: Int { feeds.reduce(0) { $0 + $1.unreadCount } }
    var starredCount: Int { feeds.reduce(0) { $0 + $1.starredCount } }

    static func groups(from feeds: [FeedSidebarItem]) -> [FolderSidebarGroup] {
        let groupedFeeds = Dictionary(
            grouping: feeds.filter { $0.folderName != nil },
            by: { $0.folderName ?? "" }
        )

        let groups = groupedFeeds.map { name, feeds in
            FolderSidebarGroup(
                name: name,
                feeds: feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }

        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum FolderSectionRow: Identifiable {
    case folder(FolderSidebarGroup)
    case feed(FeedSidebarItem)

    var id: String {
        switch self {
        case .folder(let group):
            "folder-\(group.id)"
        case .feed(let feed):
            "feed-\(feed.id.uuidString)"
        }
    }
}
