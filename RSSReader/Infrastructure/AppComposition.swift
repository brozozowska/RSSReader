import SwiftUI
import SwiftData
import Observation

/// Сборка корневого дерева приложения с зависимостями и (при наличии) SwiftData контейнером.
/// Создаёт корневой View c установленными зависимостями.
/// - Parameter modelPartition: Partition SwiftData моделей. Если `nil` — контейнер не создаётся.
enum AppComposition {
    static let persistenceModelPartition = AppPersistenceModelPartition.current
    static let syncEnablementPolicy = AppSyncEnablementPolicy.current
    static let syncBackedModels = persistenceModelPartition.syncBackedModels
    static let localOnlyModels = persistenceModelPartition.localOnlyModels
    static let appModels = persistenceModelPartition.allModels

    @MainActor
    @ViewBuilder
    static func makeRoot(modelPartition: AppPersistenceModelPartition? = nil) -> some View {
        let syncCoordinator = SyncCoordinator()
        let deps: AppDependencies = modelPartition.map {
            AppDependencies.makeWithSwiftData(
                modelPartition: $0,
                syncEnablementPolicy: syncEnablementPolicy,
                syncCoordinator: syncCoordinator
            )
        } ?? AppDependencies.makeDefault(syncCoordinator: syncCoordinator)
        let _ = deps.startSyncCoordinatorAppLifetime()

        AppRootContainer(dependencies: deps)
    }

    @MainActor
    static func makeRoot(dependencies: AppDependencies) -> some View {
        AppRootContainer(dependencies: dependencies)
    }

    @MainActor
    static func applyCurrentICloudSyncStatus(
        from syncCoordinator: SyncCoordinator?,
        to appState: AppState
    ) {
        guard let syncCoordinator else { return }

        let resolvedStatus = syncCoordinator.iCloudSyncStatus
        if appState.iCloudSyncStatus != resolvedStatus {
            appState.applyICloudSyncStatus(resolvedStatus)
        }
    }
}

struct AppRootContainer: View {
    let dependencies: AppDependencies
    @State private var appState = AppState()
    @State private var hasRestoredPersistedAppSettings = false

    var body: some View {
        let runtimeSyncStatus = dependencies.syncCoordinator?.iCloudSyncStatus

        content
        .task {
            AppComposition.applyCurrentICloudSyncStatus(
                from: dependencies.syncCoordinator,
                to: appState
            )
            dependencies.startRemoteSyncReloadAppLifetime(using: appState)
            await restorePersistedAppSettingsIfNeeded()
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

            if let iCloudSyncStatusService = dependencies.iCloudSyncStatusService {
                let iCloudSyncStatus = try iCloudSyncStatusService.currentStatus()
                if appState.iCloudSyncStatus != iCloudSyncStatus {
                    appState.applyICloudSyncStatus(iCloudSyncStatus)
                }
            }

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
