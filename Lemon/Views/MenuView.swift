import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// How dishes are rendered inside each menu section.
///
/// - `cards`:   full hand-drawn illustration + name + description (default).
/// - `compact`: just a bulleted dish name — a printed-menu reading view.
enum MenuLayout: String, CaseIterable, Identifiable {
    case cards
    case compact

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .cards:   return "rectangle.grid.1x2"
        case .compact: return "list.bullet"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cards:   return "Card view"
        case .compact: return "Compact list view"
        }
    }
}

/// The "menu" — a printed-menu layout. Dishes are grouped under user-defined
/// sections (`DishGroup`); dishes without a group fall into "Other Dishes".
/// Tap any section header to collapse / expand its dishes. Collapsed state is
/// persisted across launches in `UserDefaults`.
struct MenuView: View {
    @EnvironmentObject private var store: DishStore

    @Query(sort: \Dish.createdAt, order: .reverse)
    private var dishes: [Dish]

    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]

    @AppStorage("Lemon.menuLayout") private var layout: MenuLayout = .cards

    // The user-customizable menu masthead. Defaults keep the original copy
    // so existing installs aren't suddenly blank.
    @AppStorage("Lemon.menuTitle")
    private var menuTitle: String = "My Menu"
    @AppStorage("Lemon.menuSubtitle")
    private var menuSubtitle: String = "a personal logbook of what I cook and eat"

    @State private var newGroupName: String = ""
    @State private var newGroupEmoji: String = ""
    @State private var isAddingGroup = false
    @State private var showingNewGroupEmojiPicker = false
    @State private var addingDishToGroup: DishGroup?
    @State private var isAddingDish = false
    @State private var path = NavigationPath()

    /// IDs of collapsed sections. We use the group's own UUID for real groups
    /// and `Self.ungroupedSectionID` for the "Other Dishes" pseudo-section.
    @State private var collapsedIDs: Set<UUID> = Self.loadCollapsedIDs()
    @State private var preDragCollapsedIDs: Set<UUID> = []
    
    @State private var isEditingGroups = false
    @State private var preEditCollapsedIDs: Set<UUID> = []
    @State private var draggedGroup: DishGroup? = nil
    @State private var isDraggingDish = false
    @State private var searchText = ""
    @State private var isSearchExpanded = false

    /// Sentinel ID representing the "Other Dishes" / "All Dishes" section so
    /// it can participate in the same collapse machinery as real groups.
    private static let ungroupedSectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let collapsedKey = "Lemon.collapsedSectionIDs"

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                Theme.paper.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                if dishes.isEmpty && groups.isEmpty {
                    EmptyMenuView()
                } else {
                    ScrollView {
                        VStack(spacing: isEditingGroups ? 8 : 4) {
                            MenuHeader(
                                title: $menuTitle,
                                subtitle: $menuSubtitle,
                                isEditing: $isEditingGroups
                            )
                            .padding(.bottom, isEditingGroups ? 0 : 8)

                            if isEditingGroups {
                                HStack {
                                    Text("Drag groups to reorder")
                                        .font(Theme.serif(13).italic())
                                        .foregroundStyle(Theme.inkSoft)
                                    
                                    Spacer()
                                    
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            let trimmedTitle = menuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                            menuTitle = trimmedTitle.isEmpty ? "My Menu" : trimmedTitle
                                            menuSubtitle = menuSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                            isEditingGroups = false
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                            Text("Save")
                                                .font(Theme.serif(14, weight: .semibold))
                                        }
                                        .foregroundStyle(Theme.paper)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Theme.ink)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            } else {
                                // Custom Toolbar with search, edit, and layout view buttons
                                HStack(spacing: 12) {
                                    if isSearchExpanded {
                                        // Search bar
                                        HStack(spacing: 8) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(Theme.inkFaded)
                                            
                                            TextField("Search dishes…", text: $searchText)
                                                .font(Theme.serif(14))
                                                .textInputAutocapitalization(.never)
                                                .submitLabel(.search)
                                            
                                            Button {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                                    searchText = ""
                                                    isSearchExpanded = false
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(Theme.inkSoft)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(Color.white.opacity(0.55))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .cardStroke(cornerRadius: 12, inkOpacity: 0.15)
                                    } else {
                                        Spacer()
                                        
                                        // Collapsed Search icon
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                                isSearchExpanded = true
                                            }
                                        } label: {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Theme.ink)
                                                .frame(width: 36, height: 36)
                                                .background(Color.white.opacity(0.55))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .cardStroke(cornerRadius: 12, inkOpacity: 0.15)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Search dishes")
                                    }
                                    
                                    // Edit button next to search
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            isEditingGroups = true
                                        }
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                            .frame(width: 36, height: 36)
                                            .background(Color.white.opacity(0.55))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .cardStroke(cornerRadius: 12, inkOpacity: 0.15)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Edit menu title and description")
                                    
                                    // Layout switch Picker
                                    Picker("", selection: $layout) {
                                        ForEach(MenuLayout.allCases) { mode in
                                            Image(systemName: mode.iconName)
                                                .accessibilityLabel(mode.accessibilityLabel)
                                                .tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    .controlSize(.small)
                                    .frame(width: 90)
                                }
                                .padding(.bottom, 12)
                            }

                            if !searchText.isEmpty && filteredDishes.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 42, weight: .light))
                                        .foregroundStyle(Theme.inkFaded)
                                    Text("No dishes match \"\(searchText)\"")
                                        .font(Theme.serif(16).italic())
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                            } else {
                                ForEach(groups) { group in
                                    let groupDishes = dishesIn(group)
                                    if !groupDishes.isEmpty || searchText.isEmpty {
                                        MenuSection(
                                            group: group,
                                            dishes: groupDishes,
                                            layout: layout,
                                            isCollapsed: collapsedIDs.contains(group.id),
                                            isEditingGroups: isEditingGroups,
                                            isDraggingDish: isDraggingDish,
                                            draggedGroup: $draggedGroup,
                                            groups: groups,
                                            onToggle: { toggleCollapsed(group.id) },
                                            onAdd: { addingDishToGroup = group },
                                            onDelete: { store.deleteGroup(group) },
                                            onDragStart: handleDragStart,
                                            onDropDish: { dish in
                                                store.setGroup(group, for: dish)
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                    var nextCollapsed = preDragCollapsedIDs
                                                    nextCollapsed.remove(group.id)
                                                    collapsedIDs = nextCollapsed
                                                }
                                                isDraggingDish = false
                                            }
                                        )
                                    }
                                }

                                let ungrouped = filteredDishes.filter { $0.group == nil }
                                if !ungrouped.isEmpty {
                                    MenuSection(
                                        title: groups.isEmpty ? "All Dishes" : "Other Dishes",
                                        subtitle: countLabel(ungrouped.count),
                                        iconName: "tray",
                                        canEdit: false,
                                        dishes: ungrouped,
                                        layout: layout,
                                        isCollapsed: collapsedIDs.contains(Self.ungroupedSectionID),
                                        isEditingGroups: isEditingGroups,
                                        isDraggingDish: isDraggingDish,
                                        draggedGroup: nil,
                                        groups: [],
                                        onToggle: { toggleCollapsed(Self.ungroupedSectionID) },
                                        onAdd: nil,
                                        onDelete: {},
                                        onDragStart: handleDragStart,
                                        onDropDish: { dish in
                                            store.setGroup(nil, for: dish)
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                var nextCollapsed = preDragCollapsedIDs
                                                nextCollapsed.remove(Self.ungroupedSectionID)
                                                collapsedIDs = nextCollapsed
                                            }
                                            isDraggingDish = false
                                        }
                                    )
                                }
                            }

                            NewGroupEditor(
                                name: $newGroupName,
                                emoji: $newGroupEmoji,
                                isAdding: $isAddingGroup,
                                onTapEmoji: { showingNewGroupEmojiPicker = true },
                                onCreate: createGroup
                            )
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                        .background(
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                        )
                    }
                    .paperBackground()
                }

                addDishFAB
                    .padding(.trailing, 22)
                    .padding(.bottom, 28)
            }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    collapsedIDs = preDragCollapsedIDs
                }
                isDraggingDish = false
                return true
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Dish.self) { DishDetailView(dish: $0) }
            .navigationDestination(for: DishGroup.self) { GroupDetailView(group: $0) }
            .navigationDestination(for: Chef.self) { ChefDishesView(chef: $0) }
            .sheet(item: $addingDishToGroup) { group in
                RecipeAssistantSheet(mode: .creator(initialGroup: group), onSaved: { addedDish in
                    addingDishToGroup = nil
                    path.append(addedDish)
                })
            }
            .sheet(isPresented: $isAddingDish) {
                RecipeAssistantSheet(mode: .creator(), onSaved: { addedDish in
                    isAddingDish = false
                    path.append(addedDish)
                })
            }
            .sheet(isPresented: $showingNewGroupEmojiPicker) {
                EmojiPickerSheet(currentEmoji: newGroupEmoji) { emoji in
                    newGroupEmoji = emoji
                    showingNewGroupEmojiPicker = false
                } onClear: {
                    newGroupEmoji = ""
                    showingNewGroupEmojiPicker = false
                }
                .presentationDetents([.medium, .large])
            }
            .onChange(of: isEditingGroups) { _, newValue in
                if newValue {
                    searchText = ""
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if newValue {
                        preEditCollapsedIDs = collapsedIDs
                        collapsedIDs = Set(groups.map(\.id) + [Self.ungroupedSectionID])
                    } else {
                        collapsedIDs = preEditCollapsedIDs
                    }
                }
            }
        }
    }

    /// Floating "+" pinned to the bottom-right corner. Tapping it opens
    /// `AddDishView` with no preselected group, so the dish lands in
    /// "Other Dishes" (or wherever the user picks during the add flow).
    private var addDishFAB: some View {
        Button {
            isAddingDish = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.paper)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(Theme.ink)
                )
                .overlay(
                    Circle()
                        .stroke(Theme.paper.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Theme.ink.opacity(0.22), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Dish")
    }

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

    private func dishesIn(_ group: DishGroup) -> [Dish] {
        filteredDishes.filter { $0.group?.id == group.id }
    }

    private func countLabel(_ n: Int) -> String {
        n == 1 ? "1 Dish" : "\(n) Dishes"
    }

    private func toggleCollapsed(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if collapsedIDs.contains(id) {
                collapsedIDs.remove(id)
            } else {
                collapsedIDs.insert(id)
            }
        }
        Self.saveCollapsedIDs(collapsedIDs)
    }

    private func handleDragStart(for dish: Dish) {
        isDraggingDish = true
        preDragCollapsedIDs = collapsedIDs
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            var nextCollapsed = Set(groups.map(\.id) + [Self.ungroupedSectionID])
            if let sourceGroup = dish.group {
                nextCollapsed.remove(sourceGroup.id)
            } else {
                nextCollapsed.remove(Self.ungroupedSectionID)
            }
            collapsedIDs = nextCollapsed
        }
    }

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isAddingGroup = false
            return
        }
        _ = store.createGroup(name: name, emoji: newGroupEmoji)
        newGroupName = ""
        newGroupEmoji = ""
        isAddingGroup = false
    }

    // MARK: - Persistence

    private static func loadCollapsedIDs() -> Set<UUID> {
        guard let raw = UserDefaults.standard.array(forKey: collapsedKey) as? [String] else {
            return []
        }
        return Set(raw.compactMap { UUID(uuidString: $0) })
    }

    private static func saveCollapsedIDs(_ ids: Set<UUID>) {
        let strings = ids.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: collapsedKey)
    }
}

