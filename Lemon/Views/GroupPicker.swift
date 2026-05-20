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

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                Label("No group", systemImage: selection == nil ? "checkmark" : "circle")
            }

            if !groups.isEmpty {
                Divider()
                ForEach(groups) { group in
                    Button {
                        selection = group
                    } label: {
                        // The system Menu can't render arbitrary Text labels
                        // with emoji prefixes reliably across iOS versions, so
                        // we fold the emoji into the title string and keep the
                        // selection checkmark as the trailing system image.
                        let prefix = (group.emoji?.isEmpty == false)
                            ? "\(group.emoji!) "
                            : ""
                        if selection?.id == group.id {
                            Label("\(prefix)\(group.name)", systemImage: "checkmark")
                        } else if group.emoji?.isEmpty == false {
                            Text("\(prefix)\(group.name)")
                        } else {
                            Label(group.name, systemImage: group.iconName)
                        }
                    }
                }
            }

            Divider()
            Button {
                newGroupName = ""
                showingNewGroupPrompt = true
            } label: {
                Label("New Group…", systemImage: "plus")
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.6))
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
