import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Portability / OPML Export Service")
@MainActor
struct OPMLExportServiceTests {
    @Test
    func exportsDeterministicOPMLForUngroupedAndFlatFolderFeeds() throws {
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let ungroupedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let groupedID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let emptyFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let document = OPMLExportDocumentDTO(
            title: "My Feeds",
            feeds: [
                OPMLExportFeedDTO(
                    id: groupedID,
                    title: "Grouped Feed",
                    xmlURL: "https://example.com/grouped.xml",
                    htmlURL: "https://example.com/grouped",
                    kind: .atom,
                    folderID: folderID
                ),
                OPMLExportFeedDTO(
                    id: ungroupedID,
                    title: "Ungrouped Feed",
                    xmlURL: "https://example.com/ungrouped.xml",
                    htmlURL: nil,
                    kind: .rss,
                    folderID: nil
                )
            ],
            folders: [
                OPMLExportFolderDTO(id: emptyFolderID, name: "Empty", sortOrder: 0),
                OPMLExportFolderDTO(id: folderID, name: "Tech / Apple", sortOrder: 1)
            ]
        )

        let xml = OPMLExportService.exportDocument(document)

        #expect(xml == """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>My Feeds</title>
          </head>
          <body>
            <outline text="Ungrouped Feed" title="Ungrouped Feed" type="rss" xmlUrl="https://example.com/ungrouped.xml" />
            <outline text="Tech / Apple" title="Tech / Apple">
              <outline text="Grouped Feed" title="Grouped Feed" type="atom" xmlUrl="https://example.com/grouped.xml" htmlUrl="https://example.com/grouped" />
            </outline>
          </body>
        </opml>

        """)
    }

    @Test
    func escapesXMLTextAndAttributes() throws {
        let document = OPMLExportDocumentDTO(
            title: #"Feeds & <Archive>"#,
            feeds: [
                OPMLExportFeedDTO(
                    id: UUID(),
                    title: #"A&B "Quoted" 'Feed' <Title>"#,
                    xmlURL: #"https://example.com/feed?x=1&name="rss""#,
                    htmlURL: #"https://example.com/feed?label=A&B"#,
                    kind: .unknown,
                    folderID: nil
                )
            ],
            folders: []
        )

        let xml = OPMLExportService.exportDocument(document)

        #expect(xml.contains("<title>Feeds &amp; &lt;Archive&gt;</title>"))
        #expect(xml.contains(#"text="A&amp;B &quot;Quoted&quot; &apos;Feed&apos; &lt;Title&gt;""#))
        #expect(xml.contains(#"xmlUrl="https://example.com/feed?x=1&amp;name=&quot;rss&quot;""#))
        #expect(xml.contains(#"htmlUrl="https://example.com/feed?label=A&amp;B""#))

        let parsedDocument = try OPMLParserService.parse(Data(xml.utf8))
        #expect(parsedDocument.title == "Feeds & <Archive>")
        #expect(parsedDocument.feeds.first?.displayTitle == #"A&B "Quoted" 'Feed' <Title>"#)
    }

    @Test
    func repositoryExportUsesOnlyActiveFeedsAndCurrentMetadata() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let activeFolder = try harness.folderRepository.insert(
            Folder(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                name: "Saved",
                sortOrder: 0
            )
        )
        let activeFeed = try harness.feedRepository.insert(
            Feed(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                url: "https://example.com/active.xml",
                siteURL: "https://example.com/active",
                title: "Metadata Title",
                displayTitleOverride: "Display Title",
                kind: .rss,
                folder: activeFolder
            )
        )
        _ = try harness.feedRepository.insert(
            Feed(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
                url: "https://example.com/inactive.xml",
                title: "Inactive Feed",
                kind: .rss,
                isActive: false
            )
        )

        let xml = try OPMLExportService.exportDocument(
            feedRepository: harness.feedRepository,
            folderRepository: harness.folderRepository,
            title: "Export"
        )

        #expect(xml.contains(#"<outline text="Display Title" title="Display Title" type="rss" xmlUrl="https://example.com/active.xml" htmlUrl="https://example.com/active" />"#))
        #expect(xml.contains(activeFeed.url))
        #expect(xml.contains("inactive") == false)
    }
}
