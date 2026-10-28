import Foundation

/// Reddit's legacy Atom HTML can retain Markdown markers after flattening its layout.
/// Recover only explicit structures; never invent code indentation or parse general prose.
extension ArticleScreenBodyPayloadRenderer {
    static func recoveringRedditHTML(_ html: String, article: ReaderArticleDTO) -> String {
        guard let host = URL(string: article.articleURL)?.host?.lowercased(),
              ["reddit.com", "www.reddit.com", "old.reddit.com"].contains(host),
              htmlTags(named: "div", in: html).contains(where: {
                  htmlAttribute(named: "class", in: $0)?.split(whereSeparator: \.isWhitespace).contains("md") == true
              }) else { return html }

        return recoverRedditLists(recoverRedditFences(html))
    }

    private static func recoverRedditFences(_ html: String) -> String {
        // A language-labelled fence must occupy whole paragraphs. Encoded source
        // remains encoded until the existing <pre><code> rendering boundary.
        let pattern = #"(?is)<(pre|code)\b[^>]*>.*?</\1\s*>|<p>\s*(`{3,})([a-z][a-z0-9_+-]*)[ \t\n]+(.*?)\s+\2\s*</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let source = html as NSString
        var result = html
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)).reversed() {
            guard match.range(at: 4).location != NSNotFound else { continue }
            var body = source.substring(with: match.range(at: 4))
            body = body.replacingOccurrences(of: #"(?is)</p>\s*<p>"#, with: "\n\n", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            // Do not consume links, media, formatting or an unrelated semantic block.
            guard body.range(of: #"<\s*/?\s*[a-z!]"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  body.contains("```") == false else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: "<pre><code>" + body + "</code></pre>")
        }
        return result
    }

    private static func recoverRedditLists(_ html: String) -> String {
        let paragraphPattern = #"(?is)<(pre|code)\b[^>]*>.*?</\1\s*>|<p>(.*?)</p>"#
        let markerPattern = #"\s+-\s+(?=<strong>)"#
        guard let paragraphs = try? NSRegularExpression(pattern: paragraphPattern),
              let markers = try? NSRegularExpression(pattern: markerPattern) else { return html }
        let source = html as NSString
        var result = html
        for paragraph in paragraphs.matches(in: html, range: NSRange(location: 0, length: source.length)).reversed() {
            guard paragraph.range(at: 2).location != NSNotFound else { continue }
            let inner = source.substring(with: paragraph.range(at: 2))
            let nsInner = inner as NSString
            let matches = markers.matches(in: inner, range: NSRange(location: 0, length: nsInner.length))
            guard matches.count >= 2 else { continue }
            let prefix = nsInner.substring(to: matches[0].range.location)
            // A standalone bold introduction ending in a colon is required.
            guard prefix.range(of: #"(?is)^\s*<strong>[^<]*:(?:</strong>)\s*$"#, options: .regularExpression) != nil else { continue }
            // Match only markers outside inline code and links.
            let protectedPattern = #"(?is)<(code|a)\b[^>]*>.*?</\1\s*>"#
            guard let protectedRegex = try? NSRegularExpression(pattern: protectedPattern) else { continue }
            let protectedRanges = protectedRegex.matches(in: inner, range: NSRange(location: 0, length: nsInner.length)).map(\.range)
            let itemMarkers = matches.filter { marker in
                protectedRanges.contains { NSIntersectionRange($0, marker.range).length > 0 } == false
            }
            guard itemMarkers.count >= 2 else { continue }
            let items = itemMarkers.enumerated().map { index, marker in
                let start = NSMaxRange(marker.range)
                let end = index + 1 < itemMarkers.count ? itemMarkers[index + 1].range.location : nsInner.length
                return "<li>" + nsInner.substring(with: NSRange(location: start, length: end - start)) + "</li>"
            }.joined()
            result = (result as NSString).replacingCharacters(in: paragraph.range, with: "<p>" + prefix + "</p><ul>" + items + "</ul>")
        }
        return result
    }
}
