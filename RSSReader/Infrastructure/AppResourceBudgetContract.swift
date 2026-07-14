import Foundation

nonisolated enum AppRuntimeInput: String, CaseIterable, Sendable {
    case feedXML
    case discoveryHTML
    case feedIcon
    case articleImage
    case opml
}

nonisolated enum AppResourceBudgetViolation: Error, Equatable, Sendable {
    case compressedBodySizeExceeded(
        input: AppRuntimeInput,
        maximumBytes: Int64,
        actualBytes: Int64
    )
    case unsupportedMIMEType(
        input: AppRuntimeInput,
        receivedMIMEType: String?
    )
    case imagePixelDimensionsExceeded(
        input: AppRuntimeInput,
        maximumWidth: Int,
        maximumHeight: Int,
        maximumPixelCount: Int,
        actualWidth: Int,
        actualHeight: Int
    )
    case xmlElementCountExceeded(
        input: AppRuntimeInput,
        maximumCount: Int,
        actualCount: Int
    )
    case xmlDepthExceeded(
        input: AppRuntimeInput,
        maximumDepth: Int,
        actualDepth: Int
    )
    case xmlEntryCountExceeded(
        input: AppRuntimeInput,
        maximumCount: Int,
        actualCount: Int
    )
}

nonisolated struct RuntimeInputBodyBudget: Equatable, Sendable {
    let input: AppRuntimeInput
    let maximumCompressedBodyBytes: Int64
    let allowedMIMETypes: Set<String>
    let allowedMIMETypeSuffixes: Set<String>

    init(
        input: AppRuntimeInput,
        maximumCompressedBodyBytes: Int64,
        allowedMIMETypes: Set<String>,
        allowedMIMETypeSuffixes: Set<String> = []
    ) {
        precondition(maximumCompressedBodyBytes > 0)
        self.input = input
        self.maximumCompressedBodyBytes = maximumCompressedBodyBytes
        self.allowedMIMETypes = Set(allowedMIMETypes.map(Self.normalizeMIMEType))
        self.allowedMIMETypeSuffixes = Set(
            allowedMIMETypeSuffixes.map { $0.lowercased() }
        )
    }

    func validateCompressedBodyByteCount(_ actualBytes: Int64) throws {
        guard actualBytes <= maximumCompressedBodyBytes else {
            throw AppResourceBudgetViolation.compressedBodySizeExceeded(
                input: input,
                maximumBytes: maximumCompressedBodyBytes,
                actualBytes: actualBytes
            )
        }
    }

    func validateMIMEType(_ rawMIMEType: String?) throws {
        let normalizedMIMEType = rawMIMEType.map(Self.normalizeMIMEType)
        let isExplicitlyAllowed = normalizedMIMEType.map(allowedMIMETypes.contains) == true
        let hasAllowedSuffix = normalizedMIMEType.map { mimeType in
            allowedMIMETypeSuffixes.contains { mimeType.hasSuffix($0) }
        } == true

        guard isExplicitlyAllowed || hasAllowedSuffix else {
            throw AppResourceBudgetViolation.unsupportedMIMEType(
                input: input,
                receivedMIMEType: normalizedMIMEType
            )
        }
    }

    private static func normalizeMIMEType(_ value: String) -> String {
        value
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}

nonisolated struct RuntimeXMLInputBudget: Equatable, Sendable {
    let body: RuntimeInputBodyBudget
    let maximumElementCount: Int
    let maximumDepth: Int
    let maximumEntryCount: Int

    init(
        body: RuntimeInputBodyBudget,
        maximumElementCount: Int,
        maximumDepth: Int,
        maximumEntryCount: Int
    ) {
        precondition(maximumElementCount > 0)
        precondition(maximumDepth > 0)
        precondition(maximumEntryCount > 0)
        self.body = body
        self.maximumElementCount = maximumElementCount
        self.maximumDepth = maximumDepth
        self.maximumEntryCount = maximumEntryCount
    }

    func validateElementCount(_ actualCount: Int) throws {
        guard actualCount <= maximumElementCount else {
            throw AppResourceBudgetViolation.xmlElementCountExceeded(
                input: body.input,
                maximumCount: maximumElementCount,
                actualCount: actualCount
            )
        }
    }

    func validateDepth(_ actualDepth: Int) throws {
        guard actualDepth <= maximumDepth else {
            throw AppResourceBudgetViolation.xmlDepthExceeded(
                input: body.input,
                maximumDepth: maximumDepth,
                actualDepth: actualDepth
            )
        }
    }

    func validateEntryCount(_ actualCount: Int) throws {
        guard actualCount <= maximumEntryCount else {
            throw AppResourceBudgetViolation.xmlEntryCountExceeded(
                input: body.input,
                maximumCount: maximumEntryCount,
                actualCount: actualCount
            )
        }
    }
}

nonisolated struct RuntimeHTMLInputBudget: Equatable, Sendable {
    let body: RuntimeInputBodyBudget
    let maximumLinkTagCountToInspect: Int
    let maximumDiscoveryCandidateCount: Int

    init(
        body: RuntimeInputBodyBudget,
        maximumLinkTagCountToInspect: Int,
        maximumDiscoveryCandidateCount: Int
    ) {
        precondition(maximumLinkTagCountToInspect > 0)
        precondition(maximumDiscoveryCandidateCount > 0)
        self.body = body
        self.maximumLinkTagCountToInspect = maximumLinkTagCountToInspect
        self.maximumDiscoveryCandidateCount = maximumDiscoveryCandidateCount
    }
}

nonisolated struct RuntimeImageInputBudget: Equatable, Sendable {
    let body: RuntimeInputBodyBudget
    let maximumPixelWidth: Int
    let maximumPixelHeight: Int
    let maximumPixelCount: Int

    init(
        body: RuntimeInputBodyBudget,
        maximumPixelWidth: Int,
        maximumPixelHeight: Int,
        maximumPixelCount: Int
    ) {
        precondition(maximumPixelWidth > 0)
        precondition(maximumPixelHeight > 0)
        precondition(maximumPixelCount > 0)
        self.body = body
        self.maximumPixelWidth = maximumPixelWidth
        self.maximumPixelHeight = maximumPixelHeight
        self.maximumPixelCount = maximumPixelCount
    }

    func validatePixelDimensions(width: Int, height: Int) throws {
        let exceedsTotalPixelCount = width > 0
            && height > 0
            && width > maximumPixelCount / height
        let exceedsDimensions = width > maximumPixelWidth || height > maximumPixelHeight

        guard exceedsDimensions || exceedsTotalPixelCount else { return }

        throw AppResourceBudgetViolation.imagePixelDimensionsExceeded(
            input: body.input,
            maximumWidth: maximumPixelWidth,
            maximumHeight: maximumPixelHeight,
            maximumPixelCount: maximumPixelCount,
            actualWidth: width,
            actualHeight: height
        )
    }
}

nonisolated struct AppResourceBudgetContract: Equatable, Sendable {
    let feedXML: RuntimeXMLInputBudget
    let discoveryHTML: RuntimeHTMLInputBudget
    let feedIcon: RuntimeImageInputBudget
    let articleImage: RuntimeImageInputBudget
    let opml: RuntimeXMLInputBudget

    static let current = AppResourceBudgetContract(
        feedXML: RuntimeXMLInputBudget(
            body: RuntimeInputBodyBudget(
                input: .feedXML,
                maximumCompressedBodyBytes: 8 * 1024 * 1024,
                allowedMIMETypes: [
                    "application/atom+xml",
                    "application/rdf+xml",
                    "application/rss+xml",
                    "application/xml",
                    "text/xml"
                ],
                allowedMIMETypeSuffixes: ["+xml"]
            ),
            maximumElementCount: 100_000,
            maximumDepth: 64,
            maximumEntryCount: 5_000
        ),
        discoveryHTML: RuntimeHTMLInputBudget(
            body: RuntimeInputBodyBudget(
                input: .discoveryHTML,
                maximumCompressedBodyBytes: 2 * 1024 * 1024,
                allowedMIMETypes: [
                    "application/xhtml+xml",
                    "text/html"
                ]
            ),
            maximumLinkTagCountToInspect: 256,
            maximumDiscoveryCandidateCount: 16
        ),
        feedIcon: RuntimeImageInputBudget(
            body: RuntimeInputBodyBudget(
                input: .feedIcon,
                maximumCompressedBodyBytes: 2 * 1024 * 1024,
                allowedMIMETypes: [
                    "image/gif",
                    "image/jpeg",
                    "image/png",
                    "image/vnd.microsoft.icon",
                    "image/webp",
                    "image/x-icon"
                ]
            ),
            maximumPixelWidth: 1_024,
            maximumPixelHeight: 1_024,
            maximumPixelCount: 1_048_576
        ),
        articleImage: RuntimeImageInputBudget(
            body: RuntimeInputBodyBudget(
                input: .articleImage,
                maximumCompressedBodyBytes: 20 * 1024 * 1024,
                allowedMIMETypes: [
                    "image/avif",
                    "image/bmp",
                    "image/gif",
                    "image/heic",
                    "image/heif",
                    "image/jpeg",
                    "image/png",
                    "image/tiff",
                    "image/webp"
                ]
            ),
            maximumPixelWidth: 8_192,
            maximumPixelHeight: 8_192,
            maximumPixelCount: 24_000_000
        ),
        opml: RuntimeXMLInputBudget(
            body: RuntimeInputBodyBudget(
                input: .opml,
                maximumCompressedBodyBytes: 8 * 1024 * 1024,
                allowedMIMETypes: [
                    "application/opml+xml",
                    "application/xml",
                    "text/x-opml",
                    "text/xml"
                ],
                allowedMIMETypeSuffixes: ["+xml"]
            ),
            maximumElementCount: 100_000,
            maximumDepth: 32,
            maximumEntryCount: 20_000
        )
    )
}
