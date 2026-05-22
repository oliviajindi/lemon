import Foundation
import UIKit
import FirebaseAILogic

enum GeminiError: LocalizedError {
    case empty
    case decoding(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .empty:                  return "The AI returned no usable content."
        case .decoding(let message):  return "Failed to decode AI response: \(message)"
        case .badResponse(let msg):   return "AI returned error: \(msg)"
        }
    }
}

actor GeminiService {
    private let config: AppConfig
    private let session: URLSession

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Public

    /// Identify one or more dishes from a text hint, a photo, or both.
    func identifyDishes(text: String, image: UIImage?) async throws -> [DishIdentification] {
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.3,
                responseMIMEType: "application/json",
                responseSchema: Self.identifySchema
            )
        )
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var promptLines: [String] = [
            "You are helping someone keep a personal menu of dishes they cook or eat.",
            "Identify every distinct dish in the input and return concise JSON matching the schema."
        ]
        if image != nil {
            promptLines.append("A photo is provided. List every separately-served dish you can see (a bowl of soup, a plate of entrée, a side salad, a drink, a dessert, etc.).")
            promptLines.append("Do not list ingredients — only assembled, served dishes.")
            promptLines.append("If only one dish is visible, return an array with a single element.")
        }
        if !trimmed.isEmpty {
            promptLines.append("The user also wrote: \"\(trimmed)\". Use it as a hint; if it conflicts with the photo, prefer the photo but mention the hint in shortDescription.")
        }
        promptLines.append("IMPORTANT — Language rules:")
        promptLines.append("- First, detect the language of the user's input text (and any text visible in the photo).")
        promptLines.append("- Return the dish name and shortDescription in that SAME language. For example, if the user typed in Chinese, return the name and description in Chinese. If the user typed in Japanese, return in Japanese. And so on.")
        promptLines.append("- If the input uses multiple languages, default to English.")
        promptLines.append("- If there is no text input (photo only, no visible text), use English.")
        promptLines.append("For each dish:")
        promptLines.append("- name: short, human-friendly, max 4 words (in the detected language).")
        promptLines.append("- shortDescription: 1 sentence, max 12 words, no trailing period (in the detected language).")

        var parts: [PartsRepresentable] = [promptLines.joined(separator: "\n")]
        if let img = image {
            parts.append(img)
        }

        let response = try await model.generateContent(parts)
        guard let textResponse = response.text else {
            throw GeminiError.empty
        }
        
        let data = Data(textResponse.utf8)
        return try decodeIdentifications(from: data, fallbackName: trimmed)
    }

    /// Generate a hand-drawn illustration. Returns PNG/JPEG bytes.
    func generateIllustration(
        dishName: String,
        dishDescription: String,
        artDirection: String? = nil
    ) async throws -> Data {
        let configuredModel = await MainActor.run { config.geminiImageModel }
        let imageModelName = configuredModel.isEmpty ? "gemini-2.5-flash-image" : configuredModel
        let style = await MainActor.run { config.illustrationStyle }
        
        let descTrim = dishDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        var subject = descTrim.isEmpty ? dishName : "\(dishName) — \(descTrim)"
        let hint = artDirection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hint.isEmpty {
            subject += ". User-requested changes for the illustration: \(hint)"
        }
        let prompt = "\(style). Subject: \(subject)."

        if imageModelName.lowercased().contains("imagen") {
            let ai = FirebaseAI.firebaseAI(backend: .vertexAI())
            let model = ai.imagenModel(
                modelName: imageModelName,
                generationConfig: ImagenGenerationConfig(
                    numberOfImages: 1,
                    aspectRatio: .square1x1
                )
            )
            let response = try await model.generateImages(prompt: prompt)
            guard let data = response.images.first?.data else {
                throw GeminiError.empty
            }
            return data
        } else {
            let ai = FirebaseAI.firebaseAI(backend: .googleAI())
            let model = ai.generativeModel(
                modelName: imageModelName,
                generationConfig: GenerationConfig(
                    responseModalities: [.image]
                )
            )
            let response = try await model.generateContent(prompt)
            guard let firstPart = response.inlineDataParts.first else {
                throw GeminiError.empty
            }
            return firstPart.data
        }
    }

    /// Generate a hand-drawn illustration based on a food photo. Returns PNG/JPEG bytes.
    func generateIllustrationBasedOnPhoto(
        dishName: String,
        dishDescription: String,
        image: UIImage
    ) async throws -> Data {
        let configuredModel = await MainActor.run { config.geminiImageModel }
        let imageModelName = configuredModel.isEmpty ? "gemini-2.5-flash-image" : configuredModel
        let style = await MainActor.run { config.illustrationStyle }
        
        let descTrim = dishDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = descTrim.isEmpty ? dishName : "\(dishName) — \(descTrim)"
        let prompt = "\(style). Subject: \(subject). Please generate a beautiful hand-drawn illustration representing the dish in the provided photo, maintaining its layout and main elements but in the hand-drawn sketch style."

        // If the user has an Imagen model selected, Imagen does not support multimodal text+image input
        // for image output in FirebaseAILogic. Therefore, fallback to standard gemini-2.5-flash-image.
        let targetModel = imageModelName.lowercased().contains("imagen") ? "gemini-2.5-flash-image" : imageModelName

        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: targetModel,
            generationConfig: GenerationConfig(
                responseModalities: [.image]
            )
        )
        
        let response = try await model.generateContent([prompt, image])
        guard let firstPart = response.inlineDataParts.first else {
            throw GeminiError.empty
        }
        return firstPart.data
    }

    /// Extract a recipe (ingredients + steps) from a photo using the vision model.
    func extractRecipe(from image: UIImage) async throws -> ExtractedRecipe {
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json",
                responseSchema: Self.recipeSchema
            )
        )
        
        let parts: [PartsRepresentable] = [Self.photoRecipePrompt, image]
        let response = try await model.generateContent(parts)
        
        guard let textResponse = response.text else {
            throw GeminiError.empty
        }
        
        let data = Data(textResponse.utf8)
        return try decodeExtractedRecipe(from: data)
    }

    /// Extract a recipe from a free-form text description.
    func extractRecipe(fromText text: String) async throws -> ExtractedRecipe {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.empty }
        
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json",
                responseSchema: Self.recipeSchema
            )
        )
        
        let prompt = Self.textRecipePrompt(userText: trimmed)
        let response = try await model.generateContent(prompt)
        
        guard let textResponse = response.text else {
            throw GeminiError.empty
        }
        
        let data = Data(textResponse.utf8)
        return try decodeExtractedRecipe(from: data)
    }

    /// Extract a recipe from a video URL using FileDataPart.
    func extractRecipe(fromVideoURL urlString: String) async throws -> ExtractedRecipe {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw GeminiError.badResponse("That doesn't look like a video URL. Paste an http(s) link.")
        }
        let host = (url.host ?? "").lowercased()
        let isYouTube = host.contains("youtube.com") || host == "youtu.be" || host == "m.youtube.com"
        guard isYouTube else {
            throw GeminiError.badResponse(
                "Only YouTube links work for now (youtube.com or youtu.be). Other hosts aren't readable by the AI from a URL — save the video as a photo or paste the steps as text instead."
            )
        }
        
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json",
                responseSchema: Self.recipeSchema
            )
        )
        
        let videoPart = FileDataPart(uri: trimmed, mimeType: "video/mp4")
        let parts: [PartsRepresentable] = [Self.videoRecipePrompt, videoPart]
        let response = try await model.generateContent(parts)
        
        guard let textResponse = response.text else {
            throw GeminiError.empty
        }
        
        let data = Data(textResponse.utf8)
        return try decodeExtractedRecipe(from: data)
    }

    /// Suggest which saved dishes to schedule for each meal.
    func generateDayMealPlan(
        mealNames: [String],
        dishCatalog: [(id: UUID, name: String, tags: [String])],
        formattedDayDescription: String,
        userNote: String?
    ) async throws -> AIDayMealPlan {
        let trimmedMeals = mealNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedMeals.isEmpty else { throw GeminiError.empty }
        guard !dishCatalog.isEmpty else {
            throw GeminiError.badResponse("There are no saved dishes to plan with.")
        }

        let catalogLines = dishCatalog.map { row -> String in
            let tagStr = row.tags.joined(separator: ", ")
            let tagPart = tagStr.isEmpty ? "" : " | tags: \(tagStr)"
            return "- id \(row.id.uuidString) | \(row.name)\(tagPart)"
        }.joined(separator: "\n")

        let mealsList = trimmedMeals.joined(separator: ", ")
        let note = userNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteBlock: String = note.isEmpty
            ? ""
            : """

              Extra preferences from the cook (optional hints — still only pick from the dish list above):
              \(note)
              """

        let prompt = """
        You are helping plan one day of home-cooked meals. The user already has a personal menu of saved dishes listed below.

        Target day: \(formattedDayDescription)

        Meals you must plan for (each assignment's "mealName" MUST exactly match one of these strings, character-for-character):
        \(mealsList)

        Dishes you may choose from — each line gives a UUID id. You MUST only output dish ids copied from these lines. Do not invent ids or dish names.
        \(catalogLines)\(noteBlock)

        Rules:
        - Build a balanced, pleasant day: usually 1 dish per meal, up to 3 per meal if it fits (e.g. small sides). Leave a meal's dishIds empty if skipping that meal is reasonable.
        - Prefer variety (don't repeat the same dish at multiple meals unless the user's note asks for it).
        - Use only ids from the dish list; skip any id you are unsure about.
        - If the catalog is very small, it's fine to repeat or leave meals sparse.

        Return JSON matching the response schema.
        """

        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.35,
                responseMIMEType: "application/json",
                responseSchema: Self.dayMealPlanSchema
            )
        )

        let response = try await model.generateContent(prompt)
        guard let textResponse = response.text else {
            throw GeminiError.empty
        }
        
        let data = Data(textResponse.utf8)
        return try decodeDayMealPlan(from: data, validMeals: trimmedMeals)
    }

    // MARK: - Schemas

    private static let identifySchema = Schema.object(
        properties: [
            "dishes": Schema.array(
                items: Schema.object(
                    properties: [
                        "name": Schema.string(),
                        "shortDescription": Schema.string()
                    ]
                )
            )
        ]
    )

    private static let recipeSchema = Schema.object(
        properties: [
            "ingredients": Schema.array(items: Schema.string()),
            "steps": Schema.array(items: Schema.string())
        ]
    )

    private static let dayMealPlanSchema = Schema.object(
        properties: [
            "assignments": Schema.array(
                items: Schema.object(
                    properties: [
                        "mealName": Schema.string(),
                        "dishIds": Schema.array(items: Schema.string())
                    ]
                )
            )
        ]
    )

    // MARK: - Prompts

    private static let photoRecipePrompt = """
    You are reading a recipe from a photo. The photo may be a printed cookbook page, a handwritten recipe card, a screenshot, or a recipe written on paper.

    IMPORTANT — Language rules:
    - First, detect the language used in the recipe text visible in the photo.
    - Return the ingredients and steps in that SAME language. For example, if the recipe is written in Chinese, return ingredients and steps in Chinese. If in Japanese, return in Japanese. And so on.
    - If the recipe uses multiple languages, default to English.

    Extract two ordered lists:
    - ingredients: each entry is a single ingredient on its own line. Include the quantity, unit, and item when visible (e.g. "2 cups flour", "1 tbsp olive oil", "Salt to taste"). Do NOT bundle multiple ingredients into one entry. Do NOT include section headings like "For the sauce:" — they are not ingredients.
    - steps: each entry is one instruction step, in order. Write each step as a brief but complete sentence or two. Drop step numbers from the source (the app numbers them automatically).

    If the photo does not contain a recipe, return both arrays empty.

    Return JSON matching the response schema.
    """

    private static func textRecipePrompt(userText: String) -> String {
        """
        You are extracting a recipe from free-form text the user typed or pasted in. The text may be a casual description ("spaghetti carbonara — eggs, pancetta, pecorino, pepper; cook pasta, fry pancetta, toss with egg…"), a blog excerpt, or a list.

        IMPORTANT — Language rules:
        - First, detect the language of the user's text below.
        - Return the ingredients and steps in that SAME language. For example, if the text is in Chinese, return ingredients and steps in Chinese. If in Japanese, return in Japanese. And so on.
        - If the text uses multiple languages, default to English.

        Extract two ordered lists:
        - ingredients: each entry is a single ingredient on its own line. Keep quantities/units when given (e.g. "2 cups flour", "1 tbsp olive oil", "Salt to taste"). Don't invent quantities the user didn't mention. Don't bundle multiple ingredients into one entry.
        - steps: each entry is one instruction step, in the order they should be done. Drop any numbering — the app numbers them automatically. Rewrite as brief but complete sentences.

        If the text doesn't describe a recipe at all, return both arrays empty.

        Text:
        \"\"\"
        \(userText)
        \"\"\"

        Return JSON matching the response schema.
        """
    }

    private static let videoRecipePrompt = """
    You are watching a cooking video. Extract the recipe being demonstrated.

    IMPORTANT — Language rules:
    - First, detect the primary language used in the video (spoken narration, on-screen text, captions).
    - Return the ingredients and steps in that SAME language. For example, if the video is in Chinese, return ingredients and steps in Chinese. If in Japanese, return in Japanese. And so on.
    - If the video uses multiple languages, default to English.

    Return two ordered lists:
    - ingredients: each entry is a single ingredient on its own line. Include the quantity, unit, and item if the video states or visibly shows them (e.g. "2 cups flour", "1 tbsp olive oil", "Salt to taste"). Don't invent quantities not shown or stated. Don't bundle multiple ingredients into one entry.
    - steps: each entry is one instruction step, in the order performed in the video. Drop numbering — the app numbers them automatically. Write each step as a brief but complete sentence.

    If the video isn't a cooking video, return both arrays empty.

    Return JSON matching the response schema.
    """

    // MARK: - Decoders

    private func decodeDayMealPlan(from data: Data, validMeals: [String]) throws -> AIDayMealPlan {
        struct RawAssignment: Decodable { let mealName: String?; let dishIds: [String]? }
        struct RawPlan: Decodable { let assignments: [RawAssignment]? }

        let raw: RawPlan
        do {
            raw = try JSONDecoder().decode(RawPlan.self, from: data)
        } catch {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.decoding("schema mismatch: \(bodyString) error: \(error.localizedDescription)")
        }

        var mealLookup: [String: String] = [:]
        for m in validMeals { mealLookup[m.lowercased()] = m }

        let assignments: [AIDayMealPlan.Assignment] = (raw.assignments ?? []).compactMap { row in
            let rawMeal = (row.mealName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawMeal.isEmpty else { return nil }
            let canonicalMeal = mealLookup[rawMeal.lowercased()] ?? validMeals.first { $0.lowercased() == rawMeal.lowercased() }
            guard let mealName = canonicalMeal else { return nil }
            let ids = (row.dishIds ?? []).compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return AIDayMealPlan.Assignment(mealName: mealName, dishIds: ids)
        }

        return AIDayMealPlan(assignments: assignments)
    }

    private func decodeExtractedRecipe(from data: Data) throws -> ExtractedRecipe {
        struct Raw: Decodable { let ingredients: [String]?; let steps: [String]? }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.decoding("schema mismatch: \(bodyString) error: \(error.localizedDescription)")
        }

        let cleanIngredients = (raw.ingredients ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanSteps = (raw.steps ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ExtractedRecipe(ingredients: cleanIngredients, steps: cleanSteps)
    }

    private func decodeIdentifications(from data: Data, fallbackName: String) throws -> [DishIdentification] {
        struct RawDish: Decodable { let name: String?; let shortDescription: String? }
        struct RawEnvelope: Decodable { let dishes: [RawDish]? }

        let raw: RawEnvelope
        do {
            raw = try JSONDecoder().decode(RawEnvelope.self, from: data)
        } catch {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.decoding("schema mismatch: \(bodyString) error: \(error.localizedDescription)")
        }

        let cleaned: [DishIdentification] = (raw.dishes ?? []).compactMap { dish in
            let name = (dish.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return DishIdentification(
                name: name,
                shortDescription: (dish.shortDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if cleaned.isEmpty {
            guard !fallbackName.isEmpty else { throw GeminiError.empty }
            return [DishIdentification(name: fallbackName, shortDescription: "")]
        }
        return cleaned
    }
}
