import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Date Parsing")
struct FeedDateParsingServiceTests {
    @Test
    func parsesISO8601DatesWithAndWithoutFractionalSeconds() {
        assertParsedDate(
            "2024-01-02T10:15:30.123Z",
            equals: makeUTCDate(
                year: 2024,
                month: 1,
                day: 2,
                hour: 10,
                minute: 15,
                second: 30,
                nanosecond: 123_000_000
            )
        )
        assertParsedDate(
            "2024-01-02T10:15:30Z",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
    }

    @Test
    func parsesRSSAndRFC822DatesWithOneAndTwoDigitDays() {
        assertParsedDate(
            "Tue, 2 Jan 2024 10:15:30 +0000",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "Tue, 02 Jan 2024 10:15:30 +0000",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "Tue, 2 Jan 2024 10:15 +0000",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15)
        )
        assertParsedDate(
            "Tue, 02 Jan 2024 10:15 +0000",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15)
        )
        assertParsedDate(
            "Tue, 02 Jan 24 10:15:30 GMT",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
    }

    @Test
    func appliesTimezoneOffsetsToParsedDates() {
        assertParsedDate(
            "Tue, 02 Jan 2024 13:15:30 +0300",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "Tue, 02 Jan 2024 05:45:30 -0430",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "2024-01-02T13:15:30+03:00",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
    }

    @Test
    func parsesFallbackFormatsWithoutWeekdayOrISOSeparators() {
        assertParsedDate(
            "2 Jan 2024 10:15:30 +0000",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "02 Jan 2024 10:15 +0000",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15)
        )
        assertParsedDate(
            "Tue Jan 2 10:15:30 2024",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "2024-01-02 13:15:30 +0300",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 10, minute: 15, second: 30)
        )
        assertParsedDate(
            "2024-01-02T13:15:30.123+0300",
            equals: makeUTCDate(
                year: 2024,
                month: 1,
                day: 2,
                hour: 10,
                minute: 15,
                second: 30,
                nanosecond: 123_000_000
            )
        )
        assertParsedDate(
            "2024-01-02",
            equals: makeUTCDate(year: 2024, month: 1, day: 2, hour: 0, minute: 0)
        )
    }

    @Test
    func trimsWhitespaceAroundSupportedDates() {
        assertParsedDate(
            "  \n2024-01-02T10:15:30.486Z\t ",
            equals: makeUTCDate(
                year: 2024,
                month: 1,
                day: 2,
                hour: 10,
                minute: 15,
                second: 30,
                nanosecond: 486_000_000
            )
        )
    }

    @Test
    func returnsNilForEmptyWhitespaceAndInvalidStrings() {
        #expect(FeedDateParsingService.parse(nil) == nil)
        #expect(FeedDateParsingService.parse("") == nil)
        #expect(FeedDateParsingService.parse("   \n\t  ") == nil)
        #expect(FeedDateParsingService.parse("not a date") == nil)
        #expect(FeedDateParsingService.parse("2024-13-99T99:99:99Z") == nil)
        #expect(FeedDateParsingService.parse("2024-02-30") == nil)
    }

    private func assertParsedDate(_ value: String, equals expectedDate: Date) {
        let parsedDate = FeedDateParsingService.parse(value)
        #expect(parsedDate != nil)
        #expect(abs((parsedDate ?? .distantPast).timeIntervalSince(expectedDate)) < 0.001)
    }

    private func makeUTCDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
        nanosecond: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond

        return components.date ?? Date(timeIntervalSince1970: -1)
    }
}
