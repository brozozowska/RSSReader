import Foundation

@MainActor
struct ArticleScreenState {
    private(set) var articleID: UUID?
    private(set) var article: ReaderArticleDTO?
    private(set) var phase: ArticleScreenPhase = .noSelection
    private(set) var toolbarActions = ArticleScreenToolbarActionsState(article: nil)
    var pendingShareSheet: ArticleScreenShareSheetState?

    var placeholder: ArticleScreenPlaceholderState? {
        switch phase {
        case .noSelection:
            ArticleScreenPlaceholderState(
                title: "No Article Selected",
                systemImage: "doc.text",
                description: nil
            )
        case .loading, .loaded:
            nil
        case .notFound:
            ArticleScreenPlaceholderState(
                title: "Article Not Found",
                systemImage: "doc.text.magnifyingglass",
                description: "The selected article could not be loaded from persistence."
            )
        case .failed(let message):
            ArticleScreenPlaceholderState(
                title: "Failed to Load Article",
                systemImage: "exclamationmark.triangle",
                description: message
            )
        }
    }

    var showsPrimaryLoadingIndicator: Bool {
        phase == .loading && article == nil
    }

    var primaryFailureMessage: String? {
        guard case .failed(let message) = phase else {
            return nil
        }

        return message
    }

    mutating func beginLoading(articleID: UUID?) {
        self.articleID = articleID
        pendingShareSheet = nil

        guard articleID != nil else {
            article = nil
            phase = .noSelection
            updateToolbarActions()
            return
        }

        article = nil
        phase = .loading
        updateToolbarActions()
    }

    mutating func applyLoadedArticle(_ article: ReaderArticleDTO) {
        articleID = article.id
        self.article = article
        phase = .loaded
        pendingShareSheet = nil
        updateToolbarActions()
    }

    mutating func applyArticleNotFound(articleID: UUID?) {
        self.articleID = articleID
        article = nil
        phase = articleID == nil ? .noSelection : .notFound
        pendingShareSheet = nil
        updateToolbarActions()
    }

    mutating func applyLoadingFailure(_ message: String, articleID: UUID?) {
        self.articleID = articleID
        article = nil
        phase = articleID == nil ? .noSelection : .failed(message)
        pendingShareSheet = nil
        updateToolbarActions()
    }

    mutating func presentShareSheet() {
        pendingShareSheet = article.flatMap(ArticleScreenShareSheetState.init(article:))
    }

    mutating func dismissShareSheet() {
        pendingShareSheet = nil
    }

    func derivedViewState() -> ArticleScreenDerivedViewState {
        ArticleScreenDerivedViewState(
            placeholder: placeholder,
            content: article.map(ArticleScreenContentState.init(article:)),
            toolbarActions: toolbarActions
        )
    }

    private mutating func updateToolbarActions() {
        toolbarActions = ArticleScreenToolbarActionsState(article: article)
    }
}

extension ArticleScreenState {
    static func previewLoaded(article: ReaderArticleDTO) -> ArticleScreenState {
        var state = ArticleScreenState()
        state.applyLoadedArticle(article)
        return state
    }
}
