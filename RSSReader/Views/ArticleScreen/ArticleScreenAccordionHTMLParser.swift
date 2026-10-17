import Foundation

/// Recognizes static header/panel pairs. No feed-provided actions are executed.
enum ArticleScreenAccordionHTMLParser {
    struct Disclosure {
        let summaryHTML: String
        let panelHTML: String
        let prefixHTML: String
        let suffixHTML: String
        let isInitiallyExpanded: Bool
    }

    private struct Element {
        let name: String
        let opening: String
        let start: Int
        let innerStart: Int
        let parent: Int?
        var innerEnd: Int
        var end: Int
    }

    static func disclosure(in html: String, openingTag: String) -> Disclosure? {
        guard html.range(of: #"<button\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let elements = elements(in: html) else { return nil }
        let nsHTML = html as NSString
        let isWordPressItem = hasClass("wp-block-accordion-item", in: openingTag)
        let roots = elements.indices.filter { elements[$0].parent == nil }
        let headers = roots.filter { index in
            let name = elements[index].name
            return name == "button" || ["h1", "h2", "h3", "h4", "h5", "h6", "header"].contains(name)
        }
        // A panel can contain its own controls; only a header's controls belong to this item.
        let pairs = headers.compactMap { headerIndex -> (Int, Int)? in
            let buttons = elements.indices.filter {
                elements[$0].name == "button" &&
                ($0 == headerIndex || isDescendant($0, of: headerIndex, elements: elements))
            }
            guard buttons.count == 1 else { return nil }
            let buttonIndex = buttons[0]
            let button = elements[buttonIndex]
            let target = ArticleScreenBodyPayloadRenderer.htmlAttribute(named: "aria-controls", in: button.opening)
            let panelIndex: Int
            if let target {
                guard target.isEmpty == false, target.contains(where: \.isWhitespace) == false else { return nil }
                let targets = elements.indices.filter {
                    ArticleScreenBodyPayloadRenderer.htmlAttribute(named: "id", in: elements[$0].opening) == target
                }
                guard targets.count == 1, roots.contains(targets[0]), targets[0] != headerIndex else { return nil }
                panelIndex = targets[0]
            } else {
                // Static Gutenberg save markup has no server-generated aria-controls/id.
                guard isWordPressItem,
                      hasClass("wp-block-accordion-heading__toggle", in: button.opening) else { return nil }
                let panels = roots.filter { hasClass("wp-block-accordion-panel", in: elements[$0].opening) }
                guard panels.count == 1 else { return nil }
                panelIndex = panels[0]
            }
            let panel = elements[panelIndex]
            guard ["div", "section"].contains(panel.name),
                  elements[headerIndex].end <= panel.start else { return nil }
            let between = nsHTML.substring(with: NSRange(
                location: elements[headerIndex].end,
                length: panel.start - elements[headerIndex].end
            )).replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: "", options: .regularExpression)
            guard between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (headerIndex, panelIndex)
        }
        guard pairs.count == 1 else { return nil }
        let (headerIndex, panelIndex) = pairs[0]
        let header = elements[headerIndex]
        let panel = elements[panelIndex]
        guard let buttonIndex = elements.indices.first(where: {
            elements[$0].name == "button" &&
            ($0 == headerIndex || isDescendant($0, of: headerIndex, elements: elements))
        }) else { return nil }
        let button = elements[buttonIndex]
        // Do not silently discard content accompanying the control inside a heading.
        let beforeButton = nsHTML.substring(with: NSRange(
            location: header.innerStart, length: max(0, button.start - header.innerStart)
        ))
        let afterButton = nsHTML.substring(with: NSRange(
            location: min(button.end, header.innerEnd), length: max(0, header.innerEnd - button.end)
        ))
        if headerIndex != buttonIndex {
            guard ArticleScreenBodyPayloadRenderer.stripHTML(beforeButton + afterButton)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        }
        let panelHTML = nsHTML.substring(with: NSRange(location: panel.innerStart, length: panel.innerEnd - panel.innerStart))
        guard ArticleScreenBodyPayloadRenderer.stripHTML(panelHTML)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            panelHTML.range(of: #"<(img|video|audio|iframe|embed)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        let hidden = elements.indices.filter {
            isDescendant($0, of: buttonIndex, elements: elements) &&
            ArticleScreenBodyPayloadRenderer.htmlAttribute(named: "aria-hidden", in: elements[$0].opening)?.lowercased() == "true"
        }
        let summary = NSMutableString(string: nsHTML.substring(with: NSRange(
            location: button.innerStart, length: button.innerEnd - button.innerStart
        )))
        // Remove only outermost hidden decorations, so nested ranges never overlap.
        for index in hidden.filter({ child in
            hidden.contains { $0 != child && isDescendant(child, of: $0, elements: elements) } == false
        }).sorted(by: { elements[$0].start > elements[$1].start }) {
            let element = elements[index]
            summary.deleteCharacters(in: NSRange(location: element.start - button.innerStart, length: element.end - element.start))
        }
        return Disclosure(
            summaryHTML: summary as String,
            panelHTML: panelHTML,
            prefixHTML: nsHTML.substring(to: header.start),
            suffixHTML: nsHTML.substring(from: panel.end),
            isInitiallyExpanded: ArticleScreenBodyPayloadRenderer.htmlAttribute(named: "aria-expanded", in: button.opening)?
                .lowercased() == "true"
        )
    }

    static func hasClass(_ name: String, in tag: String) -> Bool {
        ArticleScreenBodyPayloadRenderer.htmlAttribute(named: "class", in: tag)?
            .split(whereSeparator: \.isWhitespace).contains(Substring(name)) == true
    }

    private static func isDescendant(_ index: Int, of ancestor: Int, elements: [Element]) -> Bool {
        var parent = elements[index].parent
        while let current = parent {
            if current == ancestor { return true }
            parent = elements[current].parent
        }
        return false
    }

    /// Bounded balanced traversal, with comments and code examples treated as opaque.
    private static func elements(in html: String) -> [Element]? {
        let pattern = #"(?is)<!--.*?-->|<(pre|code)\b(?:[^>"']|"[^"]*"|'[^']*')*>.*?</\1\s*>|<\s*(/?)\s*([a-z][a-z0-9:-]*)\b(?:[^>"']|"[^"]*"|'[^']*')*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsHTML = html as NSString
        var elements: [Element] = []
        var stack: [Int] = []
        let voidNames: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let tag = nsHTML.substring(with: match.range)
            if tag.hasPrefix("<!--") { continue }
            if match.range(at: 1).location != NSNotFound {
                // Opaque code cannot provide a header, panel or target id.
                continue
            }
            let name = nsHTML.substring(with: match.range(at: 3)).lowercased()
            let isClosing = match.range(at: 2).length > 0
            if isClosing {
                guard let index = stack.last, elements[index].name == name else { return nil }
                stack.removeLast()
                elements[index].innerEnd = match.range.location
                elements[index].end = NSMaxRange(match.range)
            } else {
                guard stack.count < 24, elements.count < 4096 else { return nil }
                let index = elements.count
                elements.append(Element(
                    name: name, opening: tag, start: match.range.location,
                    innerStart: NSMaxRange(match.range), parent: stack.last,
                    innerEnd: NSMaxRange(match.range), end: NSMaxRange(match.range)
                ))
                if voidNames.contains(name) == false && tag.hasSuffix("/>") == false {
                    stack.append(index)
                }
            }
        }
        return stack.isEmpty ? elements : nil
    }
}
