import Testing
@testable import RSSReader

@Suite("Infrastructure / Resource Budget Contract")
struct AppResourceBudgetContractTests {
    private let contract = AppResourceBudgetContract.current

    @Test
    func appCompositionExposesCurrentContract() {
        #expect(AppComposition.resourceBudgetContract == contract)
    }

    @Test
    func contractDefinesIndependentBodyBudgetsForEveryRuntimeInput() {
        #expect(contract.feedXML.body.input == .feedXML)
        #expect(contract.feedXML.body.maximumCompressedBodyBytes == 8 * 1024 * 1024)
        #expect(contract.discoveryHTML.input == .discoveryHTML)
        #expect(contract.discoveryHTML.maximumCompressedBodyBytes == 2 * 1024 * 1024)
        #expect(contract.feedIcon.body.input == .feedIcon)
        #expect(contract.feedIcon.body.maximumCompressedBodyBytes == 2 * 1024 * 1024)
        #expect(contract.articleImage.body.input == .articleImage)
        #expect(contract.articleImage.body.maximumCompressedBodyBytes == 20 * 1024 * 1024)
        #expect(contract.opml.body.input == .opml)
        #expect(contract.opml.body.maximumCompressedBodyBytes == 8 * 1024 * 1024)
    }

    @Test
    func bodyBudgetsAcceptBoundaryAndThrowTypedViolationsForEveryInput() throws {
        let budgets = [
            contract.feedXML.body,
            contract.discoveryHTML,
            contract.feedIcon.body,
            contract.articleImage.body,
            contract.opml.body
        ]

        for budget in budgets {
            try budget.validateCompressedBodyByteCount(budget.maximumCompressedBodyBytes)

            #expect(
                throws: AppResourceBudgetViolation.compressedBodySizeExceeded(
                    input: budget.input,
                    maximumBytes: budget.maximumCompressedBodyBytes,
                    actualBytes: budget.maximumCompressedBodyBytes + 1
                )
            ) {
                try budget.validateCompressedBodyByteCount(budget.maximumCompressedBodyBytes + 1)
            }

            #expect(
                throws: AppResourceBudgetViolation.unsupportedMIMEType(
                    input: budget.input,
                    receivedMIMEType: "application/octet-stream"
                )
            ) {
                try budget.validateMIMEType("application/octet-stream")
            }
        }
    }

    @Test
    func mimePoliciesNormalizeParametersAndAllowDeclaredXMLSuffixes() throws {
        try contract.feedXML.body.validateMIMEType("Application/RSS+XML; charset=utf-8")
        try contract.feedXML.body.validateMIMEType("application/custom+xml")
        try contract.discoveryHTML.validateMIMEType("TEXT/HTML; charset=UTF-8")
        try contract.feedIcon.body.validateMIMEType("image/png")
        try contract.articleImage.body.validateMIMEType("image/avif")
        try contract.opml.body.validateMIMEType("application/opml+xml")

        #expect(
            throws: AppResourceBudgetViolation.unsupportedMIMEType(
                input: .feedXML,
                receivedMIMEType: nil
            )
        ) {
            try contract.feedXML.body.validateMIMEType(nil)
        }
    }

    @Test
    func xmlBudgetsExposeStructuralLimitsAndExpectedViolations() throws {
        let budgets = [contract.feedXML, contract.opml]

        for budget in budgets {
            try budget.validateElementCount(budget.maximumElementCount)
            try budget.validateDepth(budget.maximumDepth)
            try budget.validateEntryCount(budget.maximumEntryCount)

            #expect(
                throws: AppResourceBudgetViolation.xmlElementCountExceeded(
                    input: budget.body.input,
                    maximumCount: budget.maximumElementCount,
                    actualCount: budget.maximumElementCount + 1
                )
            ) {
                try budget.validateElementCount(budget.maximumElementCount + 1)
            }
            #expect(
                throws: AppResourceBudgetViolation.xmlDepthExceeded(
                    input: budget.body.input,
                    maximumDepth: budget.maximumDepth,
                    actualDepth: budget.maximumDepth + 1
                )
            ) {
                try budget.validateDepth(budget.maximumDepth + 1)
            }
            #expect(
                throws: AppResourceBudgetViolation.xmlEntryCountExceeded(
                    input: budget.body.input,
                    maximumCount: budget.maximumEntryCount,
                    actualCount: budget.maximumEntryCount + 1
                )
            ) {
                try budget.validateEntryCount(budget.maximumEntryCount + 1)
            }
        }
    }

    @Test
    func imageBudgetsExposePixelLimitsAndExpectedViolations() throws {
        let budgets = [contract.feedIcon, contract.articleImage]

        for budget in budgets {
            try budget.validatePixelDimensions(
                width: budget.maximumPixelWidth,
                height: 1
            )

            #expect(
                throws: AppResourceBudgetViolation.imagePixelDimensionsExceeded(
                    input: budget.body.input,
                    maximumWidth: budget.maximumPixelWidth,
                    maximumHeight: budget.maximumPixelHeight,
                    maximumPixelCount: budget.maximumPixelCount,
                    actualWidth: budget.maximumPixelWidth + 1,
                    actualHeight: 1
                )
            ) {
                try budget.validatePixelDimensions(
                    width: budget.maximumPixelWidth + 1,
                    height: 1
                )
            }

            let overPixelCountHeight = (budget.maximumPixelCount / budget.maximumPixelWidth) + 1
            #expect(throws: AppResourceBudgetViolation.self) {
                try budget.validatePixelDimensions(
                    width: budget.maximumPixelWidth,
                    height: overPixelCountHeight
                )
            }
        }
    }
}
