import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh System Prerequisites")
struct BackgroundRefreshSystemPrerequisitesTests {
    @Test
    func appInfoPlistDeclaresBackgroundRefreshIdentifierAndFetchBackgroundMode() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RSSReader")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        let permittedIdentifiers = try #require(
            plist[BackgroundRefreshTaskConfiguration.permittedIdentifiersInfoPlistKey] as? [String]
        )
        let backgroundModes = try #require(plist["UIBackgroundModes"] as? [String])

        #expect(permittedIdentifiers == BackgroundRefreshTaskConfiguration.permittedIdentifiers)
        #expect(backgroundModes.contains("fetch"))
        #expect(backgroundModes.contains("remote-notification"))
    }
}
