import SwiftUI
import SwiftData

/// A dropdown that picks an existing `DishGroup` or `nil` (= no group).
/// Tapping "+ New group…" presents an alert with a text field to create one
/// inline. The newly-created group becomes the selected value.
///
/// Use it anywhere we need to assign a group to one or many dishes.
struct GroupPicker: View {
    @EnvironmentObject private var store: DishStore
    @Query(sort: [SortDescriptor(\DishGroup.displayOrder), SortDescriptor(\DishGroup.createdAt)])
    private var groups: [DishGroup]

    @Binding var selection: DishGroup?
    var label: String = "Group"

    @State private var showingNewGroupPrompt = false
    @State private var newGroupName: String = ""
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.hand(13))
                .foregroundStyle(Theme.inkSoft)

            VStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let emoji = selection?.emoji, !emoji.isEmpty {
                            Text(emoji).font(.system(size: 16))
                        } else {
                            Image(systemName: selection?.iconName ?? "tray")
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Text(selection?.name ?? "No group")
                            .font(Theme.hand(15))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.inkFaded)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                        .background(Theme.ink.opacity(0.12))

                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selection = nil
                                isExpanded = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .foregroundStyle(Theme.inkSoft)
                                Text("No group")
                                    .font(Theme.hand(15))
                                    .foregroundStyle(selection == nil ? Theme.ink : Theme.inkSoft)
                                Spacer()
                                if selection == nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ForEach(groups) { group in
                            Divider()
                                .background(Theme.ink.opacity(0.08))
                                .padding(.horizontal, 12)

                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selection = group
                                    isExpanded = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if let emoji = group.emoji, !emoji.isEmpty {
                                        Text(emoji).font(.system(size: 16))
                                    } else {
                                        Image(systemName: group.iconName)
                                            .foregroundStyle(Theme.inkSoft)
                                    }
                                    Text(group.name)
                                        .font(Theme.hand(15))
                                        .foregroundStyle(selection?.id == group.id ? Theme.ink : Theme.inkSoft)
                                    Spacer()
                                    if selection?.id == group.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()
                            .background(Theme.ink.opacity(0.12))

                        Button {
                            newGroupName = ""
                            showingNewGroupPrompt = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("New Group…")
                                    .font(Theme.hand(15))
                                Spacer()
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color.white.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .cardStroke(cornerRadius: 10)
        }
        .alert("New Group", isPresented: $showingNewGroupPrompt) {
            TextField("e.g. Tonight's dinner", text: $newGroupName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createGroup() }
                .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Give this section of the menu a name.")
        }
    }

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = store.createGroup(name: trimmed)
        selection = group
    }
}
