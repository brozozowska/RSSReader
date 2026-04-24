import SwiftUI
import SwiftData
import Observation

/// Сборка корневого дерева приложения с зависимостями и (при наличии) SwiftData контейнером.
/// Создаёт корневой View c установленными зависимостями.
/// - Parameter modelPartition: Partition SwiftData моделей. Если `nil` — контейнер не создаётся.
enum AppComposition {
    static let persistenceModelPartition = AppPersistenceModelPartition.current
    static let syncBackedModels = persistenceModelPartition.syncBackedModels
    static let localOnlyModels = persistenceModelPartition.localOnlyModels
    static let appModels = persistenceModelPartition.allModels

    @ViewBuilder
    static func makeRoot(modelPartition: AppPersistenceModelPartition? = nil) -> some View {
        let deps: AppDependencies = modelPartition.map {
            AppDependencies.makeWithSwiftData(modelPartition: $0)
        } ?? AppDependencies.makeDefault()

        AppRootContainer(dependencies: deps)
    }
}

private struct AppRootContainer: View {
    let dependencies: AppDependencies
    @State private var appState = AppState()
    @State private var hasRestoredPersistedAppSettings = false

    var body: some View {
        content
        .task {
            await restorePersistedAppSettingsIfNeeded()
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
