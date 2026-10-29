import Foundation

enum ArticleContentURLResolver {
    static func resolveExternalURL(canonicalURL: String?, articleURL: String) -> URL? {
        if let canonicalURL, let resolvedCanonicalURL = validatedExternalURL(from: canonicalURL) {
            return resolvedCanonicalURL
        }

        return validatedExternalURL(from: articleURL)
    }

    static func resolveArticleBodyLinkURL(rawValue: String, baseURLString: String?) -> URL? {
        resolveMediaURL(rawValue: rawValue, baseURLString: baseURLString)
    }

    static func resolveMediaURL(rawValue: String, baseURLString: String?) -> URL? {
        if let validatedURL = validatedExternalURL(from: rawValue) {
            return validatedURL
        }

        guard
            let normalizedValue = rawValue.articleContentNilIfBlank,
            let baseURLString,
            let baseURL = validatedExternalURL(from: baseURLString),
            let relativeURL = URL(string: normalizedValue, relativeTo: baseURL)?.absoluteURL,
            let components = URLComponents(url: relativeURL, resolvingAgainstBaseURL: true),
            let scheme = components.scheme?.lowercased(),
            let host = components.host,
            host.isEmpty == false,
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return relativeURL
    }

    private static func validatedExternalURL(from rawValue: String) -> URL? {
        guard
            let normalizedValue = rawValue.articleContentNilIfBlank,
            let components = URLComponents(string: normalizedValue),
            let scheme = components.scheme?.lowercased(),
            let host = components.host,
            host.isEmpty == false,
            ["http", "https"].contains(scheme),
            let url = components.url
        else {
            return nil
        }

        return url
    }
}
