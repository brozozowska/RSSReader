import Foundation
import Synchronization

/// Owns the opaque Foundation registration. The token is never exposed to
/// callbacks or consumers, and removal takes ownership of it exactly once.
nonisolated final class NotificationObservation: Sendable {
    private let center: NotificationCenter
    private let token: Mutex<(any NSObjectProtocol)?>

    init(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        token = Mutex(center.addObserver(forName: name, object: nil, queue: nil, using: handler))
    }

    func cancel() {
        let observer = token.withLock { token in
            let observer = token
            token = nil
            return observer
        }
        if let observer {
            center.removeObserver(observer)
        }
    }

    deinit { cancel() }
}
