import Foundation

extension ArticleContentBodyPayloadRenderer {
    nonisolated static func renderHTMLFigure(
        _ innerHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleContentBodyBlock] {
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

    nonisolated static func renderHTMLPicture(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        firstHTMLMediaImageBlocks(in: innerHTML, article: article) ?? []
    }

    nonisolated static func firstHTMLMediaImageBlocks(
        in innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock]? {
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

    nonisolated static func renderUnsupportedMediaFallback(
        tagName: String,
        html: String,
        innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        guard let mediaURL = resolveMediaFallbackURL(fromHTML: html, article: article) else {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        return mediaFallbackBlock(
            kind: unsupportedMediaKind(for: tagName, url: mediaURL),
            url: mediaURL
        )
    }

    nonisolated static func renderImageOrMediaFallback(
        fromImageTag imageTag: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        if let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
            return [.image(imageURL)]
        }

        if let mediaFallback = resolveVideoLikeMediaFallback(fromHTML: imageTag, article: article) {
            return mediaFallbackBlock(kind: mediaFallback.kind, url: mediaFallback.url)
        }

        return []
    }

    nonisolated static func mediaFallbackBlock(
        kind: ArticleContentMediaKind,
        url: URL
    ) -> [ArticleContentBodyBlock] {
        [.media(ArticleContentMediaBlock(kind: kind, url: url))]
    }}
