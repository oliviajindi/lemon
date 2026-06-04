import SwiftUI
import SwiftData
import Foundation
import PhotosUI
import UIKit

/// Full-screen editor for a dish. Use `scope` to show only **details** (name +
/// description), only **recipe**, or **everything** (tags and group are
/// normally edited inline on `DishDetailView`).
struct DishEditView: View {
    enum Scope: Hashable {
        /// Name, description, tags, group, and recipe (rare; prefer scoped editors).
        case full
        case detailsOnly
        case recipeOnly
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore
    @Bindable var dish: Dish
    var scope: Scope = .full
    var onDelete: (() -> Void)? = nil

    @State private var draftName: String = ""
    @State private var draftDescription: String = ""
    @State private var groupSelection: DishGroup?
    @State private var chefSelection: Chef?
    @State private var confirmingDelete = false
    @State private var showingRecipeAssistant = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if showsDetails {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(Theme.hand(13))
                                    .foregroundStyle(Theme.inkSoft)
                                TextField("Dish name", text: $draftName)
                                    .font(Theme.dishName(22, weight: .semibold))
                                    .padding(12)
                                    .background(Color.white.opacity(0.55))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ink.opacity(0.2), lineWidth: 1))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(Theme.hand(13))
                                    .foregroundStyle(Theme.inkSoft)
                                TextField("Short description", text: $draftDescription, axis: .vertical)
                                    .font(.system(size: 16, weight: .regular, design: .default).italic())
                                    .lineLimit(2...5)
                                    .padding(12)
                                    .background(Color.white.opacity(0.55))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ink.opacity(0.2), lineWidth: 1))
                            }

                            ChefPicker(selection: $chefSelection)
                        }

                        if showsTagsAndGroup {
                            GroupPicker(selection: $groupSelection)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tags")
                                    .font(Theme.hand(13))
                                    .foregroundStyle(Theme.inkSoft)
                                DishTagEditor(dish: dish)
                            }
                        }

                        if showsRecipe {
                            RecipeEditorCard(dish: dish)
                        }

                        if scope == .full {
                            PhotosEditorCard(dish: dish)
                        }

                        if scope == .full {
                            Button(role: .destructive) {
                                confirmingDelete = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                    Text("Delete Dish")
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
                            .padding(.top, 16)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 80)
                }
                .paperBackground()

                if scope == .full {
                    assistantFAB
                        .padding(.trailing, 22)
                        .padding(.bottom, 28)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Remove this dish?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    store.deleteDish(dish)
                    dismiss()
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingRecipeAssistant) {
                RecipeAssistantSheet(mode: .copilot(dish: dish))
            }
            .onAppear {
                draftName = dish.name
                draftDescription = dish.dishDescription
                groupSelection = dish.group
                chefSelection = dish.chefs.first
            }
            .onChange(of: dish.chefs) { _, newValue in
                chefSelection = newValue.first
            }
        }
    }

    private var showsDetails: Bool {
        scope == .full || scope == .detailsOnly
    }

    private var showsTagsAndGroup: Bool {
        scope == .full
    }

    private var showsRecipe: Bool {
        scope == .full || scope == .recipeOnly
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

    private var navigationTitle: String {
        switch scope {
        case .full: return "Edit Dish"
        case .detailsOnly: return "Name & description"
        case .recipeOnly: return "Edit recipe"
        }
    }

    private func saveAndDismiss() {
        let finalChefs = chefSelection.map { [$0] } ?? []
        switch scope {
        case .full:
            store.updateDishDetails(dish, name: draftName, description: draftDescription)
            store.setGroup(groupSelection, for: dish)
            store.setChefs(finalChefs, for: dish)
        case .detailsOnly:
            store.updateDishDetails(dish, name: draftName, description: draftDescription)
            store.setChefs(finalChefs, for: dish)
        case .recipeOnly:
            break
        }
        dismiss()
    }
}

// MARK: - Tags (edit)

/// Inline tag editor with suggestions on the dish detail screen.
struct DishTagEditor: View {
    @EnvironmentObject private var store: DishStore
    let dish: Dish

    @Query(sort: \Dish.createdAt, order: .reverse)
    private var allDishes: [Dish]

    @State private var draftTag = ""
    @State private var isAdding = false
    @FocusState private var addFieldFocused: Bool

