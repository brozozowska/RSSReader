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

    @Test(arguments: [
        "Apple Newsroom",
        "apple newsroom",
        " \n APPLE\t  Newsroom \n ",
        "Apple\u{00A0}Newsroom",
        "Apple\u{2003}Newsroom"
    ])
    func headerSuppressesDuplicateAuthorWithoutChangingArticle(author: String) {
        let article = makeReaderArticleDTO(feedTitle: "Apple Newsroom", author: author)
        let content = ArticleScreenContentState(article: article)

        #expect(content.header.author == nil)
        #expect(content.header.feedTitle == "Apple Newsroom")
        #expect(article.author == author)
        #expect(article.feedTitle == "Apple Newsroom")
    }

    @Test(arguments: ["Jane Doe", "Apple Newsroom Europe", "AppleNewsroom", "Ápple Newsroom"])
    func headerKeepsDistinctAuthor(author: String) {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(feedTitle: "Apple Newsroom", author: author)
        )

        #expect(content.header.author == author)
        #expect(content.header.feedTitle == "Apple Newsroom")
    }

    @Test
    func headerNormalizesFeedTitleOnlyForDuplicateComparison() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(feedTitle: " \n Apple\t Newsroom  ", author: "apple newsroom")
        )

        #expect(content.header.author == nil)
        #expect(content.header.feedTitle == "Apple\t Newsroom")
    }

    @Test(arguments: [nil, "", " \n\t\u{00A0} " ] as [String?])
    func headerKeepsFeedTitleWhenAuthorIsMissing(author: String?) {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(feedTitle: "Apple Newsroom", author: author)
        )

        #expect(content.header.author == nil)
        #expect(content.header.feedTitle == "Apple Newsroom")
    }

    @Test(arguments: ["", " \n\t\u{00A0} "])
    func headerKeepsAuthorWhenFeedTitleIsBlank(feedTitle: String) {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(feedTitle: feedTitle, author: " Jane Doe ")
        )

        #expect(content.header.author == "Jane Doe")
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
