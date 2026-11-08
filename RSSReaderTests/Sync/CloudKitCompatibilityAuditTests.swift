import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Compatibility Audit")
@MainActor
struct CloudKitCompatibilityAuditTests {
    // Hypothetical audit including local-only telemetry; never used by app bootstrap.
    private static let articleStateArticleFeedFetchLog = CloudKitCompatibilityAudit(
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
                            "SwiftDataArticleStateIdentityRepairer.stageRepairs(feedID:normalizedIdentities:cancellationCheckpoint:progressProbe:)",
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


    @Test
    func cloudKitCompatibilityAuditTracksCleanSyncBackedModelSetAfterArticlePayloadMigration() throws {
        let audit = CloudKitCompatibilityAudit.currentSyncBackedModelSet

        #expect(audit.reports.map(\.model) == [.appSettings, .articleState, .article, .feed, .folder])

        let appSettingsReport = try #require(audit.report(for: .appSettings))
        let articleStateReport = try #require(audit.report(for: .articleState))
        let articleReport = try #require(audit.report(for: .article))
        let feedReport = try #require(audit.report(for: .feed))
        let folderReport = try #require(audit.report(for: .folder))

        #expect(appSettingsReport.hasBlockingFindings == false)
        #expect(articleStateReport.hasBlockingFindings == false)
        #expect(articleReport.hasBlockingFindings == false)
        #expect(feedReport.hasBlockingFindings == false)
        #expect(folderReport.hasBlockingFindings == false)
    }

    @Test
    func cloudKitCompatibilityAuditCapturesRepositoryManagedIdentityInvariants() throws {
        let audit = CloudKitCompatibilityAudit.currentSyncBackedModelSet

        let appSettingsReport = try #require(audit.report(for: .appSettings))
        let articleStateReport = try #require(audit.report(for: .articleState))
        let articleReport = try #require(audit.report(for: .article))
        let feedReport = try #require(audit.report(for: .feed))
        let folderReport = try #require(audit.report(for: .folder))

        #expect(
            appSettingsReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataAppSettingsRepository.fetch()",
                        "SwiftDataAppSettingsRepository.fetchOrCreate()"
                    ]
            }
        )
        #expect(
            feedReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataFeedRepository.fetchFeed(url:)",
                        "SwiftDataFeedRepository.insert(_:)",
                        "SwiftDataFeedRepository.updateDetails(for:with:saveAfterOperation:)"
                    ]
            }
        )
        #expect(
            articleStateReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataArticleStateRepository.fetchState(feedID:articleExternalID:)",
                        "SwiftDataArticleStateRepository.fetchOrCreate(feedID:articleExternalID:)",
                        "SwiftDataArticleStateRepository.fetchCanonicalState(feedID:articleExternalID:removeDuplicates:)",
                        "SwiftDataArticleStateIdentityRepairer.stageRepairs(feedID:normalizedIdentities:cancellationCheckpoint:progressProbe:)",
                        "SwiftDataArticleStateRepository.shouldApply(_:to:)"
                    ]
            }
        )
        #expect(
            articleReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataArticleRepository.fetchArticles(feedID:)",
                        "SwiftDataArticleRepository.reconcileFeedSnapshot(_:into:fetchedAt:saveAfterOperation:)",
                        "DeduplicationService"
                    ]
            }
        )
        #expect(
            folderReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataFolderRepository.fetchFolder(name:)",
                        "SwiftDataFolderRepository.insert(_:)",
                        "SwiftDataFolderRepository.update(folderID:with:saveAfterOperation:)"
                    ]
            }
        )
    }

    @Test
    func cloudKitCompatibilityAuditMatchesCurrentSyncBackedPartitionWithoutDrift() {
        let audit = CloudKitCompatibilityAudit.currentSyncBackedModelSet
        let syncBackedScope = AppPersistenceModelPartition.current.syncBackedScopeModels

        #expect(Set(audit.reports.map(\.model)) == syncBackedScope)
    }

    @Test
    func cloudKitCompatibilityAuditFlagsArticlePayloadAndFeedFetchLogBoundaries() throws {
        let audit = Self.articleStateArticleFeedFetchLog

        #expect(audit.reports.map(\.model) == [.articleState, .article, .feedFetchLog])

        let articleStateReport = try #require(audit.report(for: .articleState))
        let articleReport = try #require(audit.report(for: .article))
        let feedFetchLogReport = try #require(audit.report(for: .feedFetchLog))

        #expect(articleStateReport.hasBlockingFindings == false)
        #expect(articleReport.hasBlockingFindings == false)
        #expect(feedFetchLogReport.hasBlockingFindings)
        #expect(
            articleReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataArticleRepository.fetchArticles(feedID:)",
                        "SwiftDataArticleRepository.reconcileFeedSnapshot(_:into:fetchedAt:saveAfterOperation:)",
                        "DeduplicationService"
                    ]
            }
        )
        #expect(
            articleReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "Article.feedID",
                        "Article.feedTitle",
                        "Article.feedSiteURL",
                        "Article.feedFolderName",
                        "SwiftDataArticleRepository.refreshFeedProjection(for:saveAfterOperation:)",
                        "FeedDeletionService.delete(_:in:)"
                    ]
            }
        )
        #expect(
            feedFetchLogReport.findings.contains {
                $0.rule == .localOnlyStoreBoundary
                    && $0.affectedPaths == [
                        "FeedFetchLog",
                        "SwiftDataFeedFetchLogRepository",
                        "FeedFetcher"
                    ]
            }
        )
    }

    @Test
    func cloudKitCompatibilityAuditKeepsArticleStateAsScalarSyncBoundary() throws {
        let audit = Self.articleStateArticleFeedFetchLog
        let articleStateReport = try #require(audit.report(for: .articleState))

        #expect(
            articleStateReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataArticleStateRepository.fetchState(feedID:articleExternalID:)",
                        "SwiftDataArticleStateRepository.fetchOrCreate(feedID:articleExternalID:)",
                        "SwiftDataArticleStateRepository.fetchCanonicalState(feedID:articleExternalID:removeDuplicates:)",
                        "SwiftDataArticleStateIdentityRepairer.stageRepairs(feedID:normalizedIdentities:cancellationCheckpoint:progressProbe:)",
                        "SwiftDataArticleStateRepository.shouldApply(_:to:)"
                    ]
            }
        )
        #expect(
            articleStateReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "ArticleState.feedID",
                        "ArticleState.articleExternalID",
                        "SwiftDataArticleStateRepository.fetchStateSnapshots(for:)"
                    ]
            }
        )
    }
}
