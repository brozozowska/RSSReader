import Foundation
@testable import RSSReader

@MainActor
final class SwiftDataRepositoryOperationCounter {
    private(set) var fetchCount = 0
    private(set) var fetchCountQueryCount = 0
    private(set) var saveCount = 0

    var fetchQueryCount: Int {
        fetchCount - fetchCountQueryCount
    }

    func record(_ operation: SwiftDataRepositoryOperation) {
        switch operation {
        case .fetch:
            fetchCount += 1
        case .fetchCount:
            fetchCount += 1
            fetchCountQueryCount += 1
        case .save:
            saveCount += 1
        }
    }

    func reset() {
        fetchCount = 0
        fetchCountQueryCount = 0
        saveCount = 0
    }
}
