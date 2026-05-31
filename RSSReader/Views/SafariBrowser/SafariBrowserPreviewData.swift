import SwiftUI

#Preview("Live Page") {
    NavigationStack {
        SafariBrowserView(
            route: SafariBrowserPreviewData.route,
            dismissSafari: {}
        )
    }
}

#Preview("Unsupported URL") {
    NavigationStack {
        SafariBrowserView(
            route: SafariBrowserPreviewData.unsupportedRoute,
            dismissSafari: {}
        )
    }
}

// MARK: - Preview Data

private enum SafariBrowserPreviewData {
    static let route = ArticleSafariRoute(
        articleID: UUID(),
        url: URL(string: "https://example.com")!
    )

    static let unsupportedRoute = ArticleSafariRoute(
        articleID: UUID(),
        url: URL(string: "mailto:hello@example.com")!
    )
}
