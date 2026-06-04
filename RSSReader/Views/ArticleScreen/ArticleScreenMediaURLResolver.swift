import Foundation

enum ArticleScreenMediaFallbackKind {
    case embedded
    case video
    case audio

    var title: String {
        switch self {
        case .embedded:
            "Open embedded content"
        case .video:
            "Open video"
        case .audio:
            "Open audio"
        }
    }
}

extension ArticleScreenBodyPayloadRenderer {
    static func appendLeadImageIfNeeded(
        _ blocks: [ArticleScreenBodyBlock],
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        guard blocks.containsImageBlock == false, let imageBlock = leadImageBlock(for: article) else {
            return blocks
        }

        return [imageBlock] + blocks
    }

    static func leadImageBlock(for article: ReaderArticleDTO) -> ArticleScreenBodyBlock? {
        guard
            let imageURLString = article.imageURL?.articleScreenNilIfBlank,
            let imageURL = ArticleScreenURLResolver.resolveMediaURL(
                rawValue: imageURLString,
                baseURLString: article.canonicalURL ?? article.articleURL
            )
        else {
            return nil
        }
        if let fallbackKind = videoLikeMediaFallbackKind(for: imageURL) {
            return mediaFallbackBlock(title: fallbackKind.title, url: imageURL).first
        }
        guard isRenderableImageURL(imageURL) else {
            return nil
        }

        return .image(imageURL)
    }

    static func resolveImageURL(
        fromImageTag imageTag: String,
        article: ReaderArticleDTO
    ) -> URL? {
        let directAttributes = [
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-url",
            "src"
        ]

        for attributeName in directAttributes {
            if let rawURL = htmlAttribute(named: attributeName, in: imageTag),
               let imageURL = resolveArticleMediaURL(rawURL, article: article),
               isRenderableImageURL(imageURL) {
                return imageURL
            }
        }

        let srcsetAttributes = [
            "data-srcset",
            "srcset"
        ]

        for attributeName in srcsetAttributes {
            if let rawSrcset = htmlAttribute(named: attributeName, in: imageTag),
               let rawURL = preferredURLCandidate(fromSrcset: rawSrcset),
               let imageURL = resolveArticleMediaURL(rawURL, article: article),
               isRenderableImageURL(imageURL) {
                return imageURL
            }
        }

        return nil
    }

    static func resolvePictureImageURL(
        fromInnerHTML innerHTML: String,
        article: ReaderArticleDTO
    ) -> URL? {
        if let imageTag = firstHTMLTag(named: "img", in: innerHTML),
           let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
            return imageURL
        }

        for sourceTag in htmlTags(named: "source", in: innerHTML) {
            if let rawSrcset = htmlAttribute(named: "srcset", in: sourceTag),
               let rawURL = preferredURLCandidate(fromSrcset: rawSrcset),
               let imageURL = resolveArticleMediaURL(rawURL, article: article),
               isRenderableImageURL(imageURL) {
                return imageURL
            }
        }

        return nil
    }

    static func resolveVideoLikeMediaFallback(
        fromHTML html: String,
        article: ReaderArticleDTO
    ) -> (url: URL, kind: ArticleScreenMediaFallbackKind)? {
        let directAttributes = [
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-url",
            "src"
        ]

        for attributeName in directAttributes {
            if let rawURL = htmlAttribute(named: attributeName, in: html),
               let mediaURL = resolveArticleMediaURL(rawURL, article: article),
               let kind = videoLikeMediaFallbackKind(for: mediaURL) {
                return (mediaURL, kind)
            }
        }

        let srcsetAttributes = [
            "data-srcset",
            "srcset"
        ]

        for attributeName in srcsetAttributes {
            if let rawSrcset = htmlAttribute(named: attributeName, in: html),
               let rawURL = preferredURLCandidate(fromSrcset: rawSrcset),
               let mediaURL = resolveArticleMediaURL(rawURL, article: article),
               let kind = videoLikeMediaFallbackKind(for: mediaURL) {
                return (mediaURL, kind)
            }
        }

        return nil
    }

    static func resolveMediaFallbackURL(
        fromHTML html: String,
        article: ReaderArticleDTO
    ) -> URL? {
        let directAttributes = [
            "src",
            "data-src",
            "data-original",
            "data-url",
            "href"
        ]

        for attributeName in directAttributes {
            if let rawURL = htmlAttribute(named: attributeName, in: html),
               let mediaURL = resolveArticleMediaURL(rawURL, article: article) {
                return mediaURL
            }
        }

        return nil
    }

    static func resolveArticleMediaURL(
        _ rawValue: String,
        article: ReaderArticleDTO
    ) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false, trimmedValue.lowercased().hasPrefix("data:") == false else {
            return nil
        }
        guard trimmedValue.lowercased().hasSuffix(".svg") == false else {
            return nil
        }

        return ArticleScreenURLResolver.resolveMediaURL(
            rawValue: trimmedValue,
            baseURLString: article.articleURL
        )
    }

    static func isRenderableImageURL(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "svg" {
            return false
        }
        return videoLikeMediaFallbackKind(for: url) == nil
    }

    static func videoLikeMediaFallbackKind(for url: URL) -> ArticleScreenMediaFallbackKind? {
        let fileExtension = url.pathExtension.lowercased()
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif"].contains(fileExtension) {
            return nil
        }

        if ["mp4", "m4v", "mov", "webm", "m3u8", "avi", "mkv"].contains(fileExtension) {
            return .video
        }

        if ["mp3", "m4a", "aac", "ogg", "oga", "wav", "flac"].contains(fileExtension) {
            return .audio
        }

        if host.contains("youtube.com")
            || host.contains("youtu.be")
            || host.contains("vimeo.com")
            || path.contains("/embed/") {
            return .embedded
        }

        return nil
    }

    static func preferredURLCandidate(fromSrcset srcset: String) -> String? {
        srcset
            .split(separator: ",")
            .compactMap { candidate -> String? in
                candidate
                    .split(whereSeparator: { $0.isWhitespace })
                    .first
                    .map(String.init)
            }
            .last?
            .articleScreenNilIfBlank
    }

    static func unsupportedMediaFallbackTitle(for tagName: String) -> String {
        switch tagName {
        case "iframe":
            "Open embedded content"
        case "video":
            "Open video"
        case "audio":
            "Open audio"
        default:
            "Open media"
        }
    }
}
