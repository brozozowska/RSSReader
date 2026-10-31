import SwiftUI

struct ReaderArticleTableView: View {
    let table: ArticleContentTableBlock
    let actionHandlers: ArticleScreenActionHandlers
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if layoutPolicy.minimumGridColumnWidth(
            columnCount: columnCount,
            textSize: tableTextSize
        ) != nil {
            ViewThatFits(in: .horizontal) {
                ReaderArticleTableGridView(
                    table: table,
                    columnCount: columnCount,
                    textSize: tableTextSize,
                    actionHandlers: actionHandlers
                )
                cards
            }
        } else {
            cards
        }
    }

    private var cards: some View {
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

    private var layoutPolicy: ReaderArticleTableLayoutPolicy {
        ReaderArticleTableLayoutPolicy()
    }

    private var columnCount: Int {
        max(
            table.columnHeaders.count,
            table.rows.map { $0.cells.count + ($0.hasHeadingColumn ? 1 : 0) }.max() ?? 0
        )
    }

    private var tableTextSize: ReaderArticleTableTextSize {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            .standard
        case .xLarge:
            .large
        case .xxLarge, .xxxLarge:
            .extraLarge
        default:
            .accessibility
        }
    }
}

private struct ReaderArticleTableGridView: View {
    let table: ArticleContentTableBlock
    let columnCount: Int
    let textSize: ReaderArticleTableTextSize
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        ReaderArticleTableGridLayout(
            columnCount: columnCount,
            textSize: textSize
        ) {
            if table.columnHeaders.contains(where: { $0 != nil }) {
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    ReaderArticleTableGridHeaderView(
                        header: table.columnHeaders[safe: columnIndex] ?? nil
                    )
                }
            }

            ForEach(table.rows) { row in
                let contents = row.gridContents
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    ReaderArticleTableGridCellView(
                        header: table.columnHeaders[safe: columnIndex] ?? nil,
                        content: contents[safe: columnIndex] ?? nil,
                        contentIsHeading: row.heading != nil && columnIndex == 0,
                        actionHandlers: actionHandlers
                    )
                }
            }
        }
        .background(.quaternary.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        }
    }
}

private struct ReaderArticleTableGridHeaderView: View {
    let header: ArticleContentTextBlock?

    var body: some View {
        Text(header?.attributedString ?? AttributedString())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(header == nil)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .overlay(alignment: .trailing) {
                Rectangle().fill(.separator).frame(width: 0.5)
            }
    }
}

private struct ReaderArticleTableGridCellView: View {
    let header: ArticleContentTextBlock?
    let content: ArticleContentTextBlock?
    let contentIsHeading: Bool
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        Text(content?.attributedString ?? AttributedString())
            .font(contentIsHeading ? .headline : .body)
            .environment(\.openURL, OpenURLAction { url in
                actionHandlers.bodyLinkTapped(url)
                return .handled
            })
            .accessibilityLabel(accessibilityLabel(for: content))
            .accessibilityAddTraits(contentIsHeading ? .isHeader : [])
            .accessibilityHidden(content == nil)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.separator).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Divider()
            }
    }

    private func accessibilityLabel(for content: ArticleContentTextBlock?) -> Text {
        if let header, !header.plainText.isEmpty {
            Text(verbatim: "\(header.plainText), \(content?.plainText ?? "")")
        } else {
            Text(verbatim: content?.plainText ?? "")
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct ReaderArticleTableRowView: View {
    let firstColumnHeader: ArticleContentTextBlock?
    let row: ArticleContentTableRow
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
    let header: ArticleContentTextBlock?
    let content: ArticleContentTextBlock?
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
