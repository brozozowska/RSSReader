import SwiftUI
import SwiftData
import Observation

/// Сборка корневого дерева приложения с app-level зависимостями и SwiftData контейнером.
/// Для app bootstrap всегда использует единый `makeAppDependencies()` path.
/// - Parameter modelPartition: Partition SwiftData моделей. Если `nil`, используется `current` partition.
enum AppComposition {
    static let persistenceModelPartition = AppPersistenceModelPartition.current
    static let syncEnablementPolicy = AppSyncEnablementPolicy.current
    static let syncBackedModels = persistenceModelPartition.syncBackedModels
    static let localOnlyModels = persistenceModelPartition.localOnlyModels
    static let appModels = persistenceModelPartition.allModels
    @MainActor
    static let developmentSchemaBootstrapGuard = AppLaunchBootstrapGuard()
    @MainActor
    static let backgroundRefreshLaunchSchedulingGuard = AppLaunchBootstrapGuard()

    @MainActor
    static func makeAppDependencies(
        modelPartition: AppPersistenceModelPartition? = nil,
        syncEnablementPolicy: AppSyncEnablementPolicy? = nil
    ) -> AppDependencies {
        let logger = AppDependencies.makeDefaultLogger()
        let resolvedModelPartition = modelPartition ?? persistenceModelPartition
        let resolvedSyncEnablementPolicy = syncEnablementPolicy ?? self.syncEnablementPolicy

#if DEBUG
        runDevelopmentSchemaBootstrapIfNeeded(logger: logger)
#endif

        let syncCoordinator = SyncCoordinator(logger: logger)
        let dependencies = AppDependencies.makeWithSwiftData(
            modelPartition: resolvedModelPartition,
            syncEnablementPolicy: resolvedSyncEnablementPolicy,
            syncCoordinator: syncCoordinator,
            logger: logger
        )
        dependencies.startSyncCoordinatorAppLifetime()
        return dependencies
    }

    @MainActor
    @ViewBuilder
    static func makeRoot(modelPartition: AppPersistenceModelPartition? = nil) -> some View {
        let deps = makeAppDependencies(modelPartition: modelPartition)

        AppRootContainer(dependencies: deps)
    }

    @MainActor
    static func makeRoot(dependencies: AppDependencies) -> some View {
        AppRootContainer(dependencies: dependencies)
    }
}

struct AppRootContainer: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()
    @State private var hasRestoredPersistedAppSettings = false

    var body: some View {
        let runtimeSyncStatus = dependencies.syncCoordinator?.iCloudSyncStatus

        content
        .task {
            AppComposition.scheduleBackgroundRefreshOnLaunchIfNeeded(using: dependencies)
            AppComposition.applyCurrentICloudSyncStatus(
                from: dependencies.syncCoordinator,
                to: appState
            )
            AppComposition.bindBackgroundRefreshForegroundReloadHandler(
                using: dependencies,
                appState: appState
            )
            AppComposition.applyBackgroundRefreshForegroundRuntimeState(
                from: scenePhase,
                using: dependencies
            )
            dependencies.startRemoteSyncReloadAppLifetime(using: appState)
            await restorePersistedAppSettingsIfNeeded()
            await dependencies.refreshUnreadAppIconBadgeCount()
        }
        .onChange(of: scenePhase) { _, newPhase in
            AppComposition.applyBackgroundRefreshForegroundRuntimeState(
                from: newPhase,
                using: dependencies
            )
        }
        .onChange(of: runtimeSyncStatus) { _, _ in
            AppComposition.applyCurrentICloudSyncStatus(
                from: dependencies.syncCoordinator,
                to: appState
            )
        }
        .onChange(of: appState.selectedSourcesFilter) { _, newFilter in
            guard hasRestoredPersistedAppSettings else { return }
            persistSourcesFilter(newFilter)
        }
        .onDisappear {
            AppComposition.unbindBackgroundRefreshForegroundReloadHandler(using: dependencies)
        }
    }

    @MainActor
    private func restorePersistedAppSettingsIfNeeded() async {
        guard hasRestoredPersistedAppSettings == false else { return }
        defer { hasRestoredPersistedAppSettings = true }

        guard let appSettingsService = dependencies.appSettingsService else { return }

        do {
            let settings = try appSettingsService.fetchSettings()
            let restoredFilter = SourcesFilterPersistencePolicy.restoredFilter(
                from: settings.selectedSourcesFilterRawValue
            )

            if appState.selectedSourcesFilter != restoredFilter {
                appState.selectSourcesFilter(restoredFilter)
            }

            if appState.interfaceThemeMode != settings.interfaceThemeMode {
                appState.applyInterfaceThemeMode(settings.interfaceThemeMode)
            }

            AppComposition.applyCurrentICloudSyncStatus(
                from: dependencies.syncCoordinator,
                to: appState
            )

            if settings.selectedSourcesFilterRawValue != restoredFilter.rawValue {
                _ = try appSettingsService.updateSettings(
                    SourcesFilterPersistencePolicy.makeSettingsPatch(for: restoredFilter)
                )
            }
        } catch {
            dependencies.logger.error("Failed to restore persisted app settings: \(error)")
        }
    }

    @MainActor
    private func persistSourcesFilter(_ filter: SourcesFilter) {
        guard let appSettingsService = dependencies.appSettingsService else { return }

        do {
            _ = try appSettingsService.updateSettings(
                SourcesFilterPersistencePolicy.makeSettingsPatch(for: filter)
            )
        } catch {
            dependencies.logger.error("Failed to persist sources filter \(filter.rawValue): \(error)")
        }
    }
}

enum SourcesFilterPersistencePolicy {
    static func restoredFilter(from persistedRawValue: String?) -> SourcesFilter {
        if let rawValue = persistedRawValue,
           let persistedFilter = SourcesFilter(rawValue: rawValue) {
            return persistedFilter
        }

        return .allItems
    }

    static func makeSettingsPatch(for filter: SourcesFilter, updatedAt: Date = .now) -> AppSettingsPatch {
        AppSettingsPatch(
            selectedSourcesFilterRawValue: filter.rawValue,
            updatedAt: updatedAt
        )
    }
}

private extension AppRootContainer {
    @ViewBuilder
    var content: some View {
        if let container = dependencies.modelContainer {
            RootView()
                .environment(\.appDependencies, dependencies)
                .environment(appState)
                .modelContainer(container)
        } else {
            RootView()
                .environment(\.appDependencies, dependencies)
                .environment(appState)
        }
    }
}
