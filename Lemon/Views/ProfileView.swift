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

enum ProfileDishesGroupsMode: Hashable {
    case allDishes
    case allGroups
}

struct ProfileDishesGroupsView: View {
    let mode: ProfileDishesGroupsMode

    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]

    @Query(sort: \Dish.createdAt, order: .reverse) private var dishes: [Dish]

    @State private var searchText = ""

    private var filteredDishes: [Dish] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return dishes
        }
        return dishes.filter { dish in
            dish.name.lowercased().contains(query) ||
            dish.dishDescription.lowercased().contains(query) ||
            dish.tags.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if mode == .allDishes {
                    if dishes.isEmpty {
                        ContentUnavailableView(
                            "No dishes yet",
                            systemImage: "book.closed",
                            description: Text("Add dishes from the Menu tab.")
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 32, height: 28)
                                Text("All Dishes")
                                    .font(Theme.groupName(21))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                            }

                            // Minimalist search bar
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.inkFaded)
                                
                                TextField("Search all dishes…", text: $searchText)
                                    .font(Theme.serif(15))
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.search)
                                
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Theme.inkSoft)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.ink.opacity(0.18), lineWidth: 1)
                            )
                            .padding(.bottom, 6)

                            if filteredDishes.isEmpty {
                                Text("No dishes match \"\(searchText)\".")
                                    .font(Theme.serif(14).italic())
                                    .foregroundStyle(Theme.inkFaded)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 32)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(filteredDishes) { dish in
                                        NavigationLink(value: dish) {
                                            DishCardView(dish: dish)
                                        }
                                        .buttonStyle(.plain)

                                        if dish != filteredDishes.last {
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
                } else {
                    if groups.isEmpty {
                        ContentUnavailableView(
                            "No groups yet",
                            systemImage: "folder",
                            description: Text("Create groups from the Menu tab.")
                        )
                        .padding(.top, 40)
                    } else {
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
                                            
                                            Text("\(group.dishes.count) \(group.dishes.count == 1 ? "Dish" : "Dishes")")
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
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(mode == .allDishes ? "All Dishes" : "Groups")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

struct ProfileChefsListView: View {
    @EnvironmentObject private var store: DishStore

    @Query(sort: [SortDescriptor(\Chef.name), SortDescriptor(\Chef.createdAt)])
    private var chefs: [Chef]
    @Query(sort: \Dish.createdAt, order: .reverse)
    private var dishes: [Dish]

    @State private var showingNewChef = false
    @State private var editingChef: Chef?
    @State private var deletingChef: Chef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("CHEFS")
                        .font(Theme.serif(12, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(Theme.inkFaded)
                    Spacer()
                    Button {
                        showingNewChef = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create chef")
                }

                if chefs.isEmpty {
                    ContentUnavailableView(
                        "No chefs yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Create a chef, then select them when adding or editing dishes.")
                    )
                    .padding(.top, 32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(chefs) { chef in
                            chefRow(chef)

                            if chef.id != chefs.last?.id {
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
            .padding(20)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Chefs")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .sheet(isPresented: $showingNewChef) {
            NavigationStack {
                ChefEditorSheet(chef: nil) { _ in
                    showingNewChef = false
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingChef) { chef in
            NavigationStack {
                ChefEditorSheet(chef: chef) { _ in
                    editingChef = nil
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete this chef?",
            isPresented: Binding(
                get: { deletingChef != nil },
                set: { if !$0 { deletingChef = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingChef
        ) { chef in
            Button("Delete \(chef.name)", role: .destructive) {
                store.deleteChef(chef)
                deletingChef = nil
            }
            Button("Cancel", role: .cancel) {
                deletingChef = nil
            }
        } message: { chef in
            Text("Dishes made by \(chef.name) will stay in your menu with no chef assigned.")
        }
    }

    private func chefRow(_ chef: Chef) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: chef) {
                HStack(spacing: 12) {
                    ChefAvatarView(chef: chef, size: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chef.name)
                            .font(Theme.menuDishName(16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        let count = dishes.filter { $0.chefs.contains { $0.id == chef.id } }.count
                        Text("\(count) \(count == 1 ? "dish" : "dishes")")
                            .font(Theme.hand(12))
                            .foregroundStyle(Theme.inkFaded)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    editingChef = chef
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deletingChef = chef
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
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
        case chefs
        case allPhotos
        case allDailyMenus
        case statistics
        case allTags
        case todo
    }

    @AppStorage("Lemon.profileDisplayName") private var displayName = ""
    @AppStorage("Lemon.profileTagline") private var tagline = ""
    @AppStorage("Lemon.menuTitle") private var menuTitle = "My Menu"
    @AppStorage("Lemon.todos") private var todosRaw = ""

    @Query(sort: \Dish.createdAt, order: .reverse) private var dishes: [Dish]
    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]
    @Query(sort: [SortDescriptor(\Chef.name), SortDescriptor(\Chef.createdAt)])
    private var chefs: [Chef]
    @Query(sort: \DishPhoto.addedAt, order: .reverse) private var photos: [DishPhoto]
    @Query private var todayEntries: [TodayDishEntry]

    @EnvironmentObject private var store: DishStore
    @State private var avatarJPEG: Data? = ProfileAvatarStore.load()
    @State private var showingEditProfile = false

    private var scheduledDaysCount: Int {
        let days = todayEntries.filter { $0.dish != nil }.map { Calendar.current.startOfDay(for: $0.day) }
        return Set(days).count
    }

    private var uniqueTagCount: Int {
        let all = dishes.flatMap(\.tags)
        return Set(all.map { $0.lowercased() }).count
    }

    private var todoCount: Int {
        guard let data = todosRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return 0
        }
        return decoded.filter { !$0.isCompleted }.count
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
                VStack(alignment: .leading, spacing: 28) {
                    profileHeaderCard
                    
                    DottedDivider()
                        .padding(.horizontal, 4)
                    
                    statsCard
                    versionCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }

            .paperBackground()
            .lemonNavigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditProfile = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Profile")
                }
            }
            .navigationDestination(for: ProfileDestination.self) { dest in
                switch dest {
                case .allDishes:
                    ProfileDishesGroupsView(mode: .allDishes)
                case .allGroups:
                    ProfileDishesGroupsView(mode: .allGroups)
                case .chefs:
                    ProfileChefsListView()
                case .allPhotos:
                    ProfilePhotosListView()
                case .allDailyMenus:
                    ProfileDailyMenusListView()
                case .statistics:
                    ProfileStatisticsView()
                case .allTags:
                    ProfileTagsListView()
                case .todo:
                    ProfileTodoListView()
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
            .navigationDestination(for: Chef.self) { chef in
                ChefDishesView(chef: chef)
            }
        }
        .sheet(isPresented: $showingEditProfile) {
            NavigationStack {
                EditProfileSheet(
                    avatarJPEG: $avatarJPEG,
                    displayName: $displayName,
                    tagline: $tagline
                )
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
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
        HStack(alignment: .top, spacing: 16) {
            Button {
                showingEditProfile = true
            } label: {
                avatarCircle
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lemon Cook" : displayName)
                        .font(Theme.dishName(22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    
                    Spacer()
                }
                
                let bioText = tagline.trimmingCharacters(in: .whitespacesAndNewlines)
                if !bioText.isEmpty {
                    Text(bioText)
                        .font(Theme.serif(15).italic())
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(3)
                } else {
                    Text("No bio added yet…")
                        .font(Theme.serif(15).italic())
                        .foregroundStyle(Theme.inkFaded)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            let cafeTitle = menuTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "LEMON CAFÉ" : menuTitle.uppercased()
            Text(cafeTitle)
                .font(Theme.serif(12, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Theme.inkFaded)
                .padding(.horizontal, 4)

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

                NavigationLink(value: ProfileDestination.allTags) {
                    statTile(title: "Tags", value: "\(uniqueTagCount)", systemImage: "tag")
                }
                .buttonStyle(.plain)

                NavigationLink(value: ProfileDestination.chefs) {
                    statTile(title: "Chefs", value: "\(chefs.count)", systemImage: "person.crop.circle")
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

                NavigationLink(value: ProfileDestination.todo) {
                    statTile(title: "Todo", value: "\(todoCount)", systemImage: "checklist")
                }
                .buttonStyle(.plain)
            }
        }
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
            }
        }
    }
}

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore
    
    @Binding var avatarJPEG: Data?
    @Binding var displayName: String
    @Binding var tagline: String
    
    @State private var name: String
    @State private var bio: String
    
    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var removeExistingAvatar = false
    @State private var newPreferenceText = ""
    
    init(
        avatarJPEG: Binding<Data?>,
        displayName: Binding<String>,
        tagline: Binding<String>
    ) {
        self._avatarJPEG = avatarJPEG
        self._displayName = displayName
        self._tagline = tagline
        
        self._name = State(initialValue: displayName.wrappedValue)
        self._bio = State(initialValue: tagline.wrappedValue)
    }
    
    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Edit Profile")
                    .font(Theme.title(26, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 12)
                
                HStack(spacing: 20) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            editableAvatar
                            Image(systemName: "camera.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Theme.ink.opacity(0.55))
                                .font(.system(size: 26))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME")
                            .font(Theme.hand(13))
                            .foregroundStyle(Theme.inkSoft)
                        
                        TextField("e.g. Olivia", text: $name)
                            .font(Theme.dishName(18, weight: .semibold))
                            .textInputAutocapitalization(.words)
                            .padding(12)
                            .background(Color.white.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .cardStroke(cornerRadius: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("ABOUT ME")
                        .font(Theme.hand(13))
                        .foregroundStyle(Theme.inkSoft)
                    
                    TextField("A few words about you…", text: $bio, axis: .vertical)
                        .font(Theme.serif(15).italic())
                        .lineLimit(1...3)
                        .padding(12)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .cardStroke(cornerRadius: 12)
                }
                
                preferencesCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .paperBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .font(Theme.serif(16))
                .foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .font(Theme.serif(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            }
        }
        .task(id: photoItem) {
            await loadPickedPhoto()
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DIETARY PREFERENCES")
                    .font(Theme.serif(12, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Theme.inkFaded)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.highlight)
            }
            
            let prefs = store.getStoredUserPreferences()
            if prefs.isEmpty {
                Text("No dietary preferences saved yet. Speak to your Sous Chef (e.g., \"I don't eat pork\" or \"I prefer vegetarian dishes\") to add them automatically!")
                    .font(Theme.serif(13).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Your Sous Chef remembers these preferences and respects them when creating recipes or planning your day.")
                    .font(Theme.hand(12))
                    .foregroundStyle(Theme.inkSoft)
                
                FlowLayout(spacing: 8) {
                    ForEach(prefs, id: \.self) { pref in
                        HStack(spacing: 4) {
                            Text(pref)
                                .font(Theme.serif(13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Button {
                                store.removeUserPreference(pref)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.inkFaded)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.highlight.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.highlight.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            
            // Inline add field
            HStack(spacing: 8) {
                TextField("Add custom preference...", text: $newPreferenceText)
                    .font(Theme.serif(14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.ink.opacity(0.15), lineWidth: 1)
                    )
                
                Button {
                    let trimmed = newPreferenceText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.saveUserPreference(trimmed)
                        newPreferenceText = ""
                    }
                } label: {
                    Text("Add")
                        .font(Theme.serif(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(newPreferenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color.white.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
    }
    
    private var editableAvatar: some View {
        Group {
            if let pickedImage {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFill()
            } else if let data = avatarJPEG, !removeExistingAvatar, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(Theme.display(26, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.highlight.opacity(0.35))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 1))
    }
    
    private func loadPickedPhoto() async {
        guard let photoItem else { return }
        defer { self.photoItem = nil }
        guard let data = try? await photoItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pickedImage = image
        removeExistingAvatar = false
    }
    
    private func save() {
        displayName = name
        tagline = bio
        
        if removeExistingAvatar {
            ProfileAvatarStore.save(nil)
            avatarJPEG = nil
        } else if let pickedImage {
            let data = pickedImage.jpegData(compressionQuality: 0.82)
            let downscaled = data.flatMap { ProfileAvatarStore.jpegForAvatar(from: $0) }
            ProfileAvatarStore.save(downscaled)
            avatarJPEG = downscaled
        }
        
        dismiss()
    }
}

// MARK: - Profile Tags List View

struct ProfileTagsListView: View {
    @Query private var dishes: [Dish]

    private var tagsWithCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for dish in dishes {
            for tag in dish.tags {
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    counts[normalized, default: 0] += 1
                }
            }
        }
        return counts.map { (tag: $0.key, count: $0.value) }
            .sorted { a, b in
                if a.count != b.count {
                    return a.count > b.count // Most frequent first
                }
                return a.tag.localizedCaseInsensitiveCompare(b.tag) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if tagsWithCounts.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Add tags to your dishes in the Menu detail page.")
                )
            } else {
                List {
                    ForEach(tagsWithCounts, id: \.tag) { item in
                        NavigationLink(destination: TaggedDishesView(tag: item.tag)) {
                            HStack {
                                TagPill(tag: item.tag)
                                Spacer()
                                Text("\(item.count) \(item.count == 1 ? "dish" : "dishes")")
                                    .font(Theme.serif(14))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.vertical, 4)
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
                Text("Tags")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

// MARK: - Todo Tab Models & Views

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var isCompleted = false
}

struct ProfileTodoListView: View {
    @AppStorage("Lemon.todos") private var todosRaw = ""
    
    @State private var todos: [TodoItem] = []
    @State private var newTodoText = ""

    var body: some View {
        VStack(spacing: 0) {
            // New Todo input field
            HStack(spacing: 8) {
                TextField("Add a todo...", text: $newTodoText)
                    .font(Theme.serif(15))
                    .padding(12)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .cardStroke(cornerRadius: 12)
                
                Button {
                    addTodo()
                } label: {
                    Text("Add")
                        .font(Theme.serif(15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            
            // List of Todo Items
            if todos.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No todo items",
                    systemImage: "checklist",
                    description: Text("Write down kitchen notes, grocery runs, or recipe ideas.")
                )
                Spacer()
            } else {
                List {
                    ForEach(todos) { item in
                        HStack(spacing: 12) {
                            Button {
                                toggleTodo(item)
                            } label: {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(item.isCompleted ? Theme.accent : Theme.inkSoft)
                            }
                            .buttonStyle(.plain)
                            
                            Text(item.text)
                                .font(Theme.serif(16))
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? Theme.inkFaded : Theme.ink)
                            
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteTodos)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Todo List")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .onAppear {
            loadTodos()
        }
        .onChange(of: todos) { _, _ in
            saveTodos()
        }
    }
    
    private func loadTodos() {
        guard let data = todosRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            todos = []
            return
        }
        todos = decoded
    }
    
    private func saveTodos() {
        if let data = try? JSONEncoder().encode(todos),
           let string = String(data: data, encoding: .utf8) {
            todosRaw = string
        }
    }
    
    private func addTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(text: trimmed))
        newTodoText = ""
    }
    
    private func toggleTodo(_ item: TodoItem) {
        if let idx = todos.firstIndex(where: { $0.id == item.id }) {
            todos[idx].isCompleted.toggle()
        }
    }
    
    private func deleteTodos(at offsets: IndexSet) {
        todos.remove(atOffsets: offsets)
    }
}



