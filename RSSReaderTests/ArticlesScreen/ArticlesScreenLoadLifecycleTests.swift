import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / Load Lifecycle")
@MainActor
struct ArticlesScreenLoadLifecycleTests {
    @Test
    func supersededPrimaryCleanupKeepsReplacementFlightJoinable() async throws {
        let lifecycle = ArticlesScreenPrimaryLoadLifecycle()
        let oldGate = AsyncTestGate()
        let newGate = AsyncTestGate()
        defer { oldGate.release(); newGate.release(); lifecycle.cancel() }
        let context = ArticleListSession.Context(selection: .unread, sidebarArticleFilter: .allItems)
        let oldTask = lifecycle.start(context: context) { _ in
            try? await oldGate.wait("old primary", honorsCancellation: false)
        }
        try await waitUntil("old primary suspended") { oldGate.waiterCount == 1 }
        let oldGeneration = lifecycle.generation
        let newTask = lifecycle.start(context: context) { _ in
            try? await newGate.wait("replacement primary", honorsCancellation: false)
        }
        try await waitUntil("new primary suspended") { newGate.waiterCount == 1 }
        #expect(oldTask.isCancelled)
        #expect(lifecycle.generation != oldGeneration)
        oldGate.release()
        await oldTask.value
        #expect(lifecycle.activeTask(for: context) != nil)
        #expect(lifecycle.isActive)
        newGate.release()
        await newTask.value
        #expect(lifecycle.isActive == false)
        #expect(lifecycle.activeTask(for: context) == nil)
    }

    @Test
    func cancelledContinuationCleanupCannotClearReplacementWithSameIdentity() async throws {
        let lifecycle = ArticlesScreenContinuationLifecycle()
        let oldGate = AsyncTestGate()
        let newGate = AsyncTestGate()
        defer { oldGate.release(); newGate.release(); lifecycle.cancel() }
        let identity = ArticleListNextPageIdentity(
            generation: 1, sessionID: UUID(),
            context: ArticleListSession.Context(selection: .unread, sidebarArticleFilter: .allItems),
            cursor: makeArticleSearchCursor(seed: 1)
        )
        let oldTask = lifecycle.start(identity: identity) {
            try? await oldGate.wait("old continuation", honorsCancellation: false)
            return nil
        }
        try await waitUntil("old continuation suspended") { oldGate.waiterCount == 1 }
        lifecycle.cancel()
        let newTask = lifecycle.start(identity: identity) {
            try? await newGate.wait("new continuation", honorsCancellation: false)
            return nil
        }
        try await waitUntil("new continuation suspended") { newGate.waiterCount == 1 }
        oldGate.release()
        _ = await oldTask.value
        #expect(oldTask.isCancelled)
        #expect(lifecycle.activeTask(for: identity) != nil)
        #expect(lifecycle.isActive)
        newGate.release()
        _ = await newTask.value
        #expect(lifecycle.isActive == false)
    }

    @Test(arguments: [
        SidebarSelection?.none, .inbox, .unread, .starred, .folder("News"), .feed(UUID(uuidString: "00000000-0000-0000-0000-000000000850")!)
    ], [SidebarArticleFilter.allItems, .unread, .starred])
    func queryAndMutationUseSameFilter(selection: SidebarSelection?, filter: SidebarArticleFilter) {
        #expect(ArticlesScreenMutationReducer.articleListFilter(
            selection: selection, sidebarArticleFilter: filter
        ) == ArticleSearchScope.listFilter(selection: selection, sidebarArticleFilter: filter))
    }
}
