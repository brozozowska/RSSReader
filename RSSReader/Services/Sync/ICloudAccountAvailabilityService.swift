import CloudKit
import Foundation

enum ICloudAccountAvailability: String, Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

protocol ICloudAccountAvailabilityService: Sendable {
    func currentAvailability() async -> ICloudAccountAvailability
    func availabilityChanges() -> AsyncStream<ICloudAccountAvailability>
}

protocol CloudKitAccountStatusQuerying {
    func accountStatus() async throws -> CKAccountStatus
}

extension CKContainer: CloudKitAccountStatusQuerying {}

struct DefaultICloudAccountAvailabilityService: ICloudAccountAvailabilityService, @unchecked Sendable {
    private let accountStatusQuery: any CloudKitAccountStatusQuerying
    private let notificationCenter: NotificationCenter
    private let accountChangedNotification: Notification.Name
    private let logger: Logging

    init(
        container: CKContainer = CKContainer(identifier: CloudKitContainerConfiguration.containerIdentifier),
        notificationCenter: NotificationCenter = .default,
        accountChangedNotification: Notification.Name = .CKAccountChanged,
        logger: Logging = ConsoleLogger()
    ) {
        self.init(
            accountStatusQuery: container,
            notificationCenter: notificationCenter,
            accountChangedNotification: accountChangedNotification,
            logger: logger
        )
    }

    init(
        accountStatusQuery: any CloudKitAccountStatusQuerying,
        notificationCenter: NotificationCenter,
        accountChangedNotification: Notification.Name,
        logger: Logging = ConsoleLogger()
    ) {
        self.accountStatusQuery = accountStatusQuery
        self.notificationCenter = notificationCenter
        self.accountChangedNotification = accountChangedNotification
        self.logger = logger
    }

    func currentAvailability() async -> ICloudAccountAvailability {
        do {
            let accountStatus = try await accountStatusQuery.accountStatus()
            let availability = Self.mapAccountAvailability(from: accountStatus)
            logger.info(
                "Resolved CloudKit account status \(String(describing: accountStatus)) -> iCloud availability \(availability.rawValue)"
            )
            return availability
        } catch {
            logger.error("Failed to resolve CloudKit account status: \(describe(error))")
            logger.info("Falling back to iCloud availability couldNotDetermine after account status resolution failure")
            return .couldNotDetermine
        }
    }

    func availabilityChanges() -> AsyncStream<ICloudAccountAvailability> {
        AsyncStream { continuation in
            let observer = notificationCenter.addObserver(
                forName: accountChangedNotification,
                object: nil,
                queue: nil
            ) { _ in
                logger.info("Received \(accountChangedNotification.rawValue) notification; requerying CloudKit account status")
                Task {
                    continuation.yield(await currentAvailability())
                }
            }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }

    static func mapAccountAvailability(from accountStatus: CKAccountStatus) -> ICloudAccountAvailability {
        switch accountStatus {
        case .available:
            .available
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        @unknown default:
            .couldNotDetermine
        }
    }

    private func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) localizedDescription=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
    }
}
