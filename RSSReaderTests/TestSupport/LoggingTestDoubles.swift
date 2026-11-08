import Foundation
import Synchronization
@testable import RSSReader

struct TestLogger: Logging {
    func debug(_ message: @autoclosure () -> String) {}
    func info(_ message: @autoclosure () -> String) {}
    func error(_ message: @autoclosure () -> String) {}
}

final class NoOpUnreadAppIconBadgeService: UnreadAppIconBadgeServicing {
    func refreshBadgeCount() async {}
    func applyBadgePreference(isEnabled: Bool) async {}
}

nonisolated final class RecordingLogger: Logging {
    struct Entry: Equatable, Sendable {
        let level: LogLevel
        let message: String
    }

    private let storage = Mutex<[Entry]>([])
    var entries: [Entry] { storage.withLock { $0 } }

    func debug(_ message: @autoclosure () -> String) {
        append(.debug, message())
    }

    func info(_ message: @autoclosure () -> String) {
        append(.info, message())
    }

    func error(_ message: @autoclosure () -> String) {
        append(.error, message())
    }

    private func append(_ level: LogLevel, _ message: String) {
        storage.withLock { $0.append(Entry(level: level, message: message)) }
    }

    func contains(_ fragment: String, level: LogLevel? = nil) -> Bool {
        entries.contains { entry in
            let matchesLevel = level.map { entry.level == $0 } ?? true
            return matchesLevel && entry.message.contains(fragment)
        }
    }
}
