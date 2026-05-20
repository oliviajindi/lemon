import SwiftUI
import PhotosUI

/// Edit a dish's recipe — ingredients and steps. Each list supports inline
/// text editing, swipe-to-delete, drag-to-reorder (via the Edit toolbar
/// button), and an "Add" row at the bottom of each section.
///
/// Also supports **scanning a recipe from a photo** (cookbook page,
/// handwritten card, screenshot, etc.) — Gemini's vision model fills in
/// `ingredients` + `steps`. The user can review, tweak, then save.
///
/// Why each line is wrapped in `EditableLine` with a stable UUID: stable
/// identity keeps SwiftUI from losing TextField focus and keyboard state
/// when the user reorders or deletes a row mid-edit.
struct RecipeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore

    let dish: Dish

    @State private var ingredients: [EditableLine]
    @State private var steps: [EditableLine]
    @State private var editMode: EditMode = .inactive

    // Scan-from-photo state
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingScan: ExtractedRecipe?
    @State private var showingMergeChoice = false
    @State private var isScanning = false
    @State private var scanError: String?

    init(dish: Dish) {
        self.dish = dish
        let lines: [String] = {
            let n = max(dish.ingredientQty.count, dish.ingredientUnit.count, dish.ingredientItem.count)
            if n > 0 {
                return (0..<n).map { i in
                    let q = i < dish.ingredientQty.count ? dish.ingredientQty[i] : ""
                    let u = i < dish.ingredientUnit.count ? dish.ingredientUnit[i] : ""
                    let it = i < dish.ingredientItem.count ? dish.ingredientItem[i] : ""
                    return RecipeIngredientFormat.compoundLine(quantity: q, unit: u, name: it)
                }
            }
            return dish.ingredients
        }()
        self._ingredients = State(initialValue: lines.map(EditableLine.init))
        self._steps = State(initialValue: dish.steps.map(EditableLine.init))
    }

    private var hasContent: Bool {
        !ingredients.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            || !steps.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    Section {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.viewfinder")
                                Text("Scan recipe from photo")
                                    .font(Theme.hand(15))
                                Spacer()
                                if isScanning {
                                    ProgressView()
                                }
                            }
                            .foregroundStyle(Theme.ink)
                        }
                        .disabled(isScanning)
                    } footer: {
                        Text("Pick a photo of a cookbook page, handwritten card, or screenshot — the AI will fill in ingredients and steps.")
                    }

                    Section {
                        ForEach($ingredients) { $line in
                            TextField("e.g. 2 cups flour", text: $line.text, axis: .vertical)
                                .lineLimit(1...3)
                                .submitLabel(.next)
                        }
                        .onDelete { ingredients.remove(atOffsets: $0) }
                        .onMove   { ingredients.move(fromOffsets: $0, toOffset: $1) }

                        Button {
                            ingredients.append(EditableLine(""))
                        } label: {
                            Label("Add ingredient", systemImage: "plus.circle")
                                .foregroundStyle(Theme.ink)
                        }
                    } header: {
                        Text("Ingredients")
                    } footer: {
                        Text("One ingredient per line — quantity, unit, and item.")
                    }

                    Section {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, _ in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(Theme.serif(15, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                                    .padding(.top, 8)
                                    .frame(minWidth: 22, alignment: .leading)
                                TextField("What happens at this step?",
                                          text: $steps[index].text,
                                          axis: .vertical)
                                    .lineLimit(1...8)
                            }
                        }
                        .onDelete { steps.remove(atOffsets: $0) }
                        .onMove   { steps.move(fromOffsets: $0, toOffset: $1) }

                        Button {
                            steps.append(EditableLine(""))
                        } label: {
                            Label("Add step", systemImage: "plus.circle")
                                .foregroundStyle(Theme.ink)
                        }
                    } header: {
                        Text("Steps")
                    } footer: {
                        Text("Tap Edit to drag-to-reorder, or swipe a row to delete.")
                    }
                }
                .environment(\.editMode, $editMode)
                .disabled(isScanning)
                .opacity(isScanning ? 0.5 : 1)

                if isScanning {
                    ScanningOverlay()
                }
            }
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let parsed = ingredients.map { RecipeIngredientFormat.parseImportedOrLegacy($0.text) }
                        store.updateRecipe(
                            dish,
                            ingredientQuantities: parsed.map { $0.0 },
                            ingredientUnits: parsed.map { $0.1 },
                            ingredientItems: parsed.map { $0.2 },
                            steps: steps.map(\.text)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isScanning)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePhoto(newItem) }
            }
            .confirmationDialog(
                "You already have some recipe lines. What should we do with the scanned ones?",
                isPresented: $showingMergeChoice,
                titleVisibility: .visible
            ) {
                Button("Add to current recipe") { applyScan(replace: false) }
                Button("Replace current recipe", role: .destructive) { applyScan(replace: true) }
                Button("Cancel", role: .cancel) { pendingScan = nil }
            }
            .alert(
                "Couldn't read that recipe",
                isPresented: Binding(
                    get: { scanError != nil },
                    set: { if !$0 { scanError = nil } }
                ),
                presenting: scanError
            ) { _ in
                Button("OK", role: .cancel) { scanError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    // MARK: - Scan flow

    private func handlePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil } // allow re-picking same image
        isScanning = true
        defer { isScanning = false }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let img = UIImage(data: data)
        else {
            scanError = "Couldn't load that photo. Try another."
            return
        }

        do {
            let extracted = try await store.extractRecipe(from: img)
            if extracted.isEmpty {
                scanError = "The AI couldn't find a recipe in that photo. Try a clearer shot."
                return
            }
            pendingScan = extracted
            if hasContent {
                showingMergeChoice = true
            } else {
                applyScan(replace: true)
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func applyScan(replace: Bool) {
        guard let scan = pendingScan else { return }
        defer { pendingScan = nil }

        let newIngredients = scan.ingredients.map(EditableLine.init)
        let newSteps       = scan.steps.map(EditableLine.init)

        if replace {
            ingredients = newIngredients
            steps       = newSteps
        } else {
            ingredients.append(contentsOf: newIngredients)
            steps.append(contentsOf: newSteps)
        }
    }
}

/// Translucent paper-style overlay shown while the vision model is reading
/// the photo. Keeps the editor visually present underneath but blocks input.
private struct ScanningOverlay: View {
    var body: some View {
        ZStack {
            Theme.paper.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("Reading your recipe…")
                    .font(Theme.hand(15))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(28)
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .cardStroke(cornerRadius: 18)
        }
        .transition(.opacity)
        .accessibilityElement()
        .accessibilityLabel("Reading recipe from photo")
    }
}

/// A line in the recipe editor with a stable identity. The UUID lets
/// `ForEach` track each row across reorders and deletions so SwiftUI does
/// not recycle TextFields and drop the keyboard mid-edit.
private struct EditableLine: Identifiable, Equatable {
    let id = UUID()
    var text: String

    init(_ text: String) { self.text = text }
}
