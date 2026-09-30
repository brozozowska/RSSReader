import CoreGraphics

enum ReaderArticleTablePresentation: Equatable {
    case cards
    case grid(columnWidth: CGFloat)
}

enum ReaderArticleTableTextSize: Equatable {
    case standard
    case large
    case extraLarge
    case accessibility
}

struct ReaderArticleTableLayoutPolicy {
    static let maximumGridColumnCount = 5
    static let minimumGridWidth = CGFloat(600)

    func presentation(
        availableWidth: CGFloat,
        columnCount: Int,
        textSize: ReaderArticleTableTextSize
    ) -> ReaderArticleTablePresentation {
        guard let minimumGridWidth = minimumGridWidth(
            columnCount: columnCount,
            textSize: textSize
        ),
              availableWidth.isFinite,
              availableWidth >= minimumGridWidth else {
            return .cards
        }

        return .grid(columnWidth: availableWidth / CGFloat(columnCount))
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

        return max(contentMinimum, Self.minimumGridWidth / CGFloat(columnCount))
    }

    private func minimumGridWidth(
        columnCount: Int,
        textSize: ReaderArticleTableTextSize
    ) -> CGFloat? {
        minimumGridColumnWidth(columnCount: columnCount, textSize: textSize)
            .map { $0 * CGFloat(columnCount) }
    }
}
