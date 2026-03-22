import SwiftUI
import SwiftData

/// Сборка корневого дерева приложения с зависимостями и (при наличии) SwiftData контейнером.
/// Создаёт корневой View c установленными зависимостями.
/// - Parameter models: Список SwiftData моделей. Если пустой — контейнер не создаётся.
enum AppComposition {

    @ViewBuilder
    static func makeRoot(models: [any PersistentModel.Type] = []) -> some View {
        let deps: AppDependencies = models.isEmpty
        ? AppDependencies.makeDefault()
        : AppDependencies.makeWithSwiftData(models: models)

        if let container = deps.modelContainer {
            RootView()
                .environment(\.appDependencies, deps)
                .modelContainer(container)
        } else {
            RootView()
                .environment(\.appDependencies, deps)
        }
    }
}
