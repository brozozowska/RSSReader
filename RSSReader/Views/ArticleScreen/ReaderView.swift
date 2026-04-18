import SwiftUI

struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    let articleID: UUID?
    let showsBackButton: Bool
    let navigateBackToArticles: () -> Void
    let previewScreenState: ArticleScreenState?
    @State private var controller = ArticleScreenController()

    init(
        articleID: UUID?,
        showsBackButton: Bool,
        navigateBackToArticles: @escaping () -> Void,
        previewScreenState: ArticleScreenState? = nil
    ) {
        self.articleID = articleID
        self.showsBackButton = showsBackButton
        self.navigateBackToArticles = navigateBackToArticles
        self.previewScreenState = previewScreenState
        self._controller = State(initialValue: ArticleScreenController(previewScreenState: previewScreenState))
    }

    var body: some View {
        let viewState = controller.screenState.derivedViewState()

        Group {
            if let content = viewState.content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let publishedAtText = content.header.publishedAtText {
                            Text(publishedAtText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(content.header.title)
                            .font(.title2.weight(.semibold))

                        if let author = content.header.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let feedTitle = content.header.feedTitle {
                            Text(feedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(content.body.blocks.enumerated()), id: \.offset) { _, block in
                            bodyBlockView(block)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else if let primaryLoadingState = viewState.primaryLoadingState {
                ScreenLoadingView(title: primaryLoadingState.title)
            } else if let placeholder = viewState.placeholder {
                ScreenPlaceholderView(
                    title: placeholder.title,
                    systemImage: placeholder.systemImage,
                    description: placeholder.description
                )
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            if viewState.toolbarActions.showsShareAction {
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareURL = viewState.toolbarActions.shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share")
                    } else {
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(true)
                        .accessibilityLabel("Share")
                    }
                }
            }

            if viewState.toolbarActions.showsBottomActions,
               let bottomActions = viewState.toolbarActions.bottomActions {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleMarkUnreadActionTap) {
                        Image(systemName: bottomActions.readToggleSystemImage)
                    }
                    .accessibilityLabel(bottomActions.readToggleTitle)
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleStarActionTap) {
                        Image(systemName: bottomActions.starSystemImage)
                    }
                    .accessibilityLabel(bottomActions.starTitle)
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: handleOpenInAppBrowserTap) {
                        Image(systemName: bottomActions.openInAppBrowserSystemImage)
                    }
                    .disabled(bottomActions.canOpenInAppBrowser == false)
                    .accessibilityLabel(bottomActions.openInAppBrowserTitle)
                }                
            }
        }
        .task(id: articleID) {
            guard previewScreenState == nil else { return }
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

    @MainActor
    private func handleMarkUnreadActionTap() {
        _controller.wrappedValue.toggleArticleReadStatus(
            dependencies: dependencies,
            isPreviewMode: previewScreenState != nil
        )
    }

    @MainActor
    private func handleStarActionTap() {
        _controller.wrappedValue.toggleArticleStarredStatus(
            dependencies: dependencies,
            isPreviewMode: previewScreenState != nil
        )
    }

    @MainActor
    private func handleOpenInAppBrowserTap() {
        _controller.wrappedValue.openArticleInAppBrowser(
            dependencies: dependencies,
            appState: appState
        )
    }

    @ViewBuilder
    private func bodyBlockView(_ block: ArticleScreenBodyBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text.plainText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    ContentUnavailableView(
                        "Image Unavailable",
                        systemImage: "photo",
                        description: Text("The article image could not be loaded.")
                    )
                @unknown default:
                    EmptyView()
                }
            }
        case .fallbackNotice(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}
