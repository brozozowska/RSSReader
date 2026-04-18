import SwiftUI
import SwiftData
import Observation

/// Сборка корневого дерева приложения с зависимостями и (при наличии) SwiftData контейнером.
/// Создаёт корневой View c установленными зависимостями.
/// - Parameter models: Список SwiftData моделей. Если пустой — контейнер не создаётся.
enum AppComposition {
    static let appModels: [any PersistentModel.Type] = [
        AppSettings.self,
        Article.self,
        ArticleState.self,
        Feed.self,
        FeedFetchLog.self,
        Folder.self
    ]

    @ViewBuilder
    static func makeRoot(models: [any PersistentModel.Type] = []) -> some View {
        let deps: AppDependencies = models.isEmpty
        ? AppDependencies.makeDefault()
        : AppDependencies.makeWithSwiftData(models: models)

        AppRootContainer(dependencies: deps)
    }
}

private struct AppRootContainer: View {
    let dependencies: AppDependencies
    @State private var appState = AppState()
    @State private var hasLoadedPersistedSourcesFilter = false

    var body: some View {
        content
        .task {
            await restorePersistedSourcesFilterIfNeeded()
        }
        .onChange(of: appState.selectedSourcesFilter) { _, newFilter in
            guard hasLoadedPersistedSourcesFilter else { return }
            persistSourcesFilter(newFilter)
        }
    }

    @MainActor
    private func restorePersistedSourcesFilterIfNeeded() async {
        guard hasLoadedPersistedSourcesFilter == false else { return }
        defer { hasLoadedPersistedSourcesFilter = true }

        guard let appSettingsService = dependencies.appSettingsService else { return }

        do {
            let settings = try appSettingsService.fetchSettings()
            let restoredFilter = SourcesFilterPersistencePolicy.restoredFilter(
                from: settings.selectedSourcesFilterRawValue
            )

            if appState.selectedSourcesFilter != restoredFilter {
                appState.selectSourcesFilter(restoredFilter)
            }

            if settings.selectedSourcesFilterRawValue != restoredFilter.rawValue {
                _ = try appSettingsService.updateSettings(
                    SourcesFilterPersistencePolicy.makeSettingsPatch(for: restoredFilter)
                )
            }
        } catch {
            dependencies.logger.error("Failed to restore persisted sources filter: \(error)")
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
