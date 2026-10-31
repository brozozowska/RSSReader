import Foundation

@MainActor
enum ArticleScreenPhase: Equatable {
    case noSelection
    case loading
    case loaded
    case notFound
    case failed(String)
}

@MainActor
struct ArticleScreenPlaceholderState: Equatable {
    let title: String
    let systemImage: String
    let description: String?
}

@MainActor
struct ArticleScreenContentState: Equatable {
    let articleID: UUID
    let header: ArticleScreenHeaderState
    let body: ArticleContent

    init(article: ReaderArticleDTO) {
        self.articleID = article.id
        self.header = ArticleScreenHeaderState(article: article)
        self.body = ArticleContentParser.renderBody(for: article)
    }
}

@MainActor
struct ArticleScreenHeaderState: Equatable {
    let effectiveDateText: String
    let title: String
    let author: String?
    let feedTitle: String?
    let canOpenSourceArticle: Bool

    init(article: ReaderArticleDTO) {
        self.effectiveDateText = ArticleScreenDateFormatter.string(from: article.effectiveDate)
        self.title = article.title.nilIfBlank ?? ReadingLocalization.untitledArticleTitle
        self.author = ReaderArticleMetadataPolicy.author(article.author, feedTitle: article.feedTitle)
        self.feedTitle = article.feedTitle.nilIfBlank
        self.canOpenSourceArticle = ArticleContentURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        ) != nil
    }
}

@MainActor
struct ArticleScreenBottomActionsState: Equatable {
    let readToggleTitle: String
    let readToggleSystemImage: String
    let readAccessibilityValue: String
    let starTitle: String
    let starSystemImage: String
    let starAccessibilityValue: String
    let openSourceArticleTitle: String
    let openSourceArticleSystemImage: String
    let canOpenSourceArticle: Bool

    init(article: ReaderArticleDTO) {
        self.readToggleTitle = article.isRead ? ReadingLocalization.markUnreadAction : ReadingLocalization.markReadAction
        self.readToggleSystemImage = ArticleStateSymbols.read(isRead: article.isRead)
        self.readAccessibilityValue = article.isRead ? ReadingLocalization.readState : ReadingLocalization.unreadState
        self.starTitle = article.isStarred ? ReadingLocalization.unstarAction : ReadingLocalization.starAction
        self.starSystemImage = ArticleStateSymbols.starred(isStarred: article.isStarred)
        self.starAccessibilityValue = article.isStarred ? ReadingLocalization.starredState : ReadingLocalization.unstarredState
        self.openSourceArticleTitle = ReadingLocalization.openSourceArticleAction
        self.openSourceArticleSystemImage = "safari"
        self.canOpenSourceArticle = ArticleContentURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        ) != nil
    }
}

@MainActor
struct ArticleScreenToolbarActionsState: Equatable {
    let showsShareAction: Bool
    let showsBottomActions: Bool
    let isShareEnabled: Bool
    let shareURL: URL?
    let bottomActions: ArticleScreenBottomActionsState?

    init(article: ReaderArticleDTO?) {
        let hasArticle = article != nil
        let shareURL = article.flatMap(ArticleScreenShareURLResolver.resolveShareURL(article:))
        self.showsShareAction = hasArticle
        self.showsBottomActions = hasArticle
        self.isShareEnabled = shareURL != nil
        self.shareURL = shareURL
        self.bottomActions = article.map(ArticleScreenBottomActionsState.init(article:))
    }
}

@MainActor
struct ArticleScreenPrimaryLoadingState: Equatable {
    let title: String
}

@MainActor
struct ArticleScreenDerivedViewState: Equatable {
    let primaryLoadingState: ArticleScreenPrimaryLoadingState?
    let placeholder: ArticleScreenPlaceholderState?
    let content: ArticleScreenContentState?
    let toolbarActions: ArticleScreenToolbarActionsState
}

@MainActor
enum ArticleScreenDateFormatter {
    private static let formatter = Date.FormatStyle()
        .weekday(.wide)
        .day()
        .month(.wide)
        .year()
        .hour()
        .minute()

    static func string(from date: Date) -> String {
        date.formatted(formatter)
    }
}

enum ArticleScreenShareURLResolver {
    static func resolveShareURL(article: ReaderArticleDTO) -> URL? {
        ArticleContentURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
