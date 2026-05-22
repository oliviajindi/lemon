import SwiftUI
import PhotosUI
import SwiftData
import UIKit
import Photos

/// Detail view for a single dish: illustration, metadata, recipe, and photo log.
/// Name/description and recipe each have their own edit control; tags and group
/// are edited inline on this page.
struct DishDetailView: View {
    @EnvironmentObject private var store: DishStore
    @EnvironmentObject private var config: AppConfig
    @Environment(\.dismiss) private var dismiss
    @Bindable var dish: Dish

    @State private var confirmingDelete = false
    @State private var showingDetailsEditor = false
    @State private var showingRecipeEditor = false
    @State private var groupSelection: DishGroup?

    @State private var replacePhotoItem: PhotosPickerItem?
    @State private var showingRedrawSheet = false
    @State private var redrawNotes = ""
    @State private var isIllustrationWorking = false
    @State private var infoAlert: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                illustration

                headerBlock

                DishTagEditor(dish: dish)
                    .padding(.top, 6)

                groupBlock
                    .padding(.top, 8)

                RecipeReadOnlyCard(dish: dish, onEdit: { showingRecipeEditor = true })
                    .padding(.top, 8)

                PhotoLogCard(dish: dish)
            }
            .padding(20)
        }
        .paperBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .fullScreenCover(isPresented: $showingDetailsEditor) {
            DishEditView(dish: dish, scope: .detailsOnly)
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showingRecipeEditor) {
            DishEditView(dish: dish, scope: .recipeOnly)
                .environmentObject(store)
        }
        .confirmationDialog("Remove this dish?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.deleteDish(dish)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingRedrawSheet) {
            redrawIllustrationSheet
        }
        .alert("Notice", isPresented: Binding(
            get: { infoAlert != nil },
            set: { if !$0 { infoAlert = nil } }
        )) {
            Button("OK", role: .cancel) { infoAlert = nil }
        } message: {
            Text(infoAlert ?? "")
        }
        .onAppear {
            groupSelection = dish.group
        }
        .onChange(of: dish.group) { _, newValue in
            groupSelection = newValue
        }
    }

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            readOnlyHeader
                .frame(maxWidth: .infinity)
            Button {
                showingDetailsEditor = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel("Edit name and description")
        }
    }

    private var groupBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group")
                .font(Theme.hand(13))
                .foregroundStyle(Theme.inkSoft)
            GroupPicker(selection: $groupSelection)
                .onChange(of: groupSelection) { _, newValue in
                    store.setGroup(newValue, for: dish)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var redrawIllustrationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Optional: describe how the new drawing should look — palette, angle, props, style.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkSoft)
                TextField(
                    "e.g. top-down view, more watercolor…",
                    text: $redrawNotes,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .font(Theme.serif(15))
                .padding(12)
                .background(Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .cardStroke(cornerRadius: 12)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .paperBackground()
            .navigationTitle("Redraw illustration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRedrawSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Redraw") {
                        showingRedrawSheet = false
                        Task { await performAIRedraw() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isIllustrationWorking)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var readOnlyHeader: some View {
        VStack(spacing: 6) {
            Text(dish.name)
                .font(Theme.title(26, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !dish.dishDescription.isEmpty {
                Text(dish.dishDescription)
                    .font(.system(size: 16, weight: .regular, design: .default).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            // Chef attribution badge
            if !dish.chefName.isEmpty {
                chefBadge
                    .padding(.top, 4)
            }
            Text("Added \(dish.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.hand(13))
                .foregroundStyle(Theme.inkFaded)
                .padding(.top, 2)
        }
    }

    /// A compact pill showing the chef's avatar and name.
    private var chefBadge: some View {
        HStack(spacing: 7) {
            // Avatar circle
            Group {
                if let data = dish.chefAvatarData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 26, height: 26)
                }
            }
            .overlay(Circle().stroke(Theme.ink.opacity(0.18), lineWidth: 1))

            Text(dish.chefName)
                .font(Theme.hand(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.45))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.ink.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var illustration: some View {
        ZStack(alignment: .topTrailing) {
            illustrationImage
            illustrationMenu
                .padding(10)
        }
        .overlay {
            if isIllustrationWorking {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.22))
                VStack(spacing: 8) {
                    ProgressView()
                    Text(store.statusMessage ?? "Working…")
                        .font(Theme.hand(13))
                        .foregroundStyle(Theme.paper)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
        }
        .onChange(of: replacePhotoItem) { _, item in
            Task { await replaceIllustration(with: item) }
        }
    }

    /// The illustration (or empty placeholder); separate from chrome so layout stays simple.
    @ViewBuilder
    private var illustrationImage: some View {
        if let data = dish.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .cardStroke(cornerRadius: 18)
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.5))
                .frame(height: 220)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(Theme.inkFaded)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .cardStroke(cornerRadius: 18)
        }
    }

    private var illustrationMenu: some View {
        Menu {
            if dish.imageData != nil {
                Button {
                    Task { await saveIllustrationToPhotos() }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }
            PhotosPicker(
                selection: $replacePhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Replace with photo", systemImage: "photo.on.rectangle")
            }
            Button {
                redrawNotes = ""
                showingRedrawSheet = true
            } label: {
                Label("Redraw with AI…", systemImage: "wand.and.stars")
            }
            if !dish.photos.isEmpty {
                Button {
                    Task { await performAIRedrawBasedOnPhoto() }
                } label: {
                    Label("Regenerate Based On the Photo", systemImage: "wand.and.stars")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .background(Color.white.opacity(0.92))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .disabled(isIllustrationWorking)
        .accessibilityLabel("Picture options: save, replace, or redraw")
    }

    @MainActor
    private func replaceIllustration(with item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { replacePhotoItem = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let img = UIImage(data: data)
        else {
            infoAlert = "Couldn't read that photo."
            return
        }
        store.setMenuIllustration(dish, image: img)
    }

    private func saveIllustrationToPhotos() async {
        guard let data = dish.imageData, let image = UIImage(data: data) else { return }
        let status = await requestAddOnlyPhotoAccess()
        guard status == .authorized || status == .limited else {
            infoAlert = "Allow photo library access in Settings to save images."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            infoAlert = error.localizedDescription
        }
    }

    private func requestAddOnlyPhotoAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                cont.resume(returning: status)
            }
        }
    }

    @MainActor
    private func performAIRedraw() async {
        isIllustrationWorking = true
        defer { isIllustrationWorking = false }
        let hint = redrawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.redrawMenuIllustration(
                dish,
                artDirection: hint.isEmpty ? nil : hint
            )
        } catch {
            infoAlert = error.localizedDescription
        }
    }

    @MainActor
    private func performAIRedrawBasedOnPhoto() async {
        guard let latestPhoto = dish.photos.sorted(by: { $0.effectiveDate > $1.effectiveDate }).first,
              let uiImage = UIImage(data: latestPhoto.imageData) else {
            infoAlert = "No photo found in your log to use for redraw."
            return
        }
        isIllustrationWorking = true
        defer { isIllustrationWorking = false }
        do {
            try await store.redrawMenuIllustrationBasedOnPhoto(dish, image: uiImage)
        } catch {
            infoAlert = error.localizedDescription
        }
    }
}

// MARK: - Read-only recipe

private struct RecipeReadOnlyCard: View {
    let dish: Dish
    let onEdit: () -> Void

    private var ingredientRows: [(q: String, u: String, n: String)] {
        let n = max(dish.ingredientQty.count, dish.ingredientUnit.count, dish.ingredientItem.count)
        if n > 0 {
            return (0..<n).map { i in
                (
                    i < dish.ingredientQty.count ? dish.ingredientQty[i] : "",
                    i < dish.ingredientUnit.count ? dish.ingredientUnit[i] : "",
                    i < dish.ingredientItem.count ? dish.ingredientItem[i] : ""
                )
            }
        }
        return dish.ingredients.map { line in
            let parsed = RecipeIngredientFormat.parseImportedOrLegacy(line)
            return (parsed.0, parsed.1, parsed.2)
        }
    }

    private var displayIngredients: [(q: String, u: String, n: String)] {
        ingredientRows.filter { row in
            !row.q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !row.u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !row.n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasSteps: Bool {
        dish.steps.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var trimmedNote: String {
        dish.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmpty: Bool {
        displayIngredients.isEmpty && !hasSteps && trimmedNote.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recipe")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit recipe")
            }

            Rectangle()
                .fill(Theme.ink)
                .frame(height: 1)
                .opacity(0.6)

            if isEmpty {
                Text("No recipe yet. Tap the pencil to add ingredients and steps.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkSoft)
            } else {
                if !displayIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(Theme.hand(14))
                            .foregroundStyle(Theme.inkSoft)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Qty")
                                .font(Theme.hand(11))
                                .frame(width: 52, alignment: .leading)
                            Text("Unit")
                                .font(Theme.hand(11))
                                .frame(width: 44, alignment: .leading)
                            Text("Ingredient")
                                .font(Theme.hand(11))
                        }
                        .foregroundStyle(Theme.inkFaded)

                        ForEach(Array(displayIngredients.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(row.q.isEmpty ? "—" : row.q)
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 52, alignment: .leading)
                                Text(row.u.isEmpty ? "—" : row.u)
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 44, alignment: .leading)
                                Text(row.n.isEmpty ? "—" : row.n)
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if hasSteps {
                    DottedDivider().padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Steps")
                            .font(Theme.hand(14))
                            .foregroundStyle(Theme.inkSoft)
                        ForEach(Array(dish.steps.enumerated()), id: \.offset) { index, step in
                            let s = step.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !s.isEmpty {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(Theme.serif(15, weight: .semibold))
                                        .foregroundStyle(Theme.inkSoft)
                                        .frame(width: 28, alignment: .leading)
                                    Text(s)
                                        .font(.system(size: 15, weight: .regular, design: .default))
                                        .foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    }
                }

                if !trimmedNote.isEmpty {
                    DottedDivider().padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(Theme.hand(14))
                            .foregroundStyle(Theme.inkSoft)
                        Text(trimmedNote)
                            .font(Theme.serif(15))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
    }
}

struct TagPill: View {
    let tag: String

    var body: some View {
        Text("#\(tag)")
            .font(Theme.hand(13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.highlight.opacity(0.22))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.ink.opacity(0.35), lineWidth: 1)
            )
    }
}

// MARK: - Photo log

private struct PhotoLogCard: View {
    @EnvironmentObject private var store: DishStore
    let dish: Dish

    @State private var isLoading = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var viewerPhoto: DishPhoto?
    @State private var photoToDelete: DishPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Photos")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !dish.photos.isEmpty {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 8,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Text("Add")
                            .font(Theme.hand(14))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.ink)
                    }
                    .disabled(isLoading)
                }
            }

            Rectangle()
                .fill(Theme.ink)
                .frame(height: 1)
                .opacity(0.6)

            if dish.photos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Snap the real thing when you cook this — caloric honesty over menu fantasy.")
                        .font(Theme.serif(14).italic())
                        .foregroundStyle(Theme.inkSoft)

                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 8,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Add photos from library", systemImage: "photo.on.rectangle.angled")
                            .font(Theme.hand(14))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.ink.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(dish.photos) { photo in
                            PhotoLogThumbnailCell(
                                photo: photo,
                                onOpen: { viewerPhoto = photo },
                                onRemove: { photoToDelete = photo }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving photos…")
                        .font(Theme.hand(13))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
        .fullScreenCover(item: $viewerPhoto) { photo in
            DishPhotoViewer(photo: photo)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Remove this photo from this dish?",
            isPresented: Binding(
                get: { photoToDelete != nil },
                set: { if !$0 { photoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Photo", role: .destructive) {
                if let p = photoToDelete {
                    store.deletePhoto(p)
                }
                photoToDelete = nil
            }
            Button("Cancel", role: .cancel) { photoToDelete = nil }
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await ingest(newItems) }
        }
    }

    private func ingest(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer {
            isLoading = false
            selectedItems = []
        }
        for item in items {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let img = UIImage(data: data)
            else { continue }
            let takenAt = data.exifCaptureDate()
            store.addPhoto(img, takenAt: takenAt, to: dish)
        }
    }
}

/// Isolated cell so `PhotoLogCard.body` stays small enough for the type checker.
private struct PhotoLogThumbnailCell: View {
    let photo: DishPhoto
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                PhotoThumbnail(photo: photo)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                removeBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo")
        }
    }

    private var removeBadge: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Theme.ink.opacity(0.7))
            .padding(4)
    }
}

private struct PhotoThumbnail: View {
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
        .frame(width: 110, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .cardStroke(cornerRadius: 14)
    }
}
