import SwiftUI

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
