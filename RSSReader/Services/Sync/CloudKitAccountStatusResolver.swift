import CloudKit
import Foundation
import Synchronization

enum CloudKitAccountStatusResolver {
    static func currentStatus(
        for containerIdentifier: String,
        timeout: DispatchTimeInterval = .seconds(5)
    ) -> CKAccountStatus {
        let container = CKContainer(identifier: containerIdentifier)
        return currentStatus(timeout: timeout) { completion in
            container.accountStatus(completionHandler: completion)
        }
    }

    static func currentStatus(
        timeout: DispatchTimeInterval,
        requestStatus: (@escaping @Sendable (CKAccountStatus, (any Error)?) -> Void) -> Void
    ) -> CKAccountStatus {
        let semaphore = DispatchSemaphore(value: 0)
        let resolvedStatus = Mutex(CKAccountStatus.couldNotDetermine)

        requestStatus { status, _ in
            resolvedStatus.withLock { $0 = status }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .couldNotDetermine
        }
        return resolvedStatus.withLock { $0 }
    }
}
