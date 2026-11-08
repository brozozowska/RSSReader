import Foundation
import OSLog

public nonisolated enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case error = 2

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public nonisolated protocol Logging: Sendable {
    func debug(_ message: @autoclosure () -> String)
    func info(_ message: @autoclosure () -> String)
    func error(_ message: @autoclosure () -> String)
}

public nonisolated struct ConsoleLogger: Logging {
    public init() {}

    public func debug(_ message: @autoclosure () -> String) {
        print("DEBUG: \(message())")
    }

    public func info(_ message: @autoclosure () -> String) {
        print("INFO: \(message())")
    }

    public func error(_ message: @autoclosure () -> String) {
        print("ERROR: \(message())")
    }
}

public nonisolated struct OSLogger: Logging {
    private let osLogger: Logger

    public init(category: String, subsystem: String = Bundle.main.bundleIdentifier ?? "RSSReader") {
        self.osLogger = Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.debug("\(msg)")
    }
    public func info(_ message: @autoclosure () -> String)  {
        let msg = message()
        osLogger.info("\(msg)")
    }
    public func error(_ message: @autoclosure () -> String) {
        let msg = message()
        osLogger.error("\(msg)")
    }
}

public nonisolated struct FilteredLogger: Logging {
    public let minLevel: LogLevel
    private let base: Logging

    public init(minLevel: LogLevel, base: Logging) {
        self.minLevel = minLevel
        self.base = base
    }

    public func debug(_ message: @autoclosure () -> String) {
        guard shouldLog(.debug) else { return }
        let msg = message()
        base.debug(msg)
    }

    public func info(_ message: @autoclosure () -> String)  {
        guard shouldLog(.info) else { return }
        let msg = message()
        base.info(msg)
    }

    public func error(_ message: @autoclosure () -> String) {
        guard shouldLog(.error) else { return }
        let msg = message()
        base.error(msg)
    }

    private func shouldLog(_ level: LogLevel) -> Bool {
        level >= minLevel
    }
}
