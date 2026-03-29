import Foundation
import Observation

enum SidebarSelection: Hashable, Sendable {
    case inbox
    case feed(UUID)
}

@Observable
public final class AppState {
    var selectedSidebarSelection: SidebarSelection? = .inbox

    public var selectedFeedID: UUID? {
        get {
            guard case .feed(let feedID) = selectedSidebarSelection else {
                return nil
            }
            return feedID
        }
        set {
            if let newValue {
                selectedSidebarSelection = .feed(newValue)
            } else {
                selectedSidebarSelection = nil
            }
        }
    }

    public var selectedArticleID: UUID? = nil

    public init() {}
}