    private var matchingExistingTags: [String] {
        let query = draftTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isAdding, !query.isEmpty else { return [] }

        let currentTags = Set(dish.tags.map { $0.lowercased() })
        let matches = DishTags.normalized(allDishes.flatMap(\.tags))
            .filter { tag in
                let key = tag.lowercased()
                return !currentTags.contains(key) && key.contains(query)
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Array(matches.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                if !dish.tags.isEmpty {
                    ForEach(dish.tags, id: \.self) { tag in
                        editableTagPill(tag)
                    }
                }

                addTagControl
            }

            if !matchingExistingTags.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(matchingExistingTags, id: \.self) { tag in
                        Button {
                            addExistingTag(tag)
                        } label: {
                            Text("#\(tag)")
                                .font(Theme.hand(12))
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.55))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.ink.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink.opacity(0.22), lineWidth: 1))
    }

    private enum PillMetrics {
        static let textFont = Theme.hand(12)
        static let iconSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 9
        static let verticalPadding: CGFloat = 6
    }

    private func editableTagPill(_ tag: String) -> some View {
        HStack(spacing: 5) {
            NavigationLink {
                TaggedDishesView(tag: tag)
            } label: {
                Text("#\(tag)")
                    .font(PillMetrics.textFont)
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: PillMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(Theme.inkFaded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, PillMetrics.horizontalPadding)
        .padding(.vertical, PillMetrics.verticalPadding)
        .background(Theme.highlight.opacity(0.18))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.ink.opacity(0.25), lineWidth: 1))
    }

    private var addTagControl: some View {
        HStack(spacing: 5) {
            Button(action: plusTapped) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: PillMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdding ? "Save tag" : "Add tags")

            if isAdding {
                TextField("tag", text: $draftTag)
                    .font(PillMetrics.textFont)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($addFieldFocused)
                    .onSubmit(addTags)
                    .frame(width: 86)
            } else {
                Text("Add Tags")
                    .font(PillMetrics.textFont)
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, PillMetrics.horizontalPadding)
        .padding(.vertical, PillMetrics.verticalPadding)
        .background(Color.white.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.ink.opacity(0.25), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture {
            if !isAdding {
                isAdding = true
                addFieldFocused = true
            }
        }
    }

    private func plusTapped() {
        if isAdding && !DishTags.parsed(from: draftTag).isEmpty {
            addTags()
        } else {
            isAdding = true
            addFieldFocused = true
        }
    }

    private func addTags() {
        let additions = DishTags.parsed(from: draftTag)
        guard !additions.isEmpty else { return }
        store.updateTags(dish, tags: dish.tags + additions)
        draftTag = ""
        isAdding = false
    }

    private func addExistingTag(_ tag: String) {
        store.updateTags(dish, tags: dish.tags + [tag])
        draftTag = ""
        isAdding = false
    }

    private func remove(_ tag: String) {
        store.updateTags(dish, tags: dish.tags.filter { !DishTags.matches(tag, in: [$0]) })
    }
}

// MARK: - Recipe card (structured ingredients + import)

private struct RecipeEditorCard: View {
    @EnvironmentObject private var store: DishStore
    let dish: Dish

    @State private var ingredients: [IngredientLineRow]
    @State private var steps: [InlineRecipeLine]
    @State private var notes: String
    @State private var draftQty = ""
    @State private var draftUnit = ""
    @State private var draftName = ""
    @State private var newStep = ""

    @FocusState private var notesFocused: Bool

    @State private var showingRecipeAssistant = false
    @State private var pendingScan: ExtractedRecipe?
    @State private var showingMergeChoice = false
    @State private var scanError: String?
    @State private var showingClearConfirm = false

    init(dish: Dish) {
        self.dish = dish
        self._ingredients = State(initialValue: Self.loadIngredients(from: dish))
        self._steps = State(initialValue: dish.steps.map(InlineRecipeLine.init))
        self._notes = State(initialValue: dish.notes)
    }

