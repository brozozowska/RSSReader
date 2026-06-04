import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller / Persistence")
@MainActor
struct SettingsScreenControllerPersistenceTests {
    @Test
    func settingsScreenControllerPersistsUpdatedArticleOpeningModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .articleOpeningMode,
            optionID: ArticleOpeningMode.safariView.rawValue,
            dependencies: harness.dependencies
        )

        let settingsBeforeApply = try repository.fetchOrCreate()
        #expect(controller.viewState().canApplyChanges)
        #expect(settingsBeforeApply.articleOpeningMode == .feedReader)
        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleOpeningMode == .safariView)
        #expect(persistedSettings.articleOpeningMode == .safariView)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedUnreadArticleSortOrderThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .unreadArticleSortOrder,
            optionID: UnreadArticleSortOrder.oldestFirst.rawValue,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.unreadArticleSortMode == .publishedAtAscending)
        #expect(persistedSettings.unreadSortMode == .publishedAtAscending)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedMarkAsReadOnOpenThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.markAsReadOnOpen)

        controller.handleToggleValueChange(
            itemID: .markAsReadOnOpen,
            isOn: false,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.markAsReadOnOpen == false)
        #expect(persistedSettings.markAsReadOnOpen == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedAskBeforeMarkingAllAsReadThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead)

        controller.handleToggleValueChange(
            itemID: .askBeforeMarkingAllAsRead,
            isOn: false,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedICloudSyncPreferenceThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.useiCloudSync == false)

        controller.handleToggleValueChange(
            itemID: .useICloudSync,
            isOn: true,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.useiCloudSync)
        #expect(persistedSettings.useiCloudSync)
        #expect(controller.screenState.iCloudSyncStatus == .disabled)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleBodyLinkOpeningPolicyThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .articleBodyLinkOpeningPolicy,
            optionID: ArticleBodyLinkOpeningPolicy.externalBrowser.rawValue,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(persistedSettings.articleBodyLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleSourceLinkOpeningPolicyThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .articleSourceLinkOpeningPolicy,
            optionID: ArticleSourceLinkOpeningPolicy.externalBrowser.rawValue,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(persistedSettings.articleSourceLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedReaderAdjacentNavigationControlsModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .readerAdjacentNavigationControlsMode,
            optionID: ReaderAdjacentNavigationControlsMode.toolbarControlsOnly.rawValue,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.readerAdjacentNavigationControlsMode == .toolbarControlsOnly)
        #expect(persistedSettings.readerAdjacentNavigationControlsMode == .toolbarControlsOnly)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedInterfaceThemeModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)
        controller.handlePickerOptionSelection(
            itemID: .appearance,
            optionID: InterfaceThemeMode.black.rawValue,
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(appState.interfaceThemeMode == .automaticLightDark)
        #expect(controller.applySettingsChanges(dependencies: harness.dependencies, appState: appState))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.interfaceThemeMode == .black)
        #expect(persistedSettings.interfaceThemeMode == .black)
        #expect(appState.interfaceThemeMode == .black)
    }
}
