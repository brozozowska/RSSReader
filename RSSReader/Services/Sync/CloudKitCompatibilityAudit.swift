import Foundation

enum CloudKitCompatibilitySeverity: String, Hashable, Sendable {
    case blocker
    case warning
}

enum CloudKitCompatibilityRule: String, Hashable, Sendable {
    case unsupportedUniqueConstraint
    case localOnlyStoreBoundary
    case deleteRuleStoreCoupling
    case repositoryManagedIdentityInvariant
}

struct CloudKitCompatibilityFinding: Equatable, Sendable {
    let severity: CloudKitCompatibilitySeverity
    let rule: CloudKitCompatibilityRule
    let affectedPaths: [String]
    let summary: String
    let recommendedFollowUp: String
}

struct CloudKitModelCompatibilityReport: Equatable, Sendable {
    let model: CloudKitSyncScopeModel
    let findings: [CloudKitCompatibilityFinding]

    var hasBlockingFindings: Bool {
        findings.contains { $0.severity == .blocker }
    }
}

struct CloudKitCompatibilityAudit: Equatable, Sendable {
    let reports: [CloudKitModelCompatibilityReport]
    let sourceSummary: String

    static let currentSyncBackedModelSet = CloudKitCompatibilityAudit(
        reports: [
            CloudKitModelCompatibilityReport(
                model: .appSettings,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataAppSettingsRepository.fetch()",
                            "SwiftDataAppSettingsRepository.fetchOrCreate()"
                        ],
                        summary: "AppSettings currently relies on singletonKey-based fetch-or-create semantics for global identity.",
                        recommendedFollowUp: "Preserve the singleton invariant explicitly in repository logic once schema-level uniqueness is removed."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .articleState,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataArticleStateRepository.fetchState(feedID:articleExternalID:)",
                            "SwiftDataArticleStateRepository.fetchOrCreate(feedID:articleExternalID:)",
                            "SwiftDataArticleStateRepository.fetchCanonicalState(feedID:articleExternalID:removeDuplicates:)",
                            "SwiftDataArticleStateRepository.shouldApply(_:to:)"
                        ],
                        summary: "ArticleState now relies on repository-managed composite identity, duplicate-row repair, and last-write-wins conflict resolution instead of schema-level uniqueness.",
                        recommendedFollowUp: "Keep composite-key identity repair and updatedAt-based conflict resolution in repository/service logic for the CloudKit-backed model."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "ArticleState.feedID",
                            "ArticleState.articleExternalID",
                            "SwiftDataArticleStateRepository.fetchStateSnapshots(for:)"
                        ],
                        summary: "ArticleState intentionally references articles through scalar identifiers instead of a direct SwiftData relationship, which keeps relationship ordering out of reading-state conflict handling.",
                        recommendedFollowUp: "Keep ArticleState identity and conflict resolution scalar even though Article now lives in the sync-backed store."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .article,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataArticleRepository.fetchArticle(feedID:externalID:)",
                            "SwiftDataArticleRepository.fetchArticles(feedID:)",
                            "SwiftDataArticleRepository.reconcileFeedSnapshot(_:into:fetchedAt:saveAfterOperation:)",
                            "DeduplicationService"
                        ],
                        summary: "Article now syncs through CloudKit without schema-level unique constraints, so feedID and externalID identity remains repository-managed.",
                        recommendedFollowUp: "Keep article deduplication in DeduplicationService and ArticleRepository because CloudKit does not enforce SwiftData unique constraints."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "Article.feedID",
                            "Article.feedTitle",
                            "Article.feedSiteURL",
                            "Article.feedFolderName",
                            "SwiftDataArticleRepository.refreshFeedProjection(for:saveAfterOperation:)",
                            "FeedDeletionService.delete(_:in:)"
                        ],
                        summary: "Article carries a scalar feed projection that must stay in sync with Feed updates and explicit cleanup paths in repository/service logic.",
                        recommendedFollowUp: "Preserve explicit feed-projection refresh and feedID-based cleanup while Article is synchronized as payload data."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .feed,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataFeedRepository.fetchFeed(url:)",
                            "SwiftDataFeedRepository.insert(_:)",
                            "SwiftDataFeedRepository.updateDetails(for:with:saveAfterOperation:)"
                        ],
                        summary: "FeedRepository now owns URL identity checks for duplicate prevention instead of relying on schema-level uniqueness.",
                        recommendedFollowUp: "Keep feed URL invariants in repository/service logic while the relationship boundary is still being migrated."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .folder,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataFolderRepository.fetchFolder(name:)",
                            "SwiftDataFolderRepository.insert(_:)",
                            "SwiftDataFolderRepository.update(folderID:with:saveAfterOperation:)"
                        ],
                        summary: "FolderRepository now owns duplicate-name validation instead of relying on schema-level uniqueness.",
                        recommendedFollowUp: "Keep folder-name invariants in repository/service logic while relationship semantics are still being migrated."
                    )
                ]
            )
        ],
        sourceSummary: "Audit based on Apple SwiftData CloudKit documentation: the current sync-backed model set contains AppSettings, Article, ArticleState, Feed, and Folder; Article avoids schema-level uniqueness and direct relationships so CloudKit can synchronize article payload data."
    )

    static let articleStateArticleFeedFetchLog = CloudKitCompatibilityAudit(
        reports: [
            CloudKitModelCompatibilityReport(
                model: .articleState,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataArticleStateRepository.fetchState(feedID:articleExternalID:)",
                            "SwiftDataArticleStateRepository.fetchOrCreate(feedID:articleExternalID:)",
                            "SwiftDataArticleStateRepository.fetchCanonicalState(feedID:articleExternalID:removeDuplicates:)",
                            "SwiftDataArticleStateRepository.shouldApply(_:to:)"
                        ],
                        summary: "ArticleState now relies on repository-managed composite identity, duplicate-row repair, and last-write-wins conflict resolution instead of schema-level uniqueness.",
                        recommendedFollowUp: "Keep composite-key identity repair and updatedAt-based conflict resolution in repository/service logic for the CloudKit-backed model."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "ArticleState.feedID",
                            "ArticleState.articleExternalID",
                            "SwiftDataArticleStateRepository.fetchStateSnapshots(for:)"
                        ],
                        summary: "ArticleState intentionally references articles through scalar identifiers instead of a direct SwiftData relationship, which keeps relationship ordering out of reading-state conflict handling.",
                        recommendedFollowUp: "Keep ArticleState identity and conflict resolution scalar even though Article now lives in the sync-backed store."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .article,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataArticleRepository.fetchArticle(feedID:externalID:)",
                            "SwiftDataArticleRepository.fetchArticles(feedID:)",
                            "SwiftDataArticleRepository.reconcileFeedSnapshot(_:into:fetchedAt:saveAfterOperation:)",
                            "DeduplicationService"
                        ],
                        summary: "Article now syncs through CloudKit without schema-level unique constraints, so feedID and externalID identity remains repository-managed.",
                        recommendedFollowUp: "Keep article deduplication in DeduplicationService and ArticleRepository because CloudKit does not enforce SwiftData unique constraints."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "Article.feedID",
                            "Article.feedTitle",
                            "Article.feedSiteURL",
                            "Article.feedFolderName",
                            "SwiftDataArticleRepository.refreshFeedProjection(for:saveAfterOperation:)",
                            "FeedDeletionService.delete(_:in:)"
                        ],
                        summary: "Article carries a scalar feed projection that must stay in sync with Feed updates and explicit cleanup paths in repository/service logic.",
                        recommendedFollowUp: "Preserve explicit feed-projection refresh and feedID-based cleanup while Article is synchronized as payload data."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .feedFetchLog,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .localOnlyStoreBoundary,
                        affectedPaths: [
                            "FeedFetchLog",
                            "SwiftDataFeedFetchLogRepository",
                            "FeedFetcher"
                        ],
                        summary: "FeedFetchLog is operational fetch telemetry and must remain local-only rather than synchronizing through CloudKit.",
                        recommendedFollowUp: "Exclude FeedFetchLog from the CloudKit-backed configuration and keep it in the local diagnostics store."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .unsupportedUniqueConstraint,
                        affectedPaths: [
                            "FeedFetchLog.id"
                        ],
                        summary: "If FeedFetchLog were ever moved into a CloudKit-backed store, its unique id would become unsupported as an enforced schema constraint.",
                        recommendedFollowUp: "Treat FeedFetchLog as local-only and avoid designing sync flows around its model identity."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataFeedFetchLogRepository.fetchLogs(feedID:limit:)",
                            "FeedDeletionService.delete(_:in:)"
                        ],
                        summary: "FeedFetchLog lifecycle is append-only and feed-scoped, with explicit cleanup on feed deletion rather than relationship-driven sync semantics.",
                        recommendedFollowUp: "Preserve explicit local cleanup for fetch logs when sync-backed feeds are deleted."
                    )
                ]
            )
        ],
        sourceSummary: "Audit based on Apple SwiftData CloudKit documentation: Article and ArticleState identity are repository-managed in the sync-backed store, while FeedFetchLog remains local-only operational telemetry."
    )

    func report(for model: CloudKitSyncScopeModel) -> CloudKitModelCompatibilityReport? {
        reports.first { $0.model == model }
    }
}
