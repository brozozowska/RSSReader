import Foundation

@MainActor
struct ArticleScreenState {
    private(set) var articleID: UUID?
    private(set) var article: ReaderArticleDTO?
    private(set) var phase: ArticleScreenPhase = .noSelection
    private(set) var toolbarActions = ArticleScreenToolbarActionsState(article: nil)

    var placeholder: ArticleScreenPlaceholderState? {
        switch phase {
        case .noSelection:
            ArticleScreenPlaceholderState(
                title: ReadingLocalization.noArticleSelectedTitle,
                systemImage: "doc.text",
                description: nil
            )
        case .loading, .loaded:
            nil
        case .notFound:
            ArticleScreenPlaceholderState(
                title: ReadingLocalization.articleNotFoundTitle,
                systemImage: "doc.text.magnifyingglass",
                description: ReadingLocalization.articleNotFoundDescription
            )
        case .failed(let message):
            ArticleScreenPlaceholderState(
                title: ReadingLocalization.failedToLoadArticleTitle,
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

    mutating func beginLoading(
        articleID: UUID?,
        preservesCurrentArticle: Bool = false
    ) {
        self.articleID = articleID

        guard articleID != nil else {
            article = nil
            phase = .noSelection
            updateToolbarActions()
            return
        }

        if preservesCurrentArticle == false {
            article = nil
        }
        phase = .loading
        updateToolbarActions()
    }

    mutating func applyLoadedArticle(_ article: ReaderArticleDTO) {
        articleID = article.id
        self.article = article
        phase = .loaded
        updateToolbarActions()
    }

    mutating func applyArticleMutation(_ article: ReaderArticleDTO) {
        articleID = article.id
        self.article = article
        if phase != .loading && phase != .noSelection {
            phase = .loaded
        }
        updateToolbarActions()
    }

    mutating func applyArticleNotFound(articleID: UUID?) {
        self.articleID = articleID
        article = nil
        phase = articleID == nil ? .noSelection : .notFound
        updateToolbarActions()
    }

    mutating func applyLoadingFailure(_ message: String, articleID: UUID?) {
        self.articleID = articleID
        article = nil
        phase = articleID == nil ? .noSelection : .failed(message)
        updateToolbarActions()
    }

    func derivedViewState(
        selectedArticleID: UUID?,
        preservesStaleContent: Bool = false,
        preservedStaleArticleID: UUID? = nil
    ) -> ArticleScreenDerivedViewState {
        let isSelectedArticleLoaded = article?.id == selectedArticleID
        let canPreserveStaleArticle = preservesStaleContent
            && (preservedStaleArticleID == nil || article?.id == preservedStaleArticleID)
        let resolvedArticle = isSelectedArticleLoaded || canPreserveStaleArticle ? article : nil
        let showsStaleArticle = article != nil && resolvedArticle == nil && selectedArticleID != nil
        let resolvedPrimaryLoadingState = primaryLoadingState
            ?? (showsStaleArticle ? ArticleScreenPrimaryLoadingState(title: ReadingLocalization.loadingArticleTitle) : nil)

        return ArticleScreenDerivedViewState(
            primaryLoadingState: resolvedPrimaryLoadingState,
            placeholder: placeholder,
            content: resolvedArticle.map(ArticleScreenContentState.init(article:)),
            toolbarActions: ArticleScreenToolbarActionsState(article: resolvedArticle)
        )
    }

    func derivedViewState() -> ArticleScreenDerivedViewState {
        derivedViewState(selectedArticleID: articleID)
    }

    private mutating func updateToolbarActions() {
        toolbarActions = ArticleScreenToolbarActionsState(article: article)
    }

    private var primaryLoadingState: ArticleScreenPrimaryLoadingState? {
        guard showsPrimaryLoadingIndicator else {
            return nil
        }

        return ArticleScreenPrimaryLoadingState(title: ReadingLocalization.loadingArticleTitle)
    }
}

extension ArticleScreenState {
    static func previewLoading(articleID: UUID = UUID()) -> ArticleScreenState {
        var state = ArticleScreenState()
        state.beginLoading(articleID: articleID)
        return state
    }

    static func previewFailed(
        articleID: UUID = UUID(),
        message: String
    ) -> ArticleScreenState {
        var state = ArticleScreenState()
        state.applyLoadingFailure(message, articleID: articleID)
        return state
    }

    static func previewNotFound(articleID: UUID = UUID()) -> ArticleScreenState {
        var state = ArticleScreenState()
        state.applyArticleNotFound(articleID: articleID)
        return state
    }

    static func previewLoaded(article: ReaderArticleDTO) -> ArticleScreenState {
        var state = ArticleScreenState()
        state.applyLoadedArticle(article)
        return state
    }
}
