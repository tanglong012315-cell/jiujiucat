import Foundation
import XCTest
@testable import Nvwa

final class NvwaCalendarTests: XCTestCase {
    private let enUSPOSIX = Locale(identifier: "en_US_POSIX")
    private let spanish = Locale(identifier: "es_ES")

    func testFebruary2024MonthCellsRespectMondayFirstAndWeekendDates() {
        let calendar = makeCalendar()
        let model = NvwaCalendarModel(calendar: calendar, locale: enUSPOSIX)
        let february = makeDate(year: 2024, month: 2, day: 15, calendar: calendar)

        let cells = model.monthCells(containing: february)

        XCTAssertEqual(cells.count, 35)
        XCTAssertTrue(cells.prefix(3).allSatisfy { $0.date == nil })
        XCTAssertTrue(cells.suffix(3).allSatisfy { $0.date == nil })

        let datedCells = cells.compactMap { cell -> (day: Int, isWeekend: Bool)? in
            guard let date = cell.date else { return nil }
            return (model.calendar.component(.day, from: date), cell.isWeekend)
        }
        XCTAssertEqual(datedCells.map(\.day), Array(1...29))

        let weekendByDay = Dictionary(
            uniqueKeysWithValues: datedCells.map { ($0.day, $0.isWeekend) }
        )
        XCTAssertEqual(weekendByDay[3], true)
        XCTAssertEqual(weekendByDay[4], true)
        XCTAssertEqual(weekendByDay[5], false)
        XCTAssertEqual(weekendByDay[24], true)
        XCTAssertEqual(weekendByDay[25], true)
        XCTAssertEqual(weekendByDay[26], false)
    }

    func testSpanishWeekdayHeadersMarkSaturdayAndSundayAsWeekend() {
        let calendar = makeCalendar(locale: spanish)
        let model = NvwaCalendarModel(calendar: calendar, locale: spanish)

        let headers = model.weekdayHeaders

        XCTAssertEqual(headers.count, 7)
        XCTAssertEqual(headers.map(\.weekday), [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(headers.filter(\.isWeekend).map(\.weekday), [7, 1])
        XCTAssertEqual(headers.map(\.symbol), expectedWeekdaySymbols(calendar: calendar, locale: spanish))
    }

    func testMonthTitleAndShortMonthNameFollowInjectedLocale() {
        let calendar = makeCalendar()
        let date = makeDate(year: 2024, month: 2, day: 15, calendar: calendar)
        let englishModel = NvwaCalendarModel(calendar: calendar, locale: enUSPOSIX)

        let spanishCalendar = makeCalendar(locale: spanish)
        let spanishModel = NvwaCalendarModel(calendar: spanishCalendar, locale: spanish)

        XCTAssertEqual(
            englishModel.headerTitle(for: date, mode: .month),
            expectedMonthTitle(for: date, calendar: calendar, locale: enUSPOSIX)
        )
        XCTAssertEqual(
            spanishModel.headerTitle(for: date, mode: .month),
            expectedMonthTitle(for: date, calendar: spanishCalendar, locale: spanish)
        )
        XCTAssertNotEqual(
            englishModel.headerTitle(for: date, mode: .month),
            spanishModel.headerTitle(for: date, mode: .month)
        )

        XCTAssertEqual(
            englishModel.shortMonthName(2),
            expectedShortMonthName(2, calendar: calendar, locale: enUSPOSIX)
        )
        XCTAssertEqual(
            spanishModel.shortMonthName(2),
            expectedShortMonthName(2, calendar: spanishCalendar, locale: spanish)
        )
    }

    func testStateNavigationUsesMonthYearAndTwentyYearStepsAcrossBoundaries() {
        let calendar = makeCalendar()
        let model = NvwaCalendarModel(calendar: calendar, locale: enUSPOSIX)

        var monthState = NvwaCalendarState(
            displayedDate: makeDate(year: 2024, month: 12, day: 15, calendar: calendar),
            mode: .month
        )
        monthState.move(by: 1, using: model)
        assertDate(monthState.displayedDate, year: 2025, month: 1, day: 15, calendar: calendar)
        monthState.move(by: -1, using: model)
        assertDate(monthState.displayedDate, year: 2024, month: 12, day: 15, calendar: calendar)

        var yearState = NvwaCalendarState(
            displayedDate: makeDate(year: 2024, month: 6, day: 15, calendar: calendar),
            mode: .year
        )
        yearState.move(by: -1, using: model)
        assertDate(yearState.displayedDate, year: 2023, month: 6, day: 15, calendar: calendar)
        yearState.move(by: 2, using: model)
        assertDate(yearState.displayedDate, year: 2025, month: 6, day: 15, calendar: calendar)

        var decadeState = NvwaCalendarState(
            displayedDate: makeDate(year: 2039, month: 6, day: 15, calendar: calendar),
            mode: .decades
        )
        XCTAssertEqual(model.decadeYears(containing: decadeState.displayedDate), Array(2020..<2040))
        decadeState.move(by: 1, using: model)
        assertDate(decadeState.displayedDate, year: 2059, month: 6, day: 15, calendar: calendar)
        XCTAssertEqual(model.decadeYears(containing: decadeState.displayedDate), Array(2040..<2060))
        decadeState.move(by: -1, using: model)
        assertDate(decadeState.displayedDate, year: 2039, month: 6, day: 15, calendar: calendar)
    }

    func testStateSynchronizesAnExternalSelectionWithoutChangingMode() {
        let calendar = makeCalendar()
        let initialDate = makeDate(year: 2024, month: 1, day: 31, calendar: calendar)
        let externalSelection = makeDate(year: 2026, month: 9, day: 12, calendar: calendar)
        var state = NvwaCalendarState(displayedDate: initialDate, mode: .decades)

        state.synchronizeSelection(externalSelection)

        XCTAssertEqual(state.displayedDate, externalSelection)
        XCTAssertEqual(state.mode, .decades)
    }

    private func makeCalendar(locale: Locale? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale ?? enUSPOSIX
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> Date {
        guard let date = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        ) else {
            XCTFail("Unable to construct deterministic calendar fixture")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func expectedMonthTitle(
        for date: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = makeFormatter(calendar: calendar, locale: locale)
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter.string(from: date)
    }

    private func expectedShortMonthName(
        _ month: Int,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = makeFormatter(calendar: calendar, locale: locale)
        let symbols = formatter.shortStandaloneMonthSymbols
            ?? formatter.shortMonthSymbols
            ?? []
        return symbols[month - 1]
    }

    private func expectedWeekdaySymbols(calendar: Calendar, locale: Locale) -> [String] {
        let formatter = makeFormatter(calendar: calendar, locale: locale)
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.veryShortWeekdaySymbols
            ?? []
        let firstIndex = calendar.firstWeekday - 1
        return (0..<symbols.count).map { symbols[(firstIndex + $0) % symbols.count] }
    }

    private func makeFormatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        return formatter
    }

    private func assertDate(
        _ date: Date,
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calendar.component(.year, from: date), year, file: file, line: line)
        XCTAssertEqual(calendar.component(.month, from: date), month, file: file, line: line)
        XCTAssertEqual(calendar.component(.day, from: date), day, file: file, line: line)
    }
}
