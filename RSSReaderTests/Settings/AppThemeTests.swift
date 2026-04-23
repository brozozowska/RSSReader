import SwiftUI
import Testing
@testable import RSSReader

@Suite("Settings / App Theme")
@MainActor
struct AppThemeTests {
    @Test
    func appThemeApplicationPolicyResolvesAutomaticModesAgainstSystemColorScheme() {
        let automaticDarkPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .automaticLightDark,
            systemColorScheme: .dark
        )
        let automaticBlackPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .automaticLightBlack,
            systemColorScheme: .dark
        )
        let automaticLightPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .automaticLightBlack,
            systemColorScheme: .light
        )

        #expect(automaticDarkPolicy.preferredColorScheme == nil)
        #expect(automaticDarkPolicy.resolvedTheme == .dark)
        #expect(automaticBlackPolicy.preferredColorScheme == nil)
        #expect(automaticBlackPolicy.resolvedTheme == .black)
        #expect(automaticLightPolicy.resolvedTheme == .light)
    }

    @Test
    func appThemeApplicationPolicyUsesExplicitThemeModeForResolvedThemeAndPreferredColorScheme() {
        let lightPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .light,
            systemColorScheme: .dark
        )
        let darkPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .dark,
            systemColorScheme: .light
        )
        let blackPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .black,
            systemColorScheme: .light
        )

        #expect(lightPolicy.preferredColorScheme == .light)
        #expect(lightPolicy.resolvedTheme == .light)
        #expect(darkPolicy.preferredColorScheme == .dark)
        #expect(darkPolicy.resolvedTheme == .dark)
        #expect(blackPolicy.preferredColorScheme == .dark)
        #expect(blackPolicy.resolvedTheme == .black)
    }
}
