import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Task Configuration")
struct BackgroundRefreshTaskConfigurationTests {
    @Test
    func backgroundRefreshTaskConfigurationUsesStableAppRefreshIdentifier() {
        #expect(
            BackgroundRefreshTaskConfiguration.appRefreshIdentifier
                == "ru.brozozowska.RSSReader.background-refresh"
        )
    }

    @Test
    func backgroundRefreshTaskConfigurationExposesPermittedIdentifierList() {
        #expect(
            BackgroundRefreshTaskConfiguration.permittedIdentifiers
                == [BackgroundRefreshTaskConfiguration.appRefreshIdentifier]
        )
    }

    @Test
    func backgroundRefreshTaskConfigurationUsesExpectedInfoPlistKey() {
        #expect(
            BackgroundRefreshTaskConfiguration.permittedIdentifiersInfoPlistKey
                == "BGTaskSchedulerPermittedIdentifiers"
        )
    }
}
