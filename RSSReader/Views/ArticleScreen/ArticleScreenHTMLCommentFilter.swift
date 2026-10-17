import Foundation

/// A Reader preprocessing pass, not a replacement HTML parser.
/// Comments are opaque before any block/link/media extraction. Literal code and quoted
/// attributes are copied unchanged; an unclosed comment consumes the remaining payload.
enum ArticleScreenHTMLCommentFilter {
    static func removingComments(in html: String) -> String {
        var result = ""
        var index = html.startIndex

        while index < html.endIndex {
            if html[index...].hasPrefix("<!--") {
                let contentStart = html.index(index, offsetBy: 4)
                guard let end = html.range(of: "-->", range: contentStart..<html.endIndex) else {
                    break
                }
                index = end.upperBound
                continue
            }

            if html[index] == "<", let tag = tag(in: html, at: index) {
                if tag.isClosing == false && (tag.name == "pre" || tag.name == "code") {
                    // The first closing code/pre tag terminates the literal region, just as
                    // in the existing renderer. Missing closure keeps the remainder opaque.
                    let closing = html.range(
                        of: "(?i)</" + tag.name + #"\s*>"#,
                        options: .regularExpression,
                        range: tag.end..<html.endIndex
                    )
                    let end = closing?.upperBound ?? html.endIndex
                    result += html[index..<end]
                    index = end
                } else {
                    result += html[index..<tag.end]
                    index = tag.end
                }
                continue
            }

            result.append(html[index])
            index = html.index(after: index)
        }
        return result
    }

    private static func tag(
        in html: String,
        at start: String.Index
    ) -> (name: String, isClosing: Bool, end: String.Index)? {
        var index = html.index(after: start)
        while index < html.endIndex && html[index].isWhitespace {
            index = html.index(after: index)
        }
        guard index < html.endIndex else { return nil }
        let isClosing = html[index] == "/"
        if isClosing {
            index = html.index(after: index)
            while index < html.endIndex && html[index].isWhitespace {
                index = html.index(after: index)
            }
        }
        guard index < html.endIndex, html[index].isLetter else { return nil }
        let nameStart = index
        while index < html.endIndex && (html[index].isLetter || html[index].isNumber || html[index] == "-") {
            index = html.index(after: index)
        }
        let name = html[nameStart..<index].lowercased()
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let currentQuote = quote {
                if character == currentQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return (name, isClosing, html.index(after: index))
            }
            index = html.index(after: index)
        }
        // Preserve malformed quoted markup rather than scanning its attributes as comments.
        return (name, isClosing, html.endIndex)
    }
}
