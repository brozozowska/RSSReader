import SwiftUI

struct ReaderView: View {
    @Environment(\.appDependencies) private var dependencies
    let articleID: UUID?
    @State private var controller = ArticleScreenController()

    var body: some View {
        let viewState = controller.screenState.derivedViewState()

        Group {
            if let content = viewState.content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(content.title)
                            .font(.title2.weight(.semibold))

                        Text(content.feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let author = content.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let bodyText = content.body.text {
                            Text(bodyText)
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else if controller.screenState.showsPrimaryLoadingIndicator {
                ProgressView("Loading Article")
            } else if let placeholder = viewState.placeholder {
                ContentUnavailableView(
                    placeholder.title,
                    systemImage: placeholder.systemImage,
                    description: placeholder.description.map(Text.init)
                )
            }
        }
        .navigationTitle("Reader")
        .task(id: articleID) {
            await controller.load(articleID: articleID, dependencies: dependencies)
        }
    }
}

#Preview {
    ReaderView(articleID: nil)
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
