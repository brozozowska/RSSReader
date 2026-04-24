import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Development Schema Bootstrap")
@MainActor
struct CloudKitDevelopmentSchemaBootstrapTests {
    @Test
    func cloudKitDevelopmentSchemaBootstrapSkipsWhileSyncBackedAuditHasBlockers() {
        let decision = CloudKitDevelopmentSchemaBootstrap.makeDecision()

        switch decision {
        case .run:
            Issue.record("Expected bootstrap to skip while sync-backed audit still reports blockers")
        case .skip(let reason):
            #expect(reason.contains("sync-backed schema still has CloudKit blockers"))
            #expect(reason.contains("feed: Feed.articles"))
            #expect(reason.contains("folder: Folder.feeds"))
        }
    }

    @Test
    func cloudKitDevelopmentSchemaBootstrapBuildsRequestOnceSyncBackedAuditIsClean() throws {
        let decision = CloudKitDevelopmentSchemaBootstrap.makeDecision(
            audit: cleanSyncBackedAudit(),
            syncBackedPolicy: .privateContainer("iCloud.ru.brozozowska.RSSReader")
        )

        switch decision {
        case .skip(let reason):
            Issue.record("Expected bootstrap request, got skip: \(reason)")
        case .run(let request):
            #expect(request.containerIdentifier == "iCloud.ru.brozozowska.RSSReader")
            #expect(request.storeConfigurationName == "SyncBackedStore")
            #expect(
                request.modelTypes.map { String(reflecting: $0) }
                    == [
                        String(reflecting: AppSettings.self),
                        String(reflecting: ArticleState.self),
                        String(reflecting: Feed.self),
                        String(reflecting: Folder.self)
                    ]
            )
        }
    }

    @Test
    func cloudKitDevelopmentSchemaBootstrapRequiresExplicitPrivateContainerPolicy() {
        let decision = CloudKitDevelopmentSchemaBootstrap.makeDecision(
            audit: cleanSyncBackedAudit(),
            syncBackedPolicy: .disabled
        )

        switch decision {
        case .run:
            Issue.record("Expected bootstrap to skip without explicit private container policy")
        case .skip(let reason):
            #expect(reason.contains("explicit private CloudKit container policy"))
        }
    }

    private func cleanSyncBackedAudit() -> CloudKitCompatibilityAudit {
        CloudKitCompatibilityAudit(
            reports: [
                CloudKitModelCompatibilityReport(model: .appSettings, findings: []),
                CloudKitModelCompatibilityReport(model: .feed, findings: []),
                CloudKitModelCompatibilityReport(model: .folder, findings: []),
                CloudKitModelCompatibilityReport(model: .articleState, findings: [])
            ],
            sourceSummary: "Test fixture"
        )
    }
}
