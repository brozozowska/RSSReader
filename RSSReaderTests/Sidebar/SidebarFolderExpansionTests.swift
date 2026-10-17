import Foundation
import Testing
@testable import RSSReader

@Suite("Sidebar / Folder Expansion")
@MainActor
struct SidebarFolderExpansionTests {
    @Test(arguments: [false, true])
    func filterReloadsRetainExpandedAndCollapsedHiddenFolders(collapsed: Bool) async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let news = try harness.folderRepository.insert(Folder(name: "News"))
        let tech = try harness.folderRepository.insert(Folder(name: "Tech"))
        let feed = try harness.feedRepository.insert(
            Feed(url: "https://example.com/news.xml", title: "News Feed", folder: news)
        )
        _ = try harness.insertArticle(
            feed: feed, externalID: "news", url: "https://example.com/news", title: "News"
        )
        let controller = makeController()
        _ = await load(controller, harness: harness, filter: .unread)
        #expect(folderRows(controller, filter: .unread).first?.isExpanded == true)
        if collapsed { controller.toggleFolderExpansion(named: news.name) }

        for filter: SidebarArticleFilter in [.starred, .allItems, .unread, .starred, .unread] {
            let selection = await load(controller, harness: harness, filter: filter)
            #expect(selection == .folder(news.name))
            #expect(controller.collapsedFolderIDs == (collapsed ? [news.id] : []))
            let rows = folderRows(controller, filter: filter)
            if filter == .starred {
                #expect(rows.isEmpty)
            } else {
                #expect(rows.first(where: { $0.folderID == news.id })?.isExpanded == !collapsed)
                #expect(rows.first(where: { $0.folderID == news.id })?.count == 1)
                if filter == .allItems {
                    #expect(rows.first(where: { $0.folderID == tech.id })?.isExpanded == true)
                }
            }
        }
    }

    @Test
    func refreshAndReloadDoNotExpandUserCollapsedFolder() async throws {
        let url = "https://example.com/news-refresh.xml"
        let client = ScriptedHTTPClient(
            responseSequencesByURL: [url: [.response(statusCode: 304, headers: [:], body: "")]]
        )
        let harness = try TestHarness.make(httpClient: client)
        let news = try harness.folderRepository.insert(Folder(name: "News"))
        _ = try harness.feedRepository.insert(Feed(url: url, title: "News Feed", folder: news))
        let controller = makeController()
        let appState = AppState()
        harness.dependencies.appActions.showFolder(named: news.name, using: appState)
        harness.dependencies.appActions.applySidebarArticleFilter(.allItems, using: appState)
        _ = await load(controller, harness: harness, filter: .allItems)
        controller.toggleFolderExpansion(named: news.name)

        _ = await controller.refreshSidebar(
            dependencies: harness.dependencies, appState: appState,
            currentSelection: .folder(news.name), filter: .allItems
        )
        _ = await load(controller, harness: harness, filter: .allItems)

        #expect(await client.recordedRequests().count == 1)
        #expect(controller.collapsedFolderIDs == [news.id])
        #expect(folderRows(controller, filter: .allItems).first?.isExpanded == false)
        #expect(appState.selectedSidebarSelection == .folder(news.name))
    }

    @Test(arguments: [false, true])
    func renameRetainsFolderIdentityAndExpansion(collapsed: Bool) async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let news = try harness.folderRepository.insert(Folder(name: "News"))
        let controller = makeController()
        _ = await load(controller, harness: harness, filter: .allItems)
        if collapsed { controller.toggleFolderExpansion(named: news.name) }

        _ = try harness.folderRepository.update(
            folderID: news.id, with: FolderDetailsUpdate(name: "World News")
        )
        _ = await load(controller, harness: harness, filter: .allItems)
        let row = try #require(folderRows(controller, filter: .allItems).first)
        #expect(row.name == "World News")
        #expect(row.folderID == news.id)
        #expect(row.isExpanded == !collapsed)

        controller.toggleFolderExpansion(named: "World News")
        #expect(folderRows(controller, filter: .allItems).first?.isExpanded == collapsed)
    }

    @Test
    func deletePrunesOnlyDeletedIdentityAndSameNameNewFolderStartsExpanded() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let news = try harness.folderRepository.insert(Folder(name: "News"))
        let tech = try harness.folderRepository.insert(Folder(name: "Tech"))
        let controller = makeController()
        _ = await load(controller, harness: harness, filter: .allItems)
        controller.toggleFolderExpansion(named: news.name)
        controller.toggleFolderExpansion(named: tech.name)

        try harness.folderRepository.delete(news)
        _ = await load(controller, harness: harness, filter: .starred)
        #expect(controller.collapsedFolderIDs == [tech.id])
        let replacement = try harness.folderRepository.insert(Folder(name: "News"))
        #expect(replacement.id != news.id)
        _ = await load(controller, harness: harness, filter: .allItems)

        #expect(controller.collapsedFolderIDs == [tech.id])
        #expect(folderRows(controller, filter: .allItems).first(where: {
            $0.folderID == replacement.id
        })?.isExpanded == true)
        #expect(folderRows(controller, filter: .allItems).first(where: {
            $0.folderID == tech.id
        })?.isExpanded == false)
    }

    @Test
    func localPreferencesSurviveNewStoreAndControllerAndPersistExplicitExpansion() async throws {
        let suiteName = "SidebarFolderExpansionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let news = try harness.folderRepository.insert(Folder(name: "News"))
        let tech = try harness.folderRepository.insert(Folder(name: "Tech"))
        let first = SidebarScreenController(
            folderExpansionStore: SidebarFolderExpansionStore(userDefaults: defaults)
        )
        _ = await load(first, harness: harness, filter: .allItems)
        first.toggleFolderExpansion(named: news.name)
        first.toggleFolderExpansion(named: tech.name)

        let recreatedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let second = SidebarScreenController(
            folderExpansionStore: SidebarFolderExpansionStore(userDefaults: recreatedDefaults)
        )
        _ = await load(second, harness: harness, filter: .starred)
        #expect(second.collapsedFolderIDs == [news.id, tech.id])
        _ = await load(second, harness: harness, filter: .allItems)
        #expect(folderRows(second, filter: .allItems).allSatisfy { !$0.isExpanded })
        second.toggleFolderExpansion(named: tech.name)

        let third = SidebarScreenController(
            folderExpansionStore: SidebarFolderExpansionStore(userDefaults: defaults)
        )
        _ = await load(third, harness: harness, filter: .allItems)
        #expect(third.collapsedFolderIDs == [news.id])
        #expect(folderRows(third, filter: .allItems).first(where: {
            $0.folderID == tech.id
        })?.isExpanded == true)

        try harness.folderRepository.delete(news)
        _ = await load(third, harness: harness, filter: .allItems)
        #expect(SidebarFolderExpansionStore(userDefaults: defaults).collapsedFolderIDs.isEmpty)
    }

    @Test
    func unavailableLoadDoesNotForgetCollapsedFolders() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let news = try harness.folderRepository.insert(Folder(name: "News"))
        let controller = makeController()
        _ = await load(controller, harness: harness, filter: .allItems)
        controller.toggleFolderExpansion(named: news.name)

        _ = await controller.loadFeeds(
            showsFullScreenLoading: true,
            dependencies: AppDependencies(logger: RecordingLogger()),
            currentSelection: nil, filter: .starred
        )
        #expect(controller.collapsedFolderIDs == [news.id])
        _ = await load(controller, harness: harness, filter: .allItems)
        #expect(folderRows(controller, filter: .allItems).first?.isExpanded == false)
    }

    private func makeController() -> SidebarScreenController {
        SidebarScreenController(folderExpansionStore: SidebarFolderExpansionStore(userDefaults: nil))
    }

    private func load(
        _ controller: SidebarScreenController,
        harness: TestHarness,
        filter: SidebarArticleFilter
    ) async -> SidebarSelection? {
        await controller.loadFeeds(
            showsFullScreenLoading: false, dependencies: harness.dependencies,
            currentSelection: .folder("News"), filter: filter
        )
    }

    private func folderRows(
        _ controller: SidebarScreenController,
        filter: SidebarArticleFilter
    ) -> [SidebarFolderRowState] {
        controller.viewState(filter: filter, iCloudSyncStatus: .disabled).folderRows.compactMap {
            if case .folder(let row) = $0 { return row }
            return nil
        }
    }
}
