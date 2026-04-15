import Foundation
import Observation

@MainActor
@Observable
final class WebViewScreenController {
    var screenState: WebViewScreenState

    init(route: ArticleWebViewRoute) {
        self.screenState = WebViewScreenState(route: route)
    }

    func handleNavigationStarted() {
        screenState.applyNavigationStart()
    }

    func handleLoadingProgressChanged(_ progress: Double) {
        screenState.applyLoadingProgress(progress)
    }

    func handlePageTitleChanged(_ title: String?) {
        screenState.applyPageTitle(title)
    }

    func handleNavigationFinished() {
        screenState.applyNavigationFinished()
    }

    func handleNavigationFailed(_ error: Error) {
        screenState.applyNavigationFailure(error.localizedDescription)
    }
}
