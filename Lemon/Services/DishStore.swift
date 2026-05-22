import Foundation
import SwiftData
import UIKit

private enum MealPlanStoreError: LocalizedError {
    case noDishesInMenu

    var errorDescription: String? {
        switch self {
        case .noDishesInMenu:
            return "Add at least one dish to your menu before planning the day."
        }
    }
}

/// Thin facade over the SwiftData model container. Owns the Gemini client
/// and exposes simple async helpers for the two-step add flow.
@MainActor
final class DishStore: ObservableObject {
    static let sharedContainer: ModelContainer = {
        let schema = Schema([Dish.self, DishGroup.self, DishPhoto.self, TodayDishEntry.self])
        // Keep container name so existing installs keep the same on-disk SwiftData store.
        let config = ModelConfiguration("AIMenu", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    @Published var statusMessage: String?

    private(set) lazy var gemini = GeminiService(config: AppConfig.shared)
    private var context: ModelContext { Self.sharedContainer.mainContext }

    // MARK: - Reads

    func allDishes() -> [Dish] {
        let descriptor = FetchDescriptor<Dish>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func allGroups() -> [DishGroup] {
        let descriptor = FetchDescriptor<DishGroup>(
            sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Dish mutations

    func insertDish(_ dish: Dish) {
        context.insert(dish)
        try? context.save()
    }

    func deleteDish(_ dish: Dish) {
        context.delete(dish)
        try? context.save()
    }

    func setGroup(_ group: DishGroup?, for dish: Dish) {
        dish.group = group
        try? context.save()
    }

    func updateDishDetails(_ dish: Dish, name: String, description: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        dish.name = trimmedName
        dish.dishDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
    }

    /// Update chef attribution for a dish. Pass `nil` for `avatarImage` to
    /// keep the existing avatar unchanged; pass a `UIImage` to replace it.
    /// Passing an empty string for `name` clears the chef credit entirely.
    func updateChef(_ dish: Dish, name: String, avatarImage: UIImage?) {
        dish.chefName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let image = avatarImage {
            // Compress to JPEG at 0.80 quality — good enough for a small avatar.
            dish.chefAvatarData = image.jpegData(compressionQuality: 0.80)
        }
        try? context.save()
    }

    /// Clears the chef avatar photo only (keeps the name intact).
    func removeChefAvatar(_ dish: Dish) {
        dish.chefAvatarData = nil
        try? context.save()
    }


    /// Replace a dish's tags in one save. Normalization trims whitespace,
    /// collapses duplicate tags case-insensitively, and preserves display text.
    func updateTags(_ dish: Dish, tags: [String]) {
        dish.tags = DishTags.normalized(tags)
        try? context.save()
    }

    /// Replace a dish's recipe in one save. Structured ingredient columns are
    /// the source of truth; `ingredients` is rebuilt as combined lines for
    /// backward compatibility. Rows where quantity, unit, and name are all
    /// empty are dropped. `notes`: pass `nil` to leave unchanged.
    func updateRecipe(
        _ dish: Dish,
        ingredientQuantities: [String],
        ingredientUnits: [String],
        ingredientItems: [String],
        steps: [String],
        notes: String? = nil
    ) {
        let maxIdx = max(
            ingredientQuantities.count,
            ingredientUnits.count,
            ingredientItems.count
        )
        var qOut: [String] = []
        var uOut: [String] = []
        var itemOut: [String] = []
        var legacy: [String] = []

        for i in 0..<maxIdx {
            let rawQ = (i < ingredientQuantities.count ? ingredientQuantities[i] : "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawU = (i < ingredientUnits.count ? ingredientUnits[i] : "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawItem = (i < ingredientItems.count ? ingredientItems[i] : "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (q, u, it) = RecipeIngredientFormat.normalizedFields(
                quantity: rawQ,
                unit: rawU,
                name: rawItem
            )
            if q.isEmpty && u.isEmpty && it.isEmpty { continue }
            qOut.append(q)
            uOut.append(u)
            itemOut.append(it)
            legacy.append(RecipeIngredientFormat.compoundLine(quantity: q, unit: u, name: it))
        }

        dish.ingredientQty = qOut
        dish.ingredientUnit = uOut
        dish.ingredientItem = itemOut
        dish.ingredients = legacy
        dish.steps = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let notes {
            dish.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try? context.save()
    }

    /// Replace the AI menu illustration with a user-chosen photo (compressed).
    func setMenuIllustration(_ dish: Dish, image: UIImage) {
        guard let jpeg = image.compressedJPEGForLog(maxDimension: 2048, quality: 0.82) else { return }
        dish.imageData = jpeg
        try? context.save()
    }

    /// Regenerate the menu illustration with Gemini (optional art-direction text).
    func redrawMenuIllustration(_ dish: Dish, artDirection: String?) async throws {
        statusMessage = "Redrawing your dish…"
        defer { statusMessage = nil }
        let trimmedName = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let data = try await gemini.generateIllustration(
            dishName: trimmedName,
            dishDescription: dish.dishDescription,
            artDirection: artDirection
        )
        dish.imageData = data
        try? context.save()
    }

    /// Regenerate the menu illustration with Gemini based on a provided photo.
    func redrawMenuIllustrationBasedOnPhoto(_ dish: Dish, image: UIImage) async throws {
        statusMessage = "Drawing from your photo…"
        defer { statusMessage = nil }
        let trimmedName = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let data = try await gemini.generateIllustrationBasedOnPhoto(
            dishName: trimmedName,
            dishDescription: dish.dishDescription,
            image: image
        )
        dish.imageData = data
        try? context.save()
    }

    // MARK: - Today

    func addToToday(
        _ dish: Dish,
        day: Date = .now,
        meal: TodayMeal = .defaultMeal
    ) {
        addToToday(dish, day: day, mealName: meal.rawValue, courseName: "")
    }

    func addToToday(
        _ dish: Dish,
        day: Date = .now,
        mealName: String,
        course: TodayCourse = .main
    ) {
        addToToday(dish, day: day, mealName: mealName, courseName: course.rawValue)
    }

    func addToToday(
        _ dish: Dish,
        day: Date = .now,
        mealName: String,
        courseName: String
    ) {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        let normalizedMeal = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCourse = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMeal.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<TodayDishEntry>())) ?? []
        let alreadySelected = existing.contains { entry in
            entry.day == normalizedDay &&
            entry.meal == normalizedMeal &&
            entry.course == normalizedCourse &&
            entry.dish?.id == dish.id
        }
        guard !alreadySelected else { return }

        context.insert(TodayDishEntry(dish: dish, day: normalizedDay, mealName: normalizedMeal, courseName: normalizedCourse))
        try? context.save()
    }

    func removeFromToday(_ entry: TodayDishEntry) {
        context.delete(entry)
        try? context.save()
    }

    func moveTodayEntry(_ entry: TodayDishEntry, toCourseName courseName: String) {
        let normalizedCourse = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.course = normalizedCourse
        try? context.save()
    }

    func deleteTodayMeal(_ mealName: String, day: Date = .now) {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        let normalizedMeal = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (try? context.fetch(FetchDescriptor<TodayDishEntry>())) ?? []
        for entry in existing where entry.day == normalizedDay && entry.meal == normalizedMeal {
            context.delete(entry)
        }
        try? context.save()
    }

    // MARK: - Photo log

    /// Attach a user-uploaded photo to a dish. The image is compressed to a
    /// reasonable max size before being persisted so SwiftData's external
    /// blob store doesn't fill up with multi-MB camera originals.
    ///
    /// `takenAt` should be the photo's EXIF capture date when available
    /// (parsed from the original bytes via `Data.exifCaptureDate()`). The
    /// food calendar groups by `effectiveDate`, so passing `takenAt` here
    /// is what makes "May 12" actually mean "the day I cooked this", not
    /// "the day I imported the picture".
    @discardableResult
    func addPhoto(
        _ image: UIImage,
        caption: String = "",
        takenAt: Date? = nil,
        to dish: Dish
    ) -> DishPhoto? {
        guard let jpeg = image.compressedJPEGForLog() else { return nil }
        let photo = DishPhoto(imageData: jpeg, caption: caption, takenAt: takenAt)
        photo.dish = dish
        context.insert(photo)
        try? context.save()
        return photo
    }

    func deletePhoto(_ photo: DishPhoto) {
        context.delete(photo)
        try? context.save()
    }

    func updatePhotoCaption(_ photo: DishPhoto, to caption: String) {
        photo.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
    }

    // MARK: - Group mutations

    /// Inserts a new group, putting it after every existing group in display order.
    @discardableResult
    func createGroup(name: String, emoji: String? = nil, iconName: String = "folder") -> DishGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextOrder = (allGroups().map(\.displayOrder).max() ?? -1) + 1
        let group = DishGroup(
            name: trimmed,
            emoji: Self.sanitizedEmoji(emoji),
            iconName: iconName,
            displayOrder: nextOrder
        )
        context.insert(group)
        try? context.save()
        return group
    }

    func renameGroup(_ group: DishGroup, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        group.name = trimmed
        try? context.save()
    }

    /// Update the user-visible fields of a group (name + emoji) in one save.
    /// An empty / whitespace `emoji` clears the field so the SF Symbol icon
    /// shows again.
    func updateGroup(_ group: DishGroup, name: String, emoji: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { group.name = trimmedName }
        group.emoji = Self.sanitizedEmoji(emoji)
        try? context.save()
    }

    func updateGroupEmoji(_ group: DishGroup, emoji: String?) {
        group.emoji = Self.sanitizedEmoji(emoji)
        try? context.save()
    }

    func updateGroupDescription(_ group: DishGroup, description: String?) {
        group.groupDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
    }

    /// Trim to a single grapheme cluster and treat blanks as `nil` so callers
    /// don't have to remember the rule.
    private static func sanitizedEmoji(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = stripped.first else { return nil }
        return String(first)
    }

    /// Deletes a group. Any dishes that were in this group fall back to
    /// "Other dishes" via the `.nullify` delete rule on the relationship.
    func deleteGroup(_ group: DishGroup) {
        context.delete(group)
        try? context.save()
    }

    /// Reorder a group to a new display position (0 = top). Recomputes the
    /// ordering of all groups to keep the values dense.
    func moveGroup(_ group: DishGroup, to index: Int) {
        var groups = allGroups()
        groups.removeAll { $0.id == group.id }
        let clamped = max(0, min(index, groups.count))
        groups.insert(group, at: clamped)
        for (i, g) in groups.enumerated() {
            g.displayOrder = i
        }
        try? context.save()
    }

    // MARK: - AI orchestration

    func identify(text: String, image: UIImage?) async throws -> [DishIdentification] {
        statusMessage = image == nil
            ? "Gemini is drawing!"
            : "Looking at the photo for dishes…"
        defer { statusMessage = nil }
        return try await gemini.identifyDishes(text: text, image: image)
    }

    func generateIllustration(for identification: DishIdentification, artDirection: String? = nil) async throws -> Data {
        statusMessage = "Drawing your dish by hand…"
        defer { statusMessage = nil }
        return try await gemini.generateIllustration(
            dishName: identification.name,
            dishDescription: identification.shortDescription,
            artDirection: artDirection
        )
    }

    func extractRecipe(from image: UIImage) async throws -> ExtractedRecipe {
        statusMessage = "Reading the recipe from your photo…"
        defer { statusMessage = nil }
        return try await gemini.extractRecipe(from: image)
    }

    /// Extract a recipe from free-form text the user typed/pasted in.
    func extractRecipe(fromText text: String) async throws -> ExtractedRecipe {
        statusMessage = "Reading the recipe from your notes…"
        defer { statusMessage = nil }
        return try await gemini.extractRecipe(fromText: text)
    }

    /// Extract a recipe from a video URL (YouTube only for now — see the
    /// note in `GeminiService.extractRecipe(fromVideoURL:)`).
    func extractRecipe(fromVideoURL urlString: String) async throws -> ExtractedRecipe {
        statusMessage = "Watching the video for a recipe…"
        defer { statusMessage = nil }
        return try await gemini.extractRecipe(fromVideoURL: urlString)
    }

    // MARK: - AI day plan (Today)

    /// Ask Gemini to assign saved dishes to each meal slot. Caller typically
    /// follows with `replaceTodayEntries(with:day:mealNames:)` to apply it.
    func generateDayMealPlanForToday(day: Date, mealNames: [String], userNote: String?) async throws -> AIDayMealPlan {
        statusMessage = "Planning your day from the menu…"
        defer { statusMessage = nil }

        let dishes = allDishes()
        guard !dishes.isEmpty else { throw MealPlanStoreError.noDishesInMenu }

        let dayStart = Calendar.current.startOfDay(for: day)
        let desc = dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let catalog = dishes.map { ($0.id, $0.name, $0.tags) }
        return try await gemini.generateDayMealPlan(
            mealNames: mealNames,
            dishCatalog: catalog,
            formattedDayDescription: desc,
            userNote: userNote
        )
    }

    /// Remove every `TodayDishEntry` on this calendar day, then insert planned dishes.
    func replaceTodayEntries(with plan: AIDayMealPlan, day: Date, mealNames: [String]) {
        let dayStart = Calendar.current.startOfDay(for: day)
        let existing = (try? context.fetch(FetchDescriptor<TodayDishEntry>())) ?? []
        for entry in existing where entry.day == dayStart {
            context.delete(entry)
        }

        let dishes = allDishes()
        let byId = Dictionary(uniqueKeysWithValues: dishes.map { ($0.id, $0) })

        func canonicalMeal(for raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return mealNames.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        }

        for assignment in plan.assignments {
            guard let meal = canonicalMeal(for: assignment.mealName) else { continue }
            for id in assignment.dishIds {
                guard let dish = byId[id] else { continue }
                addToToday(dish, day: dayStart, mealName: meal, courseName: "")
            }
        }
        try? context.save()
    }
}

private extension UIImage {
    /// Compress a user-uploaded photo for the dish log. We resize so the
    /// longest side is at most ~2048 px (visually crisp on iPhone/iPad without
    /// being huge), then JPEG-encode at q=0.75 — roughly 200–500 KB per photo.
    ///
    /// Falling back to PNG would balloon storage; we don't need transparency.
    func compressedJPEGForLog(maxDimension: CGFloat = 2048, quality: CGFloat = 0.75) -> Data? {
        let longestSide = max(size.width, size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // Render at 1x so pixel dimensions match `target`.
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
