import SwiftUI

// MARK: - SwiftUI Environment
private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies = AppDependencies.makeDefault()
}

public extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}

public extension View {
    func appDependencies(_ deps: AppDependencies) -> some View {
        environment(\._appDependencies, deps)
    }
}

private extension EnvironmentValues {
    var _appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
