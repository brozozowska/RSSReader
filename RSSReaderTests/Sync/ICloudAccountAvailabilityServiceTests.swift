import CloudKit
import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / iCloud Account Availability")
@MainActor
struct ICloudAccountAvailabilityServiceTests {
    @Test
    func currentAvailabilityMapsAvailableAccountStatus() async {
        let service = makeService(results: [.success(.available)])

        #expect(await service.currentAvailability() == .available)
    }

    @Test
    func currentAvailabilityMapsNoAccountStatus() async {
        let service = makeService(results: [.success(.noAccount)])

        #expect(await service.currentAvailability() == .noAccount)
    }

    @Test
    func currentAvailabilityMapsRestrictedStatus() async {
        let service = makeService(results: [.success(.restricted)])

        #expect(await service.currentAvailability() == .restricted)
    }

    @Test
    func currentAvailabilityMapsTemporarilyUnavailableStatus() async {
        let service = makeService(results: [.success(.temporarilyUnavailable)])

        #expect(await service.currentAvailability() == .temporarilyUnavailable)
    }

    @Test
    func currentAvailabilityMapsCouldNotDetermineStatus() async {
        let service = makeService(results: [.success(.couldNotDetermine)])

        #expect(await service.currentAvailability() == .couldNotDetermine)
    }

    @Test
    func currentAvailabilityMapsQueryFailureToCouldNotDetermine() async {
        let service = makeService(results: [.failure(TestError.accountStatusFailed)])

        #expect(await service.currentAvailability() == .couldNotDetermine)
    }

    @Test
    func currentAvailabilityLogsResolvedStatusAndMappedAvailability() async {
        let logger = RecordingLogger()
        let service = makeService(
            results: [.success(.temporarilyUnavailable)],
            logger: logger
        )

        _ = await service.currentAvailability()

        #expect(logger.contains("Resolved CloudKit account status"))
        #expect(logger.contains("temporarilyUnavailable"))
        #expect(logger.contains("iCloud availability temporarilyUnavailable"))
    }

    @Test
    func currentAvailabilityLogsFallbackAfterAccountStatusQueryFailure() async {
        let logger = RecordingLogger()
        let service = makeService(
            results: [.failure(TestError.accountStatusFailed)],
            logger: logger
        )

        _ = await service.currentAvailability()

        #expect(logger.contains("Failed to resolve CloudKit account status", level: .error))
        #expect(
            logger.contains(
                "Falling back to iCloud availability couldNotDetermine after account status resolution failure",
                level: .info
            )
        )
    }

    @Test
    func availabilityChangesRequeriesAccountStatusWhenAccountChangedNotificationArrives() async throws {
        let notificationCenter = NotificationCenter()
        let notificationName = Notification.Name("TestCKAccountChanged")
        let service = makeService(
            results: [.success(.restricted)],
            notificationCenter: notificationCenter,
            notificationName: notificationName
        )
        var iterator = service.availabilityChanges().makeAsyncIterator()

        notificationCenter.post(name: notificationName, object: nil)

        let update = try await #require(iterator.next())
        #expect(update == .restricted)
    }

    @Test
    func availabilityChangesLogAccountChangedRequery() async throws {
        let notificationCenter = NotificationCenter()
        let notificationName = Notification.Name("TestCKAccountChanged")
        let logger = RecordingLogger()
        let service = makeService(
            results: [.success(.restricted)],
            notificationCenter: notificationCenter,
            notificationName: notificationName,
            logger: logger
        )
        var iterator = service.availabilityChanges().makeAsyncIterator()

        notificationCenter.post(name: notificationName, object: nil)

        _ = try await #require(iterator.next())

        #expect(logger.contains("Received \(notificationName.rawValue) notification; requerying CloudKit account status"))
    }

    @Test
    func repeatedAccountNotificationsAreDeliveredUntilConsumerCancels() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("RepeatedTestCKAccountChanged")
        let logger = RecordingLogger()
        let service = makeService(
            results: [.success(.restricted), .success(.available)],
            notificationCenter: center,
            notificationName: name,
            logger: logger
        )
        let stream = service.availabilityChanges()
        var values: [ICloudAccountAvailability] = []
        let consumer = Task {
            for await value in stream { values.append(value) }
        }
        defer { consumer.cancel() }

        await Task.detached { center.post(name: name, object: nil) }.value
        try await waitUntil("first account status update") { values.count == 1 }
        await Task.detached { center.post(name: name, object: nil) }.value
        try await waitUntil("second account status update") { values.count == 2 }
        #expect(values == [.restricted, .available])

        consumer.cancel()
        await consumer.value
        let entriesAfterCancellation = logger.entries
        // Logging happens synchronously on the posting thread, before any requery.
        await Task.detached { center.post(name: name, object: nil) }.value
        #expect(logger.entries == entriesAfterCancellation)
    }

    @Test
    func bootstrapStatusResolverReturnsCallbackStatus() {
        let status = CloudKitAccountStatusResolver.currentStatus(timeout: .seconds(1)) { complete in
            DispatchQueue.global().async { complete(.available, nil) }
        }
        #expect(status == .available)
    }

    @Test
    func bootstrapStatusResolverReturnsFallbackBeforeLateCallback() {
        var completeLater: (@Sendable (CKAccountStatus, (any Error)?) -> Void)?
        let status = CloudKitAccountStatusResolver.currentStatus(timeout: .nanoseconds(0)) { complete in
            completeLater = complete
        }
        #expect(status == .couldNotDetermine)
        #expect(completeLater != nil)
        completeLater?(.available, nil)
    }

    private func makeService(
        results: [Result<CKAccountStatus, Error>],
        notificationCenter: NotificationCenter = NotificationCenter(),
        notificationName: Notification.Name = .CKAccountChanged,
        logger: Logging = TestLogger()
    ) -> DefaultICloudAccountAvailabilityService {
        DefaultICloudAccountAvailabilityService(
            accountStatusQuery: ScriptedCloudKitAccountStatusQuery(results: results),
            notificationCenter: notificationCenter,
            accountChangedNotification: notificationName,
            logger: logger
        )
    }
}

private actor ScriptedCloudKitAccountStatusQuery: CloudKitAccountStatusQuerying {
    private var results: [Result<CKAccountStatus, Error>]

    init(results: [Result<CKAccountStatus, Error>]) {
        self.results = results
    }

    func accountStatus() async throws -> CKAccountStatus {
        guard results.isEmpty == false else {
            return .couldNotDetermine
        }

        let result = results.removeFirst()
        switch result {
        case .success(let status):
            return status
        case .failure(let error):
            throw error
        }
    }
}

private enum TestError: Error {
    case accountStatusFailed
}
