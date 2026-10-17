import SwiftUI
import Testing
@testable import RSSReader

@Suite("Sidebar / Context Menu Preview")
@MainActor
struct SidebarContextMenuPreviewTests {
    @Test(arguments: [AppThemeVariant.light, .dark, .black])
    func detachedPreviewPreservesSourceEnvironment(theme: AppThemeVariant) throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: [:]))
        let appState = AppState()
        var environment = EnvironmentValues()
        environment[AppState.self] = appState
        environment.appDependencies = harness.dependencies
        environment.appThemeVariant = theme
        environment.colorScheme = theme == .light ? .light : .dark
        environment.locale = Locale(identifier: "ar")
        environment.layoutDirection = .rightToLeft
        environment.dynamicTypeSize = .xxxLarge
        environment.backgroundProminence = .increased
        var readCount = 0

        let probe = PreviewEnvironmentProbe { values, observedAppState in
            readCount += 1
            #expect(observedAppState === appState)
            #expect(values.appDependencies === harness.dependencies)
            #expect(values.appThemeVariant == theme)
            #expect(values.colorScheme == environment.colorScheme)
            #expect(values.locale.identifier == "ar")
            #expect(values.layoutDirection == .rightToLeft)
            #expect(values.dynamicTypeSize == .xxxLarge)
            #expect(values.backgroundProminence == .standard)
        }
        // No environment is supplied to this new root by an ancestor.
        let renderer = ImageRenderer(content: SidebarContextMenuPreview(
            content: probe,
            rowWidth: 370,
            sourceEnvironment: environment
        ))
        _ = try #require(renderer.uiImage)
        #expect(readCount > 0)
    }

    @Test
    func realFeedIconRendersInRepeatedDetachedPreviews() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: [:]))
        let appState = AppState()
        var environment = EnvironmentValues()
        environment[AppState.self] = appState
        environment.appDependencies = harness.dependencies

        for _ in 0..<2 {
            let renderer = ImageRenderer(content: SidebarContextMenuPreview(
                content: HStack {
                    FeedIconView(iconURL: nil)
                    Text("Feed")
                    Spacer()
                },
                rowWidth: 370,
                sourceEnvironment: environment
            ))
            renderer.scale = 1
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == 370)
            #expect(image.size.height >= 52)
        }
    }
}

private struct PreviewEnvironmentProbe: View {
    @Environment(\.self) private var values
    @Environment(AppState.self) private var appState
    let inspect: (EnvironmentValues, AppState) -> Void

    var body: some View {
        inspect(values, appState)
        return Text("Preview")
    }
}
