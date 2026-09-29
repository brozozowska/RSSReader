import Foundation

private struct ArticleScreenParsedTableCell {
    let isHeader: Bool
    let content: ArticleScreenTextBlock?

    var isStronglyEmphasized: Bool {
        guard let content, content.spans.isEmpty == false else { return false }
        return content.spans.allSatisfy { span in
            span.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || span.isStrong
        }
    }
}

private struct ArticleScreenParsedTableRow {
    let isInTableHead: Bool
    let cells: [ArticleScreenParsedTableCell]
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ArticleScreenBodyPayloadRenderer {
    private static let maximumHTMLContainerDepth = 12
    private static let semanticHTMLContainerNames = "div|section|article|main|header|footer|aside|details"

    static func renderHTML(
        _ contentHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let readableHTML = removingNonReadableHTMLBlocks(from: contentHTML)
        return renderHTML(readableHTML, article: article, containerDepth: 0)
    }

    private static func renderHTML(
        _ contentHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleScreenBodyBlock] {
        guard containerDepth < maximumHTMLContainerDepth else {
            return renderHTMLWithoutStructuralContainers(contentHTML, article: article, containerDepth: containerDepth)
        }

        let htmlNSString = contentHTML as NSString
        var blocks: [ArticleScreenBodyBlock] = []
        var currentLocation = 0

        while let container = firstStructuralHTMLContainer(
            in: contentHTML,
            startingAt: currentLocation
        ) {
            if container.outerRange.location > currentLocation {
                let prefixRange = NSRange(
                    location: currentLocation,
                    length: container.outerRange.location - currentLocation
                )
                blocks.append(
                    contentsOf: renderHTMLWithoutStructuralContainers(
                        htmlNSString.substring(with: prefixRange),
                        article: article,
                        containerDepth: containerDepth
                    )
                )
            }

            let innerHTML = htmlNSString.substring(with: container.innerRange)
            switch container.tagName {
            case "aside":
                let asideContent = renderHTML(
                    innerHTML,
                    article: article,
                    containerDepth: containerDepth + 1
                )
                if asideContent.isEmpty == false {
                    blocks.append(.aside(asideContent))
                }
            case "details":
                blocks.append(
                    contentsOf: renderHTMLDisclosure(
                        innerHTML,
                        openingTagHTML: container.openingTagHTML,
                        article: article,
                        containerDepth: containerDepth + 1
                    )
                )
            default:
                blocks.append(
                    contentsOf: renderHTML(
                        innerHTML,
                        article: article,
                        containerDepth: containerDepth + 1
                    )
                )
            }
            currentLocation = NSMaxRange(container.outerRange)
        }

        if currentLocation < htmlNSString.length {
            let trailingRange = NSRange(
                location: currentLocation,
                length: htmlNSString.length - currentLocation
            )
            blocks.append(
                contentsOf: renderHTMLWithoutStructuralContainers(
                    htmlNSString.substring(with: trailingRange),
                    article: article,
                    containerDepth: containerDepth
                )
            )
        }

        return blocks
    }

    private static func renderHTMLWithoutStructuralContainers(
        _ contentHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleScreenBodyBlock] {
        let htmlNSString = contentHTML as NSString
        let blockPattern = #"(?is)<(h[1-6]|p|blockquote|pre|ul|ol|dl|address|figure|figcaption|table|picture|iframe|video|audio)\b[^>]*>.*?</\1\s*>|<(img|hr|embed)\b[^>]*>"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return renderTextBlock(stripHTML(contentHTML))
        }

        var blocks: [ArticleScreenBodyBlock] = []
        var currentLocation = 0
        let matches = blockRegex.matches(
            in: contentHTML,
            options: [],
            range: NSRange(location: 0, length: htmlNSString.length)
        )

        for match in matches {
            let textRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if textRange.length > 0 {
                let textSegment = htmlNSString.substring(with: textRange)
                blocks.append(contentsOf: renderHTMLTextSegment(textSegment, article: article))
            }

            let blockHTML = htmlNSString.substring(with: match.range)
            blocks.append(
                contentsOf: renderHTMLBlock(
                    blockHTML,
                    article: article,
                    containerDepth: containerDepth
                )
            )

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < htmlNSString.length {
            let trailingRange = NSRange(location: currentLocation, length: htmlNSString.length - currentLocation)
            let trailingSegment = htmlNSString.substring(with: trailingRange)
            blocks.append(contentsOf: renderHTMLTextSegment(trailingSegment, article: article))
        }

        return blocks
    }

    private static func firstStructuralHTMLContainer(
        in html: String,
        startingAt location: Int
    ) -> (tagName: String, openingTagHTML: String, outerRange: NSRange, innerRange: NSRange)? {
        let pattern = #"(?is)<\s*(/?)\s*("# + semanticHTMLContainerNames + #")\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsHTML = html as NSString
        let searchRange = NSRange(location: location, length: nsHTML.length - location)
        let tags = regex.matches(in: html, range: searchRange)
        var stack: [(name: String, range: NSRange)] = []

        for tag in tags {
            let tagHTML = nsHTML.substring(with: tag.range)
            let isClosing = tag.range(at: 1).length > 0
            let tagName = nsHTML.substring(with: tag.range(at: 2)).lowercased()

            if isClosing == false {
                if tagHTML.dropLast().trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") == false {
                    stack.append((tagName, tag.range))
                }
                continue
            }

            guard let openingTag = stack.last, openingTag.name == tagName else {
                return nil
            }
            stack.removeLast()

            if stack.isEmpty {
                let outerRange = NSRange(
                    location: openingTag.range.location,
                    length: NSMaxRange(tag.range) - openingTag.range.location
                )
                let innerStart = NSMaxRange(openingTag.range)
                let innerRange = NSRange(
                    location: innerStart,
                    length: tag.range.location - innerStart
                )
                return (
                    openingTag.name,
                    nsHTML.substring(with: openingTag.range),
                    outerRange,
                    innerRange
                )
            }
        }

        return nil
    }