// MARK: - Header

private struct MenuHeader: View {
    @Binding var title: String
    @Binding var subtitle: String
    @Binding var isEditing: Bool
    @FocusState private var focusedField: Field?

    private enum Field { case title, subtitle }

    private var resolvedTitle: String { title.isEmpty ? "My Menu" : title }

    var body: some View {
        VStack(spacing: 8) {
            if isEditing {
                VStack(spacing: 8) {
                    TextField("My Menu", text: $title)
                        .font(Theme.title(32))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .subtitle }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                        )

                    TextField("a personal logbook of what I cook and eat", text: $subtitle, axis: .vertical)
                        .font(.system(size: 14, weight: .regular, design: .default).italic())
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .subtitle)
                        .submitLabel(.done)
                        .onSubmit(finishEditing)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.ink.opacity(0.18), lineWidth: 1)
                        )
                }
            } else {
                Text(resolvedTitle)
                    .font(Theme.title(40))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .default).italic())
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 6) {
                Rectangle()
                    .fill(Theme.ink.opacity(0.18))
                    .frame(width: 36, height: 1)
                Circle()
                    .fill(Theme.ink.opacity(0.18))
                    .frame(width: 4, height: 4)
                Rectangle()
                    .fill(Theme.ink.opacity(0.18))
                    .frame(width: 36, height: 1)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.top, 58)
        .accessibilityElement(children: .contain)
    }

    private func finishEditing() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmedTitle.isEmpty ? "My Menu" : trimmedTitle
        subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        focusedField = nil
        isEditing = false
    }
}

