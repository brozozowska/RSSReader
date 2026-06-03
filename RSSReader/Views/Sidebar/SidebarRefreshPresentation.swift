import SwiftUI

struct SidebarCustomRefreshIndicator: View {
    let customRefreshState: SidebarCustomRefreshState

    var body: some View {
        if customRefreshState.showsIndicator {
            VStack {
                AppRefreshIndicator(
                    state: customRefreshState.indicatorState,
                    size: 24,
                    lineWidth: 2.5
                )
                .padding(.top, 14)

                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

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
