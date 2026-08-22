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

struct ReadingShellSafariDismissalTransition: Equatable {
    let sourceRoute: ReadingDetailRoute
    let safariRoute: ArticleSafariRoute
    let dismissalTarget: ArticleSafariDismissalTarget
    let destination: ReadingShellDetailDestination
    var progress: CGFloat
}

struct ReadingShellSafariDismissalInteractionState: Equatable {
    private(set) var transition: ReadingShellSafariDismissalTransition?

    var retainedSafariRoute: ArticleSafariRoute? {
        transition?.safariRoute
    }

    var progress: CGFloat {
        transition?.progress ?? 0
    }

    mutating func update(
        sourceRoute: ReadingDetailRoute,
        selectedArticleID: UUID?,
        progress: CGFloat
    ) {
        guard let resolvedTransition = Self.transition(
            sourceRoute: sourceRoute,
            selectedArticleID: selectedArticleID,
            progress: progress
        ) else {
            return
        }

        transition = resolvedTransition
    }

    mutating func cancel() {
        transition = nil
    }

    mutating func prepareCommit(
        sourceRoute: ReadingDetailRoute,
        selectedArticleID: UUID?
    ) -> ReadingShellSafariDismissalTransition? {
        if let transition,
           transition.sourceRoute == sourceRoute {
            return transition
        }

        guard let resolvedTransition = Self.transition(
            sourceRoute: sourceRoute,
            selectedArticleID: selectedArticleID,
            progress: 0
        ) else {
            return nil
        }
        transition = resolvedTransition
        return resolvedTransition
    }

    mutating func finish(
        _ committedTransition: ReadingShellSafariDismissalTransition
    ) {
        guard transition?.sourceRoute == committedTransition.sourceRoute else {
            return
        }
        transition?.progress = 1
    }

    mutating func complete(
        _ committedTransition: ReadingShellSafariDismissalTransition
    ) {
        guard transition?.sourceRoute == committedTransition.sourceRoute,
              transition?.progress == 1 else {
            return
        }
        transition = nil
    }

    private static func transition(
        sourceRoute: ReadingDetailRoute,
        selectedArticleID: UUID?,
        progress: CGFloat
    ) -> ReadingShellSafariDismissalTransition? {
        guard case .safari(let safariRoute, let dismissalTarget) = sourceRoute else {
            return nil
        }

        return ReadingShellSafariDismissalTransition(
            sourceRoute: sourceRoute,
            safariRoute: safariRoute,
            dismissalTarget: dismissalTarget,
            destination: ReadingShellDetailNavigationState.detailDestination(
                route: sourceRoute,
                selectedArticleID: selectedArticleID
            ),
            progress: min(max(progress, 0), 1)
        )
    }
}
