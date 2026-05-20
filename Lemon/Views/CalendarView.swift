import SwiftUI
import SwiftData
import UIKit

/// The food calendar. A month grid where days with logged photos or Today
/// menu entries are circled. Tap a day to see what was eaten / cooked then.
///
/// Data flow: two `@Query`s fetch every `DishPhoto` and every
/// `TodayDishEntry`. We bucket them by
/// `Calendar.current.startOfDay(for: …)` so day granularity respects the
/// user's local timezone. A tap on a day cell navigates to `DayDetailView`
/// for that startOfDay.
struct CalendarView: View {
    @Query private var photos: [DishPhoto]
    @Query private var todayEntries: [TodayDishEntry]

    /// The first day of the month currently being viewed. Drives the grid.
    @State private var visibleMonth: Date = Calendar.current.startOfMonth(for: .now)

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }()

    /// All distinct day-buckets that have ≥1 photo or ≥1 Today menu entry.
    /// Used to mark grid cells and decide tappability.
    private var loggedDays: Set<Date> {
        var days = Set(photos.map { calendar.startOfDay(for: $0.effectiveDate) })
        for entry in todayEntries where entry.dish != nil {
            days.insert(calendar.startOfDay(for: entry.day))
        }
        return days
    }

    private var hasAnyLog: Bool {
        !photos.isEmpty || todayEntries.contains { $0.dish != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        CalendarMasthead()
                        MonthHeader(visibleMonth: $visibleMonth, calendar: calendar)
                        WeekdayLabels(calendar: calendar)
                        MonthGrid(
                            visibleMonth: visibleMonth,
                            loggedDays: loggedDays,
                            calendar: calendar
                        )
                        if hasAnyLog {
                            MonthLogPreview(
                                visibleMonth: visibleMonth,
                                todayEntries: todayEntries,
                                calendar: calendar
                            )
                        }
                        if !hasAnyLog {
                            EmptyCalendarHint()
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .paperBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
            }
            .navigationDestination(for: Dish.self) { dish in
                DishDetailView(dish: dish)
            }
        }
    }
}

// MARK: - Masthead + month header

private struct CalendarMasthead: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Food Calendar")
                .font(Theme.title(36))
                .foregroundStyle(Theme.ink)
            Text("a day-by-day record of what you ate")
                .font(Theme.serif(13).italic())
                .foregroundStyle(Theme.inkSoft)
            Rectangle()
                .fill(Theme.ink)
                .frame(width: 60, height: 1)
                .padding(.top, 4)
                .opacity(0.7)
        }
        .padding(.top, 16)
    }
}

