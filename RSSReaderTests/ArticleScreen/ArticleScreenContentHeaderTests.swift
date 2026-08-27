import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Article Screen / Content Rendering / Header")
@MainActor
struct ArticleScreenContentHeaderTests {
    @Test
    func articleScreenContentHeaderPrefersPublishedDateAndFormatsMetadata() {
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                feedTitle: "THECODE.MEDIA",
                author: "Юлия Зубарева",
                publishedAt: publishedAt,
                updatedAtSource: Date(timeIntervalSince1970: 1_800_000_000),
                fetchedAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )

        #expect(content.header.effectiveDateText == ArticleScreenDateFormatter.string(from: publishedAt))
        #expect(content.header.title == "Article")
        #expect(content.header.author == "Юлия Зубарева")
        #expect(content.header.feedTitle == "THECODE.MEDIA")
    }

    @Test
    func articleScreenContentHeaderUsesUpdatedThenFetchedFallbackAndNormalizesMetadata() {
        let updatedAtSource = Date(timeIntervalSince1970: 1_700_000_100)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                feedTitle: "   ",
                title: "   ",
                author: " \n ",
                publishedAt: nil,
                updatedAtSource: updatedAtSource,
                fetchedAt: fetchedAt
            )
        )
        let undatedContent = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                publishedAt: nil,
                updatedAtSource: nil,
                fetchedAt: fetchedAt
            )
        )

        #expect(content.header.effectiveDateText == ArticleScreenDateFormatter.string(from: updatedAtSource))
        #expect(undatedContent.header.effectiveDateText == ArticleScreenDateFormatter.string(from: fetchedAt))
        #expect(content.header.title == ReadingLocalization.untitledArticleTitle)
        #expect(content.header.author == nil)
        #expect(content.header.feedTitle == nil)
    }

    @Test
    func articleScreenStateUsesExistingRenderingPriorityForBodyContent() {
        var state = ArticleScreenState()
        let article = makeReaderArticleDTO(
            summary: "Summary copy",
            contentHTML: "<p>HTML body</p>",
            contentText: "Longer content text"
        )

        state.applyLoadedArticle(article)

        #expect(state.derivedViewState().content?.body.blocks == [.paragraph(.plainText("HTML body"))])
        #expect(state.derivedViewState().content?.body.source == .contentHTML)
    }
}
