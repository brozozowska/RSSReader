import Foundation

extension ArticleContentBodyPayloadRenderer {
    private nonisolated static let maximumHTMLContainerDepth = 12
    private nonisolated static let semanticHTMLContainerNames = "div|section|article|main|header|footer|aside|details"

    nonisolated static func renderHTML(
        _ contentHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        let uncommentedHTML = ArticleContentHTMLCommentFilter.removingComments(in: contentHTML)
        let readableHTML = removingDisclosureDecorations(removingNonReadableHTMLBlocks(from: uncommentedHTML))
        return renderHTML(recoveringRedditHTML(readableHTML, article: article), article: article, containerDepth: 0)
    }

    nonisolated static func renderHTML(
        _ contentHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleContentBodyBlock] {
        guard containerDepth < maximumHTMLContainerDepth else {
            return renderHTMLWithoutStructuralContainers(contentHTML, article: article, containerDepth: containerDepth)
        }

        let htmlNSString = contentHTML as NSString
        var blocks: [ArticleContentBodyBlock] = []
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
                if let accordion = ArticleContentAccordionHTMLParser.disclosure(
                    in: innerHTML, openingTag: container.openingTagHTML
                ), let summary = makeTextBlock(fromHTML: accordion.summaryHTML, article: article) {
                    let content = renderHTML(accordion.panelHTML, article: article, containerDepth: containerDepth + 1)
                    blocks.append(contentsOf: renderHTML(accordion.prefixHTML, article: article, containerDepth: containerDepth + 1))
                    if content.isEmpty {
                        blocks.append(.paragraph(summary))
                    } else {
                        blocks.append(.disclosure(ArticleContentDisclosureBlock(
                            summary: summary, content: content,
                            isInitiallyExpanded: accordion.isInitiallyExpanded
                        )))
                    }
                    blocks.append(contentsOf: renderHTML(accordion.suffixHTML, article: article, containerDepth: containerDepth + 1))
                } else {
                    blocks.append(contentsOf: renderHTML(innerHTML, article: article, containerDepth: containerDepth + 1))
                }
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

    private nonisolated static func renderHTMLWithoutStructuralContainers(
        _ contentHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleContentBodyBlock] {
        let htmlNSString = contentHTML as NSString
        let blockPattern = #"(?is)<(h[1-6]|p|blockquote|pre|ul|ol|dl|address|figure|figcaption|table|picture|iframe|video|audio)\b[^>]*>.*?</\1\s*>|<(img|hr|embed)\b[^>]*>"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return renderTextBlock(stripHTML(contentHTML))
        }

        var blocks: [ArticleContentBodyBlock] = []
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

    private nonisolated static func firstStructuralHTMLContainer(
        in html: String,
        startingAt location: Int
    ) -> (tagName: String, openingTagHTML: String, outerRange: NSRange, innerRange: NSRange)? {
        let pattern = #"(?is)<!--.*?-->|<(pre|code)\b[^>]*>.*?</\1\s*>|<\s*(/?)\s*("# + semanticHTMLContainerNames + #")\b(?:[^>"']|"[^"]*"|'[^']*')*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsHTML = html as NSString
        let searchRange = NSRange(location: location, length: nsHTML.length - location)
        let tags = regex.matches(in: html, range: searchRange)
        var stack: [(name: String, range: NSRange)] = []

        for tag in tags {
            let tagHTML = nsHTML.substring(with: tag.range)
            if tagHTML.hasPrefix("<!--") || tag.range(at: 1).location != NSNotFound { continue }
            let isClosing = tag.range(at: 2).length > 0
            let tagName = nsHTML.substring(with: tag.range(at: 3)).lowercased()

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

    private nonisolated static func renderHTMLDisclosure(
        _ innerHTML: String,
        openingTagHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleContentBodyBlock] {
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
                ArticleContentDisclosureBlock(
                    summary: summary,
                    content: content,
                    isInitiallyExpanded: isInitiallyExpanded
                )
            )
        ]
    }
}