// MARK: - Sections

private struct MenuSection: View {
    @EnvironmentObject private var store: DishStore

    var group: DishGroup? = nil
    var title: String? = nil
    var subtitle: String? = nil
    var iconName: String? = nil
    var canEdit: Bool = true
    let dishes: [Dish]
    let layout: MenuLayout
    let isCollapsed: Bool
    var isEditingGroups: Bool = false
    var isDraggingDish: Bool = false
    var draggedGroup: Binding<DishGroup?>? = nil
    var groups: [DishGroup] = []
    let onToggle: () -> Void
    let onAdd: (() -> Void)?
    let onDelete: () -> Void
    var onDragStart: ((Dish) -> Void)? = nil
    var onDropDish: ((Dish) -> Void)? = nil

    @State private var pendingAction: SectionAction?
    @State private var isTargeted = false

    /// The ellipsis-menu action awaiting a paper-styled sheet response.
    fileprivate enum SectionAction: Int, Identifiable {
        case rename
        case delete
        var id: Int { rawValue }
    }

    private var resolvedTitle: String { title ?? group?.name ?? "" }
    private var resolvedIcon: String  { iconName ?? group?.iconName ?? "folder" }
    private var resolvedSubtitle: String {
        if let subtitle { return subtitle }
        return dishes.count == 1 ? "1 Dish" : "\(dishes.count) Dishes"
    }

