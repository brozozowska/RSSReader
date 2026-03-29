import Foundation

enum ArticleListFilter: String, Sendable, CaseIterable {
    case all
    case unread
    case starred
    case hidden
}
