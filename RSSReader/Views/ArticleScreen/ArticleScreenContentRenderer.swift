import Foundation

@MainActor
enum ArticleScreenContentRenderer {
    static func renderBody(for article: ReaderArticleDTO) -> ArticleScreenBodyContentState {
        if let contentHTML = ArticleScreenBodyPayloadNormalizer.normalize(
            article.contentHTML,
            preferredKind: .html
        ) {
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
            preferredKind: .plainText
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
            preferredKind: .plainText
        ) {
            var summaryBlocks = ArticleScreenBodyPayloadRenderer.renderBodyPayload(summary, article: article)
            summaryBlocks = ArticleScreenBodyPayloadRenderer.appendLeadImageIfNeeded(summaryBlocks, article: article)
            summaryBlocks.append(
                ArticleScreenBodyBlock.fallbackNotice("This article included only a summary in the received feed.")
            )

            return ArticleScreenBodyContentState(
                blocks: summaryBlocks,
                source: .summary
            )
        }

        var fallbackBlocks: [ArticleScreenBodyBlock] = []
        if let imageBlock = ArticleScreenBodyPayloadRenderer.leadImageBlock(for: article) {
            fallbackBlocks.append(imageBlock)
        }
        fallbackBlocks.append(
            ArticleScreenBodyBlock.fallbackNotice("This article did not include body content in the received feed.")
        )

        return ArticleScreenBodyContentState(
            blocks: fallbackBlocks,
            source: .empty
        )
    }
}
