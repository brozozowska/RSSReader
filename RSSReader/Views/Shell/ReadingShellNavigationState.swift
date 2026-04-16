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
        horizontalSizeClass == .compact && sourceSelection != nil
    }

    static func shouldNavigateBackToSourcesOnDrag(
        startLocationX: CGFloat,
        translation: CGSize
    ) -> Bool {
        startLocationX <= 32
            && translation.width >= 80
            && abs(translation.height) <= 48
    }
}

enum ReadingShellDetailDestination: Equatable {
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
            .article(selectedArticleID)
        case .article(let articleID):
            .article(articleID)
        case .webView(let route):
            .webView(route)
        }
    }
}
