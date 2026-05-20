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

struct ProfileDishesListView: View {
    @Query(sort: \Dish.createdAt, order: .reverse) private var dishes: [Dish]

    var body: some View {
        Group {
            if dishes.isEmpty {
                ContentUnavailableView(
                    "No dishes yet",
                    systemImage: "book.closed",
                    description: Text("Add dishes from the Menu tab.")
                )
            } else {
                List(dishes) { dish in
                    NavigationLink(value: dish) {
                        Text(dish.name)
                            .font(Theme.dishName(17, weight: .light))
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("All Dishes")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

struct ProfileGroupsListView: View {
    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "No groups yet",
                    systemImage: "folder",
                    description: Text("Create a group from the Menu tab.")
                )
            } else {
                List(groups) { group in
                    NavigationLink(value: group) {
                        HStack(spacing: 10) {
                            ProfileGroupRowGlyph(group: group)
                            Text(group.name)
                                .font(Theme.dishName(17, weight: .medium))
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Groups")
                    .font(Theme.title(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

struct ProfileGroupDetailView: View {
    let group: DishGroup

    private var dishes: [Dish] {
        group.dishes.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if dishes.isEmpty {
                ContentUnavailableView(
                    "No dishes in \(group.name)",
                    systemImage: "tray",
                    description: Text("Assign dishes to this group from the Menu tab.")
                )
            } else {
                List(dishes) { dish in
                    NavigationLink(value: dish) {
                        Text(dish.name)
                            .font(Theme.dishName(17, weight: .medium))
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group.name)
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

    private var scheduledSlots: Int {
        todayEntries.filter { $0.dish != nil }.count
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
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProfileDestination.self) { dest in
                switch dest {
                case .allDishes:
                    ProfileDishesListView()
                case .allGroups:
                    ProfileGroupsListView()
                }
            }
            .navigationDestination(for: Dish.self) { dish in
                DishDetailView(dish: dish)
            }
            .navigationDestination(for: DishGroup.self) { group in
                ProfileGroupDetailView(group: group)
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
                VStack(spacing: 8) {
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

                    if hasAvatar {
                        Button("Remove photo", role: .destructive) {
                            avatarJPEG = nil
                            ProfileAvatarStore.save(nil)
                            avatarPickerItem = nil
                        }
                        .font(Theme.hand(12))
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your name")
                        .font(Theme.hand(12))
                        .foregroundStyle(Theme.inkFaded)
                    TextField("e.g. Olivia", text: $displayName)
                        .font(Theme.dishName(20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.words)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tagline (optional)")
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

                statTile(title: "Cook photos", value: "\(photos.count)", systemImage: "photo.on.rectangle.angled")
                statTile(title: "Day plans", value: "\(scheduledSlots)", systemImage: "sun.max")
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
            
            Text("A personal menu, not a feed.")
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
