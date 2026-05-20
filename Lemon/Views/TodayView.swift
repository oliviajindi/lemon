import SwiftUI
import SwiftData

/// Which meal on which calendar day (for navigation from the Today index).
private struct TodayMealRoute: Hashable {
    var mealName: String
    /// Normalized start-of-day for the menu.
    var day: Date
}

/// Minimal meal index for today. Each meal opens into a clean menu-style page
/// that lists only dish names.
struct TodayView: View {
    @EnvironmentObject private var store: DishStore
    @EnvironmentObject private var config: AppConfig

    @Query(sort: \TodayDishEntry.createdAt, order: .forward)
    private var entries: [TodayDishEntry]

    @Query(sort: \Dish.createdAt, order: .reverse)
    private var allMenuDishes: [Dish]

    @AppStorage("Lemon.todayMealNames") private var storedMealNames = ""
    @State private var isAddingMeal = false
    @State private var newMealName = ""
    @FocusState private var newMealFocused: Bool
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showingMenuDateSheet = false
    @State private var showingPlanSheet = false

    private var selectedDayStart: Date {
        Calendar.current.startOfDay(for: selectedDay)
    }

    private var isViewingActualToday: Bool {
        Calendar.current.isDateInToday(selectedDayStart)
    }

    private var menuDayPickerRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(byAdding: .year, value: -5, to: Date()) ?? .distantPast
        let end = cal.date(byAdding: .year, value: 3, to: Date()) ?? .distantFuture
        return start...end
    }

    private var todayEntries: [TodayDishEntry] {
        entries.filter { Calendar.current.isDate($0.day, inSameDayAs: selectedDayStart) && $0.dish != nil }
    }

    private var mealNames: [String] {
        let names = parsedMealNames(from: storedMealNames)
        return names.isEmpty ? TodayMeal.allCases.map(\.rawValue) : names
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 34) {
                    masthead

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(mealNames.enumerated()), id: \.element) { index, mealName in
                            if index > 0 {
                                Rectangle()
                                    .fill(Theme.ink.opacity(0.18))
                                    .frame(height: 1)
                            }

                            HStack(alignment: .top, spacing: 10) {
                                NavigationLink(value: TodayMealRoute(mealName: mealName, day: selectedDayStart)) {
                                    TodayMealIndexRow(mealName: mealName, entries: entries(for: mealName))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    deleteMeal(mealName)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.inkFaded)
                                        .padding(.top, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        addMealControl
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 36)
                .padding(.top, 42)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                planDayFAB
                    .padding(.trailing, 22)
                    .padding(.bottom, 28)
            }
            .paperBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TodayMealRoute.self) { route in
                TodayMealDetailView(mealName: route.mealName, day: route.day)
            }
            .sheet(isPresented: $showingMenuDateSheet) {
                MenuDatePickerSheet(selectedDay: $selectedDay, range: menuDayPickerRange)
            }
            .sheet(isPresented: $showingPlanSheet) {
                TodayAIMealPlanSheet(
                    day: selectedDayStart,
                    mealNames: mealNames,
                    dishCount: allMenuDishes.count
                )
                .environmentObject(store)
                .environmentObject(config)
            }
            .onChange(of: selectedDay) { _, newValue in
                let normalized = Calendar.current.startOfDay(for: newValue)
                if normalized != selectedDay {
                    selectedDay = normalized
                }
            }
        }
    }

    private var planDayFAB: some View {
        Button {
            showingPlanSheet = true
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(Theme.accent)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: Theme.ink.opacity(0.22), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plan this day with AI")
        .accessibilityHint("Chooses dishes from your menu for each meal")
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isViewingActualToday ? "Today" : selectedDayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(Theme.title(38))
                .foregroundStyle(Theme.ink)

            Button {
                showingMenuDateSheet = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedDayStart.formatted(date: .complete, time: .omitted))
                        .font(Theme.serif(14).italic())
                        .foregroundStyle(Theme.inkSoft)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaded)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose menu date")
            .accessibilityHint("Opens date picker")
        }
    }

    @ViewBuilder
    private var addMealControl: some View {
        if isAddingMeal {
            HStack(spacing: 10) {
                TextField("New meal", text: $newMealName)
                    .font(Theme.serif(18))
                    .textInputAutocapitalization(.words)
                    .focused($newMealFocused)
                    .submitLabel(.done)
                    .onSubmit(addMeal)
                Button(action: addMeal) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                isAddingMeal = true
                newMealFocused = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Meal")
                }
                .font(Theme.serif(15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private func entries(for mealName: String) -> [TodayDishEntry] {
        todayEntries.filter { $0.meal == mealName }
    }

    private func addMeal() {
        let trimmed = newMealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isAddingMeal = false
            return
        }
        storedMealNames = serializedMealNames(mealNames + [trimmed])
        newMealName = ""
        isAddingMeal = false
        newMealFocused = false
    }

    private func deleteMeal(_ mealName: String) {
        storedMealNames = serializedMealNames(mealNames.filter { $0 != mealName })
        store.deleteTodayMeal(mealName, day: selectedDayStart)
    }

    private func parsedMealNames(from value: String) -> [String] {
        value
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func serializedMealNames(_ names: [String]) -> String {
        var seen = Set<String>()
        return names.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
        .joined(separator: "\n")
    }
}

// MARK: - AI meal plan sheet

private struct TodayAIMealPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore
    @EnvironmentObject private var config: AppConfig

    let day: Date
    let mealNames: [String]
    let dishCount: Int

    @State private var note = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var dayLabel: String {
        Calendar.current.startOfDay(for: day).formatted(date: .complete, time: .omitted)
    }

    private var canUseDirectGemini: Bool {
        true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("The AI chooses only from dishes already on your Menu; it will not invent new recipes. Tapping Generate replaces every dish you had scheduled on this date.")
                        .font(Theme.serif(15))
                        .foregroundStyle(Theme.inkSoft)

                    if dishCount == 0 {
                        Text("Add dishes from the Menu tab first.")
                            .font(Theme.serif(15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES (OPTIONAL)")
                            .font(Theme.serif(12, weight: .semibold))
                            .tracking(4)
                            .foregroundStyle(Theme.inkFaded)
                        TextField("e.g. keep lunch light, vegetarian dinner", text: $note, axis: .vertical)
                            .font(Theme.serif(16))
                            .lineLimit(3...6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.ink.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .disabled(!canUseDirectGemini || dishCount == 0 || isWorking)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.hand(14))
                            .foregroundStyle(Theme.accent)
                    }

                    Button(action: runPlan) {
                        HStack(spacing: 10) {
                            if isWorking {
                                ProgressView()
                                    .tint(Color.white)
                            }
                            Text(isWorking ? "Planning…" : "Generate plan")
                                .font(Theme.serif(17, weight: .semibold))
                                .tracking(1)
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canRun ? Theme.ink : Theme.inkFaded.opacity(0.45))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRun)
                }
                .padding(24)
                .padding(.bottom, 24)
            }
            .paperBackground()
            .navigationTitle("Plan \(dayLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(Theme.hand(16))
                        .disabled(isWorking)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var canRun: Bool {
        canUseDirectGemini && dishCount > 0 && !isWorking && !mealNames.isEmpty
    }

    private func runPlan() {
        guard canRun else { return }
        isWorking = true
        errorMessage = nil
        let mealList = mealNames
        let noteCopy = note
        let dayCopy = day
        Task { @MainActor in
            do {
                let plan = try await store.generateDayMealPlanForToday(
                    day: dayCopy,
                    mealNames: mealList,
                    userNote: noteCopy.isEmpty ? nil : noteCopy
                )
                let picked = plan.assignments.reduce(0) { $0 + $1.dishIds.count }
                guard picked > 0 else {
                    errorMessage = "The AI didn't assign any dishes. Try different notes or check that your meal names match what you use in Today."
                    isWorking = false
                    return
                }
                store.replaceTodayEntries(with: plan, day: dayCopy, mealNames: mealList)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isWorking = false
            }
        }
    }
}

// MARK: - Themed menu date (Today index)

private struct MenuDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDay: Date
    let range: ClosedRange<Date>

    @State private var visibleMonth: Date = .now

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 14) {
                        MenuPickerMonthHeader(visibleMonth: $visibleMonth, calendar: calendar)
                        MenuPickerWeekdayLabels(calendar: calendar)
                        MenuPickerMonthGrid(
                            visibleMonth: visibleMonth,
                            selectedDay: $selectedDay,
                            allowedRange: range,
                            calendar: calendar
                        )
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .cardStroke(cornerRadius: 16)

                    Button {
                        let todayStart = calendar.startOfDay(for: .now)
                        selectedDay = todayStart
                        visibleMonth = calendar.startOfMonth(for: todayStart)
                    } label: {
                        Text("Jump to today")
                            .font(Theme.serif(15, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .cardStroke(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Choose date")
                        .font(Theme.serif(18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Theme.hand(16))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            visibleMonth = calendar.startOfMonth(for: selectedDay)
        }
    }
}

private struct MenuPickerMonthHeader: View {
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

private struct MenuPickerWeekdayLabels: View {
    let calendar: Calendar

    private var symbols: [String] {
        let raw = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
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

private struct MenuPickerMonthGrid: View {
    let visibleMonth: Date
    @Binding var selectedDay: Date
    let allowedRange: ClosedRange<Date>
    let calendar: Calendar

    private var dayCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else {
            return Array(repeating: nil, count: 42)
        }
        let firstDay = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for i in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: i, to: firstDay))
        }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<dayCells.count, id: \.self) { i in
                if let day = dayCells[i] {
                    MenuPickerDayCell(
                        date: day,
                        isInVisibleMonth: calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month),
                        isToday: calendar.isDateInToday(day),
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                        isSelectable: isSelectable(day),
                        calendar: calendar,
                        onSelect: {
                            selectedDay = calendar.startOfDay(for: day)
                        }
                    )
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func isSelectable(_ date: Date) -> Bool {
        let d = calendar.startOfDay(for: date)
        let lo = calendar.startOfDay(for: allowedRange.lowerBound)
        let hi = calendar.startOfDay(for: allowedRange.upperBound)
        return d >= lo && d <= hi
    }
}

/// Day cell styled like `CalendarView`’s `DayCell`, for choosing a menu date.
private struct MenuPickerDayCell: View {
    let date: Date
    let isInVisibleMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isSelectable: Bool
    let calendar: Calendar
    let onSelect: () -> Void

    private var dayNumber: String {
        String(calendar.component(.day, from: date))
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                if isSelected {
                    Circle()
                        .strokeBorder(Theme.ink, lineWidth: 1.6)
                        .background(Circle().fill(Color.white.opacity(0.55)))
                        .frame(width: 36, height: 36)
                } else if isToday {
                    Circle()
                        .strokeBorder(Theme.inkFaded, lineWidth: 1)
                        .frame(width: 32, height: 32)
                }
                Text(dayNumber)
                    .font(Theme.serif(16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }

    private var textColor: Color {
        if !isSelectable { return Theme.inkFaded.opacity(0.35) }
        if !isInVisibleMonth { return Theme.inkFaded.opacity(0.4) }
        if isSelected { return Theme.ink }
        return Theme.inkSoft
    }
}

private extension Calendar {
    func startOfMonth(for reference: Date) -> Date {
        let comps = dateComponents([.year, .month], from: reference)
        return self.date(from: comps) ?? reference
    }
}

private struct TodayMealIndexRow: View {
    let mealName: String
    let entries: [TodayDishEntry]

    private var previewNames: String {
        let names = entries.compactMap { $0.dish?.name }
        return names.prefix(2).joined(separator: ", ") + (names.count > 2 ? "..." : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(mealName.uppercased())
                    .font(Theme.serif(17, weight: .bold))
                    .tracking(7)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(entries.count == 1 ? "1" : "\(entries.count)")
                    .font(Theme.serif(13))
                    .foregroundStyle(Theme.inkFaded)
            }

            Group {
                if entries.isEmpty {
                    Text("Tap to choose from your menu")
                        .font(Theme.serif(12, weight: .light))
                        .italic()
                        .foregroundStyle(Theme.inkFaded)
                } else {
                    Text(previewNames)
                        .font(Theme.serif(18))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .lineLimit(2)
        }
        .contentShape(Rectangle())
    }
}

private struct TodayMealDetailView: View {
    @EnvironmentObject private var store: DishStore

    let mealName: String
    let day: Date

    @Query(sort: \TodayDishEntry.createdAt, order: .forward)
    private var entries: [TodayDishEntry]

    @State private var pickingSection: String?
    @State private var showingPicker = false
    @State private var sectionNames: [String] = []
    @State private var collapsedSections: Set<String> = []
    @State private var isAddingSection = false
    @State private var newSectionName = ""
    @FocusState private var newSectionFocused: Bool

    private var menuDay: Date {
        Calendar.current.startOfDay(for: day)
    }

    private var mealEntries: [TodayDishEntry] {
        entries.filter {
            Calendar.current.isDate($0.day, inSameDayAs: menuDay) &&
            $0.meal == mealName &&
            $0.dish != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            mealHeader

            VStack(alignment: .leading, spacing: 26) {
                TodayUnsectionedDishes(
                    entries: unsectionedEntries,
                    onAdd: {
                        pickingSection = nil
                        showingPicker = true
                    },
                    onRemove: { entry in store.removeFromToday(entry) }
                )

                if !sectionNames.isEmpty {
                    ForEach(sectionNames, id: \.self) { section in
                        TodayCourseSection(
                            title: section,
                            entries: entries(for: section),
                            isCollapsed: collapsedSections.contains(section),
                            onLongPressHeader: { toggleSection(section) },
                            onAdd: {
                                pickingSection = section
                                showingPicker = true
                            },
                            onRemove: { entry in store.removeFromToday(entry) },
                            onMoveEntry: { entryID in moveEntry(entryID, to: section) }
                        )
                    }
                }

                addSectionControl
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.top, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperBackground()
        .navigationTitle(mealName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Dish.self) { DishDetailView(dish: $0) }
        .onAppear {
            sectionNames = loadSections()
        }
        .sheet(isPresented: $showingPicker) {
            let section = pickingSection ?? ""
            TodayDishPickerView(
                mealName: mealName,
                sectionName: pickingSection,
                menuDay: menuDay,
                selectedDishIDs: selectedDishIDs(for: section)
            ) { dish in
                store.addToToday(dish, day: menuDay, mealName: mealName, courseName: section)
                pickingSection = nil
                showingPicker = false
            }
        }
    }

    private var mealHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mealName.uppercased())
                .font(Theme.serif(25, weight: .semibold))
                .tracking(9)
                .foregroundStyle(Theme.ink)
            Text(menuDay.formatted(date: .abbreviated, time: .omitted))
                .font(Theme.serif(14).italic())
                .foregroundStyle(Theme.inkFaded)
        }
    }

    private var unsectionedEntries: [TodayDishEntry] {
        mealEntries.filter { $0.course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @ViewBuilder
    private var addSectionControl: some View {
        if isAddingSection {
            HStack(spacing: 10) {
                TextField("Course name", text: $newSectionName)
                    .font(Theme.serif(17))
                    .textInputAutocapitalization(.words)
                    .focused($newSectionFocused)
                    .submitLabel(.done)
                    .onSubmit(addSection)
                Button(action: addSection) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                isAddingSection = true
                newSectionFocused = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Course")
                        .font(Theme.serif(15, weight: .semibold))
                        .tracking(2)
                    Text("(Appetizer, Main, Dessert…)")
                        .font(Theme.serif(13).italic())
                        .tracking(0)
                        .foregroundStyle(Theme.inkFaded)
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private func entries(for section: String) -> [TodayDishEntry] {
        mealEntries.filter { $0.course == section }
    }

    private func selectedDishIDs(for section: String) -> Set<UUID> {
        Set(entries(for: section).compactMap { $0.dish?.id })
    }

    private func toggleSection(_ section: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            if collapsedSections.contains(section) {
                collapsedSections.remove(section)
            } else {
                collapsedSections.insert(section)
            }
        }
    }

    private func moveEntry(_ entryID: String, to section: String) -> Bool {
        guard let id = UUID(uuidString: entryID),
              let entry = mealEntries.first(where: { $0.id == id })
        else { return false }
        store.moveTodayEntry(entry, toCourseName: section)
        return true
    }

    private func addSection() {
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isAddingSection = false
            return
        }
        sectionNames = normalizedSections(sectionNames + [trimmed])
        saveSections()
        newSectionName = ""
        isAddingSection = false
        newSectionFocused = false
    }

    private func loadSections() -> [String] {
        let stored = UserDefaults.standard.string(forKey: sectionsKey) ?? ""
        let saved = stored.split(separator: "\n").map(String.init)
        let fromEntries = mealEntries
            .map(\.course)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return normalizedSections(saved + fromEntries)
    }

    private func saveSections() {
        UserDefaults.standard.set(sectionNames.joined(separator: "\n"), forKey: sectionsKey)
    }

    private var sectionsKey: String {
        let stamp = Int(menuDay.timeIntervalSince1970)
        return "Lemon.todaySections.\(mealName.lowercased()).\(stamp)"
    }

    private func normalizedSections(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }
}

private struct TodayCourseSection: View {
    let title: String
    let entries: [TodayDishEntry]
    let isCollapsed: Bool
    let onLongPressHeader: () -> Void
    let onAdd: () -> Void
    let onRemove: (TodayDishEntry) -> Void
    let onMoveEntry: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaded)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    Text(title.uppercased())
                        .font(Theme.serif(17, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(Theme.ink)
                }
                .contentShape(Rectangle())
                .onLongPressGesture(perform: onLongPressHeader)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            .dropDestination(for: String.self) { items, _ in
                items.map(onMoveEntry).contains(true)
            } isTargeted: { targeted in
                // Keep the target generous without adding a visual dependency.
            }

            if !isCollapsed {
                if entries.isEmpty {
                    Text("Add from menu")
                        .font(Theme.serif(14).italic())
                        .foregroundStyle(Theme.inkFaded)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            if let dish = entry.dish {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    NavigationLink(value: dish) {
                                        Text(dish.name)
                                            .font(Theme.dishName(16))
                                            .foregroundStyle(Theme.inkSoft)
                                            .lineLimit(2)
                                    }
                                    .buttonStyle(.plain)
                                    .draggable(entry.id.uuidString)

                                    Button {
                                        onRemove(entry)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Theme.inkFaded)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            items.map(onMoveEntry).contains(true)
        }
    }
}

private struct TodayUnsectionedDishes: View {
    let entries: [TodayDishEntry]
    let onAdd: () -> Void
    let onRemove: (TodayDishEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entries.isEmpty {
                Text("No dishes yet")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkFaded)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        if let dish = entry.dish {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                NavigationLink(value: dish) {
                                    Text(dish.name)
                                        .font(Theme.dishName(16))
                                        .foregroundStyle(Theme.inkSoft)
                                        .lineLimit(2)
                                }
                                .buttonStyle(.plain)
                                .draggable(entry.id.uuidString)

                                Button {
                                    onRemove(entry)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.inkFaded)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Dish")
                }
                .font(Theme.serif(15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TodayDishPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let mealName: String
    let sectionName: String?
    /// Start-of-day for the menu row being edited.
    let menuDay: Date
    let selectedDishIDs: Set<UUID>
    let onSelect: (Dish) -> Void

    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]

    @Query(sort: \Dish.createdAt, order: .reverse)
    private var dishes: [Dish]

    @State private var searchText = ""

    private var filteredDishes: [Dish] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return dishes }
        return dishes.filter { dish in
            dish.name.lowercased().contains(query) ||
            dish.dishDescription.lowercased().contains(query) ||
            dish.tags.contains { $0.lowercased().contains(query) } ||
            (dish.group?.name.lowercased().contains(query) ?? false)
        }
    }

    private var pickerNavigationTitle: String {
        let dayLabel = menuDay.formatted(date: .abbreviated, time: .omitted)
        if let sectionName, !sectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(mealName) · \(sectionName) · \(dayLabel)"
        }
        return "Add to \(mealName) · \(dayLabel)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.inkFaded)
                    TextField("Search dishes, tags, groups", text: $searchText)
                        .font(Theme.serif(16))
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.inkFaded)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.ink.opacity(0.18), lineWidth: 1)
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(groups) { group in
                            DishPickerGroupSection(
                                title: group.name,
                                emoji: group.emoji,
                                dishes: filteredDishes.filter { $0.group?.id == group.id },
                                selectedDishIDs: selectedDishIDs,
                                onSelect: onSelect
                            )
                        }

                        DishPickerGroupSection(
                            title: groups.isEmpty ? "All Dishes" : "Other Dishes",
                            emoji: nil,
                            dishes: filteredDishes.filter { $0.group == nil },
                            selectedDishIDs: selectedDishIDs,
                            onSelect: onSelect
                        )
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(20)
            .paperBackground()
            .navigationTitle(pickerNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct DishPickerGroupSection: View {
    let title: String
    let emoji: String?
    let dishes: [Dish]
    let selectedDishIDs: Set<UUID>
    let onSelect: (Dish) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let emoji, !emoji.isEmpty { Text(emoji) }
                Text(title.uppercased())
                    .font(Theme.serif(14, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Theme.ink)
            }

            if dishes.isEmpty {
                Text("No matching dishes")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkFaded)
            } else {
                VStack(spacing: 0) {
                    ForEach(dishes) { dish in
                        Button {
                            onSelect(dish)
                        } label: {
                            HStack(spacing: 12) {
                                Text(dish.name)
                                .font(Theme.dishName(14))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: selectedDishIDs.contains(dish.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(selectedDishIDs.contains(dish.id) ? Theme.inkFaded : Theme.ink)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedDishIDs.contains(dish.id))

                        if dish.id != dishes.last?.id {
                            DottedDivider().padding(.horizontal, 2)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.32))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .cardStroke(cornerRadius: 16)
            }
        }
    }
}
