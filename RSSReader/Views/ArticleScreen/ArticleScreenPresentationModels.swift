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
    let text: String?
    let source: ArticleScreenBodySource

    init(article: ReaderArticleDTO) {
        if let summary = article.summary?.nilIfBlank {
            self.text = summary
            self.source = .summary
        } else if let contentText = article.contentText?.nilIfBlank {
            self.text = contentText
            self.source = .contentText
        } else if let contentHTML = article.contentHTML?.nilIfBlank {
            self.text = contentHTML
            self.source = .contentHTML
        } else {
            self.text = nil
            self.source = .empty
        }
    }
}

@MainActor
struct ArticleScreenContentState: Equatable {
    let title: String
    let feedTitle: String
    let author: String?
    let publishedAtText: String?
    let body: ArticleScreenBodyContentState

    init(article: ReaderArticleDTO) {
        self.title = article.title
        self.feedTitle = article.feedTitle
        self.author = article.author?.nilIfBlank
        self.publishedAtText = article.publishedAt.map(ArticleScreenDateFormatter.string(from:))
        self.body = ArticleScreenBodyContentState(article: article)
    }
}

@MainActor
struct ArticleScreenMenuActionsState: Equatable {
    let starActionTitle: String
    let starActionSystemImage: String
    let readActionTitle: String
    let readActionSystemImage: String
    let canOpenInAppBrowser: Bool

    init(article: ReaderArticleDTO) {
        self.starActionTitle = article.isStarred ? "Unstar" : "Star"
        self.starActionSystemImage = article.isStarred ? "star.slash" : "star"
        self.readActionTitle = article.isRead ? "Mark Unread" : "Mark Read"
        self.readActionSystemImage = article.isRead ? "envelope.badge" : "envelope.open"
        self.canOpenInAppBrowser = ArticleScreenURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        ) != nil
    }
}

@MainActor
struct ArticleScreenToolbarActionsState: Equatable {
    let showsShareAction: Bool
    let showsMenuAction: Bool
    let isShareEnabled: Bool
    let isMenuEnabled: Bool
    let menuActions: ArticleScreenMenuActionsState?

    init(article: ReaderArticleDTO?) {
        let hasArticle = article != nil
        self.showsShareAction = hasArticle
        self.showsMenuAction = hasArticle
        self.isShareEnabled = article.flatMap(ArticleScreenShareSheetState.init(article:)) != nil
        self.isMenuEnabled = hasArticle
        self.menuActions = article.map(ArticleScreenMenuActionsState.init(article:))
    }
}

@MainActor
struct ArticleScreenShareSheetState: Equatable {
    let articleID: UUID
    let url: URL

    init?(article: ReaderArticleDTO) {
        guard let url = ArticleScreenURLResolver.resolveExternalURL(
            canonicalURL: article.canonicalURL,
            articleURL: article.articleURL
        ) else {
            return nil
        }

        self.articleID = article.id
        self.url = url
    }
}

@MainActor
struct ArticleScreenDerivedViewState: Equatable {
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

enum ArticleScreenURLResolver {
    static func resolveExternalURL(canonicalURL: String?, articleURL: String) -> URL? {
        if let canonicalURL, let resolvedCanonicalURL = validatedExternalURL(from: canonicalURL) {
            return resolvedCanonicalURL
        }

        return validatedExternalURL(from: articleURL)
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
