import SwiftUI

struct ReaderArticleContentView: View {
    let content: ArticleScreenContentState
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: ReaderArticleContentLayout.sectionSpacing) {
            ReaderArticleHeaderView(
                header: content.header,
                actionHandlers: actionHandlers
            )

            ReaderArticleBodyBlocksView(
                blocks: content.body.blocks,
                actionHandlers: actionHandlers
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderArticleHeaderView: View {
    let header: ArticleScreenHeaderState
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: ReaderArticleContentLayout.headerSpacing) {
            Text(header.effectiveDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if header.canOpenSourceArticle {
                Button(action: actionHandlers.openSourceArticle) {
                    Text(header.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ReadingLocalization.openOriginalArticleAccessibilityLabel)
            } else {
                Text(header.title)
                    .font(.title2.weight(.semibold))
            }

            if header.author != nil || header.feedTitle != nil {
                VStack(alignment: .leading, spacing: ReaderArticleContentLayout.metadataSpacing) {
                    if let author = header.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let feedTitle = header.feedTitle {
                        Text(feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ReaderArticleBodyBlocksView: View {
    let blocks: [ArticleScreenBodyBlock]
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            ReaderArticleBodyBlockView(
                block: block,
                actionHandlers: actionHandlers
            )
        }
    }
}

private struct ReaderArticleBodyBlockView: View {
    let block: ArticleScreenBodyBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        switch block {
        case .heading(let level, let text):
            linkedText(text)
                .font(headingFont(for: level))
                .padding(.top, level <= 2 ? 10 : 6)
        case .paragraph(let text):
            linkedText(text)
                .font(.body)
        case .list(let listBlock):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(listBlock.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(listMarker(for: listBlock.kind, index: index))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        linkedText(item)
                            .font(.body)
                    }
                }
            }
            .padding(.vertical, 2)
        case .blockquote(let paragraphs):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        linkedText(paragraph)
                            .font(.body.italic())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        case .codeBlock(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .divider:
            Divider()
                .padding(.vertical, 8)
        case .caption(let text):
            linkedText(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .image(let url):
            CachedArticleImageView(url: url)
                .id(url)
        case .fallbackNotice(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func linkedText(_ text: ArticleScreenTextBlock) -> some View {
        Text(text.attributedString)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                actionHandlers.bodyLinkTapped(url)
                return .handled
            })
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case ...1:
            .title2.weight(.semibold)
        case 2:
            .title3.weight(.semibold)
        default:
            .headline
        }
    }

    private func listMarker(for kind: ArticleScreenListKind, index: Int) -> String {
        switch kind {
        case .ordered:
            "\(index + 1)."
        case .unordered:
            "•"
        }
    }
}

private enum ReaderArticleContentLayout {
    static let sectionSpacing: CGFloat = 14
    static let headerSpacing: CGFloat = 6
    static let metadataSpacing: CGFloat = 2
}
