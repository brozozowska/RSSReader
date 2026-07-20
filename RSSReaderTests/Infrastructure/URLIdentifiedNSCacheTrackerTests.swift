import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / URL Identified NSCache Tracker")
struct URLIdentifiedNSCacheTrackerTests {
    @Test
    func memoryPressureEvictionCallbackDoesNotRemoveReplacementBookkeeping() throws {
        let url = try #require(URL(string: "https://example.com/replaced-cache-entry"))
        let originalEntry = CacheTrackerTestEntry(cacheURL: url)
        let replacementEntry = CacheTrackerTestEntry(cacheURL: url)
        let tracker = URLIdentifiedNSCacheTracker<CacheTrackerTestEntry>()
        let cache = NSCache<AnyObject, AnyObject>()

        tracker.track(originalEntry)
        tracker.track(replacementEntry)
        tracker.cache(cache, willEvictObject: originalEntry)

        #expect(tracker.entryCount == 1)
        #expect(tracker.hasEntries)

        tracker.cache(cache, willEvictObject: replacementEntry)

        #expect(tracker.entryCount == 0)
        #expect(tracker.hasEntries == false)
    }
}

private final class CacheTrackerTestEntry: NSObject, URLIdentifiedNSCacheEntry {
    let cacheURL: URL

    init(cacheURL: URL) {
        self.cacheURL = cacheURL
    }
}
