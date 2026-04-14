import SwiftUI

struct ReaderView: View {
    @Environment(\.appDependencies) private var dependencies
    let articleID: UUID?
    let showsBackButton: Bool
    let navigateBackToArticles: () -> Void
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
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            if showsBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: navigateBackToArticles) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to Articles")
                }
            }
        }
        .task(id: articleID) {
            await controller.load(articleID: articleID, dependencies: dependencies)
        }
        .simultaneousGesture(backNavigationGesture)
    }

    private var backNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard showsBackButton else { return }
                guard ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                    startLocationX: value.startLocation.x,
                    translation: value.translation
                ) else {
                    return
                }
                navigateBackToArticles()
            }
    }
}

#Preview {
    ReaderView(
        articleID: nil,
        showsBackButton: false,
        navigateBackToArticles: {}
    )
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
