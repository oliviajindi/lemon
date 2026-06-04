import SwiftUI

/// Warm cream paper, dark ink, and system sans-serif typography.
enum Theme {
    static let paper       = Color(red: 0.992, green: 0.985, blue: 0.960)
    static let paperShadow = Color(red: 0.91, green: 0.895, blue: 0.855)
    static let ink         = Color(red: 0.13, green: 0.12, blue: 0.10)
    static let inkSoft     = Color(red: 0.30, green: 0.27, blue: 0.22)
    static let inkFaded    = Color(red: 0.45, green: 0.42, blue: 0.36)
    static let accent      = Color(red: 0.78, green: 0.30, blue: 0.18) // sketchy red stamp
    static let highlight   = Color(red: 0.96, green: 0.82, blue: 0.34) // mustard

    /// General headline font. Rounded SF keeps the app friendly while staying
    /// fully sans-serif and built into every iOS device.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    /// Big page masthead font: bundled Raleway.
    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.custom("Raleway", size: size).weight(weight)
    }

    /// Dish names use plain SF Pro, slightly lighter than before so the
    /// menu reads cleaner.
    static func dishName(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .default)
    }

    /// Dish names on the main menu page use Raleway so the cards share
    /// the menu masthead's typeface family. Other surfaces (detail,
    /// Today, calendar) keep `dishName` so they stay readable at small
    /// sizes.
    static func menuDishName(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.custom("Raleway", size: size).weight(weight)
    }

    /// Section/group names use Raleway too, matching the menu masthead.
    static func groupName(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        Font.custom("Raleway", size: size).weight(weight)
    }

    /// Small label/accent font.
    static func hand(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .regular, design: .rounded)
    }

    /// Body/accent font. Kept under the old helper name to avoid broad call-site
    /// churn, but it now resolves to default SF sans-serif.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Reusable view modifiers

struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Theme.paper
                    PaperTexture()
                        .opacity(0.35)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            )
    }
}

/// Subtle procedurally drawn paper grain so we don't need an asset.
struct PaperTexture: View {
    let seed: Int
    init(seed: Int = 7) { self.seed = seed }
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: UInt64(seed))
            let dotCount = Int((size.width * size.height) / 900)
            for _ in 0..<dotCount {
                let x = Double.random(in: 0...size.width, using: &rng)
                let y = Double.random(in: 0...size.height, using: &rng)
                let r = Double.random(in: 0.3...1.1, using: &rng)
                let a = Double.random(in: 0.04...0.12, using: &rng)
                let rect = CGRect(x: x, y: y, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(Theme.inkSoft.opacity(a)))
            }
        }
    }
}

struct DottedDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(Theme.inkFaded, style: StrokeStyle(lineWidth: 1, dash: [1.5, 4]))
        }
        .frame(height: 6)
    }
}

extension View {
    func paperBackground() -> some View { modifier(PaperBackground()) }

    /// Single clean 1pt outline for cards, thumbnails, and fields.
    func cardStroke(cornerRadius: CGFloat, inkOpacity: Double = 0.22) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Theme.ink.opacity(inkOpacity), lineWidth: 1)
        )
    }

    /// Standard Raleway navigation title used by the top-level tab roots
    /// (Today, Calendar, Profile). Keeps the system back-button label working
    /// via `navigationTitle(_:)` while visually replacing the inline title
    /// with a Raleway treatment that matches the rest of the app's typography.
    func lemonNavigationTitle(_ text: String) -> some View {
        navigationTitle(text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(text)
                        .font(Theme.title(22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension String {
    /// Converts ASCII letters/digits into Unicode Mathematical Double-Struck
    /// characters. Non-mapped punctuation (spaces, apostrophes, emoji, etc.)
    /// is preserved so a title like "Olivia's Menu" stays readable.
    var mathematicalDoubleStruck: String {
        var output = ""
        for scalar in unicodeScalars {
            output.unicodeScalars.append(Self.doubleStruckScalar(for: scalar) ?? scalar)
        }
        return output
    }

    private static func doubleStruckScalar(for scalar: UnicodeScalar) -> UnicodeScalar? {
        let value = scalar.value

        if (65...90).contains(value) {
            switch value {
            case 67: return UnicodeScalar(0x2102) // C
            case 72: return UnicodeScalar(0x210D) // H
            case 78: return UnicodeScalar(0x2115) // N
            case 80: return UnicodeScalar(0x2119) // P
            case 81: return UnicodeScalar(0x211A) // Q
            case 82: return UnicodeScalar(0x211D) // R
            case 90: return UnicodeScalar(0x2124) // Z
            default:
                return UnicodeScalar(0x1D538 + value - 65)
            }
        }

        if (97...122).contains(value) {
            return UnicodeScalar(0x1D552 + value - 97)
        }

        if (48...57).contains(value) {
            return UnicodeScalar(0x1D7D8 + value - 48)
        }

        return nil
    }
}

// MARK: - Deterministic randomness for the texture so it doesn't shimmer.

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
