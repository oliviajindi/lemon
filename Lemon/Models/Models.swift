import Foundation
import SwiftData

@Model
final class Dish {
    @Attribute(.unique) var id: UUID
    var name: String
    var dishDescription: String
    var imageData: Data?
    var createdAt: Date

    /// The section of the menu this dish belongs to. `nil` means the dish is
    /// shown under "Other dishes" on the menu.
    var group: DishGroup?

    /// User-defined tags like "pasta", "breakfast", or "kid favorite".
    /// Tags are normalized before saving so casing/spacing stays consistent.
    var tags: [String] = []

    /// Recipe lines — legacy combined strings (e.g. "250 g flour"). Kept in
    /// sync with the structured columns below whenever the user saves from
    /// the recipe editor; older data may populate only this array.
    var ingredients: [String] = []
    /// Structured ingredients: one entry per row — quantity ("250"), unit
    /// ("g"), ingredient name ("flour"). Parallel arrays, same length after save.
    var ingredientQty: [String] = []
    var ingredientUnit: [String] = []
    var ingredientItem: [String] = []
    var steps: [String] = []

    /// Free-form note alongside the recipe — anything that isn't an
    /// ingredient or step (e.g. "halve the sugar next time", a wine pairing,
    /// where you got the recipe). Default empty so older dishes migrate
    /// without intervention.
    var notes: String = ""

    /// User-uploaded photos of the actual dish — *not* used for AI
    /// generation, just kept as a personal log. Cascading delete ensures
    /// photos go away with their dish so we never orphan files on disk.
    @Relationship(deleteRule: .cascade, inverse: \DishPhoto.dish)
    var photos: [DishPhoto] = []

    init(
        id: UUID = UUID(),
        name: String,
        dishDescription: String = "",
        imageData: Data? = nil,
        group: DishGroup? = nil,
        tags: [String] = [],
        ingredients: [String] = [],
        ingredientQty: [String] = [],
        ingredientUnit: [String] = [],
        ingredientItem: [String] = [],
        steps: [String] = [],
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.dishDescription = dishDescription
        self.imageData = imageData
        self.group = group
        self.tags = DishTags.normalized(tags)
        self.ingredients = ingredients
        self.ingredientQty = ingredientQty
        self.ingredientUnit = ingredientUnit
        self.ingredientItem = ingredientItem
        self.steps = steps
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Format / parse single-line ingredient strings (AI import, legacy rows).
enum RecipeIngredientFormat {
    static func compoundLine(quantity: String, unit: String, name: String) -> String {
        let q = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty && u.isEmpty { return n }
        if q.isEmpty { return u.isEmpty ? n : "\(u) \(n)".trimmingCharacters(in: .whitespaces) }
        if u.isEmpty { return "\(q) \(n)".trimmingCharacters(in: .whitespaces) }
        return "\(q) \(u) \(n)".trimmingCharacters(in: .whitespaces)
    }

    /// Best-effort split of an imported or legacy line into qty / unit / name.
    static func parseImportedOrLegacy(_ line: String) -> (String, String, String) {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ("", "", "") }

        let parts = t.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return ("", "", "") }
        let first = parts[0]
        guard startsLikeQuantityToken(first) else {
            return ("", "", t)
        }

        var idx = 1
        var unit = ""
        if idx < parts.count {
            let cand = parts[idx]
            let hasLetter = cand.contains(where: \.isLetter)
            if hasLetter, cand.count <= 12 {
                unit = cand
                idx += 1
            }
        }
        let name = parts[idx...].joined(separator: " ")
        return (first, unit, name)
    }

    private static func startsLikeQuantityToken(_ s: String) -> Bool {
        guard let c = s.first else { return false }
        if c.isNumber { return true }
        return s.contains("/") || s == "½" || s == "¼" || s == "⅓" || s == "⅔"
    }
}

/// Shared tag parsing rules for creation, editing, and filtering.
/// Users type comma-separated tags; duplicates collapse case-insensitively.
enum DishTags {
    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let cleaned = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
        }
        return result
    }

    static func parsed(from text: String) -> [String] {
        normalized(text.split(separator: ",").map(String.init))
    }

    static func text(from tags: [String]) -> String {
        normalized(tags).joined(separator: ", ")
    }

    static func matches(_ tag: String, in tags: [String]) -> Bool {
        let needle = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tags.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle }
    }
}

