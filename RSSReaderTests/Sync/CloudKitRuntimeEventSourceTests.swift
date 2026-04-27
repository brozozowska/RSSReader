import CoreData
import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Runtime Event Source")
@MainActor
struct CloudKitRuntimeEventSourceTests {
    @Test
    func mapReturnsSetupStartedEventWhenCloudKitSetupIsActive() {
        let startDate = Date(timeIntervalSinceReferenceDate: 10)
        let identifier = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let event = FakePersistentCloudKitEvent(
            type: .setup,
            identifier: identifier,
            storeIdentifier: "SyncBackedStore",
            succeeded: false,
            startDate: startDate,
            endDate: nil,
            error: nil
        )

        let runtimeEvent = DefaultCloudKitRuntimeEventSource.map(event)

        #expect(
            runtimeEvent == .started(
                .setup,
                CloudKitRuntimeEventContext(
                    identifier: identifier,
                    storeIdentifier: "SyncBackedStore",
                    startDate: startDate,
                    endDate: nil
                )
            )
        )
    }

    @Test
    func mapReturnsImportFinishedEventWhenCloudKitImportSucceeds() {
        let startDate = Date(timeIntervalSinceReferenceDate: 20)
        let endDate = Date(timeIntervalSinceReferenceDate: 30)
        let identifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let event = FakePersistentCloudKitEvent(
            type: .import,
            identifier: identifier,
            storeIdentifier: "SyncBackedStore",
            succeeded: true,
            startDate: startDate,
            endDate: endDate,
            error: nil
        )

        let runtimeEvent = DefaultCloudKitRuntimeEventSource.map(event)

        #expect(
            runtimeEvent == .finished(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: identifier,
                    storeIdentifier: "SyncBackedStore",
                    startDate: startDate,
                    endDate: endDate
                )
            )
        )
    }

    @Test
    func mapReturnsExportFailedEventWhenCloudKitExportEndsWithError() {
        let startDate = Date(timeIntervalSinceReferenceDate: 40)
        let endDate = Date(timeIntervalSinceReferenceDate: 50)
        let identifier = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let event = FakePersistentCloudKitEvent(
            type: .export,
            identifier: identifier,
            storeIdentifier: "SyncBackedStore",
            succeeded: false,
            startDate: startDate,
            endDate: endDate,
            error: NSError(
                domain: "CloudKitRuntime",
                code: 17,
                userInfo: [NSLocalizedDescriptionKey: "The export request failed."]
            )
        )

        let runtimeEvent = DefaultCloudKitRuntimeEventSource.map(event)

        #expect(
            runtimeEvent == .failed(
                .export,
                CloudKitRuntimeEventContext(
                    identifier: identifier,
                    storeIdentifier: "SyncBackedStore",
                    startDate: startDate,
                    endDate: endDate
                ),
                "The export request failed."
            )
        )
    }

    @Test
    func eventsEmitMappedRuntimeEventWhenCloudKitNotificationArrives() async throws {
        let notificationCenter = NotificationCenter()
        let notificationName = Notification.Name("TestCloudKitEventChanged")
        let eventUserInfoKey = "TestCloudKitEventUserInfoKey"
        let identifier = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let startDate = Date(timeIntervalSinceReferenceDate: 60)
        let event = FakePersistentCloudKitEvent(
            type: .import,
            identifier: identifier,
            storeIdentifier: "SyncBackedStore",
            succeeded: false,
            startDate: startDate,
            endDate: nil,
            error: nil
        )
        let eventSource = DefaultCloudKitRuntimeEventSource(
            notificationCenter: notificationCenter,
            eventChangedNotification: notificationName,
            eventNotificationUserInfoKey: eventUserInfoKey
        )
        var iterator = eventSource.events().makeAsyncIterator()

        notificationCenter.post(
            name: notificationName,
            object: nil,
            userInfo: [eventUserInfoKey: event]
        )

        let runtimeEvent = try await #require(iterator.next())
        #expect(
            runtimeEvent == .started(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: identifier,
                    storeIdentifier: "SyncBackedStore",
                    startDate: startDate,
                    endDate: nil
                )
            )
        )
    }

    @Test
    func makeRuntimeEventReturnsNilWhenNotificationDoesNotContainCloudKitEvent() {
        let notification = Notification(
            name: Notification.Name("TestCloudKitEventChanged"),
            object: nil,
            userInfo: [:]
        )

        let runtimeEvent = DefaultCloudKitRuntimeEventSource.makeRuntimeEvent(
            from: notification,
            eventNotificationUserInfoKey: "TestCloudKitEventUserInfoKey"
        )

        #expect(runtimeEvent == nil)
    }
}

private struct FakePersistentCloudKitEvent: PersistentCloudKitEventRepresenting {
    let type: NSPersistentCloudKitContainer.EventType
    let identifier: UUID
    let storeIdentifier: String
    let succeeded: Bool
    let startDate: Date
    let endDate: Date?
    let error: (any Error)?
}
