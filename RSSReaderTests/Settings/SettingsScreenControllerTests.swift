import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller")
@MainActor
struct SettingsScreenControllerTests {
    @Test
    func settingsScreenControllerDoesNotTreatSyncStatusRowAsInteractiveItem() {
        let controller = SettingsScreenController(
            previewScreenState: .previewLoaded(snapshot: AppSettingsSnapshot())
        )

        controller.handleItemSelection(.iCloudSyncStatus)

        #expect(controller.viewState().presentedPicker == nil)
    }

    @Test
    func settingsScreenControllerLoadsSettingsSnapshotFromService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.appSettingsService)
        _ = try service.saveSettings(
            AppSettingsSnapshot(
                defaultReaderMode: .reader,
                selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
                refreshIntervalPreference: .every15Minutes,
                useiCloudSync: false,
                markAsReadOnOpen: true,
                askBeforeMarkingAllAsRead: false,
                sortMode: .publishedAtDescending,
                articleBodyLinkOpeningPolicy: .externalBrowser,
                articleSourceLinkOpeningPolicy: .externalBrowser,
                interfaceThemeMode: .black
            ),
            updatedAt: .distantPast
        )
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)

        let viewState = controller.viewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.isEmpty == false)
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .reader)
        #expect(controller.screenState.settingsSnapshot.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(controller.screenState.settingsSnapshot.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(controller.screenState.settingsSnapshot.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(controller.screenState.settingsSnapshot.interfaceThemeMode == .black)
        #expect(controller.screenState.iCloudSyncStatus == .disabled)
        #expect(appState.interfaceThemeMode == .black)
    }

    @Test
    func settingsScreenControllerPrefersAppLevelICloudSyncStatusOverPersistedFlag() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()
        let appState = AppState()

        _ = try repository.update(
            AppSettingsUpdate(
                useiCloudSync: true,
                updatedAt: .distantPast
            )
        )
        appState.applyICloudSyncStatus(.syncing)

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)

        let syncSection = try #require(
            controller.viewState().sections.first(where: { $0.id == .sync })
        )
        let syncItem = try #require(syncSection.items.first)

        #expect(controller.screenState.iCloudSyncStatus == .syncing)
        #expect(appState.iCloudSyncStatus == .syncing)
        #expect(
            syncItem == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "iCloud Sync",
                    subtitle: "Changes are currently syncing with iCloud.",
                    valueTitle: "Syncing"
                )
            )
        )
    }

    @Test
    func settingsScreenControllerPersistsUpdatedDefaultReaderModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.defaultReaderMode)

        #expect(controller.viewState().presentedPicker?.id == .defaultReaderMode)

        controller.handlePickerOptionSelection(
            itemID: .defaultReaderMode,
            optionID: ReaderMode.browser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .browser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.defaultReaderMode == .browser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleSortModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleSortMode)

        #expect(controller.viewState().presentedPicker?.id == .articleSortMode)

        controller.handlePickerOptionSelection(
            itemID: .articleSortMode,
            optionID: ArticleListSortOrder.oldestFirst.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.sortMode == .publishedAtAscending)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.sortMode == .publishedAtAscending)
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

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleBodyLinkOpeningPolicyThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleBodyLinkOpeningPolicy)

        #expect(controller.viewState().presentedPicker?.id == .articleBodyLinkOpeningPolicy)

        controller.handlePickerOptionSelection(
            itemID: .articleBodyLinkOpeningPolicy,
            optionID: ArticleBodyLinkOpeningPolicy.externalBrowser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.articleBodyLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleSourceLinkOpeningPolicyThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleSourceLinkOpeningPolicy)

        #expect(controller.viewState().presentedPicker?.id == .articleSourceLinkOpeningPolicy)

        controller.handlePickerOptionSelection(
            itemID: .articleSourceLinkOpeningPolicy,
            optionID: ArticleSourceLinkOpeningPolicy.externalBrowser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.articleSourceLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedRefreshIntervalThroughBackgroundRefreshService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.refreshInterval)

        #expect(controller.viewState().presentedPicker?.id == .refreshInterval)

        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.daily.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.refreshIntervalPreference == .daily)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedInterfaceThemeModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)
        controller.handleItemSelection(.appearance)

        #expect(controller.viewState().presentedPicker?.id == .appearance)

        controller.handlePickerOptionSelection(
            itemID: .appearance,
            optionID: InterfaceThemeMode.black.rawValue,
            dependencies: harness.dependencies,
            appState: appState
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.interfaceThemeMode == .black)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.interfaceThemeMode == .black)
        #expect(appState.interfaceThemeMode == .black)
    }

    @Test
    func settingsScreenControllerBuildsFailureStateWhenSettingsServiceIsUnavailable() {
        let controller = SettingsScreenController()
        let dependencies = AppDependencies.makeDefault()

        controller.loadSettings(dependencies: dependencies)

        #expect(controller.viewState().sections.isEmpty)
        #expect(
            controller.viewState().placeholder == SettingsScreenPlaceholderState(
                title: "Unable to Load Settings",
                systemImage: "exclamationmark.triangle",
                description: "Settings are unavailable in the current app environment.",
                actionTitle: "Retry"
            )
        )
    }
}
