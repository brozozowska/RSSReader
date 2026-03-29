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

        let appState = AppState()

        if let container = deps.modelContainer {
            RootView()
                .environment(\.appDependencies, deps)
                .environment(appState)
                .modelContainer(container)
        } else {
            RootView()
                .environment(\.appDependencies, deps)
                .environment(appState)
        }
    }
}
