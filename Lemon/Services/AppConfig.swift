import Foundation
import Combine

/// User-editable configuration backed by UserDefaults.
/// API keys live here for v1 simplicity; move to Keychain before shipping
/// (or — recommended — turn on the proxy and stop putting keys on the device at all).
@MainActor
final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    private let defaults: UserDefaults
    private enum Key {
        static let geminiAPIKey       = "config.geminiAPIKey"
        static let geminiTextModel    = "config.geminiTextModel"
        static let geminiImageModel   = "config.geminiImageModel"
        static let illustrationStyle  = "config.illustrationStyle"
        static let useProxy           = "config.useProxy"
        static let proxyURL           = "config.proxyURL"
        static let proxySecret        = "config.proxySecret"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.geminiAPIKey      = defaults.string(forKey: Key.geminiAPIKey) ?? ""
        self.geminiTextModel   = defaults.string(forKey: Key.geminiTextModel) ?? "gemini-2.5-flash"
        self.geminiImageModel  = defaults.string(forKey: Key.geminiImageModel) ?? "gemini-2.5-flash-image"
        self.illustrationStyle = defaults.string(forKey: Key.illustrationStyle) ?? Self.defaultIllustrationStyle
        self.useProxy          = defaults.bool(forKey: Key.useProxy)
        self.proxyURL          = defaults.string(forKey: Key.proxyURL) ?? ""
        self.proxySecret       = defaults.string(forKey: Key.proxySecret) ?? ""
    }

    static let defaultIllustrationStyle: String =
        "loose hand-drawn ink line illustration on cream paper, single subject centered, " +
        "soft watercolor wash, minimal palette, food illustration in the style of a personal recipe journal, " +
        "playful, charming, no text, no labels, no border"

    @Published var geminiAPIKey: String       { didSet { defaults.set(geminiAPIKey, forKey: Key.geminiAPIKey) } }
    @Published var geminiTextModel: String    { didSet { defaults.set(geminiTextModel, forKey: Key.geminiTextModel) } }
    @Published var geminiImageModel: String   { didSet { defaults.set(geminiImageModel, forKey: Key.geminiImageModel) } }
    @Published var illustrationStyle: String  { didSet { defaults.set(illustrationStyle, forKey: Key.illustrationStyle) } }

    @Published var useProxy: Bool             { didSet { defaults.set(useProxy, forKey: Key.useProxy) } }
    @Published var proxyURL: String           { didSet { defaults.set(proxyURL, forKey: Key.proxyURL) } }
    @Published var proxySecret: String        { didSet { defaults.set(proxySecret, forKey: Key.proxySecret) } }

    /// True when the app has a usable AI backend — either the proxy is
    /// enabled and configured, or the direct Gemini key is set.
    /// Under Firebase AI Logic, the backend is always active.
    var hasAIBackend: Bool {
        return true
    }
}
