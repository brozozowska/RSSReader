import Foundation
import Testing
@testable import RSSReader

@Suite("Settings / OPML Presentation Bridge")
@MainActor
struct SettingsOPMLPresentationBridgeTests {
    @Test
    func replacementCancelsOldImportWithoutReleasingNewTaskSlot() async throws {
        let bridge = SettingsOPMLPresentationBridge()
        let firstStarted = AsyncTestGate(), firstRelease = AsyncTestGate()
        let secondStarted = AsyncTestGate(), secondRelease = AsyncTestGate()
        var oldCompleted = false
        var oldWasCancelled = false
        bridge.handleImportResult(.success(URL(fileURLWithPath: "/first.opml")), preparePreview: { _ in
            firstStarted.release()
            try? await firstRelease.wait(honorsCancellation: false)
            oldWasCancelled = Task.isCancelled
            oldCompleted = true
        }, reportFailure: { _ in Issue.record("Unexpected import failure") })
        try await firstStarted.wait()
        bridge.handleImportResult(.success(URL(fileURLWithPath: "/second.opml")), preparePreview: { _ in
            secondStarted.release()
            try? await secondRelease.wait()
        }, reportFailure: { _ in Issue.record("Unexpected import failure") })
        try await secondStarted.wait()
        firstRelease.release()
        try await waitUntil("old import cleanup") { oldCompleted }
        #expect(oldWasCancelled)
        #expect(bridge.isPreparingImport)
        secondRelease.release()
        try await waitUntil("new import cleanup") { bridge.isPreparingImport == false }
    }

    @Test
    func dismissalCancelsImportAndReleasesExportDocument() async throws {
        let bridge = SettingsOPMLPresentationBridge()
        let started = AsyncTestGate(), cancelled = AsyncTestGate()
        bridge.presentExporter(document: SettingsOPMLFileDocument(xml: "<opml/>"))
        bridge.handleImportResult(.success(URL(fileURLWithPath: "/cancel.opml")), preparePreview: { _ in
            started.release()
            do { try await Task.sleep(for: .seconds(30)) } catch {}
            #expect(Task.isCancelled)
            cancelled.release()
        }, reportFailure: { _ in Issue.record("Unexpected import failure") })
        try await started.wait()
        bridge.endPresentation()
        try await cancelled.wait()
        #expect(bridge.exportDocument == nil)
        #expect(bridge.isExporterPresented == false)
        #expect(bridge.isImporterPresented == false)
        #expect(bridge.isPreparingImport == false)
    }

    @Test
    func platformFailurePreservesStagedChangesAndAllowsApply() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .articleOpeningMode, optionID: ArticleOpeningMode.safariView.rawValue,
            dependencies: harness.dependencies
        )
        let bridge = SettingsOPMLPresentationBridge()
        bridge.handleImportResult(.failure(CocoaError(.fileReadNoPermission)), preparePreview: { _ in
            Issue.record("Failure must not prepare a preview")
        }, reportFailure: {
            controller.applyOPMLImportPresentationFailure($0, dependencies: harness.dependencies)
        })
        #expect(controller.screenState.opmlTransferStatus?.kind == .failure)
        #expect(controller.viewState().canApplyChanges)
        bridge.endPresentation()
        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        #expect(try harness.dependencies.appSettingsService?.fetchSettings().articleOpeningMode == .safariView)
    }

    @Test
    func previewCancelAndImportSuccessKeepStagedSettingsUntilApply() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        let bridge = SettingsOPMLPresentationBridge()
        controller.loadSettings(dependencies: harness.dependencies)
        controller.handlePickerOptionSelection(
            itemID: .articleOpeningMode, optionID: ArticleOpeningMode.safariView.rawValue,
            dependencies: harness.dependencies
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".opml")
        try Data(#"<opml version="2.0"><body><outline text="Imported" xmlUrl="https://example.com/imported"/></body></opml>"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        for shouldCommit in [false, true] {
            bridge.handleImportResult(.success(url), preparePreview: {
                await controller.prepareOPMLImportPreview(fileURL: $0, dependencies: harness.dependencies)
            }, reportFailure: { _ in Issue.record("Unexpected file picker failure") })
            try await waitUntil("preview preparation finished") { bridge.isPreparingImport == false }
            #expect(controller.screenState.opmlImportPreview?.importableEntryCount == 1)
            if shouldCommit {
                controller.commitOPMLImportPreview(dependencies: harness.dependencies)
                #expect(controller.screenState.opmlTransferStatus?.kind == .success)
            } else {
                controller.dismissOPMLImportPreview()
                #expect(try harness.feedRepository.fetchFeed(url: "https://example.com/imported") == nil)
            }
            #expect(controller.screenState.opmlImportPreview == nil)
            #expect(controller.viewState().canApplyChanges)
            #expect(try harness.dependencies.appSettingsService?.fetchSettings().articleOpeningMode == .feedReader)
        }
        #expect(try harness.feedRepository.fetchFeed(url: "https://example.com/imported") != nil)
        bridge.endPresentation()
        #expect(controller.applySettingsChanges(dependencies: harness.dependencies))
        #expect(try harness.dependencies.appSettingsService?.fetchSettings().articleOpeningMode == .safariView)
    }

    @Test
    func cancelledImportDropsLateNonCancellationFailure() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        let started = AsyncTestGate(), release = AsyncTestGate()
        let task = Task {
            await controller.prepareOPMLImportPreview(
                fileURL: URL(fileURLWithPath: "/late.opml"), dependencies: harness.dependencies,
                fileLoader: LateFailureLoader(started: started, release: release)
            )
        }
        try await started.wait()
        task.cancel()
        release.release()
        await task.value
        #expect(controller.screenState.opmlTransferStatus == nil)
        #expect(controller.screenState.opmlImportPreview == nil)
    }
}

private nonisolated struct LateFailureLoader: OPMLImportFileLoading {
    let started: AsyncTestGate
    let release: AsyncTestGate
    func loadPreview(
        fileURL: URL, existingFeeds: [FeedManagementFeedSummary], existingFolders: [FeedManagementFolderSummary]
    ) async throws -> OPMLImportPreviewPlan {
        started.release()
        try await release.wait(honorsCancellation: false)
        throw CocoaError(.fileReadCorruptFile)
    }
}
