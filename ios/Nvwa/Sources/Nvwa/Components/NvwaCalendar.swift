import Foundation
import SwiftUI

public enum NvwaCalendarMode: Sendable, Equatable {
    case month
    case year
    case decades
}

struct NvwaCalendarWeekdayHeader: Equatable {
    let symbol: String
    let weekday: Int
    let isWeekend: Bool
}

struct NvwaCalendarDayCell: Equatable {
    let date: Date?
    let isWeekend: Bool
}

struct NvwaCalendarModel {
    let calendar: Calendar
    let locale: Locale

    init(calendar: Calendar, locale: Locale) {
        var configuredCalendar = calendar
        let firstWeekday = calendar.firstWeekday
        let minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        let timeZone = calendar.timeZone

        configuredCalendar.locale = locale
        configuredCalendar.timeZone = timeZone
        configuredCalendar.firstWeekday = firstWeekday
        configuredCalendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek

        self.calendar = configuredCalendar
        self.locale = locale
    }

    func headerTitle(for date: Date, mode: NvwaCalendarMode) -> String {
        switch mode {
        case .month:
            let formatter = dateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMM y")
            return formatter.string(from: date)
        case .year:
            return String(calendar.component(.year, from: date))
        case .decades:
            let years = decadeYears(containing: date)
            return "\(years.first ?? 0)–\(years.last ?? 0)"
        }
    }

    var weekdayHeaders: [NvwaCalendarWeekdayHeader] {
        let formatter = dateFormatter()
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.veryShortWeekdaySymbols
            ?? []
        guard !symbols.isEmpty else { return [] }

        let firstIndex = (calendar.firstWeekday - 1).positiveModulo(symbols.count)
        return (0..<symbols.count).map { offset in
            let symbolIndex = (firstIndex + offset) % symbols.count
            let weekday = symbolIndex + 1
            return NvwaCalendarWeekdayHeader(
                symbol: symbols[symbolIndex],
                weekday: weekday,
                isWeekend: isWeekend(weekday: weekday)
            )
        }
    }

    func monthCells(containing date: Date) -> [NvwaCalendarDayCell] {
        guard
            let interval = calendar.dateInterval(of: .month, for: date),
            let days = calendar.range(of: .day, in: .month, for: date)
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday).positiveModulo(7)
        var cells = Array(
            repeating: NvwaCalendarDayCell(date: nil, isWeekend: false),
            count: leading
        )

        for day in days {
            guard let dayDate = calendar.date(
                byAdding: .day,
                value: day - days.lowerBound,
                to: interval.start
            ) else {
                continue
            }
            cells.append(
                NvwaCalendarDayCell(
                    date: dayDate,
                    isWeekend: calendar.isDateInWeekend(dayDate)
                )
            )
        }

        let trailing = (7 - cells.count % 7) % 7
        cells.append(
            contentsOf: Array(
                repeating: NvwaCalendarDayCell(date: nil, isWeekend: false),
                count: trailing
            )
        )
        return cells
    }

    func shortMonthName(_ month: Int) -> String {
        let formatter = dateFormatter()
        let symbols = formatter.shortStandaloneMonthSymbols
            ?? formatter.shortMonthSymbols
            ?? []
        guard symbols.indices.contains(month - 1) else { return String(month) }
        return symbols[month - 1]
    }

    func decadeYears(containing date: Date) -> [Int] {
        let year = calendar.component(.year, from: date)
        let start = (year / 20) * 20
        return Array(start..<(start + 20))
    }

    func moving(_ date: Date, mode: NvwaCalendarMode, by direction: Int) -> Date {
        let component: Calendar.Component = mode == .month ? .month : .year
        let amount = mode == .decades ? direction * 20 : direction
        return calendar.date(byAdding: component, value: amount, to: date) ?? date
    }

    private func isWeekend(weekday: Int) -> Bool {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        let referenceWeekday = calendar.component(.weekday, from: referenceDate)
        let dayOffset = (weekday - referenceWeekday).positiveModulo(7)
        guard let matchingDate = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: referenceDate
        ) else {
            return false
        }
        return calendar.isDateInWeekend(matchingDate)
    }

    private func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}

struct NvwaCalendarState: Equatable {
    var displayedDate: Date
    var mode: NvwaCalendarMode

    mutating func synchronizeSelection(_ selection: Date) {
        displayedDate = selection
    }

