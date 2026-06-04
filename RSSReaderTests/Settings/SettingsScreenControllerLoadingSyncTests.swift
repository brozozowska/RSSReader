import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller / Loading And Sync")
@MainActor
struct SettingsScreenControllerLoadingSyncTests {
    @Test
    func settingsScreenControllerIgnoresPickerSelectionForSyncStatusRow() {
        let controller = SettingsScreenController(
            previewScreenState: .previewLoaded(snapshot: AppSettingsSnapshot())
        )

        controller.handlePickerOptionSelection(
            itemID: .iCloudSyncStatus,
            optionID: "unsupported",
            dependencies: .makeDefault()
        )

        #expect(controller.screenState.settingsSnapshot == AppSettingsSnapshot())
    }

    @Test
    func settingsScreenControllerLoadsSettingsSnapshotFromService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.appSettingsService)
        _ = try service.saveSettings(
            AppSettingsSnapshot(
                articleOpeningMode: .feedReader,
                selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
                refreshIntervalPreference: .every15Minutes,
                useiCloudSync: false,
                markAsReadOnOpen: true,
                askBeforeMarkingAllAsRead: false,
                unreadArticleSortMode: .publishedAtDescending,
                articleBodyLinkOpeningPolicy: .externalBrowser,
                articleSourceLinkOpeningPolicy: .externalBrowser,
                readerAdjacentNavigationControlsMode: .swipesOnly,
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
        #expect(controller.screenState.settingsSnapshot.articleOpeningMode == .feedReader)
        #expect(controller.screenState.settingsSnapshot.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(controller.screenState.settingsSnapshot.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(controller.screenState.settingsSnapshot.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(controller.screenState.settingsSnapshot.readerAdjacentNavigationControlsMode == .swipesOnly)
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
            controller.viewState().sections.first(where: { $0.id == .updatesAndSync })
        )
        let syncToggle = try #require(syncSection.items.dropFirst().first)
        let syncStatusItem = try #require(syncSection.items.last)

        #expect(controller.screenState.iCloudSyncStatus == .syncing)
        #expect(appState.iCloudSyncStatus == .syncing)
        #expect(
            syncToggle == .toggle(
                SettingsToggleItemPresentation(
                    id: .useICloudSync,
                    title: "Enable iCloud Sync",
                    subtitle: "Applies on next launch. Supported data will sync through iCloud when available.",
                    isOn: true
                )
            )
        )
        #expect(
            syncStatusItem == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Changes are currently syncing with iCloud.",
                    valueTitle: "Syncing"
                )
            )
        )
    }

    @Test
    func settingsScreenControllerUsesSyncCoordinatorRuntimeStateForDetailedICloudAccountUX() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.noAccount)
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncCoordinator: syncCoordinator
        )
        let service = try #require(dependencies.appSettingsService)
        _ = try service.saveSettings(
            AppSettingsSnapshot(useiCloudSync: true),
            updatedAt: .distantPast
        )
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: dependencies, appState: appState)

        let syncSection = try #require(
            controller.viewState().sections.first(where: { $0.id == .updatesAndSync })
        )
        let syncStatusItem = try #require(syncSection.items.last)

        #expect(controller.screenState.iCloudSyncStatus == .statusUnavailable)
        #expect(controller.screenState.syncStatusPresentation == .noAccount)
        #expect(appState.iCloudSyncStatus == .statusUnavailable)
        #expect(
            syncStatusItem == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sign in to iCloud with the Apple ID used on this device to enable sync.",
                    valueTitle: "Sign In Required"
                )
            )
        )
    }

    @Test
    func settingsScreenControllerMapsSyncCoordinatorRuntimeStateForEachAccountAvailability() throws {
        for scenario in SettingsRuntimeAccountAvailabilityScenario.allCases {
            let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
            let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
            syncCoordinator.applyAccountAvailability(scenario.availability)
            let dependencies = AppDependencies(
                logger: TestLogger(),
                httpClient: harness.httpClient,
                modelContainer: harness.modelContainer,
                syncCoordinator: syncCoordinator
            )
            let service = try #require(dependencies.appSettingsService)
            _ = try service.saveSettings(
                AppSettingsSnapshot(useiCloudSync: true),
                updatedAt: .distantPast
            )
            let controller = SettingsScreenController()
            let appState = AppState()

            controller.loadSettings(dependencies: dependencies, appState: appState)

            #expect(controller.screenState.iCloudSyncStatus == scenario.expectedICloudSyncStatus)
            #expect(controller.screenState.syncStatusPresentation == scenario.expectedPresentation)
            #expect(appState.iCloudSyncStatus == scenario.expectedICloudSyncStatus)
        }
    }

    @Test
    func settingsScreenControllerExplainsSavedSyncPreferenceWhenCurrentLaunchStayedLocalOnly() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBootstrapContext: AppSyncBootstrapContext(
                desiredBootPreference: .enabled,
                desiredSyncBackedCloudKitPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
                modelContainerCloudKitPolicy: .disabled,
                accountAvailabilityAtBootstrap: .temporarilyUnavailable
            ),
            syncCoordinator: syncCoordinator
        )
        let service = try #require(dependencies.appSettingsService)
        _ = try service.saveSettings(
            AppSettingsSnapshot(useiCloudSync: true),
            updatedAt: .distantPast
        )
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: dependencies, appState: appState)

        let syncSection = try #require(
            controller.viewState().sections.first(where: { $0.id == .updatesAndSync })
        )

        #expect(controller.screenState.iCloudSyncStatus == .statusUnavailable)
        #expect(controller.screenState.syncStatusPresentation == .temporarilyUnavailable)
        #expect(controller.screenState.settingsInput.isUsingLocalOnlySyncFallbackForCurrentLaunch)
        #expect(appState.iCloudSyncStatus == .statusUnavailable)
        #expect(
            syncSection.items.dropFirst().first == .toggle(
                SettingsToggleItemPresentation(
                    id: .useICloudSync,
                    title: "Enable iCloud Sync",
                    subtitle: "Saved for the next launch. This session keeps using local data because the current iCloud account is temporarily unavailable.",
                    isOn: true
                )
            )
        )
        #expect(
            syncSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sync is enabled, but this launch cannot use iCloud because the current account is temporarily unavailable. Relaunch after iCloud becomes available.",
                    valueTitle: "Temporarily Unavailable"
                )
            )
        )
    }

    @Test
    func settingsScreenControllerMapsBootstrapFallbackForEachUnavailableAccountAvailability() throws {
        for scenario in SettingsBootstrapFallbackScenario.allCases {
            let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
            let syncCoordinator = SyncCoordinator()
            let dependencies = AppDependencies(
                logger: TestLogger(),
                httpClient: harness.httpClient,
                modelContainer: harness.modelContainer,
                syncBootstrapContext: AppSyncBootstrapContext(
                    desiredBootPreference: .enabled,
                    desiredSyncBackedCloudKitPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
                    modelContainerCloudKitPolicy: .disabled,
                    accountAvailabilityAtBootstrap: scenario.availability
                ),
                syncCoordinator: syncCoordinator
            )
            let service = try #require(dependencies.appSettingsService)
            _ = try service.saveSettings(
                AppSettingsSnapshot(useiCloudSync: true),
                updatedAt: .distantPast
            )
            let controller = SettingsScreenController()
            let appState = AppState()

            controller.loadSettings(dependencies: dependencies, appState: appState)

            #expect(controller.screenState.iCloudSyncStatus == .statusUnavailable)
            #expect(controller.screenState.syncStatusPresentation == scenario.expectedPresentation)
            #expect(controller.screenState.settingsInput.isUsingLocalOnlySyncFallbackForCurrentLaunch)
            #expect(appState.iCloudSyncStatus == .statusUnavailable)
        }
    }
}
