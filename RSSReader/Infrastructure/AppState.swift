import Foundation
import Observation

@Observable
public final class AppState {
    public var selectedFeedID: UUID? = nil

    public var selectedArticleID: UUID? = nil

    public init() {}
}
