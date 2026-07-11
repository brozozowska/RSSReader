import Foundation
import CoreGraphics

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

struct SidebarCustomRefreshState: Equatable {
    enum Phase: Equatable {
        case idle
        case pulling
        case ready
        case refreshing
    }

    static let idle = SidebarCustomRefreshState(phase: .idle, pullProgress: 0)
    static let refreshing = SidebarCustomRefreshState(phase: .refreshing, pullProgress: 1)

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

    static func pulling(progress: Double) -> SidebarCustomRefreshState {
        let normalizedProgress = min(max(progress, 0), 1)

        if normalizedProgress <= 0 {
            return .idle
        }

        if normalizedProgress >= 1 {
            return SidebarCustomRefreshState(phase: .ready, pullProgress: 1)
        }

        return SidebarCustomRefreshState(phase: .pulling, pullProgress: normalizedProgress)
    }
}

struct SidebarCustomRefreshGeometry: Equatable {
    var contentOffsetY: CGFloat
    var contentInsetTop: CGFloat

    init(contentOffsetY: CGFloat = 0, contentInsetTop: CGFloat = 0) {
        self.contentOffsetY = contentOffsetY
        self.contentInsetTop = contentInsetTop
    }

    var topOverscrollDistance: CGFloat {
        max(0, -(contentOffsetY + contentInsetTop))
    }
}

enum SidebarCustomRefreshPullPolicy {
    static let pullThreshold: CGFloat = 72

    static func progress(
        for geometry: SidebarCustomRefreshGeometry,
        threshold: CGFloat = pullThreshold
    ) -> Double {
        guard threshold > 0 else { return 0 }

        return min(Double(geometry.topOverscrollDistance / threshold), 1)
    }
}

enum SidebarCustomRefreshReleasePolicy {
    static func shouldTriggerRefresh(
        wasInteracting: Bool,
        isInteracting: Bool,
        customRefreshState: SidebarCustomRefreshState
    ) -> Bool {
        wasInteracting && isInteracting == false && customRefreshState.phase == .ready
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

    var id: SmartSidebarItem { item.id }
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
    let folderID: UUID?
    let name: String
    let count: Int
    let isExpanded: Bool
    let selection: SidebarSelection

    var id: String { folderID?.uuidString ?? name }
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

enum SmartSidebarItem: CaseIterable, Identifiable, Hashable {
    case allItems
    case unread
    case starred

    var id: SmartSidebarItem { self }

    var title: String {
        switch self {
        case .allItems:
            SidebarLocalization.allItemsFilterTitle
        case .unread:
            SidebarLocalization.unreadFilterTitle
        case .starred:
            SidebarLocalization.starredFilterTitle
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

    static func visibleItems(for filter: SidebarArticleFilter, hasFeeds: Bool) -> [SmartSidebarItem] {
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

    static func selection(for filter: SidebarArticleFilter) -> SidebarSelection {
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
        filter: SidebarArticleFilter,
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
        filter: SidebarArticleFilter,
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
    let folderID: UUID?
    let name: String
    let sortOrder: Int
    let feeds: [FeedSidebarItem]

    var id: String { folderID?.uuidString ?? name }
    var unreadCount: Int { feeds.reduce(0) { $0 + $1.unreadCount } }
    var starredCount: Int { feeds.reduce(0) { $0 + $1.starredCount } }

    init(
        folderID: UUID? = nil,
        name: String,
        sortOrder: Int = Int.max,
        feeds: [FeedSidebarItem]
    ) {
        self.folderID = folderID
        self.name = name
        self.sortOrder = sortOrder
        self.feeds = feeds
    }

    static func groups(
        from folders: [FolderSidebarItem],
        feeds: [FeedSidebarItem],
        filter: SidebarArticleFilter = .allItems
    ) -> [FolderSidebarGroup] {
        let groupedFeeds = Dictionary(
            grouping: feeds.filter { $0.folderName != nil },
            by: { $0.folderName ?? "" }
        )

        var representedFolderNames = Set<String>()
        var groups = folders.compactMap { folder -> FolderSidebarGroup? in
            let folderFeeds = groupedFeeds[folder.name, default: []].sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            guard filter == .allItems || folderFeeds.isEmpty == false else {
                return nil
            }

            representedFolderNames.insert(folder.name)
            return FolderSidebarGroup(
                folderID: folder.id,
                name: folder.name,
                sortOrder: folder.sortOrder,
                feeds: folderFeeds
            )
        }

        let orphanGroups = groupedFeeds.compactMap { name, feeds -> FolderSidebarGroup? in
            guard representedFolderNames.contains(name) == false else { return nil }
            return FolderSidebarGroup(
                name: name,
                feeds: feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }

        groups.append(contentsOf: orphanGroups)

        return groups.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    static func groups(from feeds: [FeedSidebarItem]) -> [FolderSidebarGroup] {
        groups(from: [], feeds: feeds)
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
