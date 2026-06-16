import Foundation

enum SettingsScreenSectionID: String, Hashable, Identifiable, Sendable {
    case appearance
    case reading
    case articleList
    case updatesAndSync
    case notifications
    case sourcePortability
    case storage

    var id: String { rawValue }
}

enum SettingsScreenItemID: String, Hashable, Identifiable, Sendable {
    case articleOpeningMode
    case markAsReadOnOpen
    case articleSourceLinkOpeningPolicy
    case unreadArticleSortOrder
    case articleRetentionPolicy
    case askBeforeMarkingAllAsRead
    case refreshInterval
    case useICloudSync
    case iCloudSyncStatus
    case showUnreadCountBadge
    case articleBodyLinkOpeningPolicy
    case readerAdjacentNavigationControlsMode
    case appearance
    case importOPML
    case exportOPML
    case purgeArchivedArticles
    case clearArticleImageCache
    case clearFeedIconCache

    var id: String { rawValue }
}

struct SettingsScreenInput: Equatable, Sendable {
    var articleOpeningMode: ArticleOpeningMode
    var markAsReadOnOpen: Bool
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode
    var unreadArticleSortOrder: UnreadArticleSortOrder
    var articleRetentionPolicy: ArticleRetentionPolicy
    var askBeforeMarkingAllAsRead: Bool
    var refreshIntervalPreference: RefreshPreference
    var showUnreadCountBadge: Bool
    var useiCloudSync: Bool
    var iCloudSyncStatus: ICloudSyncStatus
    var syncStatusPresentation: SettingsSyncStatusPresentation
    var isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool
    var interfaceThemeMode: InterfaceThemeMode

    init(
        articleOpeningMode: ArticleOpeningMode = .feedReader,
        markAsReadOnOpen: Bool = true,
        articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = .inAppBrowser,
        articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = .inAppBrowser,
        readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls,
        unreadArticleSortOrder: UnreadArticleSortOrder = .newestFirst,
        articleRetentionPolicy: ArticleRetentionPolicy = .oneWeek,
        askBeforeMarkingAllAsRead: Bool = true,
        refreshIntervalPreference: RefreshPreference = .manual,
        showUnreadCountBadge: Bool = false,
        useiCloudSync: Bool = false,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        syncStatusPresentation: SettingsSyncStatusPresentation = .disabled,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool = false,
        interfaceThemeMode: InterfaceThemeMode = .automaticLightDark
    ) {
        self.articleOpeningMode = articleOpeningMode
        self.markAsReadOnOpen = markAsReadOnOpen
        self.articleBodyLinkOpeningPolicy = articleBodyLinkOpeningPolicy
        self.articleSourceLinkOpeningPolicy = articleSourceLinkOpeningPolicy
        self.readerAdjacentNavigationControlsMode = readerAdjacentNavigationControlsMode
        self.unreadArticleSortOrder = unreadArticleSortOrder
        self.articleRetentionPolicy = articleRetentionPolicy
        self.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        self.refreshIntervalPreference = refreshIntervalPreference
        self.showUnreadCountBadge = showUnreadCountBadge
        self.useiCloudSync = useiCloudSync
        self.iCloudSyncStatus = iCloudSyncStatus
        self.syncStatusPresentation = syncStatusPresentation
        self.isUsingLocalOnlySyncFallbackForCurrentLaunch = isUsingLocalOnlySyncFallbackForCurrentLaunch
        self.interfaceThemeMode = interfaceThemeMode
    }
}

enum SettingsSyncStatusPresentation: Equatable, Sendable {
    case disabled
    case statusUnavailable
    case checkingAccount
    case ready
    case syncing
    case preparing
    case importing
    case uploading
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case failed(String)

    init(iCloudSyncStatus: ICloudSyncStatus) {
        switch iCloudSyncStatus {
        case .disabled:
            self = .disabled
        case .statusUnavailable:
            self = .statusUnavailable
        case .idle:
            self = .ready
        case .syncing:
            self = .syncing
        case .failed(let message):
            self = .failed(message)
        }
    }

    init(runtimeState: SyncRuntimeState) {
        switch runtimeState.phase {
        case .disabled:
            self = .disabled
        case .statusUnavailable:
            self = .checkingAccount
        case .idle:
            self = .ready
        case .accountProblem(let availability):
            self.init(accountAvailability: availability)
        case .syncing(let activity):
            switch activity {
            case .setup:
                self = .preparing
            case .import:
                self = .importing
            case .export:
                self = .uploading
            }
        case .failed(let failure):
            self = .failed(failure.resolvedMessage)
        }
    }

    init(accountAvailability: ICloudAccountAvailability?) {
        switch accountAvailability {
        case .available:
            self = .ready
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        case .couldNotDetermine, nil:
            self = .couldNotDetermine
        }
    }

    var iCloudSyncStatus: ICloudSyncStatus {
        switch self {
        case .disabled:
            return .disabled
        case .statusUnavailable,
                .checkingAccount,
                .noAccount,
                .restricted,
                .temporarilyUnavailable,
                .couldNotDetermine:
            return .statusUnavailable
        case .ready:
            return .idle
        case .syncing, .preparing, .importing, .uploading:
            return .syncing
        case .failed(let message):
            return .failed(message)
        }
    }
}

struct SettingsScreenSectionPresentation: Identifiable, Equatable, Sendable {
    let id: SettingsScreenSectionID
    let title: String
    let footer: String?
    let items: [SettingsScreenItemPresentation]
}

