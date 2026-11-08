import Foundation

nonisolated enum FeedParserService {
    static func parseFeed(_ document: FeedXMLDocument) throws -> ParsedFeedDTO {
        switch detectFeedKind(in: document) {
        case .rss:
            try parseRSS(document)
        case .atom:
            try parseAtom(document)
        case .unknown:
            throw FeedParserError.unsupportedFeedKind(.unknown)
        }
    }

    static func parseFeed(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parseFeed(parse(response))
    }
}
