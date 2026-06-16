import SwiftUI

enum ReadingShellCompactNavigationState {
    static func preferredCompactColumn(
        sidebarSelection: SidebarSelection?,
        articleSelection: UUID?
    ) -> NavigationSplitViewColumn {
        if articleSelection != nil {
            return .detail
        }

        if sidebarSelection != nil {
            return .content
        }

        return .sidebar
    }

    static func showsArticlesBackButton(
        horizontalSizeClass: UserInterfaceSizeClass?,
        sidebarSelection: SidebarSelection?
    ) -> Bool {
        CompactBackNavigationPolicy.showsBackButton(
            horizontalSizeClass: horizontalSizeClass,
            hasSelection: sidebarSelection != nil
        )
    }

    static func shouldNavigateBackToSidebarOnDrag(
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
        case .safari(let route):
            .article(route.articleID)
        }
    }
}
