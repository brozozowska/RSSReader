import Foundation
import SwiftData

@MainActor
enum ArticleStateCanonicalization {
    static func isOrderedBefore(_ lhs: ArticleState, _ rhs: ArticleState) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }
}
