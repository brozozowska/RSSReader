import Foundation

enum CloudKitCompatibilitySeverity: String, Hashable, Sendable {
    case blocker
    case warning
}

enum CloudKitCompatibilityRule: String, Hashable, Sendable {
    case unsupportedUniqueConstraint
    case nonOptionalRelationship
    case crossStoreRelationship
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

    func report(for model: CloudKitSyncScopeModel) -> CloudKitModelCompatibilityReport? {
        reports.first { $0.model == model }
    }
}
