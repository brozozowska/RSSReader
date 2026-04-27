import CoreData
import Foundation

struct PersistentStoreRemoteChangeEvent: Equatable, Sendable {
    let storeUUID: String?
    let storeURL: URL?
}

protocol PersistentStoreRemoteChangeSource: Sendable {
    func events() -> AsyncStream<PersistentStoreRemoteChangeEvent>
}

struct DefaultPersistentStoreRemoteChangeSource: PersistentStoreRemoteChangeSource, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let remoteChangeNotification: Notification.Name

    init(
        notificationCenter: NotificationCenter = .default,
        remoteChangeNotification: Notification.Name = .NSPersistentStoreRemoteChange
    ) {
        self.notificationCenter = notificationCenter
        self.remoteChangeNotification = remoteChangeNotification
    }

    func events() -> AsyncStream<PersistentStoreRemoteChangeEvent> {
        AsyncStream { continuation in
            let observer = notificationCenter.addObserver(
                forName: remoteChangeNotification,
                object: nil,
                queue: nil
            ) { notification in
                continuation.yield(Self.makeEvent(from: notification))
            }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }

    static func makeEvent(from notification: Notification) -> PersistentStoreRemoteChangeEvent {
        PersistentStoreRemoteChangeEvent(
            storeUUID: notification.userInfo?[NSStoreUUIDKey] as? String,
            storeURL: notification.userInfo?[NSPersistentStoreURLKey] as? URL
        )
    }
}
