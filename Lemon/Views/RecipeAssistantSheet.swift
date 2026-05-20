import SwiftUI
import PhotosUI
import UIKit
import Foundation

/// Chat-style recipe import: describe a dish for the AI to draft, paste text, attach a recipe photo, or send a YouTube link.
struct RecipeAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore

    let onImported: (ExtractedRecipe) -> Void

    private struct ChatLine: Identifiable {
        enum Role { case assistant, user }
        let id = UUID()
        let role: Role
        let text: String
    }

    @State private var lines: [ChatLine] = [
        ChatLine(
            role: .assistant,
            text: "Hi — I can fill in ingredients and steps. Describe a dish and ask me to draft a recipe, paste text from anywhere, tap the photo button to scan a recipe card, or paste a YouTube cooking link. Then tap send."
        )
    ]
    @State private var draft = ""
    @State private var pendingImage: UIImage?
    @State private var photoPickItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            chatBubble(line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.paperShadow.opacity(0.35))
            }
            .paperBackground()
            .navigationTitle("Recipe assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if isWorking {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Reading your request…")
                            .font(Theme.hand(14))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .cardStroke(cornerRadius: 14)
                }
            }
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
        }
    }

    @ViewBuilder
    private func chatBubble(_ line: ChatLine) -> some View {
        HStack {
            if line.role == .user { Spacer(minLength: 40) }
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
            if line.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pendingImage != nil {
                HStack {
                    Text("Photo attached — it will be read when you send.")
                        .font(Theme.hand(12))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Button("Remove") { pendingImage = nil }
                        .font(Theme.hand(12))
                        .foregroundStyle(Theme.accent)
                }
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
                    "Message, recipe text, or YouTube link…",
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
    }

    private var canSend: Bool {
        pendingImage != nil
            || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func attachPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let img = UIImage(data: data)
        else {
            await MainActor.run { errorMessage = "Couldn't load that photo." }
            return
        }
        await MainActor.run {
            photoPickItem = nil
            pendingImage = img
            lines.append(ChatLine(role: .user, text: "Attached a recipe photo."))
        }
    }

    @MainActor
    private func sendTapped() async {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingImage != nil || !trimmedDraft.isEmpty else { return }

        if !trimmedDraft.isEmpty {
            lines.append(ChatLine(role: .user, text: trimmedDraft))
            draft = ""
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let extracted: ExtractedRecipe
            if let img = pendingImage {
                pendingImage = nil
                extracted = try await store.extractRecipe(from: img)
            } else if let url = Self.firstYouTubeURL(in: trimmedDraft) {
                extracted = try await store.extractRecipe(fromVideoURL: url)
            } else {
                extracted = try await store.extractRecipe(fromText: trimmedDraft)
            }

            guard !extracted.isEmpty else {
                lines.append(ChatLine(
                    role: .assistant,
                    text: "I couldn't pull a recipe from that. Try more detail, another photo, or a YouTube link."
                ))
                return
            }
            onImported(extracted)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
