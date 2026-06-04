import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck

/// Copies `UserDefaults` keys from the old `AIMenu.*` prefix once so installs
/// renamed from “AIMenu” to “Lemon” keep menu title, meals, profile, etc.
private enum LegacyDefaultsMigration {
    static let flagKey = "Lemon.didMigrateAIMenuDefaults"

    static func runIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: flagKey) else { return }

        let stringPairs: [(String, String)] = [
            ("AIMenu.todayMealNames", "Lemon.todayMealNames"),
            ("AIMenu.menuTitle", "Lemon.menuTitle"),
            ("AIMenu.menuSubtitle", "Lemon.menuSubtitle"),
            ("AIMenu.profileDisplayName", "Lemon.profileDisplayName"),
            ("AIMenu.profileTagline", "Lemon.profileTagline"),
        ]
        for (oldKey, newKey) in stringPairs {
            if ud.string(forKey: newKey) == nil, let v = ud.string(forKey: oldKey) {
                ud.set(v, forKey: newKey)
            }
        }

        if ud.object(forKey: "Lemon.menuLayout") == nil, let raw = ud.string(forKey: "AIMenu.menuLayout") {
            ud.set(raw, forKey: "Lemon.menuLayout")
        }

        if ud.data(forKey: "Lemon.profileAvatarJPEG") == nil, let data = ud.data(forKey: "AIMenu.profileAvatarJPEG") {
            ud.set(data, forKey: "Lemon.profileAvatarJPEG")
        }

        if ud.object(forKey: "Lemon.collapsedSectionIDs") == nil,
           let arr = ud.array(forKey: "AIMenu.collapsedSectionIDs") {
            ud.set(arr, forKey: "Lemon.collapsedSectionIDs")
        }

        ud.set(true, forKey: flagKey)
    }
}

@main
struct LemonApp: App {
    @StateObject private var config = AppConfig.shared
    @StateObject private var store = DishStore()

    init() {
        #if DEBUG
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif
        FirebaseApp.configure()

        LegacyDefaultsMigration.runIfNeeded()

        // Make the segmented picker transparent so it doesn't overlap
        // with the navigation bar toolbar background.
        UISegmentedControl.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(config)
                .environmentObject(store)
                .tint(Theme.ink)
                .preferredColorScheme(ColorScheme.light)
        }
        .modelContainer(DishStore.sharedContainer)
    }
}
