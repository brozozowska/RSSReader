import Foundation

nonisolated enum ArticleContentParser {
    static func renderBody(for article: ReaderArticleDTO) -> ArticleContent {
        let contentHTMLPayload = ArticleContentBodyPayloadNormalizer.normalize(
            article.contentHTML,
            preferredKind: .html
        )
        if let contentHTML = contentHTMLPayload {
            let bodyBlocks = ArticleContentBodyPayloadRenderer.renderBodyPayload(contentHTML, article: article)
            if bodyBlocks.isEmpty == false {
                return ArticleContent(
                    blocks: ArticleContentBodyPayloadRenderer.appendLeadImageIfNeeded(bodyBlocks, article: article),
                    source: .contentHTML
                )
            }
        }

        if let contentText = ArticleContentBodyPayloadNormalizer.normalize(
            article.contentText,
            preferredKind: fallbackKind(for: article.contentText, htmlPayload: contentHTMLPayload)
        ) {
            let bodyBlocks = ArticleContentBodyPayloadRenderer.renderBodyPayload(contentText, article: article)
            if bodyBlocks.isEmpty == false {
                return ArticleContent(
                    blocks: ArticleContentBodyPayloadRenderer.appendLeadImageIfNeeded(bodyBlocks, article: article),
                    source: .contentText
                )
            }
        }

        if let summary = ArticleContentBodyPayloadNormalizer.normalize(
            article.summary,
            preferredKind: fallbackKind(for: article.summary, htmlPayload: contentHTMLPayload)
        ) {
            var summaryBlocks = ArticleContentBodyPayloadRenderer.renderBodyPayload(summary, article: article)
            if summaryBlocks.isEmpty == false {
                summaryBlocks = ArticleContentBodyPayloadRenderer.appendLeadImageIfNeeded(summaryBlocks, article: article)
                summaryBlocks.append(
                    ArticleContentBodyBlock.fallbackNotice(.summaryOnly)
                )
                return ArticleContent(blocks: summaryBlocks, source: .summary)
            }
        }

        var fallbackBlocks: [ArticleContentBodyBlock] = []
        if let imageBlock = ArticleContentBodyPayloadRenderer.leadImageBlock(for: article) {
            fallbackBlocks.append(imageBlock)
        }
        fallbackBlocks.append(
            ArticleContentBodyBlock.fallbackNotice(.emptyBody)
        )

        return ArticleContent(
            blocks: fallbackBlocks,
            source: .empty
        )
    }

    private static func fallbackKind(
        for value: String?,
        htmlPayload: ArticleContentBodyPayload?
    ) -> ArticleContentBodyPayloadKind {
        // Atom can copy the same HTML into all three body fields. Retain its kind
        // after an empty render, without treating independent plain text as markup.
        guard let htmlPayload,
              ArticleContentBodyPayloadNormalizer.normalize(value, preferredKind: .html) == htmlPayload
        else { return .plainText }
        return .html
    }
}
