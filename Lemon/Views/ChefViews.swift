import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ChefAvatarView: View {
    let chef: Chef
    var size: CGFloat = 28

    private var initial: String {
        let trimmed = chef.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        Group {
            if let data = chef.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initial)
                    .font(Theme.display(size * 0.45, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.highlight.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.ink.opacity(0.16), lineWidth: 1))
    }
}

struct ChefPicker: View {
    @Binding var selection: Chef?
    var label: String = "Chef"

    @EnvironmentObject private var store: DishStore
    @Query(sort: [SortDescriptor(\Chef.name), SortDescriptor(\Chef.createdAt)])
    private var chefs: [Chef]

    @State private var showingCreateChef = false
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
                        if let sel = selection {
                            ChefAvatarView(chef: sel, size: 24)
                        } else {
                            Image(systemName: "person.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Text(selection?.name ?? "No chef")
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
                                Image(systemName: "person.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.inkSoft)
                                Text("No chef")
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

                        ForEach(chefs) { chef in
                            Divider()
                                .background(Theme.ink.opacity(0.08))
                                .padding(.horizontal, 12)

                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selection = chef
                                    isExpanded = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    ChefAvatarView(chef: chef, size: 20)
                                    Text(chef.name)
                                        .font(Theme.hand(15))
                                        .foregroundStyle(selection?.id == chef.id ? Theme.ink : Theme.inkSoft)
                                    Spacer()
                                    if selection?.id == chef.id {
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
                            showingCreateChef = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("New Chef…")
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
        .sheet(isPresented: $showingCreateChef) {
            NavigationStack {
                ChefEditorSheet(chef: nil) { chef in
                    selection = chef
                    showingCreateChef = false
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
    }
}


struct ChefEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore

    let chef: Chef?
    var onSave: (Chef) -> Void = { _ in }

    @State private var name: String
    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var removeExistingAvatar = false

    init(chef: Chef?, onSave: @escaping (Chef) -> Void = { _ in }) {
        self.chef = chef
        self.onSave = onSave
        self._name = State(initialValue: chef?.name ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(chef == nil ? "New Chef" : "Edit Chef")
                .font(Theme.title(26, weight: .semibold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        editableAvatar
                        Image(systemName: "camera.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Theme.ink.opacity(0.55))
                            .font(.system(size: 24))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(Theme.hand(13))
                        .foregroundStyle(Theme.inkSoft)
                    TextField("Chef name", text: $name)
                        .font(Theme.dishName(18, weight: .medium))
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .cardStroke(cornerRadius: 12)
                }
            }

            if pickedImage != nil || (chef?.avatarData != nil && !removeExistingAvatar) {
                Button("Remove photo") {
                    pickedImage = nil
                    photoItem = nil
                    removeExistingAvatar = true
                }
                .font(Theme.hand(14))
                .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperBackground()
        .navigationTitle(chef == nil ? "New Chef" : "Edit Chef")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
        .task(id: photoItem) {
            await loadPickedPhoto()
        }
    }

    private var editableAvatar: some View {
        Group {
            if let pickedImage {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFill()
            } else if let data = chef?.avatarData,
                      !removeExistingAvatar,
                      let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(trimmed.first.map { String($0).uppercased() } ?? "?")
                    .font(Theme.display(24, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.highlight.opacity(0.35))
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.ink.opacity(0.16), lineWidth: 1))
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
        if let chef {
            store.updateChef(
                chef,
                name: name,
                avatarImage: pickedImage,
                removeAvatar: removeExistingAvatar
            )
            onSave(chef)
        } else if let chef = store.createChef(name: name, avatarImage: pickedImage) {
            onSave(chef)
        }
        dismiss()
    }
}