    private static func loadIngredients(from dish: Dish) -> [IngredientLineRow] {
        let n = max(dish.ingredientQty.count, dish.ingredientUnit.count, dish.ingredientItem.count)
        if n > 0 {
            return (0..<n).map { i in
                let q = i < dish.ingredientQty.count ? dish.ingredientQty[i] : ""
                let u = i < dish.ingredientUnit.count ? dish.ingredientUnit[i] : ""
                let it = i < dish.ingredientItem.count ? dish.ingredientItem[i] : ""
                return IngredientLineRow(quantity: q, unit: u, name: it)
            }
        }
        if !dish.ingredients.isEmpty {
            return dish.ingredients.map { line in
                let (q, u, n) = RecipeIngredientFormat.parseImportedOrLegacy(line)
                return IngredientLineRow(quantity: q, unit: u, name: n)
            }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recipe")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                recipeAssistantButton
            }
            Rectangle()
                .fill(Theme.ink)
                .frame(height: 1)
                .opacity(0.6)

            IngredientListEditor(
                rows: $ingredients,
                draftQty: $draftQty,
                draftUnit: $draftUnit,
                draftName: $draftName,
                onCommit: persistRecipe
            )

            DottedDivider().padding(.vertical, 2)

            InlineRecipeList(
                title: "Steps",
                placeholder: "What happens next?",
                rows: $steps,
                draft: $newStep,
                leadingText: { "\($0 + 1)." },
                maxVisibleRows: 3,
                onCommit: persistRecipe
            )

            DottedDivider().padding(.vertical, 2)

            notesSection

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
        .sheet(isPresented: $showingRecipeAssistant) {
            RecipeAssistantSheet(mode: .copilot(dish: dish)) { scan in
                pendingScan = scan
                applyScan(replace: true)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "You already have some recipe lines. What should we do with the imported ones?",
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
        .confirmationDialog(
            "Clear entire recipe?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Recipe", role: .destructive) {
                clearRecipe()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear(perform: persistRecipe)
    }

    private var recipeAssistantButton: some View {
        HStack(spacing: 12) {
            if hasContent {
                Menu {
                    Button(action: cleanUpRecipe) {
                        Label("Clean Up (Trim)", systemImage: "sparkles")
                    }
                    Button(role: .destructive, action: { showingClearConfirm = true }) {
                        Label("Clear Recipe", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            
            Button {
                showingRecipeAssistant = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Recipe assistant — add text, photo, or video link")
        }
    }

    private func cleanUpRecipe() {
        let cleanedIngredients = ingredients.map { row in
            IngredientLineRow(
                quantity: row.quantity.trimmingCharacters(in: .whitespacesAndNewlines),
                unit: row.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter { row in
            !row.quantity.isEmpty || !row.unit.isEmpty || !row.name.isEmpty
        }

        let cleanedSteps = steps.map { step in
            InlineRecipeLine(step.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { step in
            !step.text.isEmpty
        }

        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        store.updateRecipe(
            dish,
            ingredientQuantities: cleanedIngredients.map { $0.quantity },
            ingredientUnits: cleanedIngredients.map { $0.unit },
            ingredientItems: cleanedIngredients.map { $0.name },
            steps: cleanedSteps.map { $0.text },
            notes: cleanedNotes
        )
        
        ingredients = Self.loadIngredients(from: dish)
        steps = dish.steps.map(InlineRecipeLine.init)
        notes = dish.notes
    }

    private func clearRecipe() {
        store.updateRecipe(
            dish,
            ingredientQuantities: [],
            ingredientUnits: [],
            ingredientItems: [],
            steps: [],
            notes: ""
        )
        ingredients = []
        steps = []
        notes = ""
    }

    private func receiveImport(_ extracted: ExtractedRecipe) {
        pendingScan = extracted
        if hasContent {
            showingMergeChoice = true
        } else {
            applyScan(replace: true)
        }
    }

    private var hasIngredientRows: Bool {
        ingredients.contains { row in
            !row.quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !row.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasContent: Bool {
        hasIngredientRows
            || !steps.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func persistRecipe() {
        store.updateRecipe(
            dish,
            ingredientQuantities: ingredients.map(\.quantity),
            ingredientUnits: ingredients.map(\.unit),
            ingredientItems: ingredients.map(\.name),
            steps: steps.map(\.text),
            notes: notes
        )
        ingredients = Self.loadIngredients(from: dish)
        steps = dish.steps.map(InlineRecipeLine.init)
        notes = dish.notes
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(Theme.hand(14))
                .foregroundStyle(Theme.inkSoft)

            TextField(
                "Anything worth remembering — tweaks, pairings, where you got this…",
                text: $notes,
                axis: .vertical
            )
            .font(Theme.serif(15))
            .foregroundStyle(Theme.ink)
            .lineLimit(2...8)
            .focused($notesFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.ink.opacity(0.18), lineWidth: 1)
            )
            .onChange(of: notesFocused) { _, focused in
                if !focused { persistRecipe() }
            }
        }
    }

    private func applyScan(replace: Bool) {
        guard let scan = pendingScan else { return }
        defer { pendingScan = nil }

        let newIngredients = scan.ingredients.map { IngredientLineRow(fromImportedLine: $0) }
        if replace {
            ingredients = newIngredients
            steps = scan.steps.map(InlineRecipeLine.init)
        } else {
            ingredients.append(contentsOf: newIngredients)
            steps.append(contentsOf: scan.steps.map(InlineRecipeLine.init))
        }
        persistRecipe()
    }
}

// MARK: - Ingredient row

private struct IngredientLineRow: Identifiable, Equatable {
    let id: UUID
    var quantity: String
    var unit: String
    var name: String

    init(id: UUID = UUID(), quantity: String = "", unit: String = "", name: String = "") {
        self.id = id
        self.quantity = quantity
        self.unit = unit
        self.name = name
    }

    init(fromImportedLine line: String) {
        let (q, u, n) = RecipeIngredientFormat.parseImportedOrLegacy(line)
        self.init(quantity: q, unit: u, name: n)
    }
}

private struct IngredientListEditor: View {
    @Binding var rows: [IngredientLineRow]
    @Binding var draftQty: String
    @Binding var draftUnit: String
    @Binding var draftName: String
    let onCommit: () -> Void

    /// Shared geometry so header labels line up with fields (and with the +/✕ column).
    private enum Col {
        static let rowHPadding: CGFloat = 8
        static let qty: CGFloat = 52
        static let unit: CGFloat = 44
        static let trail: CGFloat = 30
        static let gap: CGFloat = 6
    }

    private var draftEmpty: Bool {
        draftQty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients")
                .font(Theme.hand(14))
                .foregroundStyle(Theme.inkSoft)

            HStack(spacing: Col.gap) {
                Text("Qty")
                    .font(Theme.hand(11))
                    .frame(width: Col.qty, alignment: .leading)
                Text("Unit")
                    .font(Theme.hand(11))
                    .frame(width: Col.unit, alignment: .leading)
                Text("Ingredient")
                    .font(Theme.hand(11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: Col.trail)
            }
            .foregroundStyle(Theme.inkFaded)
            .padding(.horizontal, Col.rowHPadding)

            ForEach($rows) { $row in
                HStack(alignment: .center, spacing: Col.gap) {
                    TextField("—", text: $row.quantity)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .multilineTextAlignment(.leading)
                        .frame(width: Col.qty, alignment: .leading)
                        .submitLabel(.next)
                        .onSubmit(onCommit)
                    TextField("—", text: $row.unit)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .multilineTextAlignment(.leading)
                        .frame(width: Col.unit, alignment: .leading)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next)
                        .onSubmit(onCommit)
                    TextField("flour", text: $row.name)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .submitLabel(.done)
                        .onSubmit(onCommit)

                    Button {
                        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                            rows.remove(at: idx)
                            onCommit()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkFaded)
                    }
                    .buttonStyle(.plain)
                    .frame(width: Col.trail, alignment: .center)
                }
                .padding(.horizontal, Col.rowHPadding)
            }

            HStack(alignment: .center, spacing: Col.gap) {
                TextField("250", text: $draftQty)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .multilineTextAlignment(.leading)
                    .frame(width: Col.qty, alignment: .leading)
                TextField("g", text: $draftUnit)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .multilineTextAlignment(.leading)
                    .frame(width: Col.unit, alignment: .leading)
                    .textInputAutocapitalization(.never)
                TextField("flour", text: $draftName)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .submitLabel(.done)
                    .onSubmit(addDraft)

                Button(action: addDraft) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .frame(width: Col.trail, alignment: .center)
                .disabled(draftEmpty)
            }
            .padding(.horizontal, Col.rowHPadding)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func addDraft() {
        let q = draftQty.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = draftUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || !u.isEmpty || !n.isEmpty else { return }
        let normalized = RecipeIngredientFormat.normalizedFields(quantity: q, unit: u, name: n)
        rows.append(IngredientLineRow(quantity: normalized.0, unit: normalized.1, name: normalized.2))
        draftQty = ""
        draftUnit = ""
        draftName = ""
        onCommit()
    }
}

// MARK: - Recipe import sheets (same paper style as before)

private struct RecipeFromTextSheet: View {
    let isBusy: Bool
    let onImport: (String) -> Void
    let onCancel: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TYPE RECIPE")
                    .font(Theme.serif(12, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.inkFaded)
                Text("Paste or describe a recipe — the AI will split it into ingredients and steps.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkSoft)
            }

            TextField(
                "Spaghetti carbonara — eggs, pancetta, pecorino…",
                text: $draft,
                axis: .vertical
            )
            .font(Theme.serif(15))
            .lineLimit(8...16)
            .focused($focused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Theme.serif(15, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 999)
                                .strokeBorder(Theme.ink.opacity(0.55), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button {
                    onImport(draft)
                } label: {
                    HStack(spacing: 6) {
                        if isBusy { ProgressView().tint(Theme.paper) }
                        Text(isBusy ? "Reading…" : "Import")
                    }
                    .font(Theme.serif(15, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 999).fill(Theme.ink))
                }
                .buttonStyle(.plain)
                .disabled(isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity((isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.45 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperBackground()
        .onAppear { focused = true }
    }
}

private struct RecipeFromVideoSheet: View {
    let isBusy: Bool
    let onImport: (String) -> Void
    let onCancel: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FROM VIDEO")
                    .font(Theme.serif(12, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.inkFaded)
                Text("Paste a YouTube link — the AI will watch the video and pull out the recipe.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkSoft)
            }

            TextField("https://www.youtube.com/watch?v=…", text: $draft, axis: .vertical)
                .font(Theme.serif(15))
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                )

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Theme.serif(15, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 999)
                                .strokeBorder(Theme.ink.opacity(0.55), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button {
                    onImport(draft)
                } label: {
                    HStack(spacing: 6) {
                        if isBusy { ProgressView().tint(Theme.paper) }
                        Text(isBusy ? "Watching…" : "Import")
                    }
                    .font(Theme.serif(15, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 999).fill(Theme.ink))
                }
                .buttonStyle(.plain)
                .disabled(isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity((isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.45 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperBackground()
        .onAppear { focused = true }
    }
}

// MARK: - Step list (shared pattern)

private struct InlineRecipeList: View {
    let title: String
    let placeholder: String
    @Binding var rows: [InlineRecipeLine]
    @Binding var draft: String
    let leadingText: (Int) -> String
    var maxVisibleRows: Int? = nil
    let onCommit: () -> Void

    @State private var showingAllRows = false

    private var displayedRowCount: Int {
        guard let maxVisibleRows, !showingAllRows else { return rows.count }
        return min(rows.count, maxVisibleRows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.hand(14))
                .foregroundStyle(Theme.inkSoft)

            ForEach(Array($rows.enumerated()).prefix(displayedRowCount), id: \.element.id) { index, $line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(leadingText(index))
                        .font(Theme.serif(15, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: title == "Steps" ? 24 : 12, alignment: .leading)

                    TextField(placeholder, text: $line.text, axis: .vertical)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .lineLimit(1...)
                        .submitLabel(.done)
                        .onSubmit(onCommit)

                    Button {
                        rows.remove(at: index)
                        onCommit()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkFaded)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let maxVisibleRows, rows.count > maxVisibleRows {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showingAllRows.toggle()
                    }
                } label: {
                    Text(showingAllRows ? "Show fewer steps" : "Show all \(rows.count) steps")
                        .font(Theme.hand(13))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .padding(.leading, 32)
            }

            HStack(spacing: 8) {
                Text(leadingText(rows.count))
                    .font(Theme.serif(15, weight: .semibold))
                    .foregroundStyle(Theme.inkFaded)
                    .frame(width: title == "Steps" ? 24 : 12, alignment: .leading)

                TextField(placeholder, text: $draft, axis: .vertical)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .lineLimit(1...)
                    .submitLabel(.done)
                    .onSubmit(addDraft)

                Button(action: addDraft) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func addDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rows.append(InlineRecipeLine(trimmed))
        draft = ""
        onCommit()
    }
}

private struct InlineRecipeLine: Identifiable, Equatable {
    let id = UUID()
    var text: String

    init(_ text: String) { self.text = text }
}

// MARK: - Photos Editor

private struct PhotosEditorCard: View {
    @EnvironmentObject private var store: DishStore
    let dish: Dish

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var photoToDelete: DishPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Photos")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 8,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .disabled(isLoading)
            }
            Rectangle()
                .fill(Theme.ink)
                .frame(height: 1)
                .opacity(0.6)

            if dish.photos.isEmpty {
                Text("No photos yet. Add some photos of your dish.")
                    .font(Theme.serif(14).italic())
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(dish.photos) { photo in
                            ZStack(alignment: .topTrailing) {
                                PhotoThumbnail(photo: photo)
                                
                                Button {
                                    photoToDelete = photo
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Theme.ink.opacity(0.7))
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
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
        .background(Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardStroke(cornerRadius: 16)
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
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .cardStroke(cornerRadius: 12)
    }
}
