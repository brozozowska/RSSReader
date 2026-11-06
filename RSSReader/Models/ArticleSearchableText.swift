import Foundation

nonisolated enum ArticleSearchQueryNormalizationPolicy {
    static let maximumUTF8ByteCount = 16 * 1_024

    static func normalize(_ query: String) -> String {
        var bounded = ""
        var bytes = 0
        for character in query {
            let size = String(character).utf8.count
            guard bytes + size <= maximumUTF8ByteCount else { break }
            bounded.append(character)
            bytes += size
        }
        return ArticleSearchableTextPolicy.normalize(bounded)
    }
}

/// A derived, complete Reader-text projection. Newlines separate independent
/// fields/blocks/cells; normalized queries cannot match across those boundaries.
nonisolated enum ArticleSearchableTextPolicy {
    static let formatPrefix = "\u{001E}reader-text-2\n"

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func contains(_ index: String, feedTitle: String, author: String? = nil, query: String) -> Bool {
        let text = index.hasPrefix(formatPrefix) ? index.dropFirst(formatPrefix.count) : index[...]
        return text.localizedCaseInsensitiveContains(query)
            || normalize(feedTitle).localizedCaseInsensitiveContains(query)
            || normalize(ReaderArticleMetadataPolicy.author(author, feedTitle: feedTitle) ?? "").localizedCaseInsensitiveContains(query)
    }

    static func materialize(
        title: String,
        summary: String?,
        contentHTML: String?,
        contentText: String?,
        author: String?,
        articleURL: String = "",
        canonicalURL: String? = nil,
        feedSiteURL: String? = nil
    ) -> String {
        let article = ReaderArticleDTO(
            id: UUID(), feedID: UUID(), feedTitle: "", feedSiteURL: feedSiteURL,
            articleExternalID: "", title: title, summary: summary,
            contentHTML: contentHTML, contentText: contentText, author: author,
            publishedAt: nil, updatedAtSource: nil, effectiveDate: .distantPast,
            articleURL: articleURL, canonicalURL: canonicalURL, imageURL: nil,
            isRead: false, isStarred: false, isHidden: false
        )
        return materialize(article)
    }

    static func materialize(_ article: ReaderArticleDTO) -> String {
        var segments = [article.title]
        append(ArticleContentParser.renderBody(for: article).blocks, to: &segments)
        return formatPrefix + segments.map(normalize).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func append(_ blocks: [ArticleContentBodyBlock], to segments: inout [String]) {
        for block in blocks {
            switch block {
            case .heading(_, let text), .paragraph(let text), .address(let text), .caption(let text):
                segments.append(text.plainText)
            case .codeBlock(let text), .preformattedText(let text):
                segments.append(text)
            case .list(let list):
                segments.append(contentsOf: list.items.map(\.plainText))
            case .definitionList(let list):
                for entry in list.entries {
                    if let term = entry.term { segments.append(term.plainText) }
                    segments.append(contentsOf: entry.definitions.compactMap { $0?.plainText })
                }
            case .table(let table):
                segments.append(contentsOf: table.columnHeaders.compactMap { $0?.plainText })
                for row in table.rows {
                    segments.append(contentsOf: row.gridContents.compactMap { $0?.plainText })
                }
            case .blockquote(let texts):
                segments.append(contentsOf: texts.map(\.plainText))
            case .disclosure(let disclosure):
                segments.append(disclosure.summary.plainText)
                append(disclosure.content, to: &segments)
            case .aside(let children), .figure(let children):
                append(children, to: &segments)
            case .divider, .image, .media, .fallbackNotice:
                break
            }
        }
    }
}