private struct MonthHeader: View {
    @Binding var visibleMonth: Date
    let calendar: Calendar

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: visibleMonth)
    }

    var body: some View {
        HStack {
            Button { step(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
            Spacer()
            Text(monthLabel)
                .font(Theme.serif(20, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button { step(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 4)
    }

    private func step(by months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: visibleMonth) {
            withAnimation(.easeInOut(duration: 0.18)) {
                visibleMonth = calendar.startOfMonth(for: next)
            }
        }
    }
}

private struct WeekdayLabels: View {
    let calendar: Calendar

    /// E.g. ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"] reordered per locale.
    private var symbols: [String] {
        let raw = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1 // 1-based → 0-based
        return Array(raw[firstWeekdayIndex...] + raw[..<firstWeekdayIndex])
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { sym in
                Text(sym)
                    .font(Theme.hand(13))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Month text preview (below grid)

private struct MonthLogPreview: View {
    let visibleMonth: Date
    let todayEntries: [TodayDishEntry]
    let calendar: Calendar

    private var menuDaysInMonth: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        var result: [Date] = []
        var d = interval.start
        while d < interval.end {
            let start = calendar.startOfDay(for: d)
            if hasMenu(on: start) { result.append(start) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return result
    }

    private func hasMenu(on day: Date) -> Bool {
        todayEntries.contains { $0.dish != nil && calendar.isDate($0.day, inSameDayAs: day) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THIS MONTH")
                .font(Theme.serif(12, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Theme.inkFaded)

            if menuDaysInMonth.isEmpty {
                Text("No menu planned this month.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkFaded)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(menuDaysInMonth, id: \.self) { day in
                        NavigationLink(value: day) {
                            daySummaryBlock(day)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
    }

    @ViewBuilder
    private func daySummaryBlock(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(Theme.serif(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkFaded)
            }

            if let menu = menuLine(for: day) {
                Text(menu)
                    .font(Theme.serif(13).italic())
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.vertical, 6)
    }

    private func menuLine(for day: Date) -> String? {
        let entries = todayEntries.filter { $0.dish != nil && calendar.isDate($0.day, inSameDayAs: day) }
        guard !entries.isEmpty else { return nil }
        let grouped = Dictionary(grouping: entries, by: \.meal)
        let parts = grouped
            .map { meal, ents in
                let names = orderedUniqueNames(ents.compactMap(\.dish?.name))
                return "\(meal): \(names.joined(separator: ", "))"
            }
            .sorted()
        return parts.joined(separator: " · ")
    }

    private func orderedUniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for n in names {
            let key = n.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(n)
        }
        return out
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    let visibleMonth: Date
    let loggedDays: Set<Date>
    let calendar: Calendar

    /// 6-row × 7-column grid of optional dates. `nil` cells are leading
    /// or trailing padding for partial weeks.
    private var dayCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else {
            return Array(repeating: nil, count: 42)
        }
        let firstDay = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30

        // How many empty cells before day 1?
        let firstWeekday = calendar.component(.weekday, from: firstDay) // 1=Sun…7=Sat
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for i in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: i, to: firstDay))
        }
        // Pad to a full 6×7 = 42 grid so the month bottom doesn't jump
        // when scrolling between months of different lengths.
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<dayCells.count, id: \.self) { i in
                if let day = dayCells[i] {
                    let dayStart = calendar.startOfDay(for: day)
                    DayCell(
                        date: day,
                        isLogged: loggedDays.contains(dayStart),
                        isInVisibleMonth: calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month),
                        isToday: calendar.isDateInToday(day),
                        calendar: calendar
                    )
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }
}

/// A single day square in the month grid. Tappable when there's at least
/// one logged photo or Today menu entry on this day; otherwise it stays
/// inert (no point opening an empty detail view).
private struct DayCell: View {
    let date: Date
    let isLogged: Bool
    let isInVisibleMonth: Bool
    let isToday: Bool
    let calendar: Calendar

    private var dayNumber: String {
        String(calendar.component(.day, from: date))
    }

    var body: some View {
        Group {
            if isLogged {
                NavigationLink(value: calendar.startOfDay(for: date)) {
                    cellContent
                }
                .buttonStyle(.plain)
            } else {
                cellContent
            }
        }
    }

    private var cellContent: some View {
        ZStack {
            // Hand-drawn circle for days with any log (photo or menu entry).
            if isLogged {
                Circle()
                    .strokeBorder(Theme.ink, lineWidth: 1.6)
                    .background(Circle().fill(Color.white.opacity(0.55)))
                    .frame(width: 36, height: 36)
            }
            // Light circle for "today" so it's still findable.
            if isToday && !isLogged {
                Circle()
                    .strokeBorder(Theme.inkFaded, lineWidth: 1)
                    .frame(width: 32, height: 32)
            }
            Text(dayNumber)
                .font(Theme.serif(16, weight: isLogged ? .semibold : .regular))
                .foregroundStyle(textColor)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        if !isInVisibleMonth { return Theme.inkFaded.opacity(0.4) }
        if isLogged { return Theme.ink }
        return Theme.inkSoft
    }
}

private struct EmptyCalendarHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.inkFaded)
            Text("No meals logged yet.")
                .font(Theme.serif(14).italic())
                .foregroundStyle(Theme.inkFaded)
            Text("Add a dish to Today, or add a photo to any dish — both show up here.")
                .font(Theme.hand(13))
                .foregroundStyle(Theme.inkFaded)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Day detail

/// Drill-in view for a single day. Shows the day's Today menu (grouped by
/// meal) above any photo logs. Tap a thumbnail to open the photo viewer.
private struct DayDetailView: View {
    @Query private var photos: [DishPhoto]
    @Query private var todayEntries: [TodayDishEntry]
    @State private var viewingPhoto: DishPhoto?

    let day: Date

    private let calendar = Calendar.current

    /// Photos taken on `day`, grouped by their parent dish. We keep the
    /// dishes in alphabetical order so the day reads like a menu.
    private var dishGroups: [(dish: Dish, photos: [DishPhoto])] {
        let dayPhotos = photos.filter { calendar.isDate($0.effectiveDate, inSameDayAs: day) }
        let grouped = Dictionary(grouping: dayPhotos) { $0.dish?.id ?? UUID() }
        return grouped.compactMap { _, list -> (Dish, [DishPhoto])? in
            guard let dish = list.first?.dish else { return nil }
            return (dish, list.sorted { $0.effectiveDate < $1.effectiveDate })
        }
        .sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
    }

    /// Today menu entries logged on `day`, grouped by meal name. Meals
    /// fall back to canonical Breakfast / Lunch / Dinner / Other ordering;
    /// custom meals appear after, in the order they were first added.
    private var menuMeals: [(meal: String, entries: [TodayDishEntry])] {
        let dayEntries = todayEntries.filter {
            $0.dish != nil && calendar.isDate($0.day, inSameDayAs: day)
        }
        let grouped = Dictionary(grouping: dayEntries) { $0.meal }

        let canonical = TodayMeal.allCases.map(\.rawValue)

        return grouped
            .map { (meal: $0.key, entries: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { a, b in
                let ra = canonical.firstIndex(of: a.meal) ?? Int.max
                let rb = canonical.firstIndex(of: b.meal) ?? Int.max
                if ra != rb { return ra < rb }
                let ta = a.entries.first?.createdAt ?? .distantPast
                let tb = b.entries.first?.createdAt ?? .distantPast
                return ta < tb
            }
    }

    private var hasAnyContent: Bool {
        !menuMeals.isEmpty || !dishGroups.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DayHeader(day: day)

                if !hasAnyContent {
                    Text("Nothing logged on this day.")
                        .font(Theme.serif(14).italic())
                        .foregroundStyle(Theme.inkFaded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if !menuMeals.isEmpty {
                        DayMenuCard(meals: menuMeals)
                    }

                    if !dishGroups.isEmpty {
                        DaySectionLabel(title: "PHOTOS")

                        ForEach(dishGroups, id: \.dish.id) { entry in
                            DayDishCard(
                                dish: entry.dish,
                                photos: entry.photos,
                                onTapPhoto: { viewingPhoto = $0 }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewingPhoto) { photo in
            DishPhotoViewer(photo: photo)
        }
    }
}

/// Small section divider used inside `DayDetailView` to separate "Menu"
/// (Today entries) from "Photos" (DishPhoto logs).
private struct DaySectionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.serif(12, weight: .semibold))
                .tracking(6)
                .foregroundStyle(Theme.inkFaded)
            Rectangle()
                .fill(Theme.ink.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.top, 2)
    }
}

/// The Today menu card on a day-detail page. Each meal is its own block:
/// uppercase meal name, then a bulleted list of dishes. Course (if any)
/// shows as a faint italic suffix so the entry still reads at a glance.
private struct DayMenuCard: View {
    let meals: [(meal: String, entries: [TodayDishEntry])]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DaySectionLabel(title: "MENU")

            ForEach(meals, id: \.meal) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.meal.uppercased())
                        .font(Theme.serif(14, weight: .bold))
                        .tracking(5)
                        .foregroundStyle(Theme.ink)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(group.entries) { entry in
                            if let dish = entry.dish {
                                NavigationLink(value: dish) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("•")
                                            .font(Theme.serif(16))
                                            .foregroundStyle(Theme.inkSoft)
                                            .frame(width: 8, alignment: .leading)
                                        Text(dish.name)
                                            .font(.system(size: 16, weight: .light, design: .default))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        if !entry.course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(entry.course)
                                                .font(Theme.serif(12).italic())
                                                .foregroundStyle(Theme.inkFaded)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
    }
}

private struct DayHeader: View {
    let day: Date

    private var weekdayText: String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: day)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMM d, yyyy")
        return f.string(from: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekdayText)
                .font(Theme.hand(14))
                .foregroundStyle(Theme.inkSoft)
            Text(dateText)
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
            Rectangle()
                .fill(Theme.ink)
                .frame(height: 1)
                .opacity(0.6)
                .padding(.top, 4)
        }
    }
}

private struct DayDishCard: View {
    let dish: Dish
    let photos: [DishPhoto]
    let onTapPhoto: (DishPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: dish) {
                HStack(spacing: 12) {
                    illustration
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dish.name)
                            .font(Theme.dishName(14))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !dish.dishDescription.isEmpty {
                            Text(dish.dishDescription)
                                .font(.system(size: 13, weight: .regular, design: .default).italic())
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { p in
                        Button {
                            onTapPhoto(p)
                        } label: {
                            DayPhotoThumb(photo: p)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
    }

    @ViewBuilder
    private var illustration: some View {
        if let data = dish.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .cardStroke(cornerRadius: 10)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.5))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Theme.inkFaded)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .cardStroke(cornerRadius: 10)
        }
    }
}

private struct DayPhotoThumb: View {
    let photo: DishPhoto

    var body: some View {
        Group {
            if let img = UIImage(data: photo.imageData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.5)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.inkFaded)
                    )
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .cardStroke(cornerRadius: 12)
    }
}

// MARK: - Calendar helpers

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
