import SwiftUI

struct ArticleListView: View {
    let selectedFeedID: UUID?
    @Binding var selection: UUID?

    private let articles: [(id: UUID, title: String)] = [
        (UUID(), "First article"),
        (UUID(), "Second article"),
        (UUID(), "Third article"),
    ]

    var body: some View {
        List(articles, id: \.id, selection: $selection) { article in
            Text(article.title)
        }
        .navigationTitle("Articles")
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var selection: UUID? = nil
        var body: some View {
            ArticleListView(selectedFeedID: nil, selection: $selection)
        }
    }
    return PreviewContainer()
}
