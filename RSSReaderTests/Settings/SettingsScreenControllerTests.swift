import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller")
@MainActor
struct SettingsScreenControllerTests {
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
                defaultReaderMode: .embedded,
                selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
                refreshIntervalPreference: .every15Minutes,
                useiCloudSync: false,
                markAsReadOnOpen: true,
                askBeforeMarkingAllAsRead: false,
                unreadSortMode: .publishedAtDescending,
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
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .embedded)
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

    @Test
    func settingsScreenControllerPersistsUpdatedDefaultReaderModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .defaultReaderMode,
            optionID: ReaderMode.browser.rawValue,
            dependencies: harness.dependencies
        )

        let settingsBeforeApply = try repository.fetchOrCreate()
        #expect(controller.viewState().canApplyChanges)
        #expect(settingsBeforeApply.defaultReaderMode == .embedded)
        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .browser)
        #expect(persistedSettings.defaultReaderMode == .browser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedUnreadArticleSortModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .unreadArticleSortMode,
            optionID: UnreadArticleSortOrder.oldestFirst.rawValue,
            dependencies: harness.dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.unreadSortMode == .publishedAtAscending)
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
    func settingsScreenControllerPersistsUpdatedRefreshIntervalThroughBackgroundRefreshService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let scheduler = SettingsRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler
        )
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: dependencies)
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.daily.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        let replacedConfiguration = try #require(scheduler.lastReplacedConfiguration)
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(persistedSettings.refreshIntervalPreference == .daily)
        #expect(replacedConfiguration.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(replacedConfiguration.policy.minimumInterval == TimeInterval(24 * 60 * 60))
    }

    @Test
    func settingsScreenControllerCancelsBackgroundRefreshScheduleWhenRefreshPreferenceBecomesManual() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let scheduler = SettingsRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler
        )
        let controller = SettingsScreenController()
        let appSettingsService = try #require(dependencies.appSettingsService)

        _ = try appSettingsService.saveSettings(
            AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            updatedAt: .distantPast
        )

        controller.loadSettings(dependencies: dependencies)
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.manual.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        let replacedConfiguration = try #require(scheduler.lastReplacedConfiguration)
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .manual)
        #expect(persistedSettings.refreshIntervalPreference == .manual)
        #expect(replacedConfiguration.settingsSnapshot.refreshIntervalPreference == .manual)
        #expect(replacedConfiguration.policy.minimumInterval == nil)
    }

    @Test
    func settingsScreenControllerLogsTypedBackgroundRefreshScheduleFailureAfterRefreshIntervalUpdate() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let scheduler = SettingsRecordingBackgroundRefreshScheduler(
            replaceError: NSError(
                domain: BGTaskScheduler.Error.errorDomain,
                code: BGTaskScheduler.Error.Code.notPermitted.rawValue
            )
        )
        let dependencies = AppDependencies(
            logger: logger,
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler
        )
        let controller = SettingsScreenController()
        let repository = try #require(dependencies.appSettingsRepository)

        controller.loadSettings(dependencies: dependencies)
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.daily.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(persistedSettings.refreshIntervalPreference == .daily)
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(
            logger.contains(
                "Failed to replace background refresh schedule after applying settings changes",
                level: .error
            )
        )
        #expect(logger.contains("reason=notPermitted", level: .error))
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

    @Test
    func settingsScreenControllerShowsModelContainerBootstrapFailureWhenAvailable() {
        let controller = SettingsScreenController()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            modelContainerBootstrapFailureDescription: "The app could not initialize its data store for the current sync configuration."
        )

        controller.loadSettings(dependencies: dependencies)

        #expect(controller.viewState().sections.isEmpty)
        #expect(
            controller.viewState().placeholder == SettingsScreenPlaceholderState(
                title: "Unable to Load Settings",
                systemImage: "exclamationmark.triangle",
                description: "The app could not initialize its data store for the current sync configuration.",
                actionTitle: "Retry"
            )
        )
    }
}

@MainActor
private final class SettingsRecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private(set) var lastReplacedConfiguration: BackgroundRefreshConfiguration?
    private let replaceError: Error?

    init(replaceError: Error? = nil) {
        self.replaceError = replaceError
    }

    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshSchedulePlan? {
        lastReplacedConfiguration = configuration
        return DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now)
    }

    func cancel() {}

    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshScheduleResult {
        lastReplacedConfiguration = configuration

        if let replaceError {
            throw replaceError
        }

        if let plan = DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now) {
            return .scheduled(plan)
        }

        return .cancelled
    }
}

private enum SettingsRuntimeAccountAvailabilityScenario: CaseIterable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var availability: ICloudAccountAvailability {
        switch self {
        case .available:
            .available
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedPresentation: SettingsSyncStatusPresentation {
        SettingsSyncStatusPresentation(accountAvailability: availability)
    }

    var expectedICloudSyncStatus: ICloudSyncStatus {
        expectedPresentation.iCloudSyncStatus
    }
}

private enum SettingsBootstrapFallbackScenario: CaseIterable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var availability: ICloudAccountAvailability {
        switch self {
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedPresentation: SettingsSyncStatusPresentation {
        SettingsSyncStatusPresentation(accountAvailability: availability)
    }
}
