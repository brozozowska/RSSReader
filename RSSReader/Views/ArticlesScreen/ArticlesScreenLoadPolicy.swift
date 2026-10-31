import Foundation

enum ArticlesScreenLoadPolicy {
    /// A fresh query starts a new session and reapplies the current filter.
    case replace
    case retainSession
    case retainAfterRefresh
    /// Resume a covered list without losing accumulated pages or its cursor.
    case resumeMaterializedSession

    var retainsSession: Bool {
        switch self {
        case .replace: false
        case .retainSession, .retainAfterRefresh, .resumeMaterializedSession: true
        }
    }

    var preservesMaterializedSnapshot: Bool {
        if case .resumeMaterializedSession = self { return true }
        return false
    }

    var retainedMembershipStatus: ArticleListEntryMembershipStatus {
        if case .retainAfterRefresh = self { return .retainedAfterRefresh }
        return .retainedAfterFilterMutation
    }
}

enum ArticlesScreenLoadFeedbackPolicy {
    case dismiss
    case preserve
}
