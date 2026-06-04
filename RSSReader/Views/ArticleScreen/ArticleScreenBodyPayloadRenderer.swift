import Foundation

@MainActor
enum ArticleScreenBodyPayloadRenderer {
    static func renderBodyPayload(
        _ payload: ArticleScreenBodyPayload,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        switch payload.kind {
        case .plainText:
            renderTextBlock(payload.value)
        case .html:
            renderHTML(payload.value, article: article)
        }
    }
}
