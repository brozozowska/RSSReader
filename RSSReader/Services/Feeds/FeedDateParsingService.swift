import Foundation

nonisolated enum FeedDateParsingService {
    static func parse(_ value: String?) -> Date? {
        parser.parse(value)
    }

    private static let parser = SynchronizedFeedDateParser()
}

// Date formatter instances are mutable; every access is serialized by `lock`.
private nonisolated final class SynchronizedFeedDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private let dateFormatters: [DateFormatter] = [
        makeDateFormatter("EEE, d MMM yy HH:mm:ss Z"),
        makeDateFormatter("EEE, dd MMM yy HH:mm:ss Z"),
        makeDateFormatter("EEE, d MMM yy HH:mm Z"),
        makeDateFormatter("EEE, dd MMM yy HH:mm Z"),
        makeDateFormatter("EEE, d MMM yyyy HH:mm:ss Z"),
        makeDateFormatter("EEE, dd MMM yyyy HH:mm:ss Z"),
        makeDateFormatter("EEE, d MMM yyyy HH:mm Z"),
        makeDateFormatter("EEE, dd MMM yyyy HH:mm Z"),
        makeDateFormatter("d MMM yyyy HH:mm:ss Z"),
        makeDateFormatter("dd MMM yyyy HH:mm:ss Z"),
        makeDateFormatter("d MMM yyyy HH:mm Z"),
        makeDateFormatter("dd MMM yyyy HH:mm Z"),
        makeDateFormatter("EEE MMM d HH:mm:ss yyyy"),
        makeDateFormatter("EEE MMM dd HH:mm:ss yyyy"),
        makeDateFormatter("yyyy-MM-dd HH:mm:ss Z"),
        makeDateFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
        makeDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
        makeDateFormatter("yyyy-MM-dd")
    ]

    func parse(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }

        return lock.withLock {
            if let date = iso8601WithFractionalSeconds.date(from: value) {
                return date
            }

            if let date = iso8601Basic.date(from: value) {
                return date
            }

            for formatter in dateFormatters {
                if let date = formatter.date(from: value) {
                    return date
                }
            }

            return nil
        }
    }

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }
}
