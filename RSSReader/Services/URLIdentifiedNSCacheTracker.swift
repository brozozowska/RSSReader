import Foundation

protocol URLIdentifiedNSCacheEntry: AnyObject {
    var cacheURL: URL { get }
}

final class URLIdentifiedNSCacheTracker<Entry: URLIdentifiedNSCacheEntry>:
    NSObject,
    NSCacheDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var entryIdentifiersByURL: [URL: ObjectIdentifier] = [:]

    var hasEntries: Bool {
        lock.withLock {
            entryIdentifiersByURL.isEmpty == false
        }
    }

    var entryCount: Int {
        lock.withLock {
            entryIdentifiersByURL.count
        }
    }

    func track(_ entry: Entry) {
        lock.withLock {
            entryIdentifiersByURL[entry.cacheURL] = ObjectIdentifier(entry)
        }
    }

    func removeEntry(for url: URL) {
        lock.withLock {
            entryIdentifiersByURL.removeValue(forKey: url)
        }
    }

    func removeAllEntries() {
        lock.withLock {
            entryIdentifiersByURL.removeAll()
        }
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let entry = object as? Entry else { return }
        let identifier = ObjectIdentifier(entry)

        lock.withLock {
            guard entryIdentifiersByURL[entry.cacheURL] == identifier else { return }
            entryIdentifiersByURL.removeValue(forKey: entry.cacheURL)
        }
    }
}
