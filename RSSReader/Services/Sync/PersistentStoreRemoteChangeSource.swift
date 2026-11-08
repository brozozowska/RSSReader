import CoreData
import Foundation

nonisolated struct PersistentStoreRemoteChangeEvent: Sendable {
    let storeUUID: String?
    let storeURL: URL?
}

protocol PersistentStoreRemoteChangeSource: Sendable {
    func events() -> AsyncStream<PersistentStoreRemoteChangeEvent>
}

nonisolated struct DefaultPersistentStoreRemoteChangeSource: PersistentStoreRemoteChangeSource {
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
            let observation = NotificationObservation(center: notificationCenter, name: remoteChangeNotification) { notification in
                continuation.yield(Self.makeEvent(from: notification))
            }

            continuation.onTermination = { _ in observation.cancel() }
        }
    }

    static func makeEvent(from notification: Notification) -> PersistentStoreRemoteChangeEvent {
        PersistentStoreRemoteChangeEvent(
            storeUUID: notification.userInfo?[NSStoreUUIDKey] as? String,
            storeURL: notification.userInfo?[NSPersistentStoreURLKey] as? URL
        )
    }
}
