import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Share Card (rendered to image via ImageRenderer)

/// A self-contained SwiftUI view that renders today's menu as a beautiful
/// paper-textured card suitable for sharing. Designed to look stunning as a
/// screenshot — clean typography, subtle textures, and a branded footer.
struct TodayMenuShareCard: View {
    let title: String
    let day: Date
    /// Each tuple is a meal name + ordered list of dish names.
    let meals: [(name: String, dishes: [String])]

    private var cardWidth: CGFloat { 390 }

    private var dateLabel: String {
        day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var body: some View {
        ZStack {
            // Paper background
            Theme.paper

            // Subtle grain texture overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color(red: 0.97, green: 0.96, blue: 0.93).opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                // ── Header ────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(Theme.title(32, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text(dateLabel)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(Theme.inkFaded)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 24)

                // ── Divider ───────────────────────────────────────────────
                Rectangle()
                    .fill(Theme.ink.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 28)

                // ── Meal sections ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                        ShareCardMealRow(mealName: meal.name, dishNames: meal.dishes)

                        if index < meals.count - 1 {
                            // Dotted divider between meals
                            HStack(spacing: 3) {
                                ForEach(0..<38, id: \.self) { _ in
                                    Circle()
                                        .fill(Theme.ink.opacity(0.18))
                                        .frame(width: 2, height: 2)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)

                // ── Divider ───────────────────────────────────────────────
                Rectangle()
                    .fill(Theme.ink.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 28)

                // ── Footer / branding ─────────────────────────────────────
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkFaded)
                    Text("Lemon · My Personal Café")
                        .font(Theme.serif(12).italic())
                        .foregroundStyle(Theme.inkFaded)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
            }
        }
        .frame(width: cardWidth)
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 6)
    }
}

/// One meal block inside the share card.
private struct ShareCardMealRow: View {
    let mealName: String
    let dishNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mealName.uppercased())
                .font(Theme.serif(12, weight: .semibold))
                .tracking(5)
                .foregroundStyle(Theme.inkSoft)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(dishNames, id: \.self) { name in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Decorative bullet
                        Text("·")
                            .font(Theme.serif(18, weight: .light))
                            .foregroundStyle(Theme.inkFaded)
                        Text(name)
                            .font(Theme.dishName(18, weight: .light))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
    }
}

// MARK: - Shareable Image conforming to Transferable

/// A custom transferable model wrapping UIImage that registers as PNG image data.
/// This ensures the system share sheet and third-party extensions (like WeChat)
/// recognize the shared item directly as a photo rather than a document file.
struct ShareableImage: Transferable {
    let image: UIImage
    let title: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { shareable in
            guard let data = shareable.image.pngData() else {
                throw TransferError.exportFailed
            }
            return data
        }
    }
    
    enum TransferError: Error {
        case exportFailed
    }
}

// MARK: - Share Sheet Wrapper

/// Presents a preview of the rendered menu card and allows sharing it natively as a photo.
struct TodayMenuShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let image: UIImage

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark paper preview background
                Color(red: 0.12, green: 0.11, blue: 0.10)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Card preview
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                        .padding(.horizontal, 24)

                    // Share button using native ShareLink wrapping our Transferable ShareableImage
                    ShareLink(
                        item: ShareableImage(image: image, title: title),
                        preview: SharePreview(title, image: Image(uiImage: image))
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Share")
                                .font(Theme.serif(17, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.ink)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }
                .padding(.top, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Theme.serif(16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0.12, green: 0.11, blue: 0.10))
    }
}