    /// Returns the user-picked emoji if one is set; otherwise `nil` so we fall
    /// back to `resolvedIcon` (an SF Symbol).
    private var resolvedEmoji: String? {
        guard let raw = group?.emoji?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: the logo is editable on its own; the title row toggles
            // collapse/expand. Renaming and deleting live in the ellipsis menu
            // so a plain tap never opens an editor by accident.
            Group {
                if isEditingGroups, let group = group {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.trailing, 4)
                            .offset(x: -10)

                        groupLogo
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(resolvedTitle)
                                .font(Theme.groupName(16))
                                .foregroundStyle(Theme.ink)
                            Text(resolvedSubtitle)
                                .font(Theme.hand(12))
                                .foregroundStyle(Theme.inkFaded)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(6)
                    .background(Theme.paper)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .onDrag {
                        if let draggedGroup = draggedGroup {
                            draggedGroup.wrappedValue = group
                        }
                        return NSItemProvider(object: group.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: GroupDropDelegate(
                        item: group,
                        draggedItem: draggedGroup ?? .constant(nil),
                        groups: groups,
                        store: store
                    ))
                } else {
                    HStack(spacing: 8) {
                        Button(action: onToggle) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isCollapsed ? "Expand \(resolvedTitle)" : "Collapse \(resolvedTitle)")
                        .offset(x: -10)

                        if let group {
                            NavigationLink(value: group) {
                                HStack(spacing: 8) {
                                    groupLogo
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(resolvedTitle)
                                            .font(Theme.groupName(21))
                                            .foregroundStyle(Theme.ink)
                                        Text(resolvedSubtitle)
                                            .font(Theme.hand(14))
                                            .foregroundStyle(Theme.inkFaded)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: onToggle) {
                                HStack(spacing: 8) {
                                    groupLogo
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(resolvedTitle)
                                            .font(Theme.groupName(isEditingGroups ? 16 : 21))
                                            .foregroundStyle(Theme.ink)
                                        Text(resolvedSubtitle)
                                            .font(Theme.hand(isEditingGroups ? 12 : 14))
                                            .foregroundStyle(Theme.inkFaded)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if let onAdd {
                            Button(action: onAdd) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add dish to \(resolvedTitle)")
                        }
                    }
                    .padding(6)
                    .background(isTargeted ? Theme.highlight.opacity(0.18) : Theme.paper)
                    .cornerRadius(8)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isTargeted)
                    .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { string, error in
                            if let uuidString = string as? String,
                               let uuid = UUID(uuidString: uuidString) {
                                DispatchQueue.main.async {
                                    if let dish = store.allDishes().first(where: { $0.id == uuid }) {
                                        onDropDish?(dish)
                                    }
                                }
                            }
                        }
                        return true
                    }
                }
            }
            .zIndex(1)

            // Separator + dishes form a single accordion body. Gating them
            // through one `if !isCollapsed` means SwiftUI removes them as a
            // single transitioning unit, so the divider and rows slide up
            // together instead of as two disconnected ghosts.
            //
            // Crucially: the "expanded breathing room" (extra bottom padding)
            // lives *inside* this conditional, not on the outer modifier
            // chain. That way the header above never sees an animated
            // padding value — the spring can't bounce a number that
            // doesn't change.
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    if !isEditingGroups {
                        Rectangle()
                            .fill(Theme.ink)
                            .frame(height: 1)
                            .opacity(0.6)
                    }

                    if dishes.isEmpty {
                        Text("No dishes yet — add one from the + tab.")
                            .font(Theme.serif(13).italic())
                            .foregroundStyle(Theme.inkFaded)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(dishes) { dish in
                                NavigationLink(value: dish) {
                                    if layout == .cards {
                                        DishCardView(dish: dish, isCompactStyle: false)
                                    } else {
                                        CompactDishRow(dish: dish, isCompactStyle: false)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.deleteDish(dish)
                                    } label: { Label("Remove", systemImage: "trash") }
                                }
                                .onDrag {
                                    if let onDragStart {
                                        onDragStart(dish)
                                    }
                                    return NSItemProvider(object: dish.id.uuidString as NSString)
                                }
                                if dish != dishes.last, layout == .cards {
                                    DottedDivider().padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, isEditingGroups ? 0 : 14)
                .zIndex(0)
                .transition(.opacity)
            }
        }
        // Keep the outer paddings CONSTANT relative to `isCollapsed`. The
        // header's Y origin is therefore a fixed offset from the section's
        // top edge — the spring has no padding value to bounce, so the
        // header can't jitter.
        .padding(.vertical, isEditingGroups ? 2 : 8)
        .padding(.horizontal, isEditingGroups ? 0 : 8)
        // Clip on the OUTER section — this frame keeps real geometry
        // during the animation (header + padding), so the transition
        // ghost is masked against the section's real bounds rather than
        // a 0pt inner wrapper.
        .clipped()
        .sheet(item: $pendingAction) { action in
            actionSheet(for: action)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func actionSheet(for action: SectionAction) -> some View {
        switch action {
        case .rename:
            RenameGroupSheet(currentName: resolvedTitle) { newName in
                if let group {
                    store.renameGroup(group, to: newName)
                }
                pendingAction = nil
            } onCancel: {
                pendingAction = nil
            }
        case .delete:
            DeleteGroupSheet(groupName: resolvedTitle) {
                onDelete()
                pendingAction = nil
            } onCancel: {
                pendingAction = nil
            }
        }
    }

    @ViewBuilder
    private var groupLogo: some View {
        if let emoji = resolvedEmoji {
            Text(emoji)
                .font(.system(size: isEditingGroups ? 16 : 22))
                .frame(width: isEditingGroups ? 24 : 32, height: isEditingGroups ? 22 : 28)
        } else {
            Image(systemName: resolvedIcon)
                .font(.system(size: isEditingGroups ? 13 : 16))
                .foregroundStyle(Theme.ink)
                .frame(width: isEditingGroups ? 24 : 32, height: isEditingGroups ? 22 : 28)
        }
    }
}

// MARK: - Compact row

/// The one-line "just the name" row used by `MenuLayout.compact`. Matches the
/// printed-menu aesthetic: a bullet, the dish name, and a chevron hint that
/// the row drills into the detail view.
private struct CompactDishRow: View {
    let dish: Dish
    var isCompactStyle: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("•")
                .font(Theme.serif(isCompactStyle ? 14 : 20))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 8, alignment: .leading)
            Text(dish.name)
                .font(Theme.menuDishName(isCompactStyle ? 11 : 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: isCompactStyle ? 9 : 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaded)
        }
        .padding(.vertical, isCompactStyle ? 4 : 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

private struct NewGroupEditor: View {
    @Binding var name: String
    @Binding var emoji: String
    @Binding var isAdding: Bool
    let onTapEmoji: () -> Void
    let onCreate: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        if isAdding {
            HStack(spacing: 10) {
                Button {
                    onTapEmoji()
                } label: {
                    Text(emoji.isEmpty ? "🍋" : emoji)
                        .font(.system(size: 18))
                        .frame(width: 42)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.45))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .leading)))

                TextField("New group name", text: $name)
                    .font(Theme.hand(15))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(onCreate)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.45))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                Button(action: onCreate) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.32))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
            )
        } else {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isAdding = true
                }
                nameFocused = true
            } label: {
                HStack(spacing: 10) {
                    Text("New Group")
                        .font(Theme.hand(15))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 9)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.32))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentEmoji: String
    let onSelect: (String) -> Void
    let onClear: () -> Void

    @State private var searchText = ""
    @State private var typedEmoji = ""

    private var filteredOptions: [EmojiOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.options }
        return Self.options.filter { option in
            option.emoji.contains(query) ||
            option.keywords.contains { $0.contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type an emoji")
                        .font(Theme.hand(13))
                        .foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 10) {
                        TextField("🍋", text: $typedEmoji)
                            .font(.system(size: 28))
                            .multilineTextAlignment(.center)
                            .frame(width: 64)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.ink.opacity(0.18), lineWidth: 1)
                            )
                            .onChange(of: typedEmoji) { _, newValue in
                                if let first = newValue.first, newValue.count > 1 {
                                    typedEmoji = String(first)
                                }
                            }

                        Button("Use") {
                            if let emoji = typedEmoji.trimmingCharacters(in: .whitespacesAndNewlines).first {
                                onSelect(String(emoji))
                            }
                        }
                        .font(Theme.hand(14))
                        .disabled(typedEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()
                    }
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(filteredOptions) { option in
                            Button {
                                onSelect(option.emoji)
                            } label: {
                                Text(option.emoji)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        option.emoji == currentEmoji
                                            ? Theme.highlight.opacity(0.35)
                                            : Color.white.opacity(0.45)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.label)
                        }
                    }
                }
            }
            .padding(18)
            .paperBackground()
            .searchable(text: $searchText, prompt: "Search emoji")
            .navigationTitle("Group Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { onClear() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                typedEmoji = currentEmoji
            }
        }
    }

    private static let options: [EmojiOption] = [
        .init("🍋", "lemon citrus fruit yellow"),
        .init("🍎", "apple fruit red"),
        .init("🍓", "strawberry fruit berry"),
        .init("🍞", "bread baking toast"),
        .init("🥐", "croissant pastry breakfast"),
        .init("🥯", "bagel breakfast bread"),
        .init("🥞", "pancakes breakfast brunch"),
        .init("🥗", "salad vegetable healthy"),
        .init("🍜", "ramen noodles soup"),
        .init("🍲", "pot stew soup"),
        .init("🍝", "pasta spaghetti noodles"),
        .init("🍛", "curry rice"),
        .init("🍚", "rice bowl"),
        .init("🍣", "sushi fish japanese"),
        .init("🍤", "shrimp seafood"),
        .init("🐟", "fish seafood"),
        .init("🥩", "steak beef meat"),
        .init("🍗", "chicken meat"),
        .init("🍔", "burger sandwich"),
        .init("🌮", "taco mexican"),
        .init("🌯", "burrito wrap"),
        .init("🍕", "pizza"),
        .init("🥟", "dumpling"),
        .init("🍰", "cake dessert"),
        .init("🧁", "cupcake dessert"),
        .init("🍪", "cookie dessert"),
        .init("🍵", "tea matcha drink"),
        .init("☕️", "coffee drink"),
        .init("🍷", "wine drink"),
        .init("🍽️", "plate dinner meal"),
        .init("⭐️", "favorite star"),
        .init("❤️", "heart favorite")
    ]
}

