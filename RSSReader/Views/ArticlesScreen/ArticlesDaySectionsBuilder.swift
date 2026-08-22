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
        var sectionIndexByDay: [Date: Int] = [:]

        for article in articles {
            let referenceDate = article.publishedAt ?? article.fetchedAt
            let day = calendar.startOfDay(for: referenceDate)

            if let sectionIndex = sectionIndexByDay[day] {
                sections[sectionIndex].articles.append(article)
                continue
            }

            sectionIndexByDay[day] = sections.count
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
            return ReadingLocalization.todaySectionTitle
        }

        if calendar.isDateInYesterday(day) {
            return ReadingLocalization.yesterdaySectionTitle
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
