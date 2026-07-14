import Foundation

nonisolated enum FeedURLNormalizer {
    static func normalizeSourceURL(_ value: String?) -> String? {
        normalizeSourceURL(value, baseURL: nil)
    }

    static func normalizeSourceURL(_ value: String?, baseURL: String?) -> String? {
        guard let value = FeedTextHTMLNormalizer.normalizeScalar(value) else { return nil }

        let resolvedValue: String
        if let baseURL,
           hasAbsoluteWebURL(value) == false,
           let base = URL(string: baseURL),
           let resolvedURL = URL(string: value, relativeTo: base)?.absoluteURL {
            resolvedValue = resolvedURL.absoluteString
        } else {
            resolvedValue = value
        }

        guard let components = URLComponents(string: resolvedValue) else {
            return FeedTextHTMLNormalizer.normalizeInlineText(value)
        }

        var normalizedComponents = components
        normalizedComponents.scheme = components.scheme?.lowercased()
        normalizedComponents.host = components.host?.lowercased()
        normalizedComponents.fragment = nil

        if let port = normalizedComponents.port {
            let isDefaultHTTPPort = normalizedComponents.scheme == "http" && port == 80
            let isDefaultHTTPSPort = normalizedComponents.scheme == "https" && port == 443

            if isDefaultHTTPPort || isDefaultHTTPSPort {
                normalizedComponents.port = nil
            }
        }

        if normalizedComponents.path.isEmpty {
            normalizedComponents.path = "/"
        }

        return normalizedComponents.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? FeedTextHTMLNormalizer.normalizeInlineText(resolvedValue)
    }

    static func hasAbsoluteWebURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              host.isEmpty == false else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    static func makeOriginURL(from sourceURL: String?) -> String? {
        guard let sourceURL,
              var components = URLComponents(string: sourceURL),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.string
    }
}
