import Foundation

nonisolated enum HTMLDiscoveryResponseDecoder {
    static func decode(_ response: HTTPResponse) throws -> String? {
        guard (200...299).contains(response.statusCode) else { return nil }

        let bodyBudget = AppComposition.resourceBudgetContract.discoveryHTML.body
        try bodyBudget.validateCompressedBodyByteCount(Int64(response.body.count))
        try bodyBudget.validateMIMEType(response.contentType)
        return String(data: response.body, encoding: .utf8)
    }
}

nonisolated enum HTMLLinkDiscoveryParser {
    static func linkTagAttributes(
        in html: String,
        maximumLinkTagCount: Int
    ) -> [[String: String]] {
        precondition(maximumLinkTagCount > 0)
        guard let linkTagExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var attributes: [[String: String]] = []
        linkTagExpression.enumerateMatches(in: html, range: nsRange) { match, _, stop in
            guard attributes.count < maximumLinkTagCount else {
                stop.pointee = true
                return
            }
            guard let match,
                  let tagRange = Range(match.range, in: html) else {
                return
            }

            attributes.append(linkTagAttributes(in: String(html[tagRange])))
            if attributes.count == maximumLinkTagCount {
                stop.pointee = true
            }
        }
        return attributes
    }

    private static func linkTagAttributes(in tag: String) -> [String: String] {
        guard let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+)"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return attributeExpression.matches(in: tag, range: nsRange).reduce(into: [String: String]()) { result, match in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 2), in: tag) else {
                return
            }

            let name = String(tag[nameRange]).lowercased()
            result[name] = unquotedAttributeValue(String(tag[valueRange]))
        }
    }

    private static func unquotedAttributeValue(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }
}