    mutating func move(by direction: Int, using model: NvwaCalendarModel) {
        displayedDate = model.moving(displayedDate, mode: mode, by: direction)
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

public struct NvwaCalendar: View {
    @Binding private var selection: Date
    private let minimumDate: Date?
    private let previousIcon: Image
    private let nextIcon: Image
    private let model: NvwaCalendarModel

    @State private var state: NvwaCalendarState

    public init(
        selection: Binding<Date>,
        mode: NvwaCalendarMode = .month,
        /// 早于这一天的日子按 `State=Past`（`2014:7553`）画成 45% 透明并且点不动。
        /// 年/十年那两屏只负责翻页、不落选中，所以只在日格上拦就够了。
        minimumDate: Date? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current,
        previousIcon: Image,
        nextIcon: Image
    ) {
        _selection = selection
        self.minimumDate = minimumDate
        let model = NvwaCalendarModel(calendar: calendar, locale: locale)
        self.model = model
        _state = State(
            initialValue: NvwaCalendarState(
                displayedDate: selection.wrappedValue,
                mode: mode
            )
        )
        self.previousIcon = previousIcon
        self.nextIcon = nextIcon
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            switch state.mode {
            case .month:
                monthGrid
            case .year:
                yearGrid
            case .decades:
                decadeGrid
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 400)
        .background(
            Nvwa.backgroundMain,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(
            color: Color(.sRGB, red: 69 / 255, green: 71 / 255, blue: 69 / 255, opacity: 0.2),
            radius: 20
        )
        .onChange(of: selection) { newSelection in
            state.synchronizeSelection(newSelection)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            calendarButton(icon: previousIcon, label: "Previous") {
                moveBackward()
            }

            Spacer(minLength: 0)

            if state.mode != .decades {
                Button {
                    switch state.mode {
                    case .month: state.mode = .year
                    case .year: state.mode = .decades
                    case .decades: break
                    }
                } label: {
                    Text(headerTitle)
                        .font(Nvwa.bodyMediumSemibold)
                        .tracking(0.175)
                        .foregroundStyle(Nvwa.grayPrimary)
                        .padding(2)
                        .frame(minWidth: 88, minHeight: 26)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            calendarButton(icon: nextIcon, label: "Next") {
                moveForward()
            }
        }
        .frame(height: 52)
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(model.weekdayHeaders.enumerated()), id: \.offset) { _, header in
                    Text(header.symbol)
                        .font(header.isWeekend ? Nvwa.bodyMedium : Nvwa.bodyMediumSemibold)
                        .tracking(header.isWeekend ? 0.14 : 0.175)
                        .foregroundStyle(header.isWeekend ? Nvwa.graySecondary : Nvwa.grayPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 0
            ) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                    dayCell(cell)
                        .frame(height: 40)
                }
            }
        }
    }

    private var yearGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 4),
            spacing: 0
        ) {
            ForEach(1...12, id: \.self) { month in
                let isSelected = month == model.calendar.component(.month, from: selection)
                    && model.calendar.component(.year, from: state.displayedDate)
                    == model.calendar.component(.year, from: selection)

                Button {
                    state.displayedDate = model.calendar.date(
                        bySetting: .month,
                        value: month,
                        of: state.displayedDate
                    ) ?? state.displayedDate
                    state.mode = .month
                } label: {
                    Text(shortMonthName(month))
                        .font(Nvwa.bodyMediumSemibold)
                        .tracking(0.175)
                        .foregroundStyle(isSelected ? Nvwa.colorOnBlue : Nvwa.grayPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            isSelected ? Nvwa.primaryGreen : Color.clear,
                            in: Capsule()
                        )
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var decadeGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 4),
            spacing: 0
        ) {
            ForEach(decadeYears, id: \.self) { year in
                let isSelected = year == model.calendar.component(.year, from: selection)

                Button {
                    state.displayedDate = model.calendar.date(
                        bySetting: .year,
                        value: year,
                        of: state.displayedDate
                    ) ?? state.displayedDate
                    state.mode = .year
                } label: {
                    Text(String(year))
                        .font(Nvwa.bodyMediumSemibold)
                        .tracking(0.175)
                        .foregroundStyle(isSelected ? Nvwa.colorOnBlue : Nvwa.grayPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            isSelected ? Nvwa.primaryGreen : Color.clear,
                            in: Capsule()
                        )
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayCell(_ cell: NvwaCalendarDayCell) -> some View {
        Group {
            if let date = cell.date {
                let isSelected = model.calendar.isDate(date, inSameDayAs: selection)
                let isPast = isBeforeMinimum(date)

                Button {
                    selection = date
                    state.synchronizeSelection(date)
                } label: {
                    Text(String(model.calendar.component(.day, from: date)))
                        .font(cell.isWeekend ? Nvwa.bodyMedium : Nvwa.bodyMediumSemibold)
                        .tracking(cell.isWeekend ? 0.14 : 0.175)
                        .foregroundStyle(
                            isSelected
                                ? Nvwa.colorOnBlue
                                : (cell.isWeekend ? Nvwa.graySecondary : Nvwa.grayPrimary)
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            isSelected ? Nvwa.primaryGreen : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .opacity(isPast ? Self.pastDayOpacity : 1)
                .disabled(isPast)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }

    /// `2014:7553`：过去的日子只是整格压到 45%，字号配色都不变。
    private static let pastDayOpacity = 0.45

    private func isBeforeMinimum(_ date: Date) -> Bool {
        guard let minimumDate else { return false }
        return model.calendar.startOfDay(for: date)
            < model.calendar.startOfDay(for: minimumDate)
    }

    private func calendarButton(
        icon: Image,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Nvwa.grayPrimary)
        .accessibilityLabel(label)
    }

    private var headerTitle: String {
        model.headerTitle(for: state.displayedDate, mode: state.mode)
    }

    private var monthCells: [NvwaCalendarDayCell] {
        model.monthCells(containing: state.displayedDate)
    }

    private var decadeYears: [Int] {
        model.decadeYears(containing: state.displayedDate)
    }

    private func shortMonthName(_ month: Int) -> String {
        model.shortMonthName(month)
    }

    private func moveBackward() {
        state.move(by: -1, using: model)
    }

    private func moveForward() {
        state.move(by: 1, using: model)
    }
}
