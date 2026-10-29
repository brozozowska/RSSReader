import SwiftUI

struct ReaderArticleMediaView: View {
    let media: ArticleContentMediaBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        Button {
            actionHandlers.bodyLinkTapped(media.url)
        } label: {
            Label(media.kind.actionTitle, systemImage: systemImageName)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .accessibilityLabel(media.kind.actionTitle)
    }

    private var systemImageName: String {
        switch media.kind {
        case .audio:
            "waveform"
        case .video:
            "play.rectangle"
        case .knownEmbedded:
            "play.rectangle.fill"
        case .embedded:
            "rectangle.on.rectangle"
        case .generic:
            "link"
        }
    }
}
