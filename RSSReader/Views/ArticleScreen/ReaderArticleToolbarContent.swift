import SwiftUI

struct ReaderArticleToolbarContent: ToolbarContent {
    let toolbarActions: ArticleScreenToolbarActionsState
    let adjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode
    let previousArticleID: UUID?
    let canNavigateToNextArticle: Bool
    let actionHandlers: ArticleScreenActionHandlers
    let onPreviousArticleTap: () -> Void
    let onNextArticleTap: () -> Void

    var body: some ToolbarContent {
        if toolbarActions.showsShareAction {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareURL = toolbarActions.shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(ReadingLocalization.shareActionAccessibilityLabel)
                } else {
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(true)
                    .accessibilityLabel(ReadingLocalization.shareActionAccessibilityLabel)
                }
            }
        }

        if toolbarActions.showsBottomActions,
           let bottomActions = toolbarActions.bottomActions {
            ToolbarItem(placement: .bottomBar) {
                Button(action: actionHandlers.toggleReadStatus) {
                    Image(systemName: bottomActions.readToggleSystemImage)
                }
                .accessibilityLabel(bottomActions.readToggleTitle)
            }

            ToolbarSpacer(placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button(action: actionHandlers.toggleStarredStatus) {
                    Image(systemName: bottomActions.starSystemImage)
                }
                .accessibilityLabel(bottomActions.starTitle)
            }

            ToolbarSpacer(placement: .bottomBar)

            if adjacentNavigationControlsMode.showsToolbarControls {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: onNextArticleTap) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(canNavigateToNextArticle == false)
                    .accessibilityLabel(ReadingLocalization.nextArticleAccessibilityLabel)
                }

                ToolbarSpacer(placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(action: onPreviousArticleTap) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(previousArticleID == nil)
                    .accessibilityLabel(ReadingLocalization.previousArticleAccessibilityLabel)
                }

                ToolbarSpacer(placement: .bottomBar)
            }

            ToolbarItem(placement: .bottomBar) {
                Button(action: actionHandlers.openSourceArticle) {
                    Image(systemName: bottomActions.openSourceArticleSystemImage)
                }
                .disabled(bottomActions.canOpenSourceArticle == false)
                .accessibilityLabel(bottomActions.openSourceArticleTitle)
            }
        }
    }
}
