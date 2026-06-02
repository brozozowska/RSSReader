import Foundation

extension FeedParserService {
    static func detectFeedKind(in document: FeedXMLDocument) -> FeedKind {
        let rootElement = document.rootElement
        let rootName = rootElement.name.lowercased()
        let qualifiedName = rootElement.qualifiedName?.lowercased()
        let namespaceURI = rootElement.namespaceURI?.lowercased()

        if rootName == "rss" {
            return .rss
        }

        let isAtomFeedByName = rootName == "feed" || qualifiedName == "atom:feed"
        let isAtomFeedByNamespace = namespaceURI == "http://www.w3.org/2005/atom"

        if isAtomFeedByName && isAtomFeedByNamespace {
            return .atom
        }

        return .unknown
    }

    static func detectFeedKind(in response: FeedResponse) throws -> FeedKind {
        try detectFeedKind(in: parse(response))
    }
}
