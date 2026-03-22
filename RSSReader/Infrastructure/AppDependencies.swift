import Foundation
import SwiftUI
import SwiftData

// MARK: - AppDependencies protocol
public protocol AppDependenciesProtocol {
    var logger: Logging { get }
    var modelContainer: ModelContainer? { get }
}

public final class AppDependencies: AppDependenciesProtocol {
    
    public let logger: Logging
    public let modelContainer: ModelContainer?

    public init(
        logger: Logging,
        modelContainer: ModelContainer? = nil
    ) {
        self.logger = logger
        self.modelContainer = modelContainer
    }
}

// MARK: - Factory
public extension AppDependencies {
    static func makeDefault() -> AppDependencies {
#if DEBUG
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .debug, base: baseLogger)
#else
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .info, base: baseLogger)
#endif
        return AppDependencies(logger: logger)
    }
    
    static func makeWithSwiftData(models: [any PersistentModel.Type]) -> AppDependencies {
#if DEBUG
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .debug, base: baseLogger)
#else
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .info, base: baseLogger)
#endif
        return AppDependencies(logger: logger)
    }
}
