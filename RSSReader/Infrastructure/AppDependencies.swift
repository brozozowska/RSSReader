import Foundation
import SwiftUI
import SwiftData

// MARK: - Logging
public protocol Logging {
    func debug(_ message: @autoclosure () -> String)
    func info(_ message: @autoclosure () -> String)
    func error(_ message: @autoclosure () -> String)
}

public struct ConsoleLogger: Logging {
    public init() {}
    public func debug(_ message: @autoclosure () -> String) { print("[DEBUG] \(message())") }
    public func info(_ message: @autoclosure () -> String)  { print("[INFO]  \(message())") }
    public func error(_ message: @autoclosure () -> String) { print("[ERROR] \(message())") }
}

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
        let logger = ConsoleLogger()
        let deps = AppDependencies(logger: logger)
        logger.info("AppDependencies initialized")
        return deps
    }
    
    static func makeWithSwiftData(models: [any PersistentModel.Type]) -> AppDependencies {
        let logger = ConsoleLogger()
        do {
            let schema = Schema(models)
            let configuration = ModelConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let deps = AppDependencies(logger: logger, modelContainer: container)
            logger.info("AppDependencies with SwiftData initialized")
            return deps
        } catch {
            logger.error("Failed to initialize SwiftData container: \(error)")
            return AppDependencies(logger: logger, modelContainer: nil)
        }
    }
}

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
