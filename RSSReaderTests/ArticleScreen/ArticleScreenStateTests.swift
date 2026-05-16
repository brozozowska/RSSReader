import Foundation
import Testing
@testable import RSSReader

@Suite("Article Screen / State")
@MainActor
struct ArticleScreenStateTests {
    @Test
    func articleScreenStateStartsWithNoSelectionPlaceholder() {
        let state = ArticleScreenState()
        let viewState = state.derivedViewState()

        #expect(state.phase == .noSelection)
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder?.title == "No Article Selected")
        #expect(viewState.toolbarActions.showsShareAction == false)
        #expect(viewState.toolbarActions.showsBottomActions == false)
    }

    @Test
    func articleScreenStateExposesPrimaryLoadingStateThroughDerivedViewState() {
        var state = ArticleScreenState()

        state.beginLoading(articleID: UUID())

        let viewState = state.derivedViewState()

        #expect(state.phase == .loading)
        #expect(viewState.primaryLoadingState?.title == "Loading Article")
        #expect(viewState.content == nil)
        #expect(viewState.placeholder == nil)
    }

    @Test
    func articleScreenStateBuildsLoadedContentAndToolbarActions() {
        var state = ArticleScreenState()
        let article = makeReaderArticleDTO(
            summary: nil,
            contentText: "Rendered body text",
            isRead: true,
            isStarred: true
        )

        state.applyLoadedArticle(article)
        let viewState = state.derivedViewState()

        #expect(state.phase == .loaded)
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.content?.header.title == article.title)
        #expect(viewState.content?.header.feedTitle == article.feedTitle)
        #expect(viewState.content?.header.author == article.author)
        #expect(viewState.content?.body.blocks == [.paragraph(.plainText("Rendered body text"))])
        #expect(viewState.content?.body.source == .contentText)
        #expect(viewState.content?.body.readerMode == .embedded)
        #expect(viewState.toolbarActions.showsShareAction)
        #expect(viewState.toolbarActions.isShareEnabled)
        #expect(viewState.toolbarActions.showsBottomActions)
        #expect(viewState.toolbarActions.bottomActions?.readToggleTitle == "Mark Unread")
        #expect(viewState.toolbarActions.bottomActions?.readToggleSystemImage == "circle.slash")
        #expect(viewState.toolbarActions.bottomActions?.starTitle == "Unstar")
        #expect(viewState.toolbarActions.bottomActions?.starSystemImage == "star.slash")
    }

    @Test
    func articleScreenStateHidesStaleContentForDifferentSelectedArticleID() {
        var state = ArticleScreenState()
        let article = makeReaderArticleDTO(title: "Stale Article")

        state.applyLoadedArticle(article)
        let viewState = state.derivedViewState(selectedArticleID: UUID())

        #expect(viewState.content == nil)
        #expect(viewState.primaryLoadingState?.title == "Loading Article")
        #expect(viewState.toolbarActions.showsShareAction == false)
        #expect(viewState.toolbarActions.showsBottomActions == false)
    }

    @Test
    func articleScreenToolbarActionsExposeShareURLOnlyWhenArticleHasValidURL() {
        var loadedState = ArticleScreenState()
        loadedState.applyLoadedArticle(
            makeReaderArticleDTO(
                canonicalURL: "https://example.com/articles/shared"
            )
        )
        let loadedToolbarActions = loadedState.derivedViewState().toolbarActions
        #expect(loadedToolbarActions.isShareEnabled)
        #expect(loadedToolbarActions.shareURL?.absoluteString == "https://example.com/articles/shared")

        var invalidURLState = ArticleScreenState()
        invalidURLState.applyLoadedArticle(
            makeReaderArticleDTO(
                articleURL: "not a valid url",
                canonicalURL: nil
            )
        )
        let invalidToolbarActions = invalidURLState.derivedViewState().toolbarActions
        #expect(invalidToolbarActions.isShareEnabled == false)
        #expect(invalidToolbarActions.shareURL == nil)
    }

    @Test
    func articleScreenBottomActionsEnableAppBrowserOnlyWhenArticleHasValidExternalURL() {
        var loadedState = ArticleScreenState()
        loadedState.applyLoadedArticle(
            makeReaderArticleDTO(
                canonicalURL: "https://example.com/articles/openable"
            )
        )

        let loadedBottomActions = loadedState.derivedViewState().toolbarActions.bottomActions
        #expect(loadedBottomActions?.openSourceArticleTitle == "Open Source Article")
        #expect(loadedBottomActions?.openSourceArticleSystemImage == "safari")
        #expect(loadedBottomActions?.canOpenSourceArticle == true)

        var invalidURLState = ArticleScreenState()
        invalidURLState.applyLoadedArticle(
            makeReaderArticleDTO(
                articleURL: "invalid-url",
                canonicalURL: nil
            )
        )

        let invalidBottomActions = invalidURLState.derivedViewState().toolbarActions.bottomActions
        #expect(invalidBottomActions?.canOpenSourceArticle == false)
    }
}