    static func renderHTMLBlock(
        _ blockHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleScreenBodyBlock] {
        let tagName = leadingTagName(in: blockHTML)

        if tagName == "img" {
            return renderImageOrMediaFallback(fromImageTag: blockHTML, article: article)
        }

        if tagName == "hr" {
            return [.divider]
        }

        let innerHTML = unwrapHTMLBlock(blockHTML)

        switch tagName {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            guard let headingText = makeTextBlock(fromHTML: innerHTML, article: article) else { return [] }
            let level = Int(String(tagName.dropFirst())) ?? 2
            return [.heading(level: level, headingText)]
        case "p":
            return makeTextBlock(fromHTML: innerHTML, article: article).map { [.paragraph($0)] } ?? []
        case "blockquote":
            let quotedBlocks = renderHTMLTextSegment(innerHTML, article: article).compactMap { block -> ArticleScreenTextBlock? in
                if case .paragraph(let textBlock) = block {
                    return textBlock
                }
                return nil
            }
            return quotedBlocks.isEmpty ? [] : [.blockquote(quotedBlocks)]
        case "pre":
            let codeText = stripHTML(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)
            return codeText.isEmpty ? [] : [.codeBlock(codeText)]
        case "ul":
            return renderHTMLList(innerHTML, kind: .unordered, article: article)
        case "ol":
            return renderHTMLList(innerHTML, kind: .ordered, article: article)
        case "dl":
            return renderHTMLDefinitionList(innerHTML, article: article)
        case "address":
            return makeTextBlock(fromHTML: innerHTML, article: article).map { [.address($0)] } ?? []
        case "figure":
            return renderHTMLFigure(innerHTML, article: article, containerDepth: containerDepth)
        case "figcaption":
            return makeTextBlock(fromHTML: innerHTML, article: article).map { [.caption($0)] } ?? []
        case "table":
            return renderHTMLTable(innerHTML, article: article)
        case "picture":
            return renderHTMLPicture(innerHTML, article: article)
        case "iframe", "video", "audio":
            return renderUnsupportedMediaFallback(
                tagName: tagName,
                html: blockHTML,
                innerHTML: innerHTML,
                article: article
            )
        case "embed":
            return renderUnsupportedMediaFallback(
                tagName: tagName,
                html: blockHTML,
                innerHTML: "",
                article: article
            )
        default:
            return renderHTMLTextSegment(blockHTML, article: article)
        }
    }

