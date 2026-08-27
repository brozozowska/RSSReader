import SwiftUI

struct ArticleListRowView: View {
    let article: ArticleListItemDTO

    var body: some View {
        let content = ArticleListRowContent(article: article)

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

            VStack(alignment: .leading, spacing: 4) {
                Text(content.titleText)
                    .font(.body)
                    .foregroundStyle(titleForegroundStyle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let previewText = content.previewText {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(metadataForegroundStyle)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

enum ArticleListRowTimeFormatter {
    static func string(for article: ArticleListItemDTO) -> String {
        article.effectiveDate.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}
