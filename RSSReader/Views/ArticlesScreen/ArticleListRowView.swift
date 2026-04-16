import SwiftUI

struct ArticleListRowView: View {
    let article: ArticleListItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(article.feedTitle)
                    .font(.caption)
                    .foregroundStyle(metadataForegroundStyle)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if article.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(metadataForegroundStyle)
                    }

                    Text(ArticleListRowTimeFormatter.string(for: article))
                        .font(.caption)
                        .foregroundStyle(metadataForegroundStyle)
                        .lineLimit(1)
                }
            }

            Text(ArticleListRowContent.primaryText(for: article))
                .font(.body)
                .foregroundStyle(titleForegroundStyle)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var titleForegroundStyle: AnyShapeStyle {
        article.isRead
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.primary)
    }

    private var metadataForegroundStyle: AnyShapeStyle {
        article.isRead
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.secondary)
    }
}

private enum ArticleListRowContent {
    static func primaryText(for article: ArticleListItemDTO) -> String {
        guard let summary = article.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            summary.isEmpty == false,
            summary != article.title
        else {
            return article.title
        }

        return summary
    }
}

private enum ArticleListRowTimeFormatter {
    static func string(for article: ArticleListItemDTO) -> String {
        let referenceDate = article.publishedAt ?? article.fetchedAt
        return referenceDate.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}