    static func renderHTMLList(
        _ innerHTML: String,
        kind: ArticleScreenListKind,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let itemPattern = #"(?is)<li\b[^>]*>(.*?)</li\s*>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        let nsHTML = innerHTML as NSString
        let items = itemRegex.matches(
            in: innerHTML,
            options: [],
            range: NSRange(location: 0, length: nsHTML.length)
        )
        .compactMap { match -> ArticleScreenTextBlock? in
            let itemHTML = nsHTML.substring(with: match.range(at: 1))
            return makeTextBlock(fromHTML: itemHTML, article: article)
        }

        return items.isEmpty ? [] : [.list(ArticleScreenListBlock(kind: kind, items: items))]
    }

    static func renderHTMLDefinitionList(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let itemPattern = #"(?is)<(dt|dd)\b[^>]*>(.*?)</\1\s*>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern) else {
            return renderHTMLDefinitionListFallback(innerHTML, article: article)
        }

        let nsHTML = innerHTML as NSString
        let matches = itemRegex.matches(
            in: innerHTML,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        let openingItemCount = innerHTML.lowercased().matches(of: /<(?:dt|dd)\b/).count
        guard matches.isEmpty == false, matches.count == openingItemCount else {
            return renderHTMLDefinitionListFallback(innerHTML, article: article)
        }

        var entries: [ArticleScreenDefinitionEntry] = []
        var currentTerm: ArticleScreenTextBlock?
        var currentDefinitions: [ArticleScreenTextBlock?] = []
        var hasCurrentEntry = false

        func appendCurrentEntry() {
            guard hasCurrentEntry else { return }
            entries.append(
                ArticleScreenDefinitionEntry(
                    term: currentTerm,
                    definitions: currentDefinitions
                )
            )
        }

        for match in matches {
            let tagName = nsHTML.substring(with: match.range(at: 1)).lowercased()
            let content = makeTextBlock(
                fromHTML: nsHTML.substring(with: match.range(at: 2)),
                article: article
            )

            if tagName == "dt" {
                appendCurrentEntry()
                currentTerm = content
                currentDefinitions = []
                hasCurrentEntry = true
            } else {
                if hasCurrentEntry == false {
                    hasCurrentEntry = true
                }
                currentDefinitions.append(content)
            }
        }
        appendCurrentEntry()

        guard entries.isEmpty == false else {
            return renderHTMLDefinitionListFallback(innerHTML, article: article)
        }
        return [.definitionList(ArticleScreenDefinitionListBlock(entries: entries))]
    }

    static func renderHTMLDefinitionListFallback(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let fallbackHTML = innerHTML.replacingOccurrences(
            of: #"(?i)</(dt|dd)\s*>"#,
            with: "\n\n",
            options: .regularExpression
        )
        return renderHTMLTextSegment(fallbackHTML, article: article)
    }

    private static func renderHTMLDisclosure(
        _ innerHTML: String,
        openingTagHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleScreenBodyBlock] {
        let summaryPattern = #"(?is)^\s*<summary\b[^>]*>(.*?)</summary\s*>"#
        guard let summaryRegex = try? NSRegularExpression(pattern: summaryPattern),
              let summaryMatch = summaryRegex.firstMatch(
                in: innerHTML,
                range: NSRange(location: 0, length: (innerHTML as NSString).length)
              ) else {
            return renderHTML(innerHTML, article: article, containerDepth: containerDepth)
        }

        let nsHTML = innerHTML as NSString
        guard let summary = makeTextBlock(
            fromHTML: nsHTML.substring(with: summaryMatch.range(at: 1)),
            article: article
        ) else {
            return renderHTML(innerHTML, article: article, containerDepth: containerDepth)
        }

        let contentHTML = nsHTML.replacingCharacters(in: summaryMatch.range, with: "")
        let content = renderHTML(contentHTML, article: article, containerDepth: containerDepth)
        guard content.isEmpty == false else { return [.paragraph(summary)] }

        let isInitiallyExpanded = openingTagHTML.range(
            of: #"(?i)\sopen(?:\s*=|\s|/?>)"#,
            options: .regularExpression
        ) != nil
        return [
            .disclosure(
                ArticleScreenDisclosureBlock(
                    summary: summary,
                    content: content,
                    isInitiallyExpanded: isInitiallyExpanded
                )
            )
        ]
    }

