import Foundation

nonisolated enum ArticleContentBodyPayloadRenderer {
    static func renderBodyPayload(
        _ payload: ArticleContentBodyPayload,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        switch payload.kind {
        case .plainText:
            renderTextBlock(payload.value)
        case .html:
            renderHTML(payload.value, article: article)
        }
    }
}