struct SettingsScreenViewState: Equatable, Sendable {
    let sections: [SettingsScreenSectionPresentation]
    let primaryLoadingState: SettingsScreenPrimaryLoadingState?
    let placeholder: SettingsScreenPlaceholderState?
    let opmlImportPreview: SettingsOPMLImportPreviewPresentation?
    let opmlTransferStatus: SettingsOPMLTransferStatusPresentation?
    let canApplyChanges: Bool
}

struct SettingsScreenPrimaryLoadingState: Equatable, Sendable {
    let title: String
}

struct SettingsScreenPlaceholderState: Equatable, Sendable {
    let title: String
    let systemImage: String
    let description: String?
    let actionTitle: String?
}

enum SettingsScreenItemPresentation: Identifiable, Equatable, Sendable {
    case toggle(SettingsToggleItemPresentation)
    case picker(SettingsPickerItemPresentation)
    case statusRow(SettingsStatusRowItemPresentation)
    case button(SettingsButtonItemPresentation)

    var id: SettingsScreenItemID {
        switch self {
        case .toggle(let item):
            item.id
        case .picker(let item):
            item.id
        case .statusRow(let item):
            item.id
        case .button(let item):
            item.id
        }
    }
}

struct SettingsToggleItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let isOn: Bool
}

struct SettingsPickerItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let selectedValueTitle: String
    let options: [SettingsPickerOptionPresentation]
}

struct SettingsPickerOptionPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let isSelected: Bool
}

struct SettingsStatusRowItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let valueTitle: String
}

struct SettingsButtonItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let systemImage: String
    let role: SettingsButtonItemRole
    let isEnabled: Bool
}

enum SettingsButtonItemRole: Equatable, Sendable {
    case normal
    case destructive
}

struct SettingsOPMLImportPreviewPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let plan: OPMLImportPreviewPlan

    var totalEntryCount: Int {
        plan.entries.count
    }

    var importableEntryCount: Int {
        plan.importableEntries.count
    }

    var skippedEntryCount: Int {
        plan.invalidEntryCount
    }

    var createdFolderCount: Int {
        Set(plan.importableEntries.compactMap(\.normalizedFolderName)).count
    }

    static func == (
        lhs: SettingsOPMLImportPreviewPresentation,
        rhs: SettingsOPMLImportPreviewPresentation
    ) -> Bool {
        lhs.plan == rhs.plan
    }
}

struct SettingsOPMLTransferStatusPresentation: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case success
        case failure
    }

    let id = UUID()
    let title: String
    let message: String
    let kind: Kind

    static func == (
        lhs: SettingsOPMLTransferStatusPresentation,
        rhs: SettingsOPMLTransferStatusPresentation
    ) -> Bool {
        lhs.title == rhs.title
            && lhs.message == rhs.message
            && lhs.kind == rhs.kind
    }
}

enum SettingsScreenInputBuilder {
    static func build(
        from snapshot: AppSettingsSnapshot,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        syncStatusPresentation: SettingsSyncStatusPresentation? = nil,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool = false
    ) -> SettingsScreenInput {
        let resolvedSyncStatusPresentation = syncStatusPresentation
            ?? SettingsSyncStatusPresentation(iCloudSyncStatus: iCloudSyncStatus)

        return SettingsScreenInput(
            articleOpeningMode: snapshot.articleOpeningMode,
            markAsReadOnOpen: snapshot.markAsReadOnOpen,
            articleBodyLinkOpeningPolicy: snapshot.articleBodyLinkOpeningPolicy,
            articleSourceLinkOpeningPolicy: snapshot.articleSourceLinkOpeningPolicy,
            readerAdjacentNavigationControlsMode: snapshot.readerAdjacentNavigationControlsMode,
            unreadArticleSortOrder: UnreadArticleSortOrder(
                unreadArticleSortMode: snapshot.unreadArticleSortMode
            ),
            articleRetentionPolicy: snapshot.articleRetentionPolicy,
            askBeforeMarkingAllAsRead: snapshot.askBeforeMarkingAllAsRead,
            refreshIntervalPreference: snapshot.refreshIntervalPreference,
            showUnreadCountBadge: snapshot.showUnreadCountBadge,
            useiCloudSync: snapshot.useiCloudSync,
            iCloudSyncStatus: resolvedSyncStatusPresentation.iCloudSyncStatus,
            syncStatusPresentation: resolvedSyncStatusPresentation,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: isUsingLocalOnlySyncFallbackForCurrentLaunch,
            interfaceThemeMode: snapshot.interfaceThemeMode
        )
    }
}

enum SettingsScreenPresentationBuilder {
    static func buildSections(
        from input: SettingsScreenInput,
        hasArticleImageCache: Bool = false,
        hasFeedIconCache: Bool = false,
        hasArchivedArticles: Bool = false
    ) -> [SettingsScreenSectionPresentation] {
        [
            appearanceSection(from: input),
            readingSection(from: input),
            articleListSection(from: input),
            updatesAndSyncSection(from: input),
            notificationsSection(from: input),
            sourcePortabilitySection(),
            storageSection(
                hasArticleImageCache: hasArticleImageCache,
                hasFeedIconCache: hasFeedIconCache,
                hasArchivedArticles: hasArchivedArticles
            )
        ]
    }
}