struct EmojiOption: Identifiable {
    let emoji: String
    let keywords: [String]
    var id: String { emoji }
    var label: String { keywords.joined(separator: ", ") }

    init(_ emoji: String, _ keywords: String) {
        self.emoji = emoji
        self.keywords = keywords.split(separator: " ").map(String.init)
    }
}

// MARK: - Empty state

private struct EmptyMenuView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Theme.inkFaded)
            Text("Your menu is empty")
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
            Text("Tap the + button at the bottom right to add your first dish.\nType the name — the AI will draw it.")
                .font(Theme.serif(15).italic())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 32)
        }
        .paperBackground()
    }
}

// MARK: - Group action sheets

/// Rename a group via a paper-styled bottom sheet — no native iOS alert. The
/// look matches the rest of the app (cream paper, sketch borders, serif copy).
private struct RenameGroupSheet: View {
    let currentName: String
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var draftName: String
    @FocusState private var nameFocused: Bool

    init(currentName: String,
         onRename: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.currentName = currentName
        self.onRename = onRename
        self.onCancel = onCancel
        self._draftName = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RENAME GROUP")
                    .font(Theme.serif(12, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.inkFaded)
                Text(currentName)
                    .font(Theme.groupName(24))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            TextField("Group name", text: $draftName)
                .font(Theme.serif(18))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                )
                .onSubmit(save)

            HStack(spacing: 12) {
                PaperSheetButton(title: "Cancel", style: .secondary, action: onCancel)
                PaperSheetButton(
                    title: "Save",
                    style: .primary,
                    isDisabled: trimmedName.isEmpty,
                    action: save
                )
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperBackground()
        .onAppear { nameFocused = true }
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        onRename(name)
    }
}

/// Confirm deleting a group via the same paper-style aesthetic. Dishes inside
/// the group are kept (they fall back into "Other Dishes" via `.nullify`).
private struct DeleteGroupSheet: View {
    let groupName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DELETE GROUP")
                    .font(Theme.serif(12, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.accent)
                Text(groupName)
                    .font(Theme.groupName(24))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            Text("The group will be removed. Its dishes stay in your menu and move to Other Dishes — they aren't deleted.")
                .font(Theme.serif(15))
                .foregroundStyle(Theme.inkSoft)

            HStack(spacing: 12) {
                PaperSheetButton(title: "Keep", style: .secondary, action: onCancel)
                PaperSheetButton(title: "Delete", style: .destructive, action: onConfirm)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperBackground()
    }
}

/// Pill button used by the paper-styled group sheets. Three visual styles:
/// `.primary` (filled ink), `.secondary` (sketched outline), `.destructive`
/// (filled accent red). Kept inline so the sheets stay self-contained.
private struct PaperSheetButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let style: Style
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.serif(15, weight: .semibold))
                .tracking(3)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(background)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive: return Theme.paper
        case .secondary:             return Theme.ink
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 999).fill(Theme.ink)
        case .destructive:
            RoundedRectangle(cornerRadius: 999).fill(Theme.accent)
        case .secondary:
            RoundedRectangle(cornerRadius: 999)
                .strokeBorder(Theme.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.2))
        }
    }
}

// MARK: - Group Drag and Drop Reordering Delegate

struct GroupDropDelegate: DropDelegate {
    let item: DishGroup
    @Binding var draggedItem: DishGroup?
    let groups: [DishGroup]
    let store: DishStore

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != item.id else { return }
        
        if let targetIndex = groups.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                store.moveGroup(dragged, to: targetIndex)
            }
        }
    }
}

#Preview {
    MenuView()
        .environmentObject(AppConfig.shared)
        .environmentObject(DishStore())
}
