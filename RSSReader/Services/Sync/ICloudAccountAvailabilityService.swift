import CloudKit
import Foundation

enum ICloudAccountAvailability: String, Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

protocol ICloudAccountAvailabilityService {
    func currentAvailability() async -> ICloudAccountAvailability
    func availabilityChanges() -> AsyncStream<ICloudAccountAvailability>
}

protocol CloudKitAccountStatusQuerying {
    func accountStatus() async throws -> CKAccountStatus
}

extension CKContainer: CloudKitAccountStatusQuerying {}

struct DefaultICloudAccountAvailabilityService: ICloudAccountAvailabilityService {
    private let accountStatusQuery: any CloudKitAccountStatusQuerying
    private let notificationCenter: NotificationCenter
    private let accountChangedNotification: Notification.Name

    init(
        container: CKContainer = CKContainer(identifier: CloudKitContainerConfiguration.containerIdentifier),
        notificationCenter: NotificationCenter = .default,
        accountChangedNotification: Notification.Name = .CKAccountChanged
    ) {
        self.init(
            accountStatusQuery: container,
            notificationCenter: notificationCenter,
            accountChangedNotification: accountChangedNotification
        )
    }

    init(
        accountStatusQuery: any CloudKitAccountStatusQuerying,
        notificationCenter: NotificationCenter,
        accountChangedNotification: Notification.Name
    ) {
        self.accountStatusQuery = accountStatusQuery
        self.notificationCenter = notificationCenter
        self.accountChangedNotification = accountChangedNotification
    }

    func currentAvailability() async -> ICloudAccountAvailability {
        do {
            let accountStatus = try await accountStatusQuery.accountStatus()
            return Self.mapAccountAvailability(from: accountStatus)
        } catch {
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
}
