import AppKit
import SwiftUI

/// Resolves the app-shell UI font from `kterm-ui-font-family`.
///
/// Configured once at launch via `configure(family:)`. Every visible chrome
/// label (sidebar rows, tab chips, shortcut pills, empty states, …) goes
/// through `font(size:weight:)` so one config key restyles them all.
enum KtermUIFont {
    /// Configured family. Empty or `monospace` → system monospaced (default).
    private(set) static var family: String = "monospace"

    static func configure(family: String) {
        self.family = family.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// UI text font at `size` / `weight`. Unknown family names fall back to
    /// system monospaced so missing faces never blank out chrome labels.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = family
        if name.isEmpty || name.lowercased() == "monospace" {
            return .system(size: size, weight: weight, design: .monospaced)
        }

        let nsWeight = Self.nsWeight(weight)
        // Family name first ("JetBrains Mono", "Helvetica Neue").
        if let font = NSFontManager.shared.font(
            withFamily: name, traits: [], weight: nsWeight, size: size
        ) {
            return Font(font)
        }
        // PostScript / full name fallback ("JetBrainsMono-Regular").
        if let font = NSFont(name: name, size: size) {
            return Font(font)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// NSFontManager weight scale is 0…15; 5 is regular.
    private static func nsWeight(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 1
        case .thin: return 2
        case .light: return 3
        case .regular: return 5
        case .medium: return 6
        case .semibold: return 8
        case .bold: return 9
        case .heavy: return 10
        case .black: return 11
        default: return 5
        }
    }
}
