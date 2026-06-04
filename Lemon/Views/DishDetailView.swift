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

    @State private var showingDetailsEditor = false

    @State private var replacePhotoItem: PhotosPickerItem?
    @State private var showingRedrawSheet = false
    @State private var redrawNotes = ""
    @State private var isIllustrationWorking = false
    @State private var infoAlert: String?
    @State private var showingRecipeAssistant = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 20) {
                    illustration

                    metadataBar

                    RecipeReadOnlyCard(dish: dish, onAdd: { showingDetailsEditor = true })
                        .padding(.top, 4)

                    PhotoLogCard(dish: dish)
                    
                    addedDateBlock
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
                .padding(20)
            }

            assistantFAB
                .padding(.trailing, 22)
                .padding(.bottom, 28)
        }
        .paperBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingDetailsEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Dish")
            }
        }
        .fullScreenCover(isPresented: $showingDetailsEditor) {
            DishEditView(dish: dish, scope: .full, onDelete: {
                dismiss()
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showingRedrawSheet) {
            redrawIllustrationSheet
        }
        .sheet(isPresented: $showingRecipeAssistant) {
            RecipeAssistantSheet(mode: .copilot(dish: dish))
        }
        .alert("Notice", isPresented: Binding(
            get: { infoAlert != nil },
            set: { if !$0 { infoAlert = nil } }
        )) {
            Button("OK", role: .cancel) { infoAlert = nil }
        } message: {
            Text(infoAlert ?? "")
        }
    }

    private var metadataBar: some View {
        VStack(alignment: .center, spacing: 14) {
            // Line 1: Dish Name
            Text(dish.name)
                .font(Theme.title(28, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            
            // Line 2: Description
            if !dish.dishDescription.isEmpty {
                Text(dish.dishDescription)
                    .font(.system(size: 15, weight: .regular, design: .default).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            } else {
                Text("No description yet.")
                    .font(.system(size: 14, weight: .light, design: .default).italic())
                    .foregroundStyle(Theme.inkFaded)
                    .multilineTextAlignment(.center)
            }
            
            // Line 3: Chef + Group + Tags
            FlowLayout(spacing: 8, rowSpacing: 8, alignment: .center) {
                // Chefs
                if !dish.chefs.isEmpty {
                    ForEach(dish.chefs) { chef in
                        HStack(spacing: 5) {
                            ChefAvatarView(chef: chef, size: 18)
                            Text(chef.name)
                                .font(Theme.hand(13))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                } else {
                    Text("No Chef")
                        .font(Theme.hand(13).italic())
                        .foregroundStyle(Theme.inkFaded)
                }
                
                Text("•")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaded)
                
                // Group
                if let group = dish.group {
                    HStack(spacing: 5) {
                        if let emoji = group.emoji, !emoji.isEmpty {
                            Text(emoji)
                                .font(.system(size: 13))
                        } else {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Text(group.name)
                            .font(Theme.serif(13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    Text("No Group")
                        .font(Theme.serif(13).italic())
                        .foregroundStyle(Theme.inkFaded)
                }
                
                // Tags
                if !dish.tags.isEmpty {
                    Text("•")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaded)
                    
                    ForEach(dish.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(Theme.serif(13))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private var addedDateBlock: some View {
        Text("Added \(dish.createdAt.formatted(date: .abbreviated, time: .omitted))")
            .font(Theme.hand(13))
            .foregroundStyle(Theme.inkFaded)
            .frame(maxWidth: .infinity, alignment: .center)
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
            Text("Added \(dish.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.hand(13))
                .foregroundStyle(Theme.inkFaded)
                .padding(.top, 2)
            // Chef attribution badges
            if !dish.chefs.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 8, alignment: .center) {
                    ForEach(dish.chefs) { chef in
                        chefBadge(chef)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func chefBadge(_ chef: Chef) -> some View {
        NavigationLink(value: chef) {
            HStack(spacing: 7) {
                ChefAvatarView(chef: chef, size: 26)

                Text(chef.name)
                    .font(Theme.hand(13))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.45))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.ink.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    private var assistantFAB: some View {
        Button {
            showingRecipeAssistant = true
        } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Theme.ink))
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: Theme.ink.opacity(0.22), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Sous Chef assistant")
    }
}

// MARK: - Read-only recipe

private struct RecipeReadOnlyCard: View {
    let dish: Dish
    let onAdd: () -> Void

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
            HStack(alignment: .center) {
                Text("Recipe")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
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

    @State private var viewerPhoto: DishPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Photos")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }

            Rectangle()
                .fill(Theme.ink)
                .frame(height: 1)
                .opacity(0.6)

            if dish.photos.isEmpty {
                Text("Snap the real thing when you cook this — caloric honesty over menu fantasy. Tap the pencil to add photos.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(dish.photos) { photo in
                            PhotoLogThumbnailCell(
                                photo: photo,
                                onOpen: { viewerPhoto = photo }
                            )
                        }
                    }
                    .padding(.vertical, 2)
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
    }
}

/// Isolated cell so `PhotoLogCard.body` stays small enough for the type checker.
private struct PhotoLogThumbnailCell: View {
    let photo: DishPhoto
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            PhotoThumbnail(photo: photo)
        }
        .buttonStyle(.plain)
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
