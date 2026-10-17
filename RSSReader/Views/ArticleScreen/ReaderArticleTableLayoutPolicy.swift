import SwiftUI

nonisolated enum ReaderArticleTablePresentation: Equatable {
    case cards
    case grid(columnWidths: [CGFloat])
}

nonisolated enum ReaderArticleTableTextSize: Equatable {
    case standard
    case large
    case extraLarge
    case accessibility
}

nonisolated struct ReaderArticleTableLayoutPolicy {
    static let maximumGridColumnCount = 5
    static let minimumGridWidth = CGFloat(600)

    func presentation(
        availableWidth: CGFloat,
        preferredColumnWidths: [CGFloat],
        textSize: ReaderArticleTableTextSize
    ) -> ReaderArticleTablePresentation {
        guard let minimum = minimumGridWidth(preferredColumnWidths: preferredColumnWidths, textSize: textSize),
              availableWidth.isFinite, availableWidth >= minimum,
              let contentMinimum = minimumGridColumnWidth(columnCount: preferredColumnWidths.count, textSize: textSize)
        else { return .cards }

        let preferred = preferredColumnWidths.map { max(20, $0) }
        let minimums = preferred.map { min($0, contentMinimum) }
        let preferredTotal = preferred.reduce(0, +)
        let widths: [CGFloat]
        if preferredTotal <= availableWidth {
            // Preserve the content proportions when there is room to spare.
            widths = preferred.map { $0 * (availableWidth / preferredTotal) }
        } else {
            // Compress long columns while keeping short values at their natural
            // width and providing a readable floor for wrapping text.
            let remaining = availableWidth - minimums.reduce(0, +)
            let demand = zip(preferred, minimums).map { $0 - $1 }
            let totalDemand = demand.reduce(0, +)
            widths = zip(minimums, demand).map { $0 + remaining * ($1 / totalDemand) }
        }
        return .grid(columnWidths: widths)
    }

    func minimumGridColumnWidth(
        columnCount: Int,
        textSize: ReaderArticleTableTextSize
    ) -> CGFloat? {
        guard columnCount >= 2,
              columnCount <= Self.maximumGridColumnCount,
              textSize != .accessibility else {
            return nil
        }

        let contentMinimum = switch textSize {
        case .standard:
            CGFloat(132)
        case .large:
            CGFloat(144)
        case .extraLarge:
            CGFloat(156)
        case .accessibility:
            CGFloat.infinity
        }

        return contentMinimum
    }

    func minimumGridWidth(
        preferredColumnWidths: [CGFloat],
        textSize: ReaderArticleTableTextSize
    ) -> CGFloat? {
        guard let contentMinimum = minimumGridColumnWidth(columnCount: preferredColumnWidths.count, textSize: textSize),
              preferredColumnWidths.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let columnMinimums = preferredColumnWidths.map { min(max(20, $0), contentMinimum) }
        return max(Self.minimumGridWidth, columnMinimums.reduce(0, +))
    }

}

/// Reports the minimum grid width during ViewThatFits' ideal-size probe,
/// then distributes the proposed width by measured content without writing geometry to state.
struct ReaderArticleTableGridLayout: Layout {
    let columnCount: Int
    let textSize: ReaderArticleTableTextSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let preferred = preferredColumnWidths(subviews: subviews)
        let width = gridWidth(for: proposal.width, preferred: preferred)
        let widths = columnWidths(for: width, preferred: preferred)
        let heights = rowHeights(subviews: subviews, widths: widths)
        return CGSize(width: width, height: heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(for: bounds.width, preferred: preferredColumnWidths(subviews: subviews))
        guard widths.count == columnCount else { return }
        let heights = rowHeights(subviews: subviews, widths: widths)
        var y = bounds.minY
        for (rowIndex, height) in heights.enumerated() {
            var x = bounds.minX
            for columnIndex in 0..<columnCount {
                let index = rowIndex * columnCount + columnIndex
                guard index < subviews.count else { break }
                subviews[index].place(
                    // SwiftUI mirrors Layout placement in an RTL environment.
                    at: CGPoint(x: x, y: y),
                    anchor: UnitPoint(x: 0, y: 0),
                    proposal: ProposedViewSize(width: widths[columnIndex], height: height)
                )
                x += widths[columnIndex]
            }
            y += height
        }
    }

    private func gridWidth(for proposedWidth: CGFloat?, preferred: [CGFloat]) -> CGFloat {
        let policy = ReaderArticleTableLayoutPolicy()
        guard let minimum = policy.minimumGridWidth(preferredColumnWidths: preferred, textSize: textSize) else {
            return 0
        }
        guard let proposedWidth, proposedWidth.isFinite else { return minimum }
        return max(minimum, proposedWidth)
    }

    private func preferredColumnWidths(subviews: Subviews) -> [CGFloat] {
        guard columnCount > 0 else { return [] }
        var widths = [CGFloat](repeating: 20, count: columnCount)
        for index in subviews.indices {
            let column = index % columnCount
            widths[column] = max(widths[column], subviews[index].sizeThatFits(.unspecified).width)
        }
        return widths
    }

    private func columnWidths(for width: CGFloat, preferred: [CGFloat]) -> [CGFloat] {
        guard case .grid(let widths) = ReaderArticleTableLayoutPolicy().presentation(
            availableWidth: width, preferredColumnWidths: preferred, textSize: textSize
        ) else { return [] }
        return widths
    }

    private func rowHeights(subviews: Subviews, widths: [CGFloat]) -> [CGFloat] {
        guard widths.count == columnCount, columnCount > 0 else { return [] }
        return stride(from: 0, to: subviews.count, by: columnCount).map { start in
            (start..<min(start + columnCount, subviews.count)).map {
                subviews[$0].sizeThatFits(ProposedViewSize(width: widths[$0 % columnCount], height: nil)).height
            }.max() ?? 0
        }
    }
}
