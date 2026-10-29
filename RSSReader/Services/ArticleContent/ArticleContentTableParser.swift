import Foundation

private struct ArticleContentParsedTableCell {
    let isHeader: Bool
    let content: ArticleContentTextBlock?

    var isStronglyEmphasized: Bool {
        guard let content, content.spans.isEmpty == false else { return false }
        return content.spans.allSatisfy { span in
            span.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || span.isStrong
        }
    }
}

private struct ArticleContentParsedTableRow {
    let isInTableHead: Bool
    let cells: [ArticleContentParsedTableCell]
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ArticleContentBodyPayloadRenderer {
    static func renderHTMLTable(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        guard innerHTML.range(of: #"(?i)<table\b"#, options: .regularExpression) == nil,
              innerHTML.range(of: #"(?i)\b(colspan|rowspan)\s*="#, options: .regularExpression) == nil,
              let parsedRows = parseHTMLTableRows(innerHTML, article: article),
              parsedRows.isEmpty == false else {
            return renderHTMLTableFallback(innerHTML, article: article)
        }

        let firstRow = parsedRows[0]
        let hasExplicitColumnHeaders = firstRow.isInTableHead || firstRow.cells.allSatisfy(\.isHeader)
        let hasInferredColumnHeaders = hasExplicitColumnHeaders == false
            && parsedRows.count > 1
            && parsedRows.dropFirst().allSatisfy { $0.cells.count == firstRow.cells.count }
            && firstRow.cells.allSatisfy(\.isStronglyEmphasized)
        let hasColumnHeaders = hasExplicitColumnHeaders || hasInferredColumnHeaders
        let headerSource: ArticleContentTableHeaderSource? = if hasExplicitColumnHeaders {
            .explicit
        } else if hasInferredColumnHeaders {
            .inferred
        } else {
            nil
        }
        let columnHeaders = hasColumnHeaders ? firstRow.cells.map(\.content) : []
        let dataRows = hasColumnHeaders ? parsedRows.dropFirst() : parsedRows[...]

        let rows = dataRows.map { parsedRow -> ArticleContentTableRow in
            let parsedCells = parsedRow.cells
            let firstCellIsRowHeading = columnHeaders.count > 1 && parsedCells.count == columnHeaders.count
            let heading = firstCellIsRowHeading ? parsedCells.first?.content : nil
            let valueCells = firstCellIsRowHeading ? parsedCells.dropFirst() : parsedCells[...]
            let headerOffset = firstCellIsRowHeading ? 1 : 0
            let cells = valueCells.enumerated().map { index, parsedCell in
                ArticleContentTableCell(
                    columnHeader: columnHeaders[safe: index + headerOffset] ?? nil,
                    content: parsedCell.content
                )
            }
            return ArticleContentTableRow(heading: heading, cells: cells, hasHeadingColumn: firstCellIsRowHeading)
        }

        guard rows.isEmpty == false else {
            return renderHTMLTableFallback(innerHTML, article: article)
        }

        return [
            .table(
                ArticleContentTableBlock(
                    columnHeaders: columnHeaders,
                    headerSource: headerSource,
                    rows: rows
                )
            )
        ]
    }

    fileprivate static func parseHTMLTableRows(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentParsedTableRow]? {
        let rowPattern = #"(?is)<tr\b[^>]*>(.*?)</tr\s*>"#
        let cellPattern = #"(?is)<(th|td)\b([^>]*)>(.*?)</\1\s*>"#
        let tableHeadPattern = #"(?is)<thead\b[^>]*>.*?</thead\s*>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern),
              let tableHeadRegex = try? NSRegularExpression(pattern: tableHeadPattern) else {
            return nil
        }

        let nsHTML = innerHTML as NSString
        let rowMatches = rowRegex.matches(
            in: innerHTML,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        let lowercaseHTML = innerHTML.lowercased()
        let tableHeadRanges = tableHeadRegex.matches(
            in: innerHTML,
            range: NSRange(location: 0, length: nsHTML.length)
        ).map(\.range)
        let openingRowCount = lowercaseHTML.matches(of: /<tr\b/).count
        let openingCellCount = lowercaseHTML.matches(of: /<(?:th|td)\b/).count
        guard rowMatches.isEmpty == false,
              rowMatches.count == openingRowCount else { return nil }

        let rows = rowMatches.map { rowMatch in
            let rowHTML = nsHTML.substring(with: rowMatch.range(at: 1))
            let nsRowHTML = rowHTML as NSString
            let cells = cellRegex.matches(
                in: rowHTML,
                range: NSRange(location: 0, length: nsRowHTML.length)
            ).map { cellMatch in
                ArticleContentParsedTableCell(
                    isHeader: nsRowHTML.substring(with: cellMatch.range(at: 1)).lowercased() == "th",
                    content: makeTextBlock(
                        fromHTML: nsRowHTML.substring(with: cellMatch.range(at: 3)),
                        article: article
                    )
                )
            }
            return ArticleContentParsedTableRow(
                isInTableHead: tableHeadRanges.contains { NSIntersectionRange($0, rowMatch.range).length > 0 },
                cells: cells
            )
        }
        guard rows.allSatisfy({ $0.cells.isEmpty == false }),
              rows.reduce(0, { $0 + $1.cells.count }) == openingCellCount else { return nil }
        return rows
    }

    static func renderHTMLTableFallback(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        let fallbackHTML = innerHTML
            .replacingOccurrences(
                of: #"(?i)</(th|td)\s*>"#,
                with: "\n\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</tr\s*>"#,
                with: "\n\n",
                options: .regularExpression
            )

        return renderHTMLTextSegment(fallbackHTML, article: article)
    }
}
