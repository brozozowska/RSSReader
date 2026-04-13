import Foundation

struct ArticlesDaySection: Identifiable, Equatable {
    let date: Date
    let title: String
    var articles: [ArticleListItemDTO]

    var id: Date { date }
}

enum ArticlesDaySectionsBuilder {
    static func build(
        from articles: [ArticleListItemDTO],
        calendar: Calendar = .current
    ) -> [ArticlesDaySection] {
        var sections: [ArticlesDaySection] = []

        for article in articles {
            let referenceDate = article.publishedAt ?? article.fetchedAt
            let day = calendar.startOfDay(for: referenceDate)

            if sections.last?.date == day {
                sections[sections.count - 1].articles.append(article)
                continue
            }

            sections.append(
                ArticlesDaySection(
                    date: day,
                    title: title(for: day, calendar: calendar),
                    articles: [article]
                )
            )
        }

        return sections
    }

    static func title(
        for day: Date,
        calendar: Calendar = .current
    ) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }

        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        return day.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }
}
