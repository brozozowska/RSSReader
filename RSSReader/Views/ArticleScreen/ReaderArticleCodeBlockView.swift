import SwiftUI
import UIKit

struct ReaderArticleCodeBlockView: View {
    let code: String
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17

    var body: some View {
        Group {
            if code.trimmingCharacters(in: .newlines).contains(where: { $0.isNewline }) {
                ScrollView(.horizontal) {
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(10)
                }
            } else {
                ReaderArticleWrappingCodeView(code: code, fontSize: fontSize)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReaderArticleCodeBlockFramesPreferenceKey.self,
                    value: [proxy.frame(in: .global)]
                )
            }
            .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct ReaderArticleCodeBlockFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] { [] }

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

// UIKit supplies paragraph indentation and explicit hyphenation control while
// retaining native text selection. The attributed string contains only source text.
private struct ReaderArticleWrappingCodeView: UIViewRepresentable {
    let code: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> ReaderArticleWrappingCodeTextView {
        ReaderArticleWrappingCodeTextView()
    }

    func updateUIView(_ uiView: ReaderArticleWrappingCodeTextView, context: Context) {
        uiView.setCode(code, fontSize: fontSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderArticleWrappingCodeTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

final class ReaderArticleWrappingCodeTextView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCode(_ code: String, fontSize: CGFloat) {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .leftToRight
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = []
        paragraph.hyphenationFactor = 0
        paragraph.headIndent = ("  " as NSString).size(withAttributes: [.font: font]).width

        let text = NSAttributedString(string: code, attributes: [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ])
        if attributedText != text {
            attributedText = text
        }
    }
}
