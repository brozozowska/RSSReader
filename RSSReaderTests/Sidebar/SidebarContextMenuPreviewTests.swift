import SwiftUI
import Testing
import UIKit
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
        // Model a row whose inherited scheme still belongs to the previous theme.
        environment.colorScheme = theme == .light ? .dark : .light
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
            #expect(values.colorScheme == (theme == .light ? .light : .dark))
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

    @Test(arguments: [AppThemeVariant.light, .dark, .black])
    func previewForegroundResetsInheritedRowStyle(theme: AppThemeVariant) throws {
        var environment = EnvironmentValues()
        environment.appThemeVariant = theme
        environment.colorScheme = theme == .light ? .dark : .light
        let renderer = ImageRenderer(content: SidebarContextMenuPreview(
            content: Rectangle().fill(.foreground).frame(width: 20, height: 20),
            rowWidth: 100,
            sourceEnvironment: environment
        ).foregroundStyle(theme == .light ? Color.white : Color.black))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Sample the centre of the foreground, avoiding antialiasing at its edge.
        context.translateBy(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if theme == .light {
            #expect(pixel[0] < 40 && pixel[1] < 40 && pixel[2] < 40)
        } else {
            #expect(pixel[0] > 210 && pixel[1] > 210 && pixel[2] > 210)
        }
    }

    @Test
    func retainedPreviewUsesCurrentExplicitTheme() throws {
        let appState = AppState()
        var environment = EnvironmentValues()
        environment[AppState.self] = appState
        environment.appThemeVariant = .light
        environment.colorScheme = .light
        var expectedTheme = AppThemeVariant.light
        var observations = 0
        let preview = SidebarContextMenuPreview(
            content: PreviewEnvironmentProbe { values, observedState in
                observations += 1
                #expect(observedState === appState)
                #expect(values.appThemeVariant == expectedTheme)
                #expect(values.colorScheme == (expectedTheme == .light ? .light : .dark))
            },
            rowWidth: 370,
            sourceEnvironment: environment
        )

        for (mode, theme) in [(InterfaceThemeMode.dark, AppThemeVariant.dark),
                              (.black, .black), (.light, .light)] {
            expectedTheme = theme
            appState.applyInterfaceThemeMode(mode)
            let previousObservations = observations
            let renderer = ImageRenderer(content: preview)
            _ = try #require(renderer.uiImage)
            #expect(observations > previousObservations)
        }
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
