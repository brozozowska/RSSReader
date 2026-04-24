import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Compatibility Audit")
@MainActor
struct CloudKitCompatibilityAuditTests {
    @Test
    func cloudKitCompatibilityAuditTracksCleanSyncBackedModelSetAfterRelationshipMigration() throws {
        let audit = CloudKitCompatibilityAudit.appSettingsFeedFolder

        #expect(audit.reports.map(\.model) == [.appSettings, .feed, .folder])

        let appSettingsReport = try #require(audit.report(for: .appSettings))
        let feedReport = try #require(audit.report(for: .feed))
        let folderReport = try #require(audit.report(for: .folder))

        #expect(appSettingsReport.hasBlockingFindings == false)
        #expect(feedReport.hasBlockingFindings == false)
        #expect(folderReport.hasBlockingFindings == false)
    }

    @Test
    func cloudKitCompatibilityAuditCapturesRepositoryManagedIdentityInvariants() throws {
        let audit = CloudKitCompatibilityAudit.appSettingsFeedFolder

        let appSettingsReport = try #require(audit.report(for: .appSettings))
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
    func cloudKitCompatibilityAuditFlagsArticleStateArticleAndFeedFetchLogBoundaries() throws {
        let audit = CloudKitCompatibilityAudit.articleStateArticleFeedFetchLog

        #expect(audit.reports.map(\.model) == [.articleState, .article, .feedFetchLog])

        let articleStateReport = try #require(audit.report(for: .articleState))
        let articleReport = try #require(audit.report(for: .article))
        let feedFetchLogReport = try #require(audit.report(for: .feedFetchLog))

        #expect(articleStateReport.hasBlockingFindings == false)
        #expect(articleReport.hasBlockingFindings)
        #expect(feedFetchLogReport.hasBlockingFindings)
        #expect(
            articleReport.findings.contains {
                $0.rule == .localOnlyStoreBoundary
                    && $0.affectedPaths == [
                        "Article",
                        "SwiftDataArticleRepository",
                        "FeedRefreshService"
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
        let audit = CloudKitCompatibilityAudit.articleStateArticleFeedFetchLog
        let articleStateReport = try #require(audit.report(for: .articleState))

        #expect(
            articleStateReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == [
                        "SwiftDataArticleStateRepository.fetchState(feedID:articleExternalID:)",
                        "SwiftDataArticleStateRepository.fetchOrCreate(feedID:articleExternalID:)",
                        "SwiftDataArticleStateRepository.fetchCanonicalState(feedID:articleExternalID:removeDuplicates:)",
                        "SwiftDataArticleStateRepository.shouldApply(_:to:)"
                    ]
            }
        )
        #expect(
            articleStateReport.findings.contains {
                $0.rule == .crossStoreRelationship
                    && $0.affectedPaths == [
                        "ArticleState.feedID",
                        "ArticleState.articleExternalID",
                        "SwiftDataArticleStateRepository.fetchStateSnapshots(for:)"
                    ]
            }
        )
    }
}
