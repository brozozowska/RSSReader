import SwiftUI

// MARK: - SwiftUI Environment
private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies = AppDependencies.makeDefault()
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
