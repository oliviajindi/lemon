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

struct ChatTurn: Equatable {
    enum Role { case user, assistant }
    let role: Role
    let text: String
}

enum ChefRole: String, Codable {
    case creator = "creator"
    case copilot = "copilot"
}

struct PreferenceDetectionResult: Codable {
    let hasPreference: Bool
    let preference: String?
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
                responseSchema: Self.identifySchema,
                responseModalities: [.text]
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
        let textResponse = try extractTextResponse(response)
        
        let data = Data(textResponse.utf8)
        return try decodeIdentifications(from: data, fallbackName: trimmed)
    }

    /// Generate a hand-drawn illustration. Returns PNG/JPEG bytes.
    func generateIllustration(
        dishName: String,
        dishDescription: String,
        artDirection: String? = nil,
        image: UIImage? = nil
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
        
        let prompt: String
        let parts: [PartsRepresentable]
        
        if let img = image {
            let croppedImage = img.centerCroppedToSquare()
            prompt = "\(style). Subject: \(subject). Please generate a beautiful hand-drawn illustration representing the dish/graph in the provided photo/image, maintaining its layout and main elements but in the hand-drawn sketch style."
            parts = [prompt, croppedImage]
        } else {
            prompt = "\(style). Subject: \(subject)."
            parts = [prompt]
        }

        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: imageModelName,
            generationConfig: GenerationConfig(
                responseModalities: [.image]
            )
        )
        let response = try await model.generateContent(parts)
        guard let firstPart = response.inlineDataParts.first else {
            throw GeminiError.empty
        }
        return firstPart.data
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

        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: imageModelName,
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
        return try await extractRecipe(from: [image], userPrompt: "", currentRecipe: "")
    }

    func extractRecipe(from images: [UIImage], userPrompt: String = "", currentRecipe: String = "") async throws -> ExtractedRecipe {
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json",
                responseSchema: Self.recipeSchema,
                responseModalities: [.text]
            )
        )
        
        var parts: [PartsRepresentable] = [Self.photoRecipePrompt]
        
        if !currentRecipe.isEmpty {
            parts.append("The dish currently has this existing recipe:\n\(currentRecipe)\n\nPlease look at this existing recipe and apply the user's requested changes, edits, or additions from the photo(s)/prompt. If the user's request is completely new or different, rewrite it. Otherwise, modify and edit the existing recipe accordingly.")
        }
        
        let trimmedPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            parts.append("Additional context and instructions from the user: \(trimmedPrompt)")
        }
        
        for img in images {
            parts.append(img)
        }
        
        let response = try await model.generateContent(parts)
        let textResponse = try extractTextResponse(response)
        
        let data = Data(textResponse.utf8)
        return try decodeExtractedRecipe(from: data)
    }

    /// Extract a recipe from a free-form text description.
    func extractRecipe(fromText text: String, currentRecipe: String = "") async throws -> ExtractedRecipe {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.empty }
        
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json",
                responseSchema: Self.recipeSchema,
                responseModalities: [.text]
            )
        )
        
        var prompt = Self.textRecipePrompt(userText: trimmed)
        if !currentRecipe.isEmpty {
            prompt += "\n\nThe dish currently has this existing recipe:\n\(currentRecipe)\n\nPlease look at this existing recipe and apply the user's requested changes, edits, or additions. If the user's prompt is completely new or different, rewrite it. Otherwise, modify and edit the existing recipe according to their instructions."
        }
        
        let response = try await model.generateContent(prompt)
        let textResponse = try extractTextResponse(response)
        
        let data = Data(textResponse.utf8)
        return try decodeExtractedRecipe(from: data)
    }

    /// Extract a recipe from a video URL using FileDataPart.
    func extractRecipe(fromVideoURL urlString: String, currentRecipe: String = "") async throws -> ExtractedRecipe {
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
                responseSchema: Self.recipeSchema,
                responseModalities: [.text]
            )
        )
        
        let videoPart = FileDataPart(uri: trimmed, mimeType: "video/mp4")
        var parts: [PartsRepresentable] = [Self.videoRecipePrompt]
        
        if !currentRecipe.isEmpty {
            parts.append("The dish currently has this existing recipe:\n\(currentRecipe)\n\nPlease look at this existing recipe and apply the user's requested changes, edits, or additions from the video. If the user's request is completely new or different, rewrite it. Otherwise, modify and edit the existing recipe accordingly.")
        }
        
        parts.append(videoPart)
        let response = try await model.generateContent(parts)
        let textResponse = try extractTextResponse(response)
        
        let data = Data(textResponse.utf8)
        return try decodeExtractedRecipe(from: data)
    }

    /// Suggest which saved dishes to schedule for each meal.
    func generateDayMealPlan(
        mealNames: [String],
        dishCatalog: [(id: UUID, name: String, tags: [String])],
        formattedDayDescription: String,
        userNote: String?,
        userPreferences: [String] = [],
        history: [ChatTurn] = []
    ) async throws -> AIDayMealPlan {
        let trimmedMeals = mealNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let activeMealsList = trimmedMeals.isEmpty ? "None" : trimmedMeals.joined(separator: ", ")
        guard !dishCatalog.isEmpty else {
            throw GeminiError.badResponse("There are no saved dishes to plan with.")
        }

        let catalogLines = dishCatalog.map { row -> String in
            let tagStr = row.tags.joined(separator: ", ")
            let tagPart = tagStr.isEmpty ? "" : " | tags: \(tagStr)"
            return "- id \(row.id.uuidString) | \(row.name)\(tagPart)"
        }.joined(separator: "\n")

        let note = userNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var noteBlock: String = note.isEmpty
            ? ""
            : """

              Extra preferences from the cook (optional hints — still only pick from the dish list above):
              \(note)
              """

        if !userPreferences.isEmpty {
            noteBlock += """
            
            Stored user dietary/culinary preferences (you MUST prioritize choosing dishes that respect these preferences and avoid any that violate them):
            \(userPreferences.map { "- \($0)" }.joined(separator: "\n"))
            """
        }

        var historyBlock = ""
        if !history.isEmpty {
            historyBlock = "\n\nPrevious conversation history:\n"
            for turn in history {
                let roleLabel = turn.role == .user ? "User" : "Assistant (you)"
                historyBlock += "- \(roleLabel): \(turn.text)\n"
            }
        }

        let prompt = """
        You are helping plan home-cooked meals for a day. The user already has a personal menu of saved dishes listed below.

        Target day: \(formattedDayDescription)

        Currently active meals in the user's planner:
        \(activeMealsList)

        Standard meal slots available: Breakfast, Lunch, Dinner, Other

        Dishes you may choose from — each line gives a UUID id. You MUST only output dish ids copied from these lines. Do not invent ids or dish names.
        \(catalogLines)\(noteBlock)\(historyBlock)

        Instructions:
        1. Analyze the cook's preferences/note and the previous conversation history to determine their intent:
           - Identify which meal slot(s) they are currently focusing on, adjusting, or changing to (e.g. if they previously planned dinner and now say "plan for lunch", they are switching focus to lunch).
           - Understand relative changes (e.g., if they previously planned dinner and say "at least three dishes", they mean 3 dishes for dinner, not for other meals).
           - If the user specifies a specific meal or is currently focusing on a specific meal based on the history/note, plan or adjust ONLY for that meal/meals. Do not plan for the other meals.
           - If the user does not specify any specific meal and the history doesn't focus on one, plan for all the currently active meals.
           - If the user requests a meal slot that is not currently active (e.g. they deleted "Dinner" but now say "plan a dinner"), you MUST still plan for it using the appropriate meal name (like "Dinner").
        2. Assign a balanced selection of dishes: usually 1 dish per meal, up to 3 per meal if it fits (e.g. small sides). Leave a meal's dishIds empty if skipping that meal is reasonable.
        3. Prefer variety (don't repeat the same dish at multiple meals unless the user's note asks for it).
        4. Use only ids from the dish list; skip any id you are unsure about.

        Return JSON matching the response schema.
        """

        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.35,
                responseMIMEType: "application/json",
                responseSchema: Self.dayMealPlanSchema,
                responseModalities: [.text]
            )
        )

        let response = try await model.generateContent(prompt)
        let textResponse = try extractTextResponse(response)
        
        let data = Data(textResponse.utf8)
        return try decodeDayMealPlan(from: data, validMeals: trimmedMeals)
    }

    /// Converse with the Sous Chef assistant. Takes the user's latest message, optional image input,
    /// dish context, and conversation history, and returns a structured AssistantAction.
    func converseWithAssistant(
        role: ChefRole,
        prompt: String,
        image: UIImage?,
        dishName: String,
        dishDescription: String,
        currentRecipe: String,
        groupName: String,
        tags: [String],
        chefs: [String],
        availableGroups: [String] = [],
        userPreferences: [String] = [],
        history: [ChatTurn]
    ) async throws -> AssistantAction {
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.4,
                responseMIMEType: "application/json",
                responseSchema: Self.assistantActionSchema,
                responseModalities: [.text]
            )
        )
        
        var promptParts: [String] = [
            Self.assistantPrompt(
                role: role,
                dishName: dishName,
                dishDescription: dishDescription,
                currentRecipe: currentRecipe,
                groupName: groupName,
                tags: tags,
                chefs: chefs,
                availableGroups: availableGroups,
                userPreferences: userPreferences
            )
        ]
        
        if !history.isEmpty {
            promptParts.append("\nHere is the recent chat history for context:")
            for turn in history {
                let roleStr = turn.role == .user ? "User" : "Sous Chef"
                promptParts.append("\(roleStr): \(turn.text)")
            }
        }
        
        promptParts.append("\nUser's latest message: \"\(prompt)\"")
        
        var parts: [PartsRepresentable] = [promptParts.joined(separator: "\n")]
        if let img = image {
            parts.append(img)
        }
        
        let response = try await model.generateContent(parts)
        let textResponse = try extractTextResponse(response)
        
        let data = Data(textResponse.utf8)
        
        do {
            return try JSONDecoder().decode(AssistantAction.self, from: data)
        } catch {
            throw GeminiError.decoding("schema mismatch: \(textResponse) error: \(error.localizedDescription)")
        }
    }

    /// Dynamically detect if a user's input expresses a dietary or culinary preference.
    func detectUserPreference(from text: String) async throws -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let modelName = await MainActor.run { config.geminiTextModel }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        
        let model = ai.generativeModel(
            modelName: modelName.isEmpty ? "gemini-2.5-flash" : modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1,
                responseMIMEType: "application/json",
                responseSchema: Self.preferenceDetectionSchema,
                responseModalities: [.text]
            )
        )
        
        let prompt = """
        Analyze the user's input to detect if they are expressing a general culinary preference, dietary habit, favorite ingredient, allergy, dislike, or eating preference (e.g. "I want to eat vegetables", "I don't like spicy food", "I am vegan", "I love dessert").
        
        Input text: "\(trimmed)"
        
        Respond in JSON matching the schema.
        """
        
        let response = try await model.generateContent(prompt)
        let textResponse = try extractTextResponse(response)
        guard let data = textResponse.data(using: .utf8) else { return nil }
        let result = try JSONDecoder().decode(PreferenceDetectionResult.self, from: data)
        if result.hasPreference, let pref = result.preference, !pref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pref.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
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

    private static let assistantActionSchema = Schema.object(
        properties: [
            "reply": Schema.string(),
            "action": Schema.string(
                description: "The action to perform. Must be one of: 'reply', 'create_dish', 'update_title', 'update_description', 'update_recipe', 'redraw', 'add_tag', 'remove_tag', 'add_chef', 'set_group'."
            ),
            "title": Schema.string(),
            "description": Schema.string(),
            "ingredients": Schema.array(
                items: Schema.object(
                    properties: [
                        "qty": Schema.string(description: "Quantity/amount value, e.g. '50', '1.5', '2/3', '3'. Empty string if none."),
                        "unit": Schema.string(description: "Unit, e.g. 'g', 'ml', 'tbsp', 'cup', 'pieces', 'can'. Empty string if none."),
                        "name": Schema.string(description: "Name of the ingredient, e.g. 'flour', 'sugar', 'egg', 'heavy cream'.")
                    ]
                )
            ),
            "steps": Schema.array(items: Schema.string()),
            "redrawNotes": Schema.string(),
            "tag": Schema.string(),
            "chefName": Schema.string(),
            "groupName": Schema.string()
        ]
    )

    private static let preferenceDetectionSchema = Schema.object(
        properties: [
            "hasPreference": Schema.boolean(description: "True if the input expresses a culinary or dietary preference, food like, food dislike, allergy, or dietary habit."),
            "preference": Schema.string(description: "A concise, clean summary of the preference found (e.g. 'loves vegetables', 'allergic to peanuts', 'spicy lover', 'no pork', 'prefers healthy'). Leave empty if hasPreference is false.")
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
    - ingredients: each entry is a single ingredient on its own line. Keep quantities/units when given. Format each entry consistently so quantity, unit, and ingredient name are easily parsed, using either `<quantity> <unit> <ingredient name>` (e.g., "2 cups flour", "250g flour", "250克 中筋面粉") or `<ingredient name> <quantity><unit>` (e.g., "flour 200g", "中筋面粉 250克", "鸡蛋 3"). Keep quantities/units when given, and omit/leave them out if not mentioned. Don't bundle multiple ingredients into one entry. Do NOT include section headings like "For the sauce:" — they are not ingredients.
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
        - ingredients: each entry is a single ingredient on its own line. Keep quantities/units when given. Format each entry consistently so quantity, unit, and ingredient name are easily parsed, using either `<quantity> <unit> <ingredient name>` (e.g., "2 cups flour", "250g flour", "250克 中筋面粉") or `<ingredient name> <quantity><unit>` (e.g., "flour 200g", "中筋面粉 250克", "鸡蛋 3"). Keep quantities/units when given, and omit/leave them out if not mentioned. Don't bundle multiple ingredients into one entry.
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
    - ingredients: each entry is a single ingredient on its own line. Format each entry consistently so quantity, unit, and ingredient name are easily parsed, using either `<quantity> <unit> <ingredient name>` (e.g., "2 cups flour", "250g flour", "250克 中筋面粉") or `<ingredient name> <quantity><unit>` (e.g., "flour 200g", "中筋面粉 250克", "鸡蛋 3"). Include the quantity, unit, and item if the video states or visibly shows them. Don't invent quantities not shown or stated. Don't bundle multiple ingredients into one entry.
    - steps: each entry is one instruction step, in the order performed in the video. Drop numbering — the app numbers them automatically. Write each step as a brief but complete sentence.

    If the video isn't a cooking video, return both arrays empty.

    Return JSON matching the response schema.
    """

    private static func assistantPrompt(
        role: ChefRole,
        dishName: String,
        dishDescription: String,
        currentRecipe: String,
        groupName: String,
        tags: [String],
        chefs: [String],
        availableGroups: [String] = [],
        userPreferences: [String] = []
    ) -> String {
        let rolePrompt: String
        let actionsList: String
        
        switch role {
        case .creator:
            rolePrompt = """
            You are the "Creator Sous Chef". Your main responsibility is to help the user identify, draft, and configure brand-new dishes from photos or text descriptions.
            The user has not saved this dish yet. You can create one or more new dish drafts, rename those drafts, redraw their illustrations, or link tags/chefs before they get saved to the main menu database.
            Note: There is NO need to generate a description for the dish when adding it; please keep the "description" field empty or omitted.
            """
            actionsList = """
            Operations you support (you MUST output the appropriate "action" code):
            1. "create_dish": Identify or draft a brand-new dish (or multiple dishes) from the user's input photo or text description.
               - Provide the "title" representing the new dish. Leave the "description" field empty.
               - IMPORTANT: Do NOT generate or include a recipe (leave the "ingredients" and "steps" fields empty/omitted) unless the user explicitly requested to add a recipe, typed/pasted recipe details, or uploaded a photo showing recipe text. If they only mention the dish name or upload a photo of the finished dish, create it as a blank dish without a recipe.
               - GROUP AUTO-MATCHING: When creating a dish, you MUST also try to match it to one of the available groups listed below. If a group is a good semantic match for the dish (e.g. a pasta dish matches an "Italian" or "Pasta" group), include the "groupName" field with the exact group name. If NO existing group is a reasonable match, suggest creating a new group in your "reply" (e.g. "This doesn't fit any existing group. Would you like me to create a new group called 'X' for it?") and wait for the user to confirm before using "set_group".
            2. "update_title": Rename the current draft dish.
               - Provide the new "title" field.
            3. "update_description": Change or write a new description for the current draft dish.
               - Provide the new "description" field.
            4. "update_recipe": Add, remove, scale, rewrite, or edit the ingredients and/or steps of the recipe for the current draft dish.
               - Provide both the full "ingredients" and "steps" lists representing the complete updated recipe.
            5. "redraw": Draw a new hand-drawn illustration sketch of the current draft dish.
               - Provide the optional "redrawNotes" describing the style/composition requested by the user.
            6. "add_tag": Add a tag to the draft dish.
               - Provide the "tag" field.
            7. "remove_tag": Remove a tag from the draft dish.
               - Provide the "tag" field.
            8. "add_chef": Assign a chef to the draft dish.
               - Provide the "chefName" field.
            9. "set_group": Assign the draft dish to a group/section (e.g. "Dinner", "Appetizers").
               - Provide the "groupName" field. You may use an existing group name or a new name the user confirmed.
            10. "reply": Standard conversational reply. Use this when the user is just chatting, asking cooking questions, or if their request doesn't map to a direct database/UI change.
            """
            
        case .copilot:
            rolePrompt = """
            You are the "Copilot Sous Chef". Your responsibility is to help the user edit and manage an already existing dish that is saved on the menu.
            The dish already exists in the database. You can rename the dish, refine its description, update its ingredients and steps, redraw its illustration, or manage tags and chefs in real-time.
            """
            actionsList = """
            Operations you support (you MUST output the appropriate "action" code):
            1. "update_title": Rename the dish or change its title.
               - Provide the new "title" field.
            2. "update_description": Change or write a new description for the dish.
               - Provide the new "description" field.
            3. "update_recipe": Add, remove, rewrite, scale, or edit the ingredients and/or steps of the recipe.
               - Provide both the full "ingredients" and "steps" lists representing the complete updated recipe.
            4. "redraw": Draw a new hand-drawn illustration sketch of the dish.
               - Provide the optional "redrawNotes" describing the style/composition requested by the user.
            5. "add_tag": Add a new tag (e.g. "pasta", "spicy", "kid-friendly").
               - Provide the "tag" field.
            6. "remove_tag": Remove an existing tag.
               - Provide the "tag" field.
            7. "add_chef": Assign or attribute a chef to the dish.
               - Provide the "chefName" field.
            8. "set_group": Assign the dish to a group/section (e.g. "Italian", "Desserts").
               - Provide the "groupName" field.
            9. "reply": Standard conversational reply. Use this when the user is just chatting, asking cooking questions, or if their request doesn't map to a direct database/UI change.
            """
        }
        
        let availableGroupsList = availableGroups.isEmpty
            ? "No groups exist yet."
            : availableGroups.joined(separator: ", ")

        let preferencesBlock = userPreferences.isEmpty
            ? ""
            : """
            User's dietary and culinary preferences (strictly adapt recipe creations, edits, meal suggestions, and plan modifications to respect these preferences):
            \(userPreferences.map { "- \($0)" }.joined(separator: "\n"))
            
            """

        let dishState = role == .copilot ? """
        The user is currently viewing/editing this dish:
        - Name: "\(dishName)"
        - Description: "\(dishDescription)"
        - Current Group: "\(groupName)"
        - Current Tags: \(tags.isEmpty ? "None" : tags.joined(separator: ", "))
        - Current Chefs: \(chefs.isEmpty ? "None" : chefs.joined(separator: ", "))
        - Available Groups: \(availableGroupsList)
        \(preferencesBlock)- Current Recipe:
        \(currentRecipe.isEmpty ? "No recipe ingredients/steps defined yet." : currentRecipe)
        """ : """
        The user is currently drafting new dishes.
        Current draft dishes stage has \(dishName == "None" ? "no dishes" : dishName) loaded.
        - Current Draft Group: "\(groupName)"
        - Current Draft Tags: \(tags.isEmpty ? "None" : tags.joined(separator: ", "))
        - Current Draft Chefs: \(chefs.isEmpty ? "None" : chefs.joined(separator: ", "))
        - Available Groups: \(availableGroupsList)
        \(preferencesBlock)- Current Draft Recipe:
        \(currentRecipe.isEmpty ? "No recipe ingredients/steps defined yet." : currentRecipe)
        """

        return """
        \(rolePrompt)

        Context:
        \(dishState)

        \(actionsList)

        Guidelines:
        - Language rules:
          * First, detect the language of the user's latest message (and any text in history or visible in a photo).
          * You MUST write your "reply", "title", "description", "ingredients", "steps", "tag", and "chefName" values in that SAME language. For example, if the user typed in Chinese, return the conversational reply, recipe lists, and tags in Chinese. If they typed in French, return in French. And so on.
          * If multiple languages are used in the user's message, default to English.
          * If there is no text input (photo only, no text), use English.
        - "reply" field: You MUST always provide a warm, helpful, and highly conversational response (like a friendly professional chef talking to a home cook). Explain what you are doing, the changes you are applying, or answer their questions. Even when returning structured actions (such as 'update_recipe', 'create_dish', 'update_title', etc.), you MUST talk to the user and give a complete conversational reply first before the structured parameters. Under no circumstances should the "reply" field be empty or generic.
        - Always return JSON matching the schema.
        """
    }

    private func extractTextResponse(_ response: GenerateContentResponse) throws -> String {
        guard let text = response.text else {
            if let imagePart = response.inlineDataParts.first {
                throw GeminiError.badResponse("The model generated an unexpected visual output (\(imagePart.mimeType)) instead of text content. Please ensure you are not passing a model name configured only for image output.")
            }
            throw GeminiError.empty
        }
        
        // Clean thinking/reasoning tags and their contents (both closed and unclosed, stopping before JSON starts)
        var cleanText = text
        let patterns = [
            "(?s)<(think|thought|thinking|reasoning|thought_process|scratchpad)>.*?(?:</\\1>|(?=\\{)|$)",
            "(?s)\\[(think|thought|thinking|reasoning|thought_process|scratchpad)\\].*?(?:\\[/\\1\\]|(?=\\{)|$)",
            "(?s)```(thinking|thought|reasoning).*?```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(cleanText.startIndex..<cleanText.endIndex, in: cleanText)
                cleanText = regex.stringByReplacingMatches(in: cleanText, options: [], range: range, withTemplate: "")
            }
        }
        
        return cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            // Case-insensitively map to active meals if possible, otherwise keep the raw name
            let mealName = mealLookup[rawMeal.lowercased()] ?? rawMeal
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

// MARK: - UIImage cropping helper
private extension UIImage {
    func centerCroppedToSquare() -> UIImage {
        let sideLength = min(size.width, size.height)
        let targetSize = CGSize(width: sideLength, height: sideLength)
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            let drawRect = CGRect(
                x: (sideLength - size.width) / 2.0,
                y: (sideLength - size.height) / 2.0,
                width: size.width,
                height: size.height
            )
            self.draw(in: drawRect)
        }
    }
}
