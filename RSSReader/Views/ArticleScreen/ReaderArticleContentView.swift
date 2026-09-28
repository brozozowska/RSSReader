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
            .id(content.articleID)
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
        case .definitionList(let definitionList):
            ReaderArticleDefinitionListView(
                definitionList: definitionList,
                actionHandlers: actionHandlers
            )
        case .table(let tableBlock):
            ReaderArticleTableView(
                table: tableBlock,
                actionHandlers: actionHandlers
            )
        case .disclosure(let disclosure):
            ReaderArticleDisclosureView(
                disclosure: disclosure,
                actionHandlers: actionHandlers
            )
        case .aside(let blocks):
            ReaderArticleAsideView(
                blocks: blocks,
                actionHandlers: actionHandlers
            )
        case .address(let text):
            ReaderArticleAddressView(
                text: text,
                actionHandlers: actionHandlers
            )
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

private struct ReaderArticleDefinitionListView: View {
    let definitionList: ArticleScreenDefinitionListBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(definitionList.entries) { entry in
                ReaderArticleDefinitionEntryView(
                    term: entry.term,
                    definitions: entry.definitions,
                    actionHandlers: actionHandlers
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderArticleDefinitionEntryView: View {
    let term: ArticleScreenTextBlock?
    let definitions: [ArticleScreenTextBlock?]
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let term {
                ReaderArticleSemanticTextView(
                    text: term,
                    actionHandlers: actionHandlers
                )
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(definitions.enumerated()), id: \.offset) { _, definition in
                    if let definition {
                        ReaderArticleSemanticTextView(
                            text: definition,
                            actionHandlers: actionHandlers
                        )
                        .font(.body)
                    }
                }
            }
            .padding(.leading, term == nil ? 0 : 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderArticleDisclosureView: View {
    let disclosure: ArticleScreenDisclosureBlock
    let actionHandlers: ArticleScreenActionHandlers
    @State private var isExpanded: Bool

    init(
        disclosure: ArticleScreenDisclosureBlock,
        actionHandlers: ArticleScreenActionHandlers
    ) {
        self.disclosure = disclosure
        self.actionHandlers = actionHandlers
        _isExpanded = State(initialValue: disclosure.isInitiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ReaderArticleBodyBlocksView(
                blocks: disclosure.content,
                actionHandlers: actionHandlers
            )
            .padding(.top, 8)
        } label: {
            ReaderArticleSemanticTextView(
                text: disclosure.summary,
                actionHandlers: actionHandlers
            )
            .font(.headline)
        }
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ReaderArticleAsideView: View {
    let blocks: [ArticleScreenBodyBlock]
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            ReaderArticleBodyBlocksView(
                blocks: blocks,
                actionHandlers: actionHandlers
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.tint.opacity(0.28), lineWidth: 0.5)
        }
    }
}

private struct ReaderArticleAddressView: View {
    let text: ArticleScreenTextBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            ReaderArticleSemanticTextView(
                text: text,
                actionHandlers: actionHandlers
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderArticleSemanticTextView: View {
    let text: ArticleScreenTextBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        Text(text.attributedString)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                actionHandlers.bodyLinkTapped(url)
                return .handled
            })
    }
}

private struct ReaderArticleTableView: View {
    let table: ArticleScreenTableBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(table.rows) { row in
                ReaderArticleTableRowView(
                    firstColumnHeader: table.columnHeaders.first ?? nil,
                    row: row,
                    actionHandlers: actionHandlers
                )

                if row.id != table.rows.last?.id {
                    Divider()
                }
            }
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }
}

private struct ReaderArticleTableRowView: View {
    let firstColumnHeader: ArticleScreenTextBlock?
    let row: ArticleScreenTableRow
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading = row.heading {
                ReaderArticleTableCellView(
                    header: firstColumnHeader,
                    content: heading,
                    contentIsHeading: true,
                    actionHandlers: actionHandlers
                )
            }

            ForEach(row.cells) { cell in
                ReaderArticleTableCellView(
                    header: cell.columnHeader,
                    content: cell.content,
                    contentIsHeading: false,
                    actionHandlers: actionHandlers
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderArticleTableCellView: View {
    let header: ArticleScreenTextBlock?
    let content: ArticleScreenTextBlock?
    let contentIsHeading: Bool
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let header {
                Text(header.attributedString)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }

            if let content {
                Text(content.attributedString)
                    .font(contentIsHeading ? .headline : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        actionHandlers.bodyLinkTapped(url)
                        return .handled
                    })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ReaderArticleContentLayout {
    static let sectionSpacing: CGFloat = 14
    static let headerSpacing: CGFloat = 6
    static let metadataSpacing: CGFloat = 2
}
