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
enum ArticleScreenBodySource: Equatable {
    case summary
    case contentText
    case contentHTML
    case empty
}

@MainActor
struct ArticleScreenBodyContentState: Equatable {
    let blocks: [ArticleScreenBodyBlock]
    let source: ArticleScreenBodySource

    init(
        blocks: [ArticleScreenBodyBlock],
        source: ArticleScreenBodySource
    ) {
        self.blocks = blocks
        self.source = source
    }
}

@MainActor
struct ArticleScreenContentState: Equatable {
    let articleID: UUID
    let header: ArticleScreenHeaderState
    let body: ArticleScreenBodyContentState

    init(article: ReaderArticleDTO) {
        self.articleID = article.id
        self.header = ArticleScreenHeaderState(article: article)
        self.body = ArticleScreenContentRenderer.renderBody(for: article)
    }
}

@MainActor
struct ArticleScreenHeaderState: Equatable {
    let publishedAtText: String?
    let title: String
    let author: String?
    let feedTitle: String?
    let canOpenSourceArticle: Bool

    init(article: ReaderArticleDTO) {
        self.publishedAtText = article.publishedAt.map(ArticleScreenDateFormatter.string(from:))
        self.title = article.title.nilIfBlank ?? "Untitled Article"
        self.author = article.author?.nilIfBlank
        self.feedTitle = article.feedTitle.nilIfBlank
        self.canOpenSourceArticle = ArticleScreenURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        ) != nil
    }
}

@MainActor
struct ArticleScreenBottomActionsState: Equatable {
    let readToggleTitle: String
    let readToggleSystemImage: String
    let starTitle: String
    let starSystemImage: String
    let openSourceArticleTitle: String
    let openSourceArticleSystemImage: String
    let canOpenSourceArticle: Bool

    init(article: ReaderArticleDTO) {
        self.readToggleTitle = article.isRead ? "Mark Unread" : "Mark Read"
        self.readToggleSystemImage = article.isRead ? "circle.slash" : "circle"
        self.starTitle = article.isStarred ? "Unstar" : "Star"
        self.starSystemImage = article.isStarred ? "star.slash" : "star"
        self.openSourceArticleTitle = "Open Source Article"
        self.openSourceArticleSystemImage = "safari"
        self.canOpenSourceArticle = ArticleScreenURLResolver.resolveExternalURL(
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
        ArticleScreenURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        )
    }
}

enum ArticleScreenURLResolver {
    static func resolveExternalURL(canonicalURL: String?, articleURL: String) -> URL? {
        if let canonicalURL, let resolvedCanonicalURL = validatedExternalURL(from: canonicalURL) {
            return resolvedCanonicalURL
        }

        return validatedExternalURL(from: articleURL)
    }

    static func resolveArticleBodyLinkURL(rawValue: String, baseURLString: String?) -> URL? {
        resolveMediaURL(rawValue: rawValue, baseURLString: baseURLString)
    }

    static func resolveMediaURL(rawValue: String, baseURLString: String?) -> URL? {
        if let validatedURL = validatedExternalURL(from: rawValue) {
            return validatedURL
        }

        guard
            let normalizedValue = rawValue.nilIfBlank,
            let baseURLString,
            let baseURL = validatedExternalURL(from: baseURLString),
            let relativeURL = URL(string: normalizedValue, relativeTo: baseURL)?.absoluteURL,
            let components = URLComponents(url: relativeURL, resolvingAgainstBaseURL: true),
            let scheme = components.scheme?.lowercased(),
            let host = components.host,
            host.isEmpty == false,
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return relativeURL
    }

    private static func validatedExternalURL(from rawValue: String) -> URL? {
        guard
            let normalizedValue = rawValue.nilIfBlank,
            let components = URLComponents(string: normalizedValue),
            let scheme = components.scheme?.lowercased(),
            let host = components.host,
            host.isEmpty == false,
            ["http", "https"].contains(scheme),
            let url = components.url
        else {
            return nil
        }

        return url
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
