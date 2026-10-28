import Foundation
import CoreGraphics
import SwiftUI

enum ArticlesScreenPhase: Equatable {
    case noSelection
    case loading
    case loaded
    case empty
    case failed(String)
}

enum ArticlesScreenEmptyContentKind: Equatable {
    case selection
    case searchResults
}

enum ArticlesScreenRefreshState: Equatable {
    case idle
    case refreshing
}

struct ArticleListPaginationGeometry: Equatable {
    var contentHeight: CGFloat
    var visibleMaxY: CGFloat

    init(
        contentHeight: CGFloat = 0,
        visibleMaxY: CGFloat = 0
    ) {
        self.contentHeight = contentHeight
        self.visibleMaxY = visibleMaxY
    }

    var distanceToEnd: CGFloat {
        max(0, contentHeight - visibleMaxY)
    }
}

enum ArticleListPaginationPrefetchPolicy {
    static let distanceThreshold: CGFloat = 1_200

    static func shouldRequestNextPage(
        geometry: ArticleListPaginationGeometry,
        hasUserDrivenScrollDemand: Bool,
        canLoadNextPage: Bool,
        isRefreshInteractionActive: Bool = false,
        threshold: CGFloat = distanceThreshold
    ) -> Bool {
        hasUserDrivenScrollDemand
            && isRefreshInteractionActive == false
            && canLoadNextPage
            && threshold >= 0
            && geometry.contentHeight > 0
            && geometry.distanceToEnd <= threshold
    }
}

enum ArticlesScreenConfirmationDialog: Equatable {
    case markAllAsRead
}

struct ArticlesScreenPlaceholderState: Equatable {
    let title: String
    let systemImage: String
    let description: String?
}

struct ArticlesScreenRefreshFeedback: Equatable {
    let message: String
}

struct ArticlesScreenNavigationTitleResolver {
    static func resolve(
        selection: SidebarSelection?,
        selectedFeedTitle: String? = nil
    ) -> String {
        switch selection {
        case .none:
            ReadingLocalization.articlesTitle
        case .inbox:
            ReadingLocalization.allItemsTitle
        case .unread:
            ReadingLocalization.unreadTitle
        case .starred:
            ReadingLocalization.starredTitle
        case .folder(let folderName):
            folderName
        case .feed:
            selectedFeedTitle ?? ReadingLocalization.feedFallbackTitle
        }
    }
}

struct ArticlesScreenNavigationChromeState: Equatable {
    let sessionContext: ArticleListSession.Context
    let title: String
    let subtitle: String
}

struct ArticleListAnimationState: Equatable {
    enum ChangeKind: Equatable {
        case snapshotReplacement
        case localMutation
        case searchTransition
    }

    private(set) var revision: UInt = 0
    private(set) var changeKind: ChangeKind = .snapshotReplacement

    func allowsAnimation(reduceMotion: Bool) -> Bool {
        reduceMotion == false && changeKind != .snapshotReplacement
    }

    func animation(reduceMotion: Bool) -> Animation? {
        allowsAnimation(reduceMotion: reduceMotion) ? .snappy(duration: 0.24) : nil
    }

    mutating func prepareForSnapshotReplacement() {
        revision &+= 1
        changeKind = .snapshotReplacement
    }

    mutating func prepareForSearchTransition() {
        revision &+= 1
        changeKind = .searchTransition
    }

    mutating func prepareForLocalMutation() {
        revision &+= 1
        changeKind = .localMutation
    }
}

struct ArticlesScreenSubtitleResolver {
    static func resolve(
        articles: [ArticleListItemDTO],
        sidebarArticleFilter: SidebarArticleFilter,
        scopeMetric: ArticleScopeMetric? = nil
    ) -> String {
        if let scopeMetric {
            switch scopeMetric.kind {
            case .unread:
                guard scopeMetric.count > 0 else {
                    return ReadingLocalization.noUnreadItemsSubtitle
                }
                return ReadingLocalization.unreadItemsSubtitle(count: scopeMetric.count)
            case .starred:
                return ReadingLocalization.starredItemsSubtitle(count: scopeMetric.count)
            }
        }

        switch sidebarArticleFilter {
        case .allItems, .unread:
            let count = articles.filter { $0.isRead == false && $0.isHidden == false }.count
            guard count > 0 else {
                return ReadingLocalization.noUnreadItemsSubtitle
            }
            return ReadingLocalization.unreadItemsSubtitle(count: count)
        case .starred:
            let count = articles.filter { $0.isStarred && $0.isHidden == false }.count
            return ReadingLocalization.starredItemsSubtitle(count: count)
        }
    }
}

