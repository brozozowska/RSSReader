import Foundation

@MainActor
enum ArticleScreenContentRenderer {
    static func renderBody(for article: ReaderArticleDTO) -> ArticleScreenBodyContentState {
        let contentHTMLPayload = ArticleScreenBodyPayloadNormalizer.normalize(
            article.contentHTML,
            preferredKind: .html
        )
        if let contentHTML = contentHTMLPayload {
            let bodyBlocks = ArticleScreenBodyPayloadRenderer.renderBodyPayload(contentHTML, article: article)
            if bodyBlocks.isEmpty == false {
                return ArticleScreenBodyContentState(
                    blocks: ArticleScreenBodyPayloadRenderer.appendLeadImageIfNeeded(bodyBlocks, article: article),
                    source: .contentHTML
                )
            }
        }

        if let contentText = ArticleScreenBodyPayloadNormalizer.normalize(
            article.contentText,
            preferredKind: fallbackKind(for: article.contentText, htmlPayload: contentHTMLPayload)
        ) {
            let bodyBlocks = ArticleScreenBodyPayloadRenderer.renderBodyPayload(contentText, article: article)
            if bodyBlocks.isEmpty == false {
                return ArticleScreenBodyContentState(
                    blocks: ArticleScreenBodyPayloadRenderer.appendLeadImageIfNeeded(bodyBlocks, article: article),
                    source: .contentText
                )
            }
        }

        if let summary = ArticleScreenBodyPayloadNormalizer.normalize(
            article.summary,
            preferredKind: fallbackKind(for: article.summary, htmlPayload: contentHTMLPayload)
        ) {
            var summaryBlocks = ArticleScreenBodyPayloadRenderer.renderBodyPayload(summary, article: article)
            if summaryBlocks.isEmpty == false {
                summaryBlocks = ArticleScreenBodyPayloadRenderer.appendLeadImageIfNeeded(summaryBlocks, article: article)
                summaryBlocks.append(
                    ArticleScreenBodyBlock.fallbackNotice(ReadingLocalization.summaryOnlyFallbackNotice)
                )
                return ArticleScreenBodyContentState(blocks: summaryBlocks, source: .summary)
            }
        }

        var fallbackBlocks: [ArticleScreenBodyBlock] = []
        if let imageBlock = ArticleScreenBodyPayloadRenderer.leadImageBlock(for: article) {
            fallbackBlocks.append(imageBlock)
        }
        fallbackBlocks.append(
            ArticleScreenBodyBlock.fallbackNotice(ReadingLocalization.emptyBodyFallbackNotice)
        )

        return ArticleScreenBodyContentState(
            blocks: fallbackBlocks,
            source: .empty
        )
    }

    private static func fallbackKind(
        for value: String?,
        htmlPayload: ArticleScreenBodyPayload?
    ) -> ArticleScreenBodyPayloadKind {
        // Atom can copy the same HTML into all three body fields. Retain its kind
        // after an empty render, without treating independent plain text as markup.
        guard let htmlPayload,
              ArticleScreenBodyPayloadNormalizer.normalize(value, preferredKind: .html) == htmlPayload
        else { return .plainText }
        return .html
    }
}
