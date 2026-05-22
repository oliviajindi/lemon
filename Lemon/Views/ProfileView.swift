import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum ProfileAvatarStore {
    static let key = "Lemon.profileAvatarJPEG"

    static func load() -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    static func save(_ data: Data?) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Downscale wide photos so avatar storage stays small.
    static func jpegForAvatar(from data: Data, maxDimension: CGFloat = 400, quality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 1 else { return nil }
        let scale = min(1, maxDimension / longest)
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let scaled = renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}

// MARK: - Profile lists from stat tiles

private struct ProfileGroupRowGlyph: View {
    let group: DishGroup

    var body: some View {
        let trimmed = group.emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            Text(String(trimmed.prefix(16)))
                .font(.system(size: 22))
                .frame(width: 32, height: 28, alignment: .center)
        } else {
            Image(systemName: group.iconName)
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 28)
        }
    }
}

struct ProfileDishesGroupsView: View {
    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]

    @Query(sort: \Dish.createdAt, order: .reverse) private var dishes: [Dish]

    private var ungroupedDishes: [Dish] {
        dishes.filter { $0.group == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if groups.isEmpty && dishes.isEmpty {
                    ContentUnavailableView(
                        "No dishes yet",
                        systemImage: "book.closed",
                        description: Text("Add dishes from the Menu tab.")
                    )
                    .padding(.top, 40)
                } else {
                    // Render all custom groups in a unified card container
                    if !groups.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 32, height: 28)
                                Text("Groups")
                                    .font(Theme.groupName(21))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                            }

                            VStack(spacing: 0) {
                                ForEach(groups) { group in
                                    NavigationLink(value: group) {
                                        HStack(spacing: 12) {
                                            ProfileGroupRowGlyph(group: group)
                                            Text(group.name)
                                                .font(Theme.menuDishName(16, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                            Spacer()
                                            
                                            Text("\(group.dishes.count) \(group.dishes.count == 1 ? "dish" : "dishes")")
                                                .font(Theme.hand(12))
                                                .foregroundStyle(Theme.inkFaded)
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Theme.inkSoft)
                                        }
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if group != groups.last {
                                        DottedDivider().padding(.horizontal, 4)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .background(Color.white.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .cardStroke(cornerRadius: 16)
                        }
                    }

                    // Render ungrouped dishes if present
                    if !ungroupedDishes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 32, height: 28)
                                Text(groups.isEmpty ? "All Dishes" : "Other Dishes")
                                    .font(Theme.groupName(21))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                            }

                            VStack(spacing: 0) {
                                ForEach(ungroupedDishes) { dish in
                                    NavigationLink(value: dish) {
                                        DishCardView(dish: dish)
                                    }
                                    .buttonStyle(.plain)

                                    if dish != ungroupedDishes.last {
                                        DottedDivider().padding(.horizontal, 4)
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .cardStroke(cornerRadius: 16)
                        }
                    }
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Dishes & Groups")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

struct ProfilePhotosListView: View {
    @EnvironmentObject private var store: DishStore
    @Query(sort: \DishPhoto.addedAt, order: .reverse) private var photos: [DishPhoto]
    
    @State private var viewerPhoto: DishPhoto?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var groupedPhotos: [(date: Date, photos: [DishPhoto])] {
        var seenData = Set<Data>()
        var uniquePhotos: [DishPhoto] = []
        for photo in photos {
            if !seenData.contains(photo.imageData) {
                seenData.insert(photo.imageData)
                uniquePhotos.append(photo)
            }
        }
        
        let grouped = Dictionary(grouping: uniquePhotos) { photo in
            Calendar.current.startOfDay(for: photo.effectiveDate)
        }
        return grouped.map { (date: $0.key, photos: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No photos yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Snap real photos of your dishes in the Menu tab.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedPhotos, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.date.formatted(date: .complete, time: .omitted))
                                    .font(Theme.serif(14, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 4)
                                
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(group.photos) { photo in
                                        Button {
                                            viewerPhoto = photo
                                        } label: {
                                            Rectangle()
                                                .fill(Color.clear)
                                                .aspectRatio(1.0, contentMode: .fit)
                                                .overlay(
                                                    GeometryReader { geo in
                                                        Group {
                                                            if let img = UIImage(data: photo.imageData) {
                                                                Image(uiImage: img)
                                                                    .resizable()
                                                                    .scaledToFill()
                                                                    .frame(width: geo.size.width, height: geo.size.height)
                                                                    .clipped()
                                                            } else {
                                                                Color.white.opacity(0.4)
                                                                    .overlay(
                                                                        Image(systemName: "photo")
                                                                            .foregroundStyle(Theme.inkFaded)
                                                                    )
                                                            }
                                                        }
                                                    }
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .cardStroke(cornerRadius: 12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Photos by Date")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .fullScreenCover(item: $viewerPhoto) { photo in
            DishPhotoViewer(photo: photo)
                .environmentObject(store)
        }
    }
}

struct ProfileDailyMenusListView: View {
    @Query private var todayEntries: [TodayDishEntry]

    private var groupedMenus: [(date: Date, entries: [TodayDishEntry])] {
        let activeEntries = todayEntries.filter { $0.dish != nil }
        let grouped = Dictionary(grouping: activeEntries) { entry in
            Calendar.current.startOfDay(for: entry.day)
        }
        return grouped.map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if groupedMenus.isEmpty {
                ContentUnavailableView(
                    "No daily menus",
                    systemImage: "sun.max",
                    description: Text("Plan your daily meals in the Today tab.")
                )
            } else {
                List {
                    ForEach(groupedMenus, id: \.date) { group in
                        NavigationLink(value: group.date) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.date.formatted(date: .complete, time: .omitted))
                                    .font(Theme.serif(16, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                
                                let mealsGrouped = Dictionary(grouping: group.entries) { $0.meal }
                                let canonical = TodayMeal.allCases.map(\.rawValue)
                                let sortedMeals = mealsGrouped.map { (meal: $0.key, entries: $0.value) }
                                    .sorted { a, b in
                                        let ra = canonical.firstIndex(of: a.meal) ?? Int.max
                                        let rb = canonical.firstIndex(of: b.meal) ?? Int.max
                                        if ra != rb { return ra < rb }
                                        return a.meal < b.meal
                                    }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(sortedMeals, id: \.meal) { mealGroup in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(mealGroup.meal.uppercased() + ":")
                                                .font(Theme.serif(12, weight: .semibold))
                                                .tracking(1)
                                                .foregroundStyle(Theme.inkSoft)
                                            
                                            let dishNames = mealGroup.entries.compactMap { $0.dish?.name }
                                            Text(dishNames.joined(separator: ", "))
                                                .font(Theme.serif(14))
                                                .foregroundStyle(Theme.ink)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Daily Menus")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

/// Personal snapshot: display name, tagline, menu stats, and app version details.
struct ProfileView: View {
    private enum ProfileDestination: Hashable {
        case allDishes
        case allGroups
        case allPhotos
        case allDailyMenus
        case statistics
    }

    @AppStorage("Lemon.profileDisplayName") private var displayName = ""
    @AppStorage("Lemon.profileTagline") private var tagline = ""

    @Query(sort: \Dish.createdAt, order: .reverse) private var dishes: [Dish]
    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]
    @Query(sort: \DishPhoto.addedAt, order: .reverse) private var photos: [DishPhoto]
    @Query private var todayEntries: [TodayDishEntry]

    @State private var avatarJPEG: Data? = ProfileAvatarStore.load()
    @State private var avatarPickerItem: PhotosPickerItem?

    private var scheduledDaysCount: Int {
        let days = todayEntries.filter { $0.dish != nil }.map { Calendar.current.startOfDay(for: $0.day) }
        return Set(days).count
    }

    private var uniqueTagCount: Int {
        let all = dishes.flatMap(\.tags)
        return Set(all.map { $0.lowercased() }).count
    }

    private var initials: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 2,
           let a = parts[0].first,
           let b = parts[1].first {
            return String(a).uppercased() + String(b).uppercased()
        }
        let s = String(trimmed.prefix(2))
        return s.uppercased()
    }

    private var hasAvatar: Bool {
        avatarJPEG.flatMap({ UIImage(data: $0) }) != nil
    }



    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileHeaderCard
                    statsCard
                    versionCard
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .paperBackground()
            .lemonNavigationTitle("Profile")
            .navigationDestination(for: ProfileDestination.self) { dest in
                switch dest {
                case .allDishes, .allGroups:
                    ProfileDishesGroupsView()
                case .allPhotos:
                    ProfilePhotosListView()
                case .allDailyMenus:
                    ProfileDailyMenusListView()
                case .statistics:
                    ProfileStatisticsView()
                }
            }
            .navigationDestination(for: Dish.self) { dish in
                DishDetailView(dish: dish)
            }
            .navigationDestination(for: DishGroup.self) { group in
                GroupDetailView(group: group)
            }
            .navigationDestination(for: Date.self) { date in
                DayDetailView(day: date)
            }
        }
    }

    private var avatarCircle: some View {
        Group {
            if let data = avatarJPEG, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(Theme.display(26, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: 72, height: 72)
        .background(Theme.highlight.opacity(0.35))
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
        )
    }

    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarCircle
                        Image(systemName: "camera.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Theme.ink.opacity(0.55))
                            .font(.system(size: 26))
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Choose profile photo")
                }
                .buttonStyle(.plain)

                TextField("e.g. Olivia", text: $displayName)
                    .font(Theme.dishName(20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .textInputAutocapitalization(.words)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("About Me")
                    .font(Theme.hand(12))
                    .foregroundStyle(Theme.inkFaded)
                TextField("Home cook · meal planner", text: $tagline, axis: .vertical)
                    .font(Theme.serif(15).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2...4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
        .task(id: avatarPickerItem) {
            guard let item = avatarPickerItem else { return }
            await loadAvatar(from: item)
        }
    }

    private func loadAvatar(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run { avatarPickerItem = nil }
            return
        }
        let jpeg = await Task.detached {
            ProfileAvatarStore.jpegForAvatar(from: data)
        }.value

        await MainActor.run {
            defer { avatarPickerItem = nil }
            guard let jpeg else { return }
            ProfileAvatarStore.save(jpeg)
            avatarJPEG = jpeg
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR MENU")
                .font(Theme.serif(12, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Theme.inkFaded)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                NavigationLink(value: ProfileDestination.allDishes) {
                    statTile(title: "Dishes", value: "\(dishes.count)", systemImage: "book.closed")
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileDestination.allGroups) {
                    statTile(title: "Groups", value: "\(groups.count)", systemImage: "folder")
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileDestination.allPhotos) {
                    statTile(title: "Photos", value: "\(photos.count)", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileDestination.allDailyMenus) {
                    statTile(title: "Daily Menus", value: "\(scheduledDaysCount)", systemImage: "sun.max")
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileDestination.statistics) {
                    statTile(title: "Statistics", value: "\(todayEntries.filter { $0.dish != nil }.count)", systemImage: "chart.bar")
                }
                .buttonStyle(.plain)

                statTile(title: "Tags", value: "\(uniqueTagCount)", systemImage: "tag")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
    }



    private func statTile(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            Text(value)
                .font(Theme.display(22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(Theme.hand(12))
                .foregroundStyle(Theme.inkFaded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
        )
    }

    private var versionCard: some View {
        VStack(spacing: 6) {
            Text("Lemon · v1")
                .font(Theme.serif(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            
            Text("My Personal Cafes")
                .font(Theme.serif(12).italic())
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppConfig.shared)
        .environmentObject(DishStore())
}

struct ProfileStatisticsView: View {
    @Query private var todayEntries: [TodayDishEntry]
    
    private enum StatRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        
        var id: String { rawValue }
    }
    
    @State private var selectedStatRange: StatRange = .week
    
    private var filteredTodayEntries: [TodayDishEntry] {
        let calendar = Calendar.current
        let now = Date()
        let cutoffDate: Date
        switch selectedStatRange {
        case .week:
            cutoffDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            cutoffDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .year:
            cutoffDate = calendar.date(byAdding: .day, value: -365, to: now) ?? now
        }
        
        let startOfCutoff = calendar.startOfDay(for: cutoffDate)
        return todayEntries.filter { entry in
            guard entry.dish != nil else { return false }
            return entry.day >= startOfCutoff
        }
    }
    
    private var dishStats: [(dish: Dish, count: Int)] {
        let entries = filteredTodayEntries
        var frequencies: [UUID: Int] = [:]
        var dishMap: [UUID: Dish] = [:]
        
        for entry in entries {
            if let dish = entry.dish {
                frequencies[dish.id, default: 0] += 1
                dishMap[dish.id] = dish
            }
        }
        
        return frequencies.map { (id, count) in
            (dish: dishMap[id]!, count: count)
        }
        .sorted { a, b in
            if a.count != b.count {
                return a.count > b.count
            }
            return a.dish.name.localizedCaseInsensitiveCompare(b.dish.name) == .orderedAscending
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("STATISTICS RANGE")
                        .font(Theme.serif(12, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(Theme.inkFaded)
                    Spacer()
                    Picker("Range", selection: $selectedStatRange) {
                        ForEach(StatRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.horizontal, 4)
                
                let stats = dishStats
                
                if stats.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.inkFaded)
                            .padding(.top, 40)
                        
                        Text("No dishes logged in this period")
                            .font(Theme.serif(16).italic())
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    let maxCount = stats.first?.count ?? 1
                    
                    VStack(spacing: 0) {
                        ForEach(stats, id: \.dish.id) { stat in
                            NavigationLink(value: stat.dish) {
                                HStack(spacing: 14) {
                                    DishIllustrationView(dish: stat.dish, size: 44)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(stat.dish.name)
                                                .font(Theme.menuDishName(16, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                                .lineLimit(1)
                                            
                                            Spacer()
                                            
                                            Text("\(stat.count) \(stat.count == 1 ? "time" : "times")")
                                                .font(Theme.hand(13))
                                                .foregroundStyle(Theme.inkSoft)
                                        }
                                        
                                        GeometryReader { geo in
                                            let progress = CGFloat(stat.count) / CGFloat(maxCount)
                                            let barWidth = geo.size.width * progress
                                            Capsule()
                                                .fill(Theme.highlight)
                                                .frame(width: min(geo.size.width, max(8, barWidth)))
                                        }
                                        .frame(height: 8)
                                    }
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if stat.dish.id != stats.last?.dish.id {
                                DottedDivider().padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .cardStroke(cornerRadius: 16)
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Dish Statistics")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

