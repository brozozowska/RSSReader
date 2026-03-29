import SwiftUI

struct ReaderView: View {
    @Environment(\.appDependencies) private var dependencies
    let articleID: UUID?
    @State private var article: ReaderArticleDTO?
    @State private var hasLoadedArticle = false

    var body: some View {
        Group {
            if let article {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(article.title)
                            .font(.title2.weight(.semibold))

                        Text(article.feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let author = article.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let summary = article.summary {
                            Text(summary)
                                .font(.body)
                        } else if let contentText = article.contentText {
                            Text(contentText)
                                .font(.body)
                        } else if let contentHTML = article.contentHTML {
                            Text(contentHTML)
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else if hasLoadedArticle, articleID != nil {
                ContentUnavailableView(
                    "Article Not Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("The selected article could not be loaded from persistence.")
                )
            } else {
                ContentUnavailableView("No Article Selected", systemImage: "doc.text")
            }
        }
        .navigationTitle("Reader")
        .task(id: articleID) {
            await loadArticle()
        }
    }

    @MainActor
    private func loadArticle() async {
        defer { hasLoadedArticle = true }

        guard let articleID, let articleRepository = dependencies.articleRepository else {
            article = nil
            return
        }

        do {
            article = try articleRepository.fetchReaderArticle(id: articleID)
        } catch {
            dependencies.logger.error("Failed to load article by ID \(articleID): \(error)")
            article = nil
        }
    }
}

#Preview {
    ReaderView(articleID: nil)
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
