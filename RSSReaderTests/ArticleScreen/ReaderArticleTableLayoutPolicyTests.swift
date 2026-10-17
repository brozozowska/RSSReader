import SwiftUI
import Testing
@testable import RSSReader

@Suite("Reader article table layout policy")
@MainActor
struct ReaderArticleTableLayoutPolicyTests {
    private let policy = ReaderArticleTableLayoutPolicy()

    @Test("Compact widths use cards for two through five columns", arguments: 2...5)
    func compactWidthsUseCards(columnCount: Int) {
        #expect(
            policy.presentation(
                availableWidth: 390,
                preferredColumnWidths: Array(repeating: 300, count: columnCount),
                textSize: .standard
            ) == .cards
        )
    }

    @Test("Regular width uses a grid when every column has enough room")
    func regularWidthUsesGrid() {
        #expect(
            policy.presentation(
                availableWidth: 900,
                preferredColumnWidths: Array(repeating: 300, count: 5),
                textSize: .standard
            ) == .grid(columnWidths: Array(repeating: 180, count: 5))
        )
    }

    @Test("Split View width returns a grid to cards")
    func splitViewWidthUsesCards() {
        #expect(
            policy.presentation(
                availableWidth: 600,
                preferredColumnWidths: Array(repeating: 300, count: 5),
                textSize: .standard
            ) == .cards
        )
    }

    @Test("Larger text raises the minimum grid width")
    func largerTextRaisesMinimumWidth() {
        #expect(policy.presentation(availableWidth: 600, preferredColumnWidths: Array(repeating: 300, count: 4), textSize: .standard) != .cards)
        #expect(policy.presentation(availableWidth: 600, preferredColumnWidths: Array(repeating: 300, count: 4), textSize: .extraLarge) == .cards)
    }

    @Test("Accessibility text sizes always use cards")
    func accessibilityTextUsesCards() {
        #expect(
            policy.presentation(
                availableWidth: 1_400,
                preferredColumnWidths: Array(repeating: 300, count: 3),
                textSize: .accessibility
            ) == .cards
        )
    }

    @Test("Very wide semantic tables use the bounded cards fallback")
    func manyColumnsUseCards() {
        #expect(
            policy.presentation(
                availableWidth: 1_400,
                preferredColumnWidths: Array(repeating: 300, count: 6),
                textSize: .standard
            ) == .cards
        )
    }

    @Test("ViewThatFits changes presentation as the same layout width changes")
    func renderedLayoutChangesWithWidth() throws {
        for width in [900.0, 390.0, 900.0, 600.0] {
            let image = try renderGrid(width: width, textSize: .standard)
            #expect(image.width == Int(width))
            if width < 600 {
                #expect(try pixel(image, x: 10) == [255, 0, 255])
            } else {
                #expect(try pixel(image, x: Int(width / 3) - 2) == [255, 0, 0])
                #expect(try pixel(image, x: Int(width / 3) + 2) == [0, 255, 0])
                #expect(try pixel(image, x: Int(width) - 2) == [0, 0, 255])
            }
        }
    }

    @Test("Short columns keep less space than long descriptions")
    func contentDeterminesColumnWidths() {
        #expect(policy.presentation(availableWidth: 900, preferredColumnWidths: [100, 400, 100], textSize: .standard)
                == .grid(columnWidths: [150, 600, 150]))
        #expect(policy.presentation(availableWidth: 600, preferredColumnWidths: [80, 1_000, 80], textSize: .standard)
                == .grid(columnWidths: [80, 440, 80]))
    }

    @Test("Content width is measured across all rows, including later descriptions")
    func renderedWidthsIncludeLaterRows() throws {
        let red = Color(red: 1, green: 0, blue: 0)
        let green = Color(red: 0, green: 1, blue: 0)
        let renderer = ImageRenderer(content: ReaderArticleTableGridLayout(columnCount: 2, textSize: .standard) {
            Text("ID").padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(red)
            Text("Name").padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(green)
            Text("1").padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(red)
            Text("A long description from a later row needs more space than a short identifier")
                .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity).background(green)
        })
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 900, height: nil)
        let image = try #require(renderer.cgImage)
        #expect(image.width == 900)
        #expect(try pixel(image, x: 1) == [255, 0, 0])
        #expect(try pixel(image, x: 200) == [0, 255, 0])
    }

    @Test("Accessibility uses cards even when the rendered container is wide")
    func renderedAccessibilityUsesCards() throws {
        let image = try renderGrid(width: 900, textSize: .accessibility)
        #expect(try pixel(image, x: 10) == [255, 0, 255])
    }

    @Test("Columns with identical content still share the available width equally")
    func renderedFiveColumnsUseAvailableWidth() throws {
        let image = try renderGrid(width: 900, textSize: .standard, columnCount: 5)
        #expect(try pixel(image, x: 178) == [255, 0, 0])
        #expect(try pixel(image, x: 182) == [0, 255, 0])
        #expect(try pixel(image, x: 358) == [0, 255, 0])
        #expect(try pixel(image, x: 362) == [0, 0, 255])
        #expect(try pixel(image, x: 898) == [0, 255, 0])
    }

    @Test("Each row reserves the height of its tallest cell")
    func renderedRowsUseTallestCellHeight() throws {
        let renderer = ImageRenderer(content: ReaderArticleTableGridLayout(columnCount: 2, textSize: .standard) {
            Color.red.frame(height: 20)
            Color.green.frame(height: 40)
            Color.blue.frame(height: 10)
            Color.yellow.frame(height: 30)
        })
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 900, height: nil)
        let image = try #require(renderer.cgImage)
        #expect(image.height == 70)
    }

    @Test("RTL mirrors visual columns without changing source order")
    func renderedRTLReversesVisualColumns() throws {
        let image = try renderGrid(width: 900, textSize: .standard, direction: .rightToLeft)
        #expect(try pixel(image, x: 10) == [0, 0, 255])
        #expect(try pixel(image, x: 890) == [255, 0, 0])
    }

    private func renderGrid(
        width: CGFloat,
        textSize: ReaderArticleTableTextSize,
        columnCount: Int = 3,
        direction: LayoutDirection = .leftToRight
    ) throws -> CGImage {
        let colors = [Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0), Color(red: 0, green: 0, blue: 1)]
        let renderer = ImageRenderer(content: ViewThatFits(in: .horizontal) {
            if policy.minimumGridColumnWidth(columnCount: columnCount, textSize: textSize) != nil {
                ReaderArticleTableGridLayout(columnCount: columnCount, textSize: textSize) {
                    ForEach(0..<columnCount, id: \.self) { index in
                        colors[index % colors.count].frame(height: 20)
                    }
                }
            }
            Color(red: 1, green: 0, blue: 1).frame(height: 20)
        }.environment(\.layoutDirection, direction))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return try #require(renderer.cgImage)
    }

    private func pixel(_ image: CGImage, x: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: -x, y: -image.height / 2, width: image.width, height: image.height))
        }
        return Array(bytes.prefix(3))
    }
}
