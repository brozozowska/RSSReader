import Foundation
import Synchronization

nonisolated protocol URLIdentifiedNSCacheEntry: AnyObject {
    var cacheURL: URL { get }
}

nonisolated final class URLIdentifiedNSCacheTracker<Entry: URLIdentifiedNSCacheEntry>:
    NSObject,
    NSCacheDelegate,
    Sendable
{
    private let entryIdentifiersByURL = Mutex<[URL: ObjectIdentifier]>([:])

    var hasEntries: Bool {
        entryIdentifiersByURL.withLock { !$0.isEmpty }
    }

    var entryCount: Int {
        entryIdentifiersByURL.withLock { $0.count }
    }

    func track(_ entry: Entry) {
        entryIdentifiersByURL.withLock {
            $0[entry.cacheURL] = ObjectIdentifier(entry)
        }
    }

    func removeEntry(for url: URL) {
        _ = entryIdentifiersByURL.withLock { $0.removeValue(forKey: url) }
    }

    func removeAllEntries() {
        entryIdentifiersByURL.withLock { $0.removeAll() }
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let entry = object as? Entry else { return }
        let identifier = ObjectIdentifier(entry)

        entryIdentifiersByURL.withLock {
            guard $0[entry.cacheURL] == identifier else { return }
            $0.removeValue(forKey: entry.cacheURL)
        }
    }
}
