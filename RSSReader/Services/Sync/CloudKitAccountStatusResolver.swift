import CloudKit
import Foundation

enum CloudKitAccountStatusResolver {
    static func currentStatus(
        for containerIdentifier: String,
        timeout: DispatchTimeInterval = .seconds(5)
    ) -> CKAccountStatus {
        let container = CKContainer(identifier: containerIdentifier)
        let semaphore = DispatchSemaphore(value: 0)
        var resolvedStatus: CKAccountStatus = .couldNotDetermine

        container.accountStatus { status, _ in
            resolvedStatus = status
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)
        return resolvedStatus
    }
}
