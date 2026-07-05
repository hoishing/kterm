import AppKit
import XCTest

/// Terminal input paths that libghostty owns internally, verified end-to-end
/// by reading back the real system pasteboard (mouse events and key encodings
/// are forwarded raw, so there's no SwiftUI/accessibility state to assert on):
///
/// - Mouse-drag text selection + ⌘C copy.
/// - Option+Delete word deletion. `macos-option-as-alt` is a built-in default
///   (`KtermConfig.swift`) that tells libghostty to prefix Option-modified
///   keys with an Alt/ESC sequence so zsh's zle binds them to
///   `backward-kill-word`. A wrong key encoding (e.g. marking Option as
///   already "consumed" by text translation) silently degrades this to a
///   plain single-character backspace.
final class TerminalInputTests: KtermUITestCase {
    func testSelectionCopyAndWordDelete() {
        // 1. Drag-select a typed marker and ⌘C-copy it. A fresh, unique marker
        // avoids matching stale pasteboard content.
        let marker = "KTERME2E\(UInt32.random(in: 0..<UInt32.max))"
        typeInTerminal("clear")
        typeInTerminal(marker, pressReturn: false)
        Thread.sleep(forTimeInterval: 0.3)

        // Drag across the top of the surface, a few rows deep, so the marker is
        // captured even if a long prompt (e.g. CI's long runner hostname) wraps
        // the line onto a second row.
        let copiedMarker = copyOfSelection(
            from: CGVector(dx: 0.01, dy: 0.03), to: CGVector(dx: 0.99, dy: 0.12), until: marker)
        XCTAssertTrue(copiedMarker.contains(marker),
                      "expected copied text to contain \(marker), got: \(copiedMarker)")

        // 2. Option+Delete should remove the whole trailing word
        // (backward-kill-word via zsh's zle), not just the last character.
        let word = "KTERME2E\(UInt32.random(in: 0..<UInt32.max))"
        let keep = "\(word)_AAA"
        let drop = "\(word)_BBB"
        typeInTerminal("clear")
        typeInTerminal("echo \(keep) \(drop)", pressReturn: false)

        app.typeKey(.delete, modifierFlags: .option)

        surface.typeText("\r")
        Thread.sleep(forTimeInterval: 0.3)

        let copied = copyOfSelection(
            from: CGVector(dx: 0.01, dy: 0.03), to: CGVector(dx: 0.99, dy: 0.25), until: keep)
        XCTAssertTrue(copied.contains(keep), "expected output to contain \(keep), got: \(copied)")
        XCTAssertFalse(
            copied.contains(drop),
            "Option+Delete should remove the whole word \(drop), but it (or part of it) survived: \(copied)"
        )
    }
}
