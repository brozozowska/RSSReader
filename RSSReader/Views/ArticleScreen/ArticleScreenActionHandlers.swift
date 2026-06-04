import Foundation

struct ArticleScreenActionHandlers {
    let toggleReadStatus: () -> Void
    let toggleStarredStatus: () -> Void
    let openSourceArticle: () -> Void
    let bodyLinkTapped: (URL) -> Void
}
