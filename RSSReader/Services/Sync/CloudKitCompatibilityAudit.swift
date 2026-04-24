import Foundation

enum CloudKitCompatibilitySeverity: String, Hashable, Sendable {
    case blocker
    case warning
}

enum CloudKitCompatibilityRule: String, Hashable, Sendable {
    case unsupportedUniqueConstraint
    case nonOptionalRelationship
    case crossStoreRelationship
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

    static let appSettingsFeedFolder = CloudKitCompatibilityAudit(
        reports: [
            CloudKitModelCompatibilityReport(
                model: .appSettings,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .unsupportedUniqueConstraint,
                        affectedPaths: [
                            "AppSettings.id",
                            "AppSettings.singletonKey"
                        ],
                        summary: "CloudKit-backed SwiftData does not support uniqueness enforcement for AppSettings identity fields.",
                        recommendedFollowUp: "Remove schema-level uniqueness from AppSettings and keep singleton resolution in repository/service logic."
                    ),
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
                model: .feed,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .unsupportedUniqueConstraint,
                        affectedPaths: [
                            "Feed.id",
                            "Feed.url"
                        ],
                        summary: "CloudKit-backed SwiftData cannot enforce unique Feed identifiers or source URLs at the schema level.",
                        recommendedFollowUp: "Move feed identity and duplicate prevention into repository/service upsert paths."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .nonOptionalRelationship,
                        affectedPaths: [
                            "Feed.articles"
                        ],
                        summary: "CloudKit compatibility requires relationships to remain optional, but Feed currently owns a nonoptional articles collection.",
                        recommendedFollowUp: "Remove the sync-backed Feed -> Article relationship from the CloudKit store boundary."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .crossStoreRelationship,
                        affectedPaths: [
                            "Feed.articles",
                            "Article.feed"
                        ],
                        summary: "The current Feed <-> Article relationship crosses the intended sync-backed/local-only store boundary.",
                        recommendedFollowUp: "Separate sync-backed Feed persistence from local Article storage before enabling CloudKit."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataFeedRepository.fetchFeed(url:)"
                        ],
                        summary: "FeedRepository currently assumes URL-based identity lookup for duplicate prevention and edit flows.",
                        recommendedFollowUp: "Keep URL identity checks in repository/service logic after removing schema-level uniqueness."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .folder,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .unsupportedUniqueConstraint,
                        affectedPaths: [
                            "Folder.id",
                            "Folder.name"
                        ],
                        summary: "CloudKit-backed SwiftData cannot enforce unique Folder identifiers or folder names at the schema level.",
                        recommendedFollowUp: "Move folder identity and duplicate-name validation into repository/service logic."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .nonOptionalRelationship,
                        affectedPaths: [
                            "Folder.feeds"
                        ],
                        summary: "CloudKit compatibility requires relationships to remain optional, but Folder currently owns a nonoptional feeds collection.",
                        recommendedFollowUp: "Rework Folder <-> Feed relationship semantics for the sync-backed store configuration."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataFolderRepository.fetchFolder(name:)"
                        ],
                        summary: "FolderRepository currently uses name-based lookup as a user-visible identity invariant.",
                        recommendedFollowUp: "Preserve duplicate-name validation in repository/service logic after removing schema-level uniqueness."
                    )
                ]
            )
        ],
        sourceSummary: "Audit based on Apple SwiftData CloudKit documentation: CloudKit does not support unique constraints, requires relationships to remain optional, and forbids cross-configuration relationships between stores."
    )

    static let articleStateArticleFeedFetchLog = CloudKitCompatibilityAudit(
        reports: [
            CloudKitModelCompatibilityReport(
                model: .articleState,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .unsupportedUniqueConstraint,
                        affectedPaths: [
                            "ArticleState.id",
                            "ArticleState.#Unique(feedID, articleExternalID)"
                        ],
                        summary: "CloudKit-backed SwiftData cannot enforce ArticleState identity via unique id or compound uniqueness on feedID and articleExternalID.",
                        recommendedFollowUp: "Remove schema-level uniqueness from ArticleState and preserve composite-key upsert logic in repository code."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .repositoryManagedIdentityInvariant,
                        affectedPaths: [
                            "SwiftDataArticleStateRepository.fetchState(feedID:articleExternalID:)",
                            "SwiftDataArticleStateRepository.fetchOrCreate(feedID:articleExternalID:)",
                            "SwiftDataArticleStateRepository.shouldApply(_:to:)"
                        ],
                        summary: "ArticleState currently relies on repository-managed composite identity and last-write-wins conflict resolution instead of model relationships.",
                        recommendedFollowUp: "Keep composite-key identity and updatedAt-based conflict resolution in repository/service logic after schema migration."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .warning,
                        rule: .crossStoreRelationship,
                        affectedPaths: [
                            "ArticleState.feedID",
                            "ArticleState.articleExternalID",
                            "SwiftDataArticleStateRepository.fetchStateSnapshots(for:)"
                        ],
                        summary: "ArticleState intentionally references articles through scalar identifiers, which preserves the boundary between sync-backed state and the local article cache.",
                        recommendedFollowUp: "Do not introduce direct SwiftData relationships from ArticleState to Article when enabling CloudKit."
                    )
                ]
            ),
            CloudKitModelCompatibilityReport(
                model: .article,
                findings: [
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .unsupportedUniqueConstraint,
                        affectedPaths: [
                            "Article.id",
                            "Article.#Unique(feed, externalID)"
                        ],
                        summary: "Article cannot rely on unique id or compound uniqueness over feed and externalID in a CloudKit-backed schema.",
                        recommendedFollowUp: "Keep article deduplication in ArticleRepository and DeduplicationService instead of schema-level uniqueness."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .nonOptionalRelationship,
                        affectedPaths: [
                            "Article.feed"
                        ],
                        summary: "CloudKit compatibility requires relationships to remain optional, but Article currently requires a nonoptional Feed relationship.",
                        recommendedFollowUp: "Keep Article out of the CloudKit-backed store or redesign the relationship boundary before sync is enabled."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .crossStoreRelationship,
                        affectedPaths: [
                            "Article.feed",
                            "Feed.articles"
                        ],
                        summary: "Article currently depends on a direct relationship to sync-backed Feed, which prevents a clean split between local cache and sync-backed models.",
                        recommendedFollowUp: "Break the direct Feed <-> Article store coupling before introducing separate CloudKit and local stores."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .localOnlyStoreBoundary,
                        affectedPaths: [
                            "Article",
                            "SwiftDataArticleRepository",
                            "FeedRefreshService"
                        ],
                        summary: "Article is the local materialized cache produced by refresh flows and should not be synchronized through CloudKit.",
                        recommendedFollowUp: "Keep Article in the local-only store and materialize it from manual/background refresh on each device."
                    ),
                    CloudKitCompatibilityFinding(
                        severity: .blocker,
                        rule: .deleteRuleStoreCoupling,
                        affectedPaths: [
                            "Feed.articles",
                            "Article.feed",
                            "FeedDeletionService.delete(_:in:)"
                        ],
                        summary: "The current cascade-based Feed -> Article lifecycle couples local article deletion to sync-backed Feed ownership.",
                        recommendedFollowUp: "Replace delete-rule coupling with explicit local-store cleanup once Feed and Article live in separate store configurations."
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
        sourceSummary: "Audit based on Apple SwiftData CloudKit documentation: unique constraints are unsupported, CloudKit-compatible relationships must remain optional, and local-only cache models should be isolated from sync-backed store configuration."
    )

    func report(for model: CloudKitSyncScopeModel) -> CloudKitModelCompatibilityReport? {
        reports.first { $0.model == model }
    }
}
