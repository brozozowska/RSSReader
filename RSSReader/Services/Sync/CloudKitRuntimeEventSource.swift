import CoreData
import Foundation

enum CloudKitRuntimeActivity: String, Equatable, Sendable {
    case setup
    case `import`
    case export
}

struct CloudKitRuntimeEventContext: Equatable, Sendable {
    let identifier: UUID
    let storeIdentifier: String
    let startDate: Date
    let endDate: Date?
}

enum CloudKitRuntimeEvent: Equatable, Sendable {
    case started(CloudKitRuntimeActivity, CloudKitRuntimeEventContext)
    case finished(CloudKitRuntimeActivity, CloudKitRuntimeEventContext)
    case failed(CloudKitRuntimeActivity, CloudKitRuntimeEventContext, String?)
}

protocol CloudKitRuntimeEventSource: Sendable {
    func events() -> AsyncStream<CloudKitRuntimeEvent>
}

protocol PersistentCloudKitEventRepresenting {
    var type: NSPersistentCloudKitContainer.EventType { get }
    var identifier: UUID { get }
    var storeIdentifier: String { get }
    var succeeded: Bool { get }
    var startDate: Date { get }
    var endDate: Date? { get }
    var error: (any Error)? { get }
}

extension NSPersistentCloudKitContainer.Event: PersistentCloudKitEventRepresenting {}

struct DefaultCloudKitRuntimeEventSource: CloudKitRuntimeEventSource, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let eventChangedNotification: Notification.Name
    private let eventNotificationUserInfoKey: String

    init(
        notificationCenter: NotificationCenter = .default,
        eventChangedNotification: Notification.Name = NSPersistentCloudKitContainer.eventChangedNotification,
        eventNotificationUserInfoKey: String = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ) {
        self.notificationCenter = notificationCenter
        self.eventChangedNotification = eventChangedNotification
        self.eventNotificationUserInfoKey = eventNotificationUserInfoKey
    }

    func events() -> AsyncStream<CloudKitRuntimeEvent> {
        AsyncStream { continuation in
            let observer = notificationCenter.addObserver(
                forName: eventChangedNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard let runtimeEvent = Self.makeRuntimeEvent(
                    from: notification,
                    eventNotificationUserInfoKey: eventNotificationUserInfoKey
                ) else {
                    return
                }

                continuation.yield(runtimeEvent)
            }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }

    static func makeRuntimeEvent(
        from notification: Notification,
        eventNotificationUserInfoKey: String = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ) -> CloudKitRuntimeEvent? {
        guard let event = notification.userInfo?[eventNotificationUserInfoKey] as? any PersistentCloudKitEventRepresenting else {
            return nil
        }

        return map(event)
    }

    static func map(_ event: any PersistentCloudKitEventRepresenting) -> CloudKitRuntimeEvent {
        let activity = mapActivity(from: event.type)
        let context = CloudKitRuntimeEventContext(
            identifier: event.identifier,
            storeIdentifier: event.storeIdentifier,
            startDate: event.startDate,
            endDate: event.endDate
        )

        guard event.endDate != nil else {
            return .started(activity, context)
        }

        if event.succeeded, event.error == nil {
            return .finished(activity, context)
        }

        return .failed(activity, context, describe(event.error))
    }

    static func mapActivity(
        from eventType: NSPersistentCloudKitContainer.EventType
    ) -> CloudKitRuntimeActivity {
        switch eventType {
        case .setup:
            .setup
        case .import:
            .import
        case .export:
            .export
        @unknown default:
            .setup
        }
    }

    private static func describe(_ error: (any Error)?) -> String? {
        error.map { ($0 as NSError).localizedDescription }
    }
}
