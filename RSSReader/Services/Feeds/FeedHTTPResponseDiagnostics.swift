import Foundation

nonisolated enum FeedHTTPResponseDiagnostics {
    // Reject unusable or unreasonably distant server hints; no retry is scheduled here.
    private static let maximumRetryDelay: TimeInterval = 7 * 24 * 60 * 60

    static func safeURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid URL>"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<invalid URL>"
    }

    static func retryAt(for response: HTTPResponse, now: Date = .now) -> Date? {
        if let value = response.headerValue(named: "Retry-After") {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return retryDate(seconds: value, now: now)
            }
            guard value.count <= 64 else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            formatter.isLenient = false
            guard let date = formatter.date(from: value),
                  date.timeIntervalSince(now) <= maximumRetryDelay else { return nil }
            return max(date, now)
        }
        guard ["reddit.com", "www.reddit.com", "old.reddit.com"].contains(response.url.host?.lowercased() ?? ""),
              let reset = response.headerValue(named: "x-ratelimit-reset") else { return nil }
        return retryDate(seconds: reset.trimmingCharacters(in: .whitespacesAndNewlines), now: now)
    }

    private static func retryDate(seconds: String, now: Date) -> Date? {
        guard seconds.count <= 32,
              seconds.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let delay = TimeInterval(seconds), delay.isFinite,
              delay >= 0, delay <= maximumRetryDelay else { return nil }
        return now.addingTimeInterval(delay)
    }
}
