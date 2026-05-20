import SwiftUI

/// Full-size viewer for a single user-logged photo. Shows the image, lets
/// the user edit the caption, and exposes a delete button. Presented as a
/// sheet from `DishDetailView`.
struct DishPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DishStore

    let photo: DishPhoto

    @State private var caption: String
    @State private var confirmingDelete = false

    init(photo: DishPhoto) {
        self.photo = photo
        self._caption = State(initialValue: photo.caption)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = UIImage(data: photo.imageData) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .cardStroke(cornerRadius: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.5))
                            .frame(height: 240)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(Theme.inkFaded)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .cardStroke(cornerRadius: 16)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Caption")
                            .font(Theme.hand(13))
                            .foregroundStyle(Theme.inkSoft)
                        TextField("Add a note about this photo…",
                                  text: $caption,
                                  axis: .vertical)
                            .lineLimit(1...6)
                            .font(Theme.serif(15))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .cardStroke(cornerRadius: 12)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "calendar")
                            Text(photo.effectiveDate.formatted(date: .complete, time: .shortened))
                        }
                        if photo.takenAt != nil {
                            Text("Added to Lemon \(photo.addedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.hand(12))
                                .opacity(0.7)
                        }
                    }
                    .font(Theme.hand(13))
                    .foregroundStyle(Theme.inkFaded)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete photo", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .paperBackground()
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.updatePhotoCaption(photo, to: caption)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete this photo?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    store.deletePhoto(photo)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
