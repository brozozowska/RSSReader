import CoreData
import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / Persistent Store Remote Change Source")
struct PersistentStoreRemoteChangeSourceTests {
    @Test
    func persistentStoreRemoteChangeSourceMapsStoreUUIDAndURLFromNotification() throws {
        let storeURL = try #require(URL(string: "file:///tmp/SyncBackedStore.sqlite"))
        let notification = Notification(
            name: .NSPersistentStoreRemoteChange,
            object: nil,
            userInfo: [
                NSStoreUUIDKey: "SyncBackedStore",
                NSPersistentStoreURLKey: storeURL
            ]
        )

        let event = DefaultPersistentStoreRemoteChangeSource.makeEvent(from: notification)

        #expect(event.storeUUID == "SyncBackedStore")
        #expect(event.storeURL == storeURL)
    }
}