/// A user-uploaded photo of a real dish (i.e. how it actually turned out),
/// kept as a personal log alongside the AI-generated illustration. Stores
/// the JPEG bytes in an external file via `.externalStorage` so the
/// underlying SQLite database stays small even with many photos.
@Model
final class DishPhoto {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var imageData: Data
    var caption: String
    /// When the user added this photo to Lemon (always set).
    var addedAt: Date
    /// When the photo was actually taken, lifted from EXIF/TIFF metadata
    /// when the user picks an image from the library. `nil` if the photo
    /// has no embedded date (rare — usually screenshots or hand-rolled
    /// imports). Calendar grouping uses `effectiveDate` so a missing
    /// EXIF date gracefully falls back to `addedAt`.
    var takenAt: Date?
    var dish: Dish?

    init(
        id: UUID = UUID(),
        imageData: Data,
        caption: String = "",
        addedAt: Date = .now,
        takenAt: Date? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.caption = caption
        self.addedAt = addedAt
        self.takenAt = takenAt
    }

    /// The date this photo represents on the food calendar — its EXIF
    /// capture date if known, otherwise when it was added to the app.
    var effectiveDate: Date { takenAt ?? addedAt }
}

/// A lightweight "I chose this from the menu today" entry. This is separate
/// from photos: a dish can be logged for today even when the user doesn't
/// upload a picture.
@Model
final class TodayDishEntry {
    @Attribute(.unique) var id: UUID
    var day: Date
    var meal: String = TodayMeal.defaultMeal.rawValue
    var course: String = TodayCourse.main.rawValue
    var createdAt: Date
    var dish: Dish?

    init(
        id: UUID = UUID(),
        dish: Dish,
        day: Date = Calendar.current.startOfDay(for: .now),
        meal: TodayMeal = .defaultMeal,
        course: TodayCourse = .main,
        createdAt: Date = .now
    ) {
        self.id = id
        self.dish = dish
        self.day = Calendar.current.startOfDay(for: day)
        self.meal = meal.rawValue
        self.course = course.rawValue
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        dish: Dish,
        day: Date = Calendar.current.startOfDay(for: .now),
        mealName: String,
        course: TodayCourse = .main,
        createdAt: Date = .now
    ) {
        self.id = id
        self.dish = dish
        self.day = Calendar.current.startOfDay(for: day)
        self.meal = mealName
        self.course = course.rawValue
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        dish: Dish,
        day: Date = Calendar.current.startOfDay(for: .now),
        mealName: String,
        courseName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.dish = dish
        self.day = Calendar.current.startOfDay(for: day)
        self.meal = mealName
        self.course = courseName
        self.createdAt = createdAt
    }
}

enum TodayMeal: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case other = "Other"

    var id: String { rawValue }

    static var defaultMeal: TodayMeal {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 11 { return .breakfast }
        if hour < 16 { return .lunch }
        return .dinner
    }
}

enum TodayCourse: String, CaseIterable, Identifiable {
    /// A course is an optional part of a meal, for example Appetizer, Main, or
    /// Dessert. Today can also have ungrouped dishes without any course.
    case appetizer = "Appetizer"
    case main = "Main"
    case dessert = "Dessert"
    case other = "Other"

    var id: String { rawValue }
}

/// A user-defined section of the menu, e.g. "Tonight's dinner", "Italian",
/// "Sunday brunch". A dish belongs to at most one group at a time.
///
/// A group's visual "logo" is either a single user-picked emoji
/// (`emoji`, preferred when set) or the SF Symbol named in `iconName`
/// (legacy fallback so groups created before emoji support still render).
@Model
final class DishGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String?            // single-grapheme emoji logo (preferred)
    var iconName: String          // SF Symbol fallback when emoji is nil/empty
    var displayOrder: Int         // user-controlled section ordering
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Dish.group)
    var dishes: [Dish] = []

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        iconName: String = "folder",
        displayOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.iconName = iconName
        self.displayOrder = displayOrder
        self.createdAt = createdAt
    }
}

/// One-day meal sketch from Gemini: assigns catalog dish UUIDs to named meals.
struct AIDayMealPlan: Equatable, Codable {
    struct Assignment: Equatable, Codable {
        /// Must match one of the user’s configured meal titles (Breakfast, Lunch, …).
        var mealName: String
        /// Dish ids from `Dish.id` — only IDs that exist in their menu are honored.
        var dishIds: [UUID]
    }

    /// One entry per meal slot the model understood; callers fill gaps as empty meals.
    var assignments: [Assignment]
}

/// Plain DTO returned by the AI: a cleaned-up dish name plus a short
/// one-line description that we feed into the illustration prompt.
struct DishIdentification: Equatable, Codable {
    var name: String
    var shortDescription: String
}

/// What the vision model extracts when the user scans a recipe from a photo.
/// Both lists are already trimmed of empty entries by the service layer.
struct ExtractedRecipe: Equatable, Codable {
    var ingredients: [String]
    var steps: [String]

    var isEmpty: Bool { ingredients.isEmpty && steps.isEmpty }
}
