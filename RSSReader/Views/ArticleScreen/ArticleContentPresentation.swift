import SwiftUI

extension ArticleContentMediaKind {
    var actionTitle: String {
        switch self {
        case .audio:
            ReadingLocalization.openAudioAction
        case .video:
            ReadingLocalization.openVideoAction
        case .knownEmbedded, .embedded:
            ReadingLocalization.openEmbeddedContentAction
        case .generic:
            ReadingLocalization.openMediaAction
        }
    }
}

extension ArticleContentTextBlock {
    var attributedString: AttributedString {
        spans.reduce(into: AttributedString()) { partialResult, span in
            var attributedSpan = AttributedString(span.text)
            attributedSpan.link = span.linkURL
            attributedSpan.inlinePresentationIntent = span.inlinePresentationIntent
            // Source <mark> semantics do not override the Reader theme's text styling.
            if span.isInserted {
                attributedSpan.underlineStyle = .single
            }
            if let verticalAlignment = span.verticalAlignment {
                attributedSpan.font = .caption
                attributedSpan.baselineOffset = verticalAlignment == .superscript ? 4 : -2
            }
            partialResult.append(attributedSpan)
        }
    }
}

private extension ArticleContentTextSpan {
    var inlinePresentationIntent: InlinePresentationIntent? {
        var intent = InlinePresentationIntent()

        if isStrong {
            intent.insert(.stronglyEmphasized)
        }
        if isEmphasized {
            intent.insert(.emphasized)
        }
        if isCode {
            intent.insert(.code)
        }
        if isDeleted {
            intent.insert(.strikethrough)
        }
        if isCitation || codeSemantic == .variable {
            intent.insert(.emphasized)
        }

        return intent.isEmpty ? nil : intent
    }
}

extension ArticleContentNotice {
    var localizedText: String {
        switch self {
        case .summaryOnly: ReadingLocalization.summaryOnlyFallbackNotice
        case .emptyBody: ReadingLocalization.emptyBodyFallbackNotice
        }
    }
}
