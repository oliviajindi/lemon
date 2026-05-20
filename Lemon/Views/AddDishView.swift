import SwiftUI
import PhotosUI

/// Add flow with two input modes that can be combined:
///   - Type a dish name or description.
///   - Pick a photo (which may contain multiple dishes).
/// After "Find dishes" the AI returns 1+ dishes; for each, an illustration is
/// generated in parallel. The user can edit name / description, redraw, or
/// remove any candidate before saving them all to the menu.
struct AddDishView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore
    @EnvironmentObject private var config: AppConfig
    var onSaved: () -> Void = {}

    enum Step: Hashable { case input, preview }
    @State private var step: Step = .input

    @State private var inputText: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?

    @State private var candidates: [DishCandidate] = []
    @State private var batchGroup: DishGroup?

    @State private var error: String?
    @State private var isBusy: Bool = false

    init(initialGroup: DishGroup? = nil, onSaved: @escaping () -> Void = {}) {
        self.onSaved = onSaved
        self._batchGroup = State(initialValue: initialGroup)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        switch step {
                        case .input:   inputStep
                        case .preview: previewStep
                        }
                        if let error {
                            Text(error)
                                .font(Theme.serif(13).italic())
                                .foregroundStyle(Theme.accent)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(20)
                }
                .paperBackground()
                if isBusy { BusyOverlay(message: store.statusMessage ?? "Working…") }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exit") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add to your menu")
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            Text(stepDescription)
                .font(Theme.serif(14).italic())
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var stepDescription: String {
        switch step {
        case .input:
            return "Type the dish, pick a photo, or both. The AI will draw each dish it finds."
        case .preview:
            let n = activeCandidates.count
            if n <= 1 { return "Tweak the name if needed, then add it to your menu." }
            return "Found \(n) dishes. Edit, redraw, or remove — then add them all."
        }
    }

    // MARK: - Step 1: input

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Text field
            VStack(alignment: .leading, spacing: 6) {
                Text("Dish name or description (optional)")
                    .font(Theme.hand(15))
                    .foregroundStyle(Theme.inkSoft)
                TextField("e.g. miso-butter pasta with corn", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(Theme.serif(17))
                    .padding(12)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .cardStroke(cornerRadius: 10)
            }

            // Photo picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Photo (optional)")
                    .font(Theme.hand(15))
                    .foregroundStyle(Theme.inkSoft)

                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(sourceImage == nil ? "Pick a photo" : "Change photo",
                              systemImage: "photo")
                            .font(Theme.hand(15))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(Theme.ink)
                            .background(Color.white.opacity(0.6))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.ink.opacity(0.22), lineWidth: 1)
                            )
                    }
                    if sourceImage != nil {
                        Button("Remove photo") {
                            sourceImage = nil
                            photoItem = nil
                        }
                        .font(Theme.hand(14))
                        .foregroundStyle(Theme.accent)
                    }
                }
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadPickedPhoto(newItem) }
                }

                if let sourceImage {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .cardStroke(cornerRadius: 12)
                }
            }

            // Action
            Button {
                Task { await findDishes() }
            } label: {
                Text(actionLabel)
                    .font(Theme.display(18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? Theme.ink : Theme.inkFaded)
                    .foregroundStyle(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canSubmit)
        }
    }

    private var canSubmit: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
        return hasText || sourceImage != nil
    }

    private var actionLabel: String {
        if sourceImage != nil { return "Find dishes & draw" }
        return "Draw it"
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                sourceImage = img
            } else {
                error = "Couldn't read that photo."
            }
        } catch {
            self.error = "Couldn't read that photo: \(error.localizedDescription)"
        }
    }

    private func findDishes() async {
        error = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let ids = try await store.identify(text: inputText, image: sourceImage)
            candidates = ids.map {
                DishCandidate(name: $0.name, description: $0.shortDescription, isGenerating: true)
            }
            step = .preview
        } catch {
            self.error = error.localizedDescription
            return
        }
        // Kick off illustration generation for every candidate in parallel.
        await withTaskGroup(of: Void.self) { group in
            for cand in candidates {
                let id = cand.id
                group.addTask { @MainActor in
                    await self.drawCandidate(id: id)
                }
            }
        }
    }

    // MARK: - Step 2: preview

    private var activeCandidates: [DishCandidate] { candidates }

    @ViewBuilder
    private var previewStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(candidates.count > 1 ? "Group these dishes under" : "Add to group")
                    .font(Theme.hand(13))
                    .foregroundStyle(Theme.inkSoft)
                GroupPicker(selection: $batchGroup)
            }

            ForEach($candidates) { $candidate in
                CandidateCard(
                    candidate: $candidate,
                    onRedrawWithHints: { hints in
                        Task { await drawCandidate(id: candidate.id, artDirection: hints) }
                    },
                    onRemove: { candidates.removeAll { $0.id == candidate.id } }
                )
            }

            HStack {
                Button("Start over") { reset() }
                    .font(Theme.hand(14))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Button(action: saveAll) {
                    Text(saveLabel)
                        .font(Theme.display(18))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(canSave ? Theme.ink : Theme.inkFaded)
                        .foregroundStyle(Theme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !candidates.isEmpty &&
        candidates.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var saveLabel: String {
        let n = candidates.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return n <= 1 ? "Add to menu" : "Add \(n) to menu"
    }

    // MARK: - Illustration generation

    @MainActor
    private func drawCandidate(id: UUID, artDirection: String = "") async {
        guard let startIdx = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[startIdx].isGenerating = true
        candidates[startIdx].error = nil
        let name = candidates[startIdx].name
        let desc = candidates[startIdx].description
        let hint = artDirection.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let data = try await store.gemini.generateIllustration(
                dishName: name,
                dishDescription: desc,
                artDirection: hint.isEmpty ? nil : hint
            )
            if let idx = candidates.firstIndex(where: { $0.id == id }) {
                candidates[idx].illustration = data
                candidates[idx].isGenerating = false
            }
        } catch {
            if let idx = candidates.firstIndex(where: { $0.id == id }) {
                candidates[idx].isGenerating = false
                candidates[idx].error = error.localizedDescription
            }
        }
    }

    // MARK: - Save / reset

    private func saveAll() {
        for cand in candidates {
            let name = cand.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let dish = Dish(
                name: name,
                dishDescription: cand.description.trimmingCharacters(in: .whitespacesAndNewlines),
                imageData: cand.illustration,
                group: batchGroup,
                tags: DishTags.parsed(from: cand.tagsText)
            )
            store.insertDish(dish)
        }
        reset()
        onSaved()
    }

    private func reset() {
        step = .input
        inputText = ""
        photoItem = nil
        sourceImage = nil
        candidates = []
        batchGroup = nil
        error = nil
    }
}

// MARK: - Candidate model + card

struct DishCandidate: Identifiable, Equatable {
    let id: UUID = UUID()
    var name: String
    var description: String
    var tagsText: String = ""
    var illustration: Data? = nil
    var isGenerating: Bool = false
    var error: String? = nil

    static func == (l: Self, r: Self) -> Bool {
        l.id == r.id &&
        l.name == r.name &&
        l.description == r.description &&
        l.tagsText == r.tagsText &&
        l.illustration == r.illustration &&
        l.isGenerating == r.isGenerating &&
        l.error == r.error
    }
}

private struct CandidateCard: View {
    @Binding var candidate: DishCandidate
    /// Pass art-direction text from the redraw sheet (empty string = same as last draw).
    let onRedrawWithHints: (String) -> Void
    let onRemove: () -> Void

    @State private var showRedrawSheet = false
    @State private var redrawNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                illustration
                Spacer()
                Menu {
                    Button {
                        redrawNotes = ""
                        showRedrawSheet = true
                    } label: {
                        Label("Redraw…", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        onRemove()
                    } label: { Label("Remove from batch", systemImage: "xmark") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(Theme.hand(13))
                    .foregroundStyle(Theme.inkSoft)
                TextField("Dish name", text: $candidate.name)
                    .font(Theme.display(20))
                    .padding(10)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .cardStroke(cornerRadius: 10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(Theme.hand(13))
                    .foregroundStyle(Theme.inkSoft)
                TextField("Short description", text: $candidate.description, axis: .vertical)
                    .font(Theme.serif(14).italic())
                    .lineLimit(1...3)
                    .padding(10)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .cardStroke(cornerRadius: 10)
            }

            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkFaded)
                TextField("tags: pasta, dinner, favorite", text: $candidate.tagsText)
                    .font(Theme.hand(13))
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.45))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.ink.opacity(0.25), lineWidth: 1)
            )

            if let err = candidate.error {
                Text(err)
                    .font(Theme.serif(12).italic())
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .background(Theme.paperShadow.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .cardStroke(cornerRadius: 14)
        .sheet(isPresented: $showRedrawSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tell the AI how the drawing should change — style, angle, props, mood, anything.")
                        .font(Theme.serif(14).italic())
                        .foregroundStyle(Theme.inkSoft)
                    TextField(
                        "e.g. softer watercolor, overhead view, include chopsticks…",
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
                        Button("Cancel") { showRedrawSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Regenerate") {
                            showRedrawSheet = false
                            onRedrawWithHints(redrawNotes)
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var illustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.7))
            if candidate.isGenerating {
                VStack(spacing: 6) {
                    ProgressView().tint(Theme.ink)
                    Text("drawing…")
                        .font(Theme.hand(12))
                        .foregroundStyle(Theme.inkSoft)
                }
            } else if let data = candidate.illustration, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if candidate.error != nil {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                    Button("Try again", action: { onRedrawWithHints("") })
                        .font(Theme.hand(12))
                }
                .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.inkFaded)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .cardStroke(cornerRadius: 12)
    }
}

// MARK: - Busy overlay

struct BusyOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Theme.paper)
                Text(message)
                    .font(Theme.hand(15))
                    .foregroundStyle(Theme.paper)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .transition(.opacity)
    }
}
