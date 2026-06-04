import SwiftUI
import PhotosUI
import UIKit
import Foundation

// MARK: - Mode

/// The mode the assistant sheet operates in.
enum SousChefMode {
    /// Creating a new dish from scratch. Optionally pre-assign to a group or chef.
    case creator(initialGroup: DishGroup? = nil, initialChef: Chef? = nil)
    /// Copilot for an existing dish — edit recipe, add tags, etc.
    case copilot(dish: Dish)
    /// Plan today's meals from the user's existing menu.
    case today(day: Date, mealNames: [String])
}

// MARK: - RecipeAssistantSheet

/// Chat-style Sous Chef: create a dish, edit an existing one, or plan today's meals.
struct RecipeAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore
    @AppStorage("Lemon.profileDisplayName") private var displayName = ""

    @State private var currentMode: SousChefMode
    /// Creator mode: called after a new dish is persisted.
    var onSaved: ((Dish) -> Void)?
    /// Copilot mode (DishEditView): called with the raw extracted recipe scan.
    var onImported: ((ExtractedRecipe) -> Void)?

    // MARK: Init helpers

    init(mode: SousChefMode, onSaved: ((Dish) -> Void)? = nil) {
        self._currentMode = State(initialValue: mode)
        self.onSaved = onSaved
        self.onImported = nil
    }

    /// Copilot convenience: trailing closure receives an `ExtractedRecipe`.
    init(mode: SousChefMode, onImported: @escaping (ExtractedRecipe) -> Void) {
        self._currentMode = State(initialValue: mode)
        self.onSaved = nil
        self.onImported = onImported
    }

    // MARK: State

    @State private var lines: [AssistantChatLine] = []
    @State private var draft = ""
    @State private var pendingImage: UIImage?
    @State private var photoPickItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didLoadHistory = false
    @State private var pendingExtractedRecipe: ExtractedRecipe? = nil
    @State private var pendingCandidateDish: DishCandidate? = nil
    @State private var uploadedDishPhotoData: Data? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            chatScrollView
                .safeAreaInset(edge: .bottom) { composerBar }
                .paperBackground()
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { persistHistory(); dismiss() }
                    }
                }
                .overlay { thinkingOverlay }
                .alert("Something went wrong", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
                .onChange(of: photoPickItem) { _, item in
                    Task { await attachPhoto(item) }
                }
                .onAppear { loadHistory() }
        }
    }

    // MARK: - Sub-views (extracted for compiler performance)

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        chatBubble(line)
                            .id(line.id)
                    }
                    if isWorking {
                        thinkingBubble
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: lines.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isWorking) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if isWorking {
            proxy.scrollTo("thinking", anchor: .bottom)
        } else if let last = lines.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.inkSoft)
                        .frame(width: 7, height: 7)
                        .opacity(0.6)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: isWorking
                        )
                        .scaleEffect(isWorking ? 1.0 : 0.5)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.ink.opacity(0.15), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if onSaved != nil, let candidate = pendingCandidateDish {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Draft Dish Ready")
                            .font(Theme.hand(14).bold())
                            .foregroundStyle(Theme.ink)
                        Text("Confirm to add \(candidate.name) to your menu, or talk to edit.")
                            .font(Theme.hand(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Button {
                        var initialGroup: DishGroup? = nil
                        var initialChef: Chef? = nil
                        if case .creator(let g, let c) = currentMode {
                            initialGroup = g
                            initialChef = c
                        }
                        
                        // If the user changed the group via chat, use that instead
                        let resolvedGroup: DishGroup?
                        if let overrideName = candidate.groupName,
                           !overrideName.isEmpty {
                            resolvedGroup = store.allGroups().first {
                                $0.name.caseInsensitiveCompare(overrideName) == .orderedSame
                            } ?? {
                                // Create the group if it doesn't exist
                                return store.createGroup(name: overrideName)
                            }()
                        } else {
                            resolvedGroup = initialGroup
                        }
                        
                        let finalDish = Dish(
                            name: candidate.name,
                            dishDescription: candidate.description,
                            group: resolvedGroup
                        )
                        if let initialChef {
                            finalDish.chefs.append(initialChef)
                        }
                        // Apply chefs accumulated via chat
                        for chefName in candidate.chefs {
                            store.linkChef(named: chefName, to: finalDish)
                        }
                        if let imgData = candidate.illustration {
                            finalDish.imageData = imgData
                        }
                        
                        // Parse ingredients
                        let parsedIngs = candidate.ingredients.map { RecipeIngredientFormat.parseImportedOrLegacy($0) }
                        finalDish.ingredientQty = parsedIngs.map { $0.0 }
                        finalDish.ingredientUnit = parsedIngs.map { $0.1 }
                        finalDish.ingredientItem = parsedIngs.map { $0.2 }
                        finalDish.ingredients = candidate.ingredients
                        finalDish.steps = candidate.steps
                        
                        // Apply tags accumulated via chat
                        if !candidate.tags.isEmpty {
                            finalDish.tags = candidate.tags
                        }
                        
                        // If they uploaded a photo in this session, save it to the dish's photos list!
                        if let photoData = uploadedDishPhotoData {
                            let takenAt = photoData.exifCaptureDate()
                            let dishPhoto = DishPhoto(
                                imageData: photoData,
                                caption: "Uploaded during creation",
                                addedAt: Date(),
                                takenAt: takenAt
                            )
                            dishPhoto.dish = finalDish
                            finalDish.photos.append(dishPhoto)
                        }
                        
                        store.insertDish(finalDish)
                        onSaved?(finalDish)
                        store.clearCreatorSession()
                        uploadedDishPhotoData = nil
                        dismiss()
                    } label: {
                        Text("Confirm & Add")
                            .font(Theme.serif(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Theme.highlight.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.highlight.opacity(0.3), lineWidth: 1)
                )
            }

            if onImported != nil, let extracted = pendingExtractedRecipe {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extracted Recipe Ready")
                            .font(Theme.hand(14).bold())
                            .foregroundStyle(Theme.ink)
                        Text("Review in chat, ask for changes, or click import.")
                            .font(Theme.hand(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Button {
                        if let cb = onImported {
                            switch currentMode {
                            case .copilot(let dish):
                                let finalRecipe = ExtractedRecipe(
                                    ingredients: dish.ingredients,
                                    steps: dish.steps
                                )
                                cb(finalRecipe)
                            default:
                                cb(extracted)
                            }
                        }
                        dismiss()
                    } label: {
                        Text("Import Recipe")
                            .font(Theme.serif(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Theme.highlight.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.highlight.opacity(0.3), lineWidth: 1)
                )
            }

            if let img = pendingImage {
                HStack(spacing: 10) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.ink.opacity(0.15), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo attached")
                            .font(Theme.hand(13))
                            .foregroundStyle(Theme.ink)
                        Text("It will be read when you send.")
                            .font(Theme.hand(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Button {
                        pendingImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.inkFaded)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
                )
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoPickItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.ink.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                TextField(
                    placeholderText,
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(Theme.serif(15))
                .padding(10)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.ink.opacity(0.2), lineWidth: 1)
                )

                Button(action: { Task { await sendTapped() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(canSend ? Theme.ink : Theme.inkFaded)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isWorking)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.paperShadow.opacity(0.35))
    }

    @ViewBuilder
    private var thinkingOverlay: some View {
        EmptyView()
    }

    // MARK: - Chat bubble

    @ViewBuilder
    private func chatBubble(_ line: AssistantChatLine) -> some View {
        HStack {
            if line.role == .user { Spacer(minLength: 40) }
            VStack(alignment: line.role == .assistant ? .leading : .trailing, spacing: 6) {
                // User-uploaded photo preview
                if let imgData = line.imageData, let uiImg = UIImage(data: imgData) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 180, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.ink.opacity(0.15), lineWidth: 1)
                        )
                }
                // AI-generated illustration
                if let imgData = line.illustrationData, let uiImg = UIImage(data: imgData) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !line.text.isEmpty {
                    Text(line.text)
                        .font(Theme.serif(15))
                        .foregroundStyle(Theme.ink)
                        .padding(12)
                        .background(
                            line.role == .assistant
                                ? Color.white.opacity(0.5)
                                : Theme.highlight.opacity(0.22)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.ink.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            if line.role == .assistant { Spacer(minLength: 40) }
        }
    }

    // MARK: - Mode-specific helpers

    private var navigationTitle: String {
        switch currentMode {
        case .creator: return "Sous Chef · Creator"
        case .copilot: return "Sous Chef · Copilot"
        case .today:   return "Sous Chef · Today"
        }
    }

    private var placeholderText: String {
        switch currentMode {
        case .creator: return "Describe a new dish…"
        case .copilot: return "Ask about this recipe…"
        case .today:   return "Any preferences for today?"
        }
    }

    private var userNameSuffix: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? " there" : " \(trimmed)"
    }

    private var greetingText: String {
        switch currentMode {
        case .creator:
            return "Hi\(userNameSuffix)! 👩‍🍳 Sous chef ready. What do we want to add today? Describe a dish, paste a recipe, attach a photo, or send a YouTube cooking link to get started!"
        case .copilot(let dish):
            return "Hi\(userNameSuffix)! 👋 Sous chef ready to help with \"\(dish.name)\". What do we want to edit today? I can help you update the ingredients, steps, description, or tags!"
        case .today:
            return "Hi\(userNameSuffix)! 📅 Sous chef ready. What do we want to cook today? Tell me what you're in the mood for, or say \"go ahead\" and I'll draft today's meal plan!"
        }
    }

    private var canSend: Bool {
        pendingImage != nil
            || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - History persistence

    private func loadHistory() {
        guard !didLoadHistory else { return }
        didLoadHistory = true

        let restored: [AssistantChatLine]
        switch currentMode {
        case .creator:
            restored = store.getCreatorHistory()
        case .copilot(let dish):
            restored = store.getCopilotHistory(for: dish.id)
        case .today:
            restored = store.getTodayHistory()
        }

        if restored.isEmpty {
            lines = [AssistantChatLine(role: .assistant, text: greetingText)]
        } else {
            lines = restored
        }
    }

    private func persistHistory() {
        switch currentMode {
        case .creator:
            store.setCreatorHistory(lines)
        case .copilot(let dish):
            store.setCopilotHistory(lines, for: dish.id)
        case .today:
            store.setTodayHistory(lines)
        }
    }

    // MARK: - Photo attachment

    private func attachPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let img = UIImage(data: data)
        else {
            await MainActor.run { errorMessage = "Couldn't load that photo." }
            return
        }
        
        let originalJPEGData = img.jpegData(compressionQuality: 0.85)
        
        // Compress for thumbnail preview in chat (max 400px, q=0.6 ≈ 30-80 KB)
        let thumbData = img.thumbnailJPEG(maxDimension: 400, quality: 0.6)
        await MainActor.run {
            photoPickItem = nil
            pendingImage = img
            uploadedDishPhotoData = originalJPEGData
            lines.append(AssistantChatLine(
                role: .user,
                text: "",
                imageData: thumbData
            ))
        }
    }

    // MARK: - Send

    @MainActor
    private func sendTapped() async {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingImage != nil || !trimmedDraft.isEmpty else { return }

        if !trimmedDraft.isEmpty {
            lines.append(AssistantChatLine(role: .user, text: trimmedDraft))
            draft = ""
            
            // Extract user preferences concurrently in the background
            Task {
                if let newPref = await store.detectAndSaveUserPreference(from: trimmedDraft) {
                    await MainActor.run {
                        lines.append(AssistantChatLine(
                            role: .assistant,
                            text: "💡 Memory updated: Saved your dietary preference \"\(newPref)\"."
                        ))
                    }
                }
            }
        }

        isWorking = true
        defer {
            isWorking = false
            persistHistory()
        }

        do {
            switch currentMode {
            case .creator(let initialGroup, let initialChef):
                try await handleCreator(prompt: trimmedDraft, image: pendingImage, initialGroup: initialGroup, initialChef: initialChef)
            case .copilot(let dish):
                try await handleCopilot(prompt: trimmedDraft, image: pendingImage, dish: dish)
            case .today(let day, let mealNames):
                try await handleToday(prompt: trimmedDraft, day: day, mealNames: mealNames)
            }
            pendingImage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Creator mode

    @MainActor
    private func handleCreator(prompt: String, image: UIImage?, initialGroup: DishGroup?, initialChef: Chef?) async throws {
        let history = lines.compactMap { line -> ChatTurn? in
            ChatTurn(role: line.role == .user ? .user : .assistant, text: line.text)
        }

        let currentRecipeText = pendingCandidateDish?.ingredients.joined(separator: "\n") ?? ""

        // Pass the candidate's accumulated tags/chefs/group to the AI
        // so it knows what's already set on the draft.
        let candidateTags = pendingCandidateDish?.tags ?? []
        let candidateChefs = pendingCandidateDish?.chefs ?? (initialChef != nil ? [initialChef!.name] : [])
        let candidateGroup = pendingCandidateDish?.groupName ?? initialGroup?.name ?? ""
        let groupNames = store.allGroups().map(\.name)

        let action = try await store.converseWithCreator(
            prompt: prompt,
            image: image,
            draftDishesNames: pendingCandidateDish?.name ?? "",
            currentRecipe: currentRecipeText,
            groupName: candidateGroup,
            tags: candidateTags,
            chefs: candidateChefs,
            availableGroups: groupNames,
            history: history
        )

        // Always show the reply
        if !action.reply.isEmpty {
            lines.append(AssistantChatLine(role: .assistant, text: action.reply))
        }

        // If we already have a candidate, apply modifications to it
        if pendingCandidateDish != nil {
            let summary = applyCreatorAction(action, image: image)
            if let summary {
                lines.append(AssistantChatLine(role: .assistant, text: summary))
            }
            return
        }

        // If no candidate exists yet, handle creation of a new candidate
        if action.action == .create_dish, let title = action.title, !title.isEmpty {
            let candidate = DishCandidate(
                name: title,
                description: action.description ?? "",
                groupName: action.groupName,
                ingredients: action.ingredients?.map { ing in
                    RecipeIngredientFormat.compoundLine(
                        quantity: ing.qty ?? "",
                        unit: ing.unit ?? "",
                        name: ing.name ?? ""
                    )
                } ?? [],
                steps: action.steps?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
            )
            pendingCandidateDish = candidate

            lines.append(AssistantChatLine(
                role: .assistant,
                text: "✨ I've drafted a new dish: **\"\(title)\"**!\n\n🎨 Drawing the sketch illustration in the background right now. I will post it here when it's ready!"
            ))

            // Generate illustration in background and append it when ready
            Task {
                do {
                    let imgData = try await store.gemini.generateIllustration(
                        dishName: title,
                        dishDescription: action.description ?? "",
                        artDirection: nil,
                        image: image
                    )
                    await MainActor.run {
                        if pendingCandidateDish?.name == title {
                            pendingCandidateDish?.illustration = imgData
                            lines.append(AssistantChatLine(
                                role: .assistant,
                                text: "🎨 Here is the sketch illustration for **\"\(title)\"**! How do you like this graph, or would you like to redraw it with some instructions?",
                                illustrationData: imgData
                            ))
                        }
                    }
                } catch {
                    await MainActor.run {
                        lines.append(AssistantChatLine(
                            role: .assistant,
                            text: "⚠️ I couldn't generate the illustration sketch: \(error.localizedDescription). You can try asking me to \"redraw it\" with different instructions."
                        ))
                    }
                }
            }
        }
    }

    private func applyCreatorAction(_ action: AssistantAction, image: UIImage? = nil) -> String? {
        guard var candidate = pendingCandidateDish else { return nil }
        
        switch action.action {
        case .update_title:
            if let t = action.title, !t.isEmpty {
                let old = candidate.name
                candidate.name = t
                pendingCandidateDish = candidate
                return "✏️ Title updated: \"\(old)\" → \"\(t)\""
            }
        case .update_description:
            if let d = action.description, !d.isEmpty {
                candidate.description = d
                pendingCandidateDish = candidate
                return "📝 Description updated:\n\(d)"
            }
        case .update_recipe:
            if let ings = action.ingredients, !ings.isEmpty {
                candidate.ingredients = ings.map { ing in
                    RecipeIngredientFormat.compoundLine(
                        quantity: ing.qty ?? "",
                        unit: ing.unit ?? "",
                        name: ing.name ?? ""
                    )
                }
                if let steps = action.steps {
                    candidate.steps = steps
                }
                pendingCandidateDish = candidate
                return Self.formatRecipeChangeSummary(ingredients: ings, steps: candidate.steps)
            } else if let steps = action.steps, !steps.isEmpty {
                candidate.steps = steps
                pendingCandidateDish = candidate
                return Self.formatStepsChangeSummary(steps: steps)
            }
        case .redraw:
            let title = candidate.name
            let desc = candidate.description
            Task {
                do {
                    let imgData = try await store.gemini.generateIllustration(
                        dishName: title,
                        dishDescription: desc,
                        artDirection: action.redrawNotes,
                        image: image
                    )
                    await MainActor.run {
                        if pendingCandidateDish?.name == title {
                            pendingCandidateDish?.illustration = imgData
                            lines.append(AssistantChatLine(
                                role: .assistant,
                                text: "🎨 Here is the redrawn sketch illustration! How do you like this graph, or would you like to redraw it again with some instructions?",
                                illustrationData: imgData
                            ))
                        }
                    }
                } catch {
                    await MainActor.run {
                        lines.append(AssistantChatLine(
                            role: .assistant,
                            text: "⚠️ I couldn't redraw the illustration sketch: \(error.localizedDescription)"
                        ))
                    }
                }
            }
            return "🎨 Redrawing the illustration sketch right now in the background..."
        case .add_tag:
            if let tag = action.tag, !tag.isEmpty {
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.tags.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                    candidate.tags.append(normalized)
                }
                pendingCandidateDish = candidate
                return "🏷️ Tag added: \(normalized)"
            }
        case .remove_tag:
            if let tag = action.tag, !tag.isEmpty {
                candidate.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                pendingCandidateDish = candidate
                return "🏷️ Tag removed: \(tag)"
            }
        case .add_chef:
            if let name = action.chefName, !name.isEmpty {
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.chefs.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                    candidate.chefs.append(normalized)
                }
                pendingCandidateDish = candidate
                return "👨‍🍳 Chef added: \(normalized)"
            }
        case .set_group:
            if let gName = action.groupName, !gName.isEmpty {
                candidate.groupName = gName.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingCandidateDish = candidate
                return "📂 Group set to: \(candidate.groupName!)"
            }
        case .reply, .create_dish:
            break
        }
        return nil
    }

    // MARK: - Copilot mode

    @MainActor
    private func handleCopilot(prompt: String, image: UIImage?, dish: Dish) async throws {
        // If there's an image but no text prompt, try recipe extraction first
        if let img = image, prompt.isEmpty {
            let extracted = try await store.extractRecipe(from: img)
            if !extracted.isEmpty {
                applyExtractedRecipe(extracted, to: dish)
                pendingExtractedRecipe = extracted
                lines.append(AssistantChatLine(
                    role: .assistant,
                    text: "I scanned that photo and extracted the recipe:\n\n\(Self.formatExtractedRecipe(extracted))"
                ))
                lines.append(AssistantChatLine(
                    role: .assistant,
                    text: "Does this look correct, or is there anything you would like to change?"
                ))
                return
            }
        }

        // Check for YouTube URL
        if let url = Self.firstYouTubeURL(in: prompt) {
            let extracted = try await store.extractRecipe(fromVideoURL: url)
            if !extracted.isEmpty {
                applyExtractedRecipe(extracted, to: dish)
                pendingExtractedRecipe = extracted
                lines.append(AssistantChatLine(
                    role: .assistant,
                    text: "Got it! I extracted the recipe from that video:\n\n\(Self.formatExtractedRecipe(extracted))"
                ))
                lines.append(AssistantChatLine(
                    role: .assistant,
                    text: "Does this look correct, or is there anything you would like to change?"
                ))
                return
            }
        }

        // Conversational copilot
        let history = lines.compactMap { line -> ChatTurn? in
            ChatTurn(role: line.role == .user ? .user : .assistant, text: line.text)
        }

        let action = try await store.converseWithAssistant(
            prompt: prompt,
            image: image,
            dish: dish,
            history: history
        )

        // Show the reply
        if !action.reply.isEmpty {
            lines.append(AssistantChatLine(role: .assistant, text: action.reply))
        }

        // Apply structured actions and show change summary
        let changeSummary = applyCopilotAction(action, to: dish, image: image)
        if let summary = changeSummary {
            lines.append(AssistantChatLine(role: .assistant, text: summary))
        }
    }

    /// Applies the AI action to the dish and returns an optional change summary for the chat.
    @discardableResult
    private func applyCopilotAction(_ action: AssistantAction, to dish: Dish, image: UIImage? = nil) -> String? {
        switch action.action {
        case .update_recipe:
            if let ings = action.ingredients, !ings.isEmpty {
                let qtys = ings.map { $0.qty ?? "" }
                let units = ings.map { $0.unit ?? "" }
                let items = ings.map { $0.name ?? "" }
                let steps = action.steps ?? dish.steps
                store.updateRecipe(
                    dish,
                    ingredientQuantities: qtys,
                    ingredientUnits: units,
                    ingredientItems: items,
                    steps: steps
                )
                if pendingExtractedRecipe != nil {
                    pendingExtractedRecipe = ExtractedRecipe(
                        ingredients: dish.ingredients,
                        steps: steps
                    )
                }
                return Self.formatRecipeChangeSummary(ingredients: ings, steps: steps)
            } else if let steps = action.steps, !steps.isEmpty {
                store.updateRecipe(
                    dish,
                    ingredientQuantities: dish.ingredientQty,
                    ingredientUnits: dish.ingredientUnit,
                    ingredientItems: dish.ingredientItem,
                    steps: steps
                )
                if pendingExtractedRecipe != nil {
                    pendingExtractedRecipe = ExtractedRecipe(
                        ingredients: dish.ingredients,
                        steps: steps
                    )
                }
                return Self.formatStepsChangeSummary(steps: steps)
            }
            return nil
        case .update_title:
            if let t = action.title, !t.isEmpty {
                let old = dish.name
                store.updateDishDetails(dish, name: t, description: dish.dishDescription)
                return "✏️ Title updated: \"\(old)\" → \"\(t)\""
            }
            return nil
        case .update_description:
            if let d = action.description, !d.isEmpty {
                store.updateDishDetails(dish, name: dish.name, description: d)
                return "📝 Description updated:\n\(d)"
            }
            return nil
        case .add_tag:
            if let tag = action.tag, !tag.isEmpty {
                var tags = dish.tags
                tags.append(tag)
                store.updateTags(dish, tags: tags)
                return "🏷️ Tag added: \(tag)"
            }
            return nil
        case .remove_tag:
            if let tag = action.tag, !tag.isEmpty {
                let filtered = dish.tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
                store.updateTags(dish, tags: filtered)
                return "🏷️ Tag removed: \(tag)"
            }
            return nil
        case .add_chef:
            if let name = action.chefName, !name.isEmpty {
                store.linkChef(named: name, to: dish)
                return "👨‍🍳 Chef added: \(name)"
            }
            return nil
        case .set_group:
            if let gName = action.groupName, !gName.isEmpty {
                let group = store.allGroups().first { $0.name.caseInsensitiveCompare(gName) == .orderedSame }
                store.setGroup(group, for: dish)
                return "📂 Group set to: \(gName)"
            }
            return nil
        case .redraw:
            Task {
                do {
                    try await store.redrawMenuIllustration(dish, artDirection: action.redrawNotes, image: image)
                    await MainActor.run {
                        if let imgData = dish.imageData {
                            lines.append(AssistantChatLine(
                                role: .assistant,
                                text: "🎨 Here is the redrawn sketch illustration! How do you like this graph, or would you like to redraw it again with some instructions?",
                                illustrationData: imgData
                            ))
                        }
                    }
                } catch {
                    await MainActor.run {
                        lines.append(AssistantChatLine(
                            role: .assistant,
                            text: "⚠️ I couldn't redraw the illustration sketch: \(error.localizedDescription)."
                        ))
                    }
                }
            }
            return "🎨 Redrawing the illustration sketch right now in the background..."
        case .reply, .create_dish:
            return nil
        }
    }

    private func applyExtractedRecipe(_ extracted: ExtractedRecipe, to dish: Dish) {
        var qtys: [String] = []
        var units: [String] = []
        var items: [String] = []
        for ing in extracted.ingredients {
            let (q, u, n) = RecipeIngredientFormat.parseImportedOrLegacy(ing)
            qtys.append(q)
            units.append(u)
            items.append(n)
        }
        store.updateRecipe(
            dish,
            ingredientQuantities: qtys,
            ingredientUnits: units,
            ingredientItems: items,
            steps: extracted.steps
        )
    }

    // MARK: - Change summary formatting

    private static func formatExtractedRecipe(_ recipe: ExtractedRecipe) -> String {
        var parts: [String] = []
        if !recipe.ingredients.isEmpty {
            parts.append("🥬 Ingredients:")
            for ing in recipe.ingredients {
                parts.append("  • \(ing)")
            }
        }
        if !recipe.steps.isEmpty {
            if !parts.isEmpty { parts.append("") }
            parts.append("📋 Steps:")
            for (i, step) in recipe.steps.enumerated() {
                parts.append("  \(i + 1). \(step)")
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func formatRecipeChangeSummary(ingredients: [AssistantIngredient], steps: [String]) -> String {
        var parts: [String] = ["📖 Recipe updated:"]
        if !ingredients.isEmpty {
            parts.append("")
            parts.append("🥬 Ingredients:")
            for ing in ingredients {
                let line = RecipeIngredientFormat.compoundLine(
                    quantity: ing.qty ?? "",
                    unit: ing.unit ?? "",
                    name: ing.name ?? ""
                )
                if !line.isEmpty {
                    parts.append("  • \(line)")
                }
            }
        }
        if !steps.isEmpty {
            parts.append("")
            parts.append("📋 Steps:")
            for (i, step) in steps.enumerated() {
                let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append("  \(i + 1). \(trimmed)")
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func formatStepsChangeSummary(steps: [String]) -> String {
        var parts: [String] = ["📋 Steps updated:"]
        for (i, step) in steps.enumerated() {
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append("  \(i + 1). \(trimmed)")
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Today mode

    @MainActor
    private func handleToday(prompt: String, day: Date, mealNames: [String]) async throws {
        let history = lines.compactMap { line -> ChatTurn? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ChatTurn(role: line.role == .user ? .user : .assistant, text: text)
        }

        let plan = try await store.generateDayMealPlanForToday(
            day: day,
            mealNames: mealNames,
            userNote: prompt.isEmpty ? nil : prompt,
            history: history
        )

        store.replaceTodayEntries(with: plan, day: day, mealNames: mealNames)
        store.setTodayLastGeneratedPlan(plan)

        // Build a summary reply
        let dishes = store.allDishes()
        let byId = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })
        var summary = "Done! Here's what I planned:\n"
        for assignment in plan.assignments {
            let dishNames = assignment.dishIds.compactMap { byId[$0]?.name }
            if dishNames.isEmpty { continue }
            summary += "\n**\(assignment.mealName):** \(dishNames.joined(separator: ", "))"
        }
        summary += "\n\nYou can close this and check the Today tab, or tell me to adjust."

        lines.append(AssistantChatLine(role: .assistant, text: summary))
    }

    // MARK: - YouTube URL extraction

    private static func firstYouTubeURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in detector.matches(in: text, options: [], range: range) where match.resultType == .link {
            guard let url = match.url?.absoluteString else { continue }
            let host = (match.url?.host ?? "").lowercased()
            if host.contains("youtube") || host == "youtu.be" || host.contains("youtu.be") {
                return url
            }
        }
        return nil
    }
}

// MARK: - UIImage thumbnail helper

private extension UIImage {
    /// Compress to a small JPEG thumbnail for chat preview display.
    func thumbnailJPEG(maxDimension: CGFloat = 400, quality: CGFloat = 0.6) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 1 else { return nil }
        let scale = min(1, maxDimension / longestSide)
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
