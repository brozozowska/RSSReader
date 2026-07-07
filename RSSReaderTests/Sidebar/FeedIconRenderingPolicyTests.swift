import SwiftUI
import Testing
@testable import RSSReader

@Suite("Sidebar / Feed Icon Rendering Policy")
struct FeedIconRenderingPolicyTests {
    @Test
    func sidebarPolicyKeepsIconInsideStableRoundedContainer() {
        let policy = FeedIconRenderingPolicy.sidebar(colorScheme: .light)

        #expect(policy.containerSize == 20)
        #expect(policy.iconSize == 18)
        #expect(policy.iconSize < policy.containerSize)
        #expect(policy.cornerRadius == 5)
        #expect(policy.iconCornerRadius == 4)
        #expect(policy.borderWidth == 1)
    }

    @Test
    func sidebarPolicyUsesVisibleButSubtleBackdropForBothThemes() {
        let lightPolicy = FeedIconRenderingPolicy.sidebar(colorScheme: .light)
        let darkPolicy = FeedIconRenderingPolicy.sidebar(colorScheme: .dark)

        #expect(lightPolicy.backgroundOpacity > 0)
        #expect(lightPolicy.borderOpacity > lightPolicy.backgroundOpacity)
        #expect(darkPolicy.backgroundOpacity > 0)
        #expect(darkPolicy.borderOpacity > darkPolicy.backgroundOpacity)
        #expect(darkPolicy.backgroundOpacity >= lightPolicy.backgroundOpacity)
        #expect(darkPolicy.borderOpacity >= lightPolicy.borderOpacity)
    }
}
