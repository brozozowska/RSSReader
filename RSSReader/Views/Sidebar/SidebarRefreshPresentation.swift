import SwiftUI

struct SidebarOverlayContent: View {
    let viewState: SidebarScreenDerivedViewState

    var body: some View {
        if let primaryLoadingState = viewState.primaryLoadingState {
            ScreenLoadingView(title: primaryLoadingState.title)
        } else if let placeholder = viewState.placeholder {
            ScreenPlaceholderView(
                title: placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description
            )
        }
    }
}