struct ArticlesScreenToolbarActionsState: Equatable {
    let showsMarkAllAsReadAction: Bool
    let isMarkAllAsReadEnabled: Bool

    init(
        selection: SidebarSelection?,
        visibleArticles: [ArticleListItemDTO],
        phase: ArticlesScreenPhase,
        allowsMutations: Bool = true
    ) {
        let hasSelection = selection != nil
        self.showsMarkAllAsReadAction = hasSelection && phase != .loading && phase.isFailed == false
        self.isMarkAllAsReadEnabled = allowsMutations && visibleArticles.contains(where: { $0.isRead == false })
    }
}

struct ArticleListSearchLifecycleState: Equatable {
    let keepsSearchUIAttached: Bool
    let allowsQueryLoad: Bool

    init(
        retainedSelection: SidebarSelection?,
        presentedSelection: SidebarSelection?
    ) {
        self.keepsSearchUIAttached = retainedSelection != nil
        self.allowsQueryLoad = presentedSelection != nil
    }
}

struct ArticlesScreenPrimaryLoadingState: Equatable {
    let title: String
}

struct ArticlesScreenRefreshBannerState: Equatable {
    enum Style: Equatable {
        case refreshing
        case failed
    }

    let style: Style
    let title: String
    let message: String

    var showsActivityIndicator: Bool {
        style == .refreshing
    }

    var showsRetryAction: Bool {
        style == .failed
    }

    var showsDismissAction: Bool {
        style == .failed
    }
}

struct ArticleRowSwipeActionsState: Equatable {
    static let readStatusEdge: HorizontalEdge = .leading
    static let starredStatusEdge: HorizontalEdge = .trailing

    let readActionTitle: String
    let readActionSystemImage: String
    let starActionTitle: String
    let starActionSystemImage: String

    init(article: ArticleListItemDTO) {
        self.readActionTitle = article.isRead ? ReadingLocalization.markUnreadAction : ReadingLocalization.markReadAction
        self.readActionSystemImage = ArticleStateSymbols.read(isRead: article.isRead)
        self.starActionTitle = article.isStarred ? ReadingLocalization.unstarAction : ReadingLocalization.starAction
        self.starActionSystemImage = ArticleStateSymbols.starred(isStarred: article.isStarred)
    }
}

struct ArticleListRowContent: Equatable {
    let titleText: String
    let previewText: String?

    init(article: ArticleListItemDTO) {
        let titleText = article.title.nilIfBlank ?? ReadingLocalization.untitledArticleTitle
        let previewText = ArticleListRowPreviewNormalizer.normalizedPreview(from: article.summary)

        self.titleText = titleText
        self.previewText = previewText == titleText ? nil : previewText
    }
}

private enum ArticleListRowPreviewNormalizer {
    static func normalizedPreview(from rawValue: String?) -> String? {
        guard let payload = ArticleScreenBodyPayloadNormalizer.normalize(
            rawValue,
            preferredKind: .plainText
        ) else {
            return nil
        }

        let normalizedValue: String
        switch payload.kind {
        case .plainText:
            normalizedValue = payload.value
        case .html:
            normalizedValue = stripHTML(payload.value)
        }

        return normalizedValue
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</?(p|div|section|article|blockquote|ul|ol|li|h[1-6]|pre|figure|figcaption|table|tbody|thead|tr|td|th)\b[^>]*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            .decodingHTMLEntitiesForArticleListPreview()
    }
}

private extension ArticlesScreenPhase {
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    func decodingHTMLEntitiesForArticleListPreview() -> String {
        ArticleScreenBodyPayloadNormalizer.decodeHTMLEntities(in: self)
    }
}
