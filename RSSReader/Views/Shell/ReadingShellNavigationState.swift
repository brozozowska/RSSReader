import SwiftUI

enum ReadingShellCompactNavigationState {
    static func preferredCompactColumn(
        sourceSelection: SidebarSelection?,
        articleSelection: UUID?
    ) -> NavigationSplitViewColumn {
        if articleSelection != nil {
            return .detail
        }

        if sourceSelection != nil {
            return .content
        }

        return .sidebar
    }

    static func showsArticlesBackButton(
        horizontalSizeClass: UserInterfaceSizeClass?,
        sourceSelection: SidebarSelection?
    ) -> Bool {
        CompactBackNavigationPolicy.showsBackButton(
            horizontalSizeClass: horizontalSizeClass,
            hasSelection: sourceSelection != nil
        )
    }

    static func shouldNavigateBackToSourcesOnDrag(
        startLocationX: CGFloat,
        translation: CGSize
    ) -> Bool {
        CompactBackNavigationPolicy.shouldNavigateBackOnDrag(
            startLocationX: startLocationX,
            translation: translation
        )
    }
}

enum ReadingShellDetailDestination: Equatable {
    case none
    case article(UUID?)
    case webView(ArticleWebViewRoute)
}

enum ReadingShellDetailNavigationState {
    static func detailDestination(
        route: ReadingDetailRoute,
        selectedArticleID: UUID?
    ) -> ReadingShellDetailDestination {
        switch route {
        case .none:
            selectedArticleID.map(ReadingShellDetailDestination.article) ?? .none
        case .article(let articleID):
            .article(articleID)
        case .webView(let route):
            .webView(route)
        }
    }
}
