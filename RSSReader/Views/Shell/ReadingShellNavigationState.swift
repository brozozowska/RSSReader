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
        containerWidth: CGFloat,
        layoutDirection: LayoutDirection,
        translation: CGSize
    ) -> Bool {
        CompactBackNavigationPolicy.shouldNavigateBackOnDrag(
            startLocationX: startLocationX,
            containerWidth: containerWidth,
            layoutDirection: layoutDirection,
            translation: translation
        )
    }
}

enum ReadingShellTransitionAnimation {
    static let screen: Animation = .snappy(duration: 0.32)
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
        case .safari(let route, let dismissalTarget):
            switch dismissalTarget {
            case .article:
                .article(route.articleID)
            case .articleList:
                .none
            }
        }
    }
}
