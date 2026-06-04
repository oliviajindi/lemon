import SwiftUI
import SwiftData

/// Detailed view for a single `DishGroup`: displays group metadata (name, emoji, and description)
/// and a list of all dishes associated with this group. Allows editing the group emoji, name,
/// and description here rather than on the main page.
struct GroupDetailView: View {
    @EnvironmentObject private var store: DishStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var group: DishGroup

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftDescription = ""
    @State private var draftEmoji: String? = nil
    @State private var showingEmojiPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header block
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 72, height: 72)
                            .cardStroke(cornerRadius: 36)
                            .shadow(color: Theme.paperShadow, radius: 4, x: 0, y: 2)

                        if isEditing {
                            Button {
                                showingEmojiPicker = true
                            } label: {
                                ZStack {
                                    if let emoji = draftEmoji, !emoji.isEmpty {
                                        Text(emoji)
                                            .font(.system(size: 36))
                                    } else {
                                        Image(systemName: group.iconName)
                                            .font(.system(size: 26, weight: .light))
                                            .foregroundStyle(Theme.ink)
                                    }
                                    
                                    // Edit badge
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(Theme.accent)
                                                .background(Circle().fill(Theme.paper))
                                                .offset(x: 2, y: 2)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 72, height: 72)
                        } else {
                            if let emoji = group.emoji, !emoji.isEmpty {
                                Text(emoji)
                                    .font(.system(size: 36))
                            } else {
                                Image(systemName: group.iconName)
                                    .font(.system(size: 26, weight: .light))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    .padding(.top, 10)

                    if isEditing {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Group Name")
                                .font(Theme.hand(13))
                                .foregroundStyle(Theme.inkSoft)
                            TextField("e.g. Sunday Brunch", text: $draftName)
                                .font(Theme.display(17))
                                .padding(12)
                                .background(Color.white.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .cardStroke(cornerRadius: 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(Theme.hand(13))
                                .foregroundStyle(Theme.inkSoft)
                            TextField("Describe this group…", text: $draftDescription, axis: .vertical)
                                .font(Theme.serif(15))
                                .lineLimit(1...3)
                                .padding(12)
                                .background(Color.white.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .cardStroke(cornerRadius: 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("Delete Group")
                            }
                            .font(Theme.serif(15, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        .padding(.horizontal, 8)
                    } else {
                        // View mode
                        Text(group.name)
                            .font(Theme.groupName(28))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)

                        if let desc = group.groupDescription, !desc.isEmpty {
                            Text(desc)
                                .font(Theme.serif(15).italic())
                                .foregroundStyle(Theme.inkSoft)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        } else {
                            Text("No description yet.")
                                .font(Theme.serif(13).italic())
                                .foregroundStyle(Theme.inkFaded)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if !isEditing {
                    // Search bar below the title / description part
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.inkFaded)
                        
                        TextField("Search dishes in this group…", text: $searchText)
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
                    .padding(.horizontal, 8)
                }

                DottedDivider()
                    .padding(.vertical, 4)

                // Dishes Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Dishes in this Group")
                            .font(Theme.display(20))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(group.dishes.count) total")
                            .font(Theme.hand(13))
                            .foregroundStyle(Theme.inkFaded)
                    }

                    if group.dishes.isEmpty {
                        Text("No dishes belong to this group yet.")
                            .font(Theme.serif(14).italic())
                            .foregroundStyle(Theme.inkFaded)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        let dishesToShow = filteredDishes
                        if dishesToShow.isEmpty {
                            Text("No dishes match \"\(searchText)\".")
                                .font(Theme.serif(14).italic())
                                .foregroundStyle(Theme.inkFaded)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(dishesToShow) { dish in
                                    NavigationLink(value: dish) {
                                        DishCardView(dish: dish)
                                    }
                                    .buttonStyle(.plain)

                                    if dish != dishesToShow.last {
                                        DottedDivider()
                                            .padding(.horizontal, 4)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 60)
            }
            .padding(20)
        }
        .paperBackground()
        .navigationTitle(isEditing ? "Edit Group" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Done") {
                        saveChanges()
                    }
                    .font(Theme.display(16, weight: .semibold))
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        enterEditing()
                    }
                    .font(Theme.display(16, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerSheet(currentEmoji: draftEmoji ?? "") { emoji in
                draftEmoji = emoji
                showingEmojiPicker = false
            } onClear: {
                draftEmoji = nil
                showingEmojiPicker = false
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Delete Group?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteGroup()
            }
        } message: {
            Text("Are you sure you want to delete this group? The dishes won't be deleted.")
        }
    }

    private func enterEditing() {
        draftName = group.name
        draftDescription = group.groupDescription ?? ""
        draftEmoji = group.emoji
        isEditing = true
    }

    private func saveChanges() {
        store.updateGroup(group, name: draftName, emoji: draftEmoji)
        store.updateGroupDescription(group, description: draftDescription.isEmpty ? nil : draftDescription)
        isEditing = false
    }

    private func deleteGroup() {
        store.deleteGroup(group)
        dismiss()
    }

    private var filteredDishes: [Dish] {
        let sorted = group.dishes.sorted(by: { $0.createdAt > $1.createdAt })
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return sorted
        }
        return sorted.filter { $0.name.lowercased().contains(query) }
    }
}
