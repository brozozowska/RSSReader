import Foundation
@testable import RSSReader

@MainActor
final class NoOpFeedIconDiscoveryService: FeedIconDiscovering {
    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async -> URL? {
        nil
    }
}

@MainActor
final class StubFeedIconDiscoveryService: FeedIconDiscovering {
    private let iconURL: URL?

    init(iconURL: URL?) {
        self.iconURL = iconURL
    }

    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async -> URL? {
        iconURL
    }
}

@MainActor
final class RecordingFeedIconDiscoveryService: FeedIconDiscovering {
    private let iconURL: URL?
    private(set) var calls: [FeedIconDiscoveryCall] = []

    init(iconURL: URL?) {
        self.iconURL = iconURL
    }

    func discoverIconURL(
        feedURL: URL,
        siteURL: URL?,
        metadataIconURL: URL?
    ) async -> URL? {
        calls.append(
            FeedIconDiscoveryCall(
                feedURL: feedURL,
                siteURL: siteURL,
                metadataIconURL: metadataIconURL
            )
        )
        return iconURL
    }
}

struct FeedIconDiscoveryCall {
    let feedURL: URL
    let siteURL: URL?
    let metadataIconURL: URL?
}
