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

    static func extractFeedMetadata(from document: FeedXMLDocument) throws -> ParsedFeedMetadataDTO {
        switch detectFeedKind(in: document) {
        case .rss:
            try extractRSSMetadata(from: document)
        case .atom:
            try extractAtomMetadata(from: document)
        case .unknown:
            throw FeedParserError.unsupportedFeedKind(.unknown)
        }
    }

    static func extractArticlePayloads(from document: FeedXMLDocument) throws -> [ParsedFeedEntryDTO] {
        switch detectFeedKind(in: document) {
        case .rss:
            try extractRSSArticlePayloads(from: document)
        case .atom:
            try extractAtomArticlePayloads(from: document)
        case .unknown:
            throw FeedParserError.unsupportedFeedKind(.unknown)
        }
    }
}
