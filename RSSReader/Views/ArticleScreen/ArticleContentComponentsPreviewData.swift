import SwiftUI

#Preview("Content Components", traits: .sizeThatFitsLayout) {
    ArticleContentComponentsPreview()
        .environment(\.locale, Locale(identifier: "en"))
        .frame(width: 390)
}

#Preview("Content Components RTL Accessibility", traits: .sizeThatFitsLayout) {
    ArticleContentComponentsPreview()
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.dynamicTypeSize, .accessibility1)
        .frame(width: 600)
}

private struct ArticleContentComponentsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReaderArticleBodyBlocksView(
                blocks: Self.blocks,
                actionHandlers: ArticleScreenActionHandlers(
                    toggleReadStatus: {}, toggleStarredStatus: {},
                    openSourceArticle: {}, bodyLinkTapped: { _ in }
                )
            )
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
    }

    private static var blocks: [ArticleContentBodyBlock] {
        [
            .figure([
                .media(ArticleContentMediaBlock(kind: .audio, url: URL(string: "https://example.com/audio.mp3")!)),
                .caption(.plainText("Figure caption / 図の説明"))
            ]),
            .media(ArticleContentMediaBlock(kind: .video, url: URL(string: "https://example.com/video.mp4")!)),
            .media(ArticleContentMediaBlock(kind: .knownEmbedded, url: URL(string: "https://youtu.be/example")!)),
            .disclosure(ArticleContentDisclosureBlock(
                summary: .plainText("Expanded details / تفاصيل"),
                content: [.paragraph(.plainText("Panel content with preserved source order."))],
                isInitiallyExpanded: true
            )),
            .disclosure(ArticleContentDisclosureBlock(
                summary: .plainText("Collapsed details"),
                content: [.paragraph(.plainText("Hidden panel"))],
                isInitiallyExpanded: false
            )),
            .aside([.paragraph(.plainText("Related information / 関連情報"))]),
            .definitionList(ArticleContentDefinitionListBlock(entries: [
                ArticleContentDefinitionEntry(
                    term: .plainText("Term / 用語"),
                    definitions: [.plainText("First definition"), nil, .plainText("Second definition")]
                )
            ])),
            .address(.plainText("Author metadata / بيانات المؤلف")),
            .fallbackNotice(.summaryOnly)
        ]
    }
}
