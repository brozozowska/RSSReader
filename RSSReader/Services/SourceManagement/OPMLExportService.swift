import Foundation

struct OPMLExportDocumentDTO: Equatable, Sendable {
    let title: String
    let feeds: [OPMLExportFeedDTO]
    let folders: [OPMLExportFolderDTO]
}

struct OPMLExportFeedDTO: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let xmlURL: String
    let htmlURL: String?
    let kind: FeedKind
    let folderID: UUID?
}

struct OPMLExportFolderDTO: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
}

enum OPMLExportService {
    @MainActor
    static func exportDocument(
        feedRepository: any FeedRepository,
        folderRepository: any FolderRepository,
        title: String = defaultDocumentTitle
    ) throws -> String {
        try exportDocument(
            OPMLExportDocumentDTO(
                title: title,
                feeds: feedRepository.fetchActiveFeeds().map(OPMLExportFeedDTO.init(feed:)),
                folders: folderRepository.fetchAllFolders().map(OPMLExportFolderDTO.init(folder:))
            )
        )
    }

    static func exportDocument(_ document: OPMLExportDocumentDTO) -> String {
        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            #"  <head>"#,
            #"    <title>\#(escapeText(document.title))</title>"#,
            #"  </head>"#,
            #"  <body>"#
        ]

        let groupedFeeds = Dictionary(grouping: sortedFeeds(document.feeds), by: \.folderID)
        for feed in groupedFeeds[nil] ?? [] {
            lines.append(feedOutline(feed, indentation: "    "))
        }

        for folder in sortedFolders(document.folders) {
            guard let feeds = groupedFeeds[folder.id], feeds.isEmpty == false else {
                continue
            }

            let folderName = escapeAttribute(folder.name)
            lines.append(#"    <outline text="\#(folderName)" title="\#(folderName)">"#)
            for feed in feeds {
                lines.append(feedOutline(feed, indentation: "      "))
            }
            lines.append("    </outline>")
        }

        lines.append(contentsOf: [
            "  </body>",
            "</opml>"
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    private nonisolated static let defaultDocumentTitle = "RSSReader Subscriptions"

    private static func sortedFolders(_ folders: [OPMLExportFolderDTO]) -> [OPMLExportFolderDTO] {
        folders.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func sortedFeeds(_ feeds: [OPMLExportFeedDTO]) -> [OPMLExportFeedDTO] {
        feeds.sorted { lhs, rhs in
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            let urlComparison = lhs.xmlURL.localizedCaseInsensitiveCompare(rhs.xmlURL)
            if urlComparison != .orderedSame {
                return urlComparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func feedOutline(_ feed: OPMLExportFeedDTO, indentation: String) -> String {
        let title = escapeAttribute(feed.title)
        var attributes = [
            #"text="\#(title)""#,
            #"title="\#(title)""#,
            #"type="\#(escapeAttribute(feed.kind.opmlTypeValue))""#,
            #"xmlUrl="\#(escapeAttribute(feed.xmlURL))""#
        ]

        if let htmlURL = feed.htmlURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           htmlURL.isEmpty == false {
            attributes.append(#"htmlUrl="\#(escapeAttribute(htmlURL))""#)
        }

        return "\(indentation)<outline \(attributes.joined(separator: " ")) />"
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private extension OPMLExportFeedDTO {
    @MainActor
    init(feed: Feed) {
        self.init(
            id: feed.id,
            title: feed.displayTitle,
            xmlURL: feed.url,
            htmlURL: feed.siteURL,
            kind: feed.kind,
            folderID: feed.folder?.id
        )
    }
}

private extension OPMLExportFolderDTO {
    @MainActor
    init(folder: Folder) {
        self.init(
            id: folder.id,
            name: folder.name,
            sortOrder: folder.sortOrder
        )
    }
}

private extension FeedKind {
    var opmlTypeValue: String {
        switch self {
        case .atom:
            "atom"
        case .rss, .unknown:
            "rss"
        }
    }
}
