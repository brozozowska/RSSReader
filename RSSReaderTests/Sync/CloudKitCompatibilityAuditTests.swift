import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Compatibility Audit")
@MainActor
struct CloudKitCompatibilityAuditTests {
    @Test
    func cloudKitCompatibilityAuditFlagsCurrentAppSettingsFeedAndFolderBlockers() throws {
        let audit = CloudKitCompatibilityAudit.appSettingsFeedFolder

        #expect(audit.reports.map(\.model) == [.appSettings, .feed, .folder])

        let appSettingsReport = try #require(audit.report(for: .appSettings))
        let feedReport = try #require(audit.report(for: .feed))
        let folderReport = try #require(audit.report(for: .folder))

        #expect(appSettingsReport.hasBlockingFindings)
        #expect(feedReport.hasBlockingFindings)
        #expect(folderReport.hasBlockingFindings)

        #expect(
            appSettingsReport.findings.contains {
                $0.rule == .unsupportedUniqueConstraint
                    && $0.affectedPaths == ["AppSettings.id", "AppSettings.singletonKey"]
            }
        )
        #expect(
            feedReport.findings.contains {
                $0.rule == .unsupportedUniqueConstraint
                    && $0.affectedPaths == ["Feed.id", "Feed.url"]
            }
        )
        #expect(
            feedReport.findings.contains {
                $0.rule == .nonOptionalRelationship
                    && $0.affectedPaths == ["Feed.articles"]
            }
        )
        #expect(
            feedReport.findings.contains {
                $0.rule == .crossStoreRelationship
                    && $0.affectedPaths == ["Feed.articles", "Article.feed"]
            }
        )
        #expect(
            folderReport.findings.contains {
                $0.rule == .unsupportedUniqueConstraint
                    && $0.affectedPaths == ["Folder.id", "Folder.name"]
            }
        )
        #expect(
            folderReport.findings.contains {
                $0.rule == .nonOptionalRelationship
                    && $0.affectedPaths == ["Folder.feeds"]
            }
        )
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
                    && $0.affectedPaths == ["SwiftDataFeedRepository.fetchFeed(url:)"]
            }
        )
        #expect(
            folderReport.findings.contains {
                $0.rule == .repositoryManagedIdentityInvariant
                    && $0.affectedPaths == ["SwiftDataFolderRepository.fetchFolder(name:)"]
            }
        )
    }
}
