import SwiftUI

struct ReaderArticleFigureView: View {
    let blocks: [ArticleContentBodyBlock]
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReaderArticleBodyBlocksView(
                blocks: blocks,
                actionHandlers: actionHandlers
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct ReaderArticleDefinitionListView: View {
    let definitionList: ArticleContentDefinitionListBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(definitionList.entries) { entry in
                ReaderArticleDefinitionEntryView(
                    term: entry.term,
                    definitions: entry.definitions,
                    actionHandlers: actionHandlers
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderArticleDefinitionEntryView: View {
    let term: ArticleContentTextBlock?
    let definitions: [ArticleContentTextBlock?]
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let term {
                ReaderArticleSemanticTextView(
                    text: term,
                    actionHandlers: actionHandlers
                )
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(definitions.enumerated()), id: \.offset) { _, definition in
                    if let definition {
                        ReaderArticleSemanticTextView(
                            text: definition,
                            actionHandlers: actionHandlers
                        )
                        .font(.body)
                    }
                }
            }
            .padding(.leading, term == nil ? 0 : 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReaderArticleDisclosureView: View {
    let disclosure: ArticleContentDisclosureBlock
    let actionHandlers: ArticleScreenActionHandlers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool

    init(disclosure: ArticleContentDisclosureBlock, actionHandlers: ArticleScreenActionHandlers) {
        self.disclosure = disclosure
        self.actionHandlers = actionHandlers
        _isExpanded = State(initialValue: disclosure.isInitiallyExpanded)
    }

    private var summaryText: AttributedString {
        var text = disclosure.summary.attributedString
        // The header is one disclosure control, including when a source summary contains a link.
        for run in text.runs where run.link != nil {
            text[run.range].link = nil
        }
        return text
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ReaderArticleBodyBlocksView(
                blocks: disclosure.content,
                actionHandlers: actionHandlers
            )
            .padding(.top, 8)
        } label: {
            Text(summaryText)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: disclosure) { _, newValue in
            isExpanded = newValue.isInitiallyExpanded
        }
        .transaction { if reduceMotion { $0.animation = nil } }
    }
}

struct ReaderArticleAsideView: View {
    let blocks: [ArticleContentBodyBlock]
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            ReaderArticleBodyBlocksView(
                blocks: blocks,
                actionHandlers: actionHandlers
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.tint.opacity(0.28), lineWidth: 0.5)
        }
    }
}

struct ReaderArticleAddressView: View {
    let text: ArticleContentTextBlock
    let actionHandlers: ArticleScreenActionHandlers

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            ReaderArticleSemanticTextView(
                text: text,
                actionHandlers: actionHandlers
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
