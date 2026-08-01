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

struct ArticlesScreenCustomRefreshState: Equatable {
    enum Phase: Equatable {
        case idle
        case pulling
        case ready
        case refreshing
    }

    static let idle = ArticlesScreenCustomRefreshState(
        phase: .idle,
        pullProgress: 0
    )

    static let refreshing = ArticlesScreenCustomRefreshState(
        phase: .refreshing,
        pullProgress: 1
    )

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

    static func pulling(progress: Double) -> ArticlesScreenCustomRefreshState {
        let normalizedProgress = min(max(progress, 0), 1)

        if normalizedProgress <= 0 {
            return .idle
        }

        if normalizedProgress >= 1 {
            return ArticlesScreenCustomRefreshState(
                phase: .ready,
                pullProgress: 1
            )
        }

        return ArticlesScreenCustomRefreshState(
            phase: .pulling,
            pullProgress: normalizedProgress
        )
    }
}

struct ArticleListCustomRefreshGeometry: Equatable {
    var contentOffsetY: CGFloat
    var contentInsetTop: CGFloat

    init(
        contentOffsetY: CGFloat = 0,
        contentInsetTop: CGFloat = 0
    ) {
        self.contentOffsetY = contentOffsetY
        self.contentInsetTop = contentInsetTop
    }

    var topOverscrollDistance: CGFloat {
        max(0, -(contentOffsetY + contentInsetTop))
    }
}

enum ArticleListCustomRefreshPullPolicy {
    static let pullThreshold: CGFloat = 72

    static func progress(
        for geometry: ArticleListCustomRefreshGeometry,
        threshold: CGFloat = pullThreshold
    ) -> Double {
        guard threshold > 0 else {
            return 0
        }

        return min(Double(geometry.topOverscrollDistance / threshold), 1)
    }
}

enum ArticleListCustomRefreshReleasePolicy {
    static func shouldTriggerRefresh(
        wasInteracting: Bool,
        isInteracting: Bool,
        customRefreshState: ArticlesScreenCustomRefreshState
    ) -> Bool {
        wasInteracting && isInteracting == false && customRefreshState.phase == .ready
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

struct ArticlesScreenSubtitleResolver {
    static func resolve(
        articles: [ArticleListItemDTO],
        sidebarArticleFilter: SidebarArticleFilter,
        hasMorePages: Bool = false
    ) -> String {
        let count: Int

        switch sidebarArticleFilter {
        case .allItems, .unread:
            count = articles.filter { $0.isRead == false }.count
            if hasMorePages {
                return ReadingLocalization.unreadItemsLowerBoundSubtitle(count: count)
            }
            guard count > 0 else {
                return ReadingLocalization.noUnreadItemsSubtitle
            }
            return ReadingLocalization.unreadItemsSubtitle(count: count)
        case .starred:
            count = articles.filter(\.isStarred).count
            if hasMorePages {
                return ReadingLocalization.starredItemsLowerBoundSubtitle(count: count)
            }
            return ReadingLocalization.starredItemsSubtitle(count: count)
        }
    }
}

struct ArticlesScreenToolbarActionsState: Equatable {
    let showsSearchAction: Bool
    let showsMarkAllAsReadAction: Bool
    let isMarkAllAsReadEnabled: Bool

    init(
        selection: SidebarSelection?,
        visibleArticles: [ArticleListItemDTO],
        phase: ArticlesScreenPhase
    ) {
        let hasSelection = selection != nil
        let showsInteractiveActions = hasSelection && phase != .loading && phase.isFailed == false
        self.showsSearchAction = showsInteractiveActions
        self.showsMarkAllAsReadAction = showsInteractiveActions
        self.isMarkAllAsReadEnabled = visibleArticles.contains(where: { $0.isRead == false })
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
        self.readActionTitle = article.isRead ? ReadingLocalization.unreadAction : ReadingLocalization.readAction
        self.readActionSystemImage = article.isRead ? "circle.slash" : "circle"
        self.starActionTitle = article.isStarred ? ReadingLocalization.unstarAction : ReadingLocalization.starAction
        self.starActionSystemImage = article.isStarred ? "star.slash" : "star"
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
