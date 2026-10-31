import Testing
@testable import RSSReader

@Suite("Articles Screen / Coverage Lifecycle")
@MainActor
struct ArticleListCoverageLifecycleTests {
    @Test
    func reCoveringCancelsPendingResumeAndKeepsReloadDeferred() async throws {
        let lifecycle = ArticleListCoverageLifecycle()
        let started = AsyncTestGate(), release = AsyncTestGate()
        var loaded = false, delayCompleted = false, suspensions = 0
        lifecycle.deferLoad { suspensions += 1 }
        lifecycle.resume(canResume: { true }, load: { loaded = true }, delay: {
            started.release()
            try await release.wait(honorsCancellation: false)
            delayCompleted = true
        })
        try await started.wait()
        lifecycle.deferLoad { suspensions += 1 }
        release.release()
        try await waitUntil("cancelled deferred load") { delayCompleted }
        #expect(loaded == false)
        #expect(suspensions == 2)
        #expect(lifecycle.hasDeferredLoad)
        lifecycle.resume(canResume: { true }, load: { loaded = true }, delay: {})
        try await waitUntil("retaining resume") { loaded }
        #expect(lifecycle.hasDeferredLoad == false)
    }

    @Test
    func nativeBackDropsPendingResumeWithoutLoading() async throws {
        let lifecycle = ArticleListCoverageLifecycle()
        let started = AsyncTestGate(), release = AsyncTestGate()
        var loaded = false, delayCompleted = false
        lifecycle.deferLoad {}
        lifecycle.resume(canResume: { true }, load: { loaded = true }, delay: {
            started.release()
            try await release.wait(honorsCancellation: false)
            delayCompleted = true
        })
        try await started.wait()
        lifecycle.endPresentation()
        release.release()
        try await waitUntil("cancelled Back completion") { delayCompleted }
        #expect(loaded == false)
        #expect(lifecycle.hasDeferredLoad == false)
    }

    @Test
    func staleResumeCannotLoadWhileRouteIsCovered() async throws {
        let lifecycle = ArticleListCoverageLifecycle()
        let completed = AsyncTestGate()
        var loaded = false
        lifecycle.deferLoad {}
        lifecycle.resume(canResume: { false }, load: { loaded = true }, delay: { completed.release() })
        try await completed.wait()
        #expect(loaded == false)
        #expect(lifecycle.hasDeferredLoad)
        lifecycle.resume(canResume: { true }, load: { loaded = true }, delay: {})
        try await waitUntil("retry uncovered reload") { loaded }
        #expect(lifecycle.hasDeferredLoad == false)
    }
}
