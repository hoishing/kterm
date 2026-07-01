import SwiftUI

/// A small "⌘N" capsule shown over a sidebar row while the user holds ⌘,
/// hinting at that row's `Select Vertical Tab N` shortcut. Modeled on cmux's
/// `ShortcutHintPill`, trimmed to just the material capsule + label.
struct ShortcutHintPill: View {
    let number: Int

    var body: some View {
        Text("⌘\(number)")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