    static func renderHTMLTable(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
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
        let headerSource: ArticleScreenTableHeaderSource? = if hasExplicitColumnHeaders {
            .explicit
        } else if hasInferredColumnHeaders {
            .inferred
        } else {
            nil
        }
        let columnHeaders = hasColumnHeaders ? firstRow.cells.map(\.content) : []
        let dataRows = hasColumnHeaders ? parsedRows.dropFirst() : parsedRows[...]

        let rows = dataRows.map { parsedRow -> ArticleScreenTableRow in
            let parsedCells = parsedRow.cells
            let firstCellIsRowHeading = columnHeaders.count > 1 && parsedCells.count == columnHeaders.count
            let heading = firstCellIsRowHeading ? parsedCells.first?.content : nil
            let valueCells = firstCellIsRowHeading ? parsedCells.dropFirst() : parsedCells[...]
            let headerOffset = firstCellIsRowHeading ? 1 : 0
            let cells = valueCells.enumerated().map { index, parsedCell in
                ArticleScreenTableCell(
                    columnHeader: columnHeaders[safe: index + headerOffset] ?? nil,
                    content: parsedCell.content
                )
            }
            return ArticleScreenTableRow(heading: heading, cells: cells)
        }

        guard rows.isEmpty == false else {
            return renderHTMLTableFallback(innerHTML, article: article)
        }

        return [
            .table(
                ArticleScreenTableBlock(
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
    ) -> [ArticleScreenParsedTableRow]? {
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
                ArticleScreenParsedTableCell(
                    isHeader: nsRowHTML.substring(with: cellMatch.range(at: 1)).lowercased() == "th",
                    content: makeTextBlock(
                        fromHTML: nsRowHTML.substring(with: cellMatch.range(at: 3)),
                        article: article
                    )
                )
            }
            return ArticleScreenParsedTableRow(
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
    ) -> [ArticleScreenBodyBlock] {
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

    static func renderHTMLFigure(
        _ innerHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleScreenBodyBlock] {
        let content = renderHTML(innerHTML, article: article, containerDepth: containerDepth)
        let containsMedia = content.contains { block in
            switch block {
            case .image, .media:
                true
            default:
                false
            }
        }
        return containsMedia ? [.figure(content)] : content
    }

    static func renderHTMLPicture(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        firstHTMLMediaImageBlocks(in: innerHTML, article: article) ?? []
    }

    static func firstHTMLMediaImageBlocks(
        in innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock]? {
        if let pictureURL = resolvePictureImageURL(fromInnerHTML: innerHTML, article: article) {
            return [.image(pictureURL)]
        }

        if let imageTag = firstHTMLTag(named: "img", in: innerHTML) {
            let imageBlocks = renderImageOrMediaFallback(fromImageTag: imageTag, article: article)
            if imageBlocks.isEmpty == false {
                return imageBlocks
            }
        }

        return nil
    }

    static func renderUnsupportedMediaFallback(
        tagName: String,
        html: String,
        innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        guard let mediaURL = resolveMediaFallbackURL(fromHTML: html, article: article) else {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        return mediaFallbackBlock(
            kind: unsupportedMediaKind(for: tagName, url: mediaURL),
            url: mediaURL
        )
    }

    static func renderImageOrMediaFallback(
        fromImageTag imageTag: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        if let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
            return [.image(imageURL)]
        }

        if let mediaFallback = resolveVideoLikeMediaFallback(fromHTML: imageTag, article: article) {
            return mediaFallbackBlock(kind: mediaFallback.kind, url: mediaFallback.url)
        }

        return []
    }

    static func mediaFallbackBlock(
        kind: ArticleScreenMediaKind,
        url: URL
    ) -> [ArticleScreenBodyBlock] {
        [.media(ArticleScreenMediaBlock(kind: kind, url: url))]
    }
}
