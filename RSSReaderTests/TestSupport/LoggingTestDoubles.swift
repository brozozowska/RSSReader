import Foundation
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

final class RecordingLogger: Logging {
    struct Entry: Equatable {
        let level: LogLevel
        let message: String
    }

    private(set) var entries: [Entry] = []

    func debug(_ message: @autoclosure () -> String) {
        entries.append(Entry(level: .debug, message: message()))
    }

    func info(_ message: @autoclosure () -> String) {
        entries.append(Entry(level: .info, message: message()))
    }

    func error(_ message: @autoclosure () -> String) {
        entries.append(Entry(level: .error, message: message()))
    }

    func contains(_ fragment: String, level: LogLevel? = nil) -> Bool {
        entries.contains { entry in
            let matchesLevel = level.map { entry.level == $0 } ?? true
            return matchesLevel && entry.message.contains(fragment)
        }
    }
}
