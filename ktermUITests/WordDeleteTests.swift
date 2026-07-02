import AppKit
import XCTest

/// Regression test for Option+Delete word-deletion. `macos-option-as-alt` is
/// a built-in default (`KtermConfig.swift`), which tells libghostty to
/// prefix Option-modified keys with an Alt/ESC sequence so zsh's zle can bind
/// them to `backward-kill-word`. Getting the key encoding wrong (e.g. marking
/// Option as already "consumed" by text translation) silently degrades this
/// to a plain single-character backspace instead, so this drives the real
/// key combo and reads back what the shell actually executed.
final class WordDeleteTests: KtermUITestCase {
    func testOptionDeleteRemovesWholeWordBackward() {
        let marker = "KTERME2E\(UInt32.random(in: 0..<UInt32.max))"
        let keep = "\(marker)_AAA"
        let drop = "\(marker)_BBB"

        typeInTerminal("clear")
        typeInTerminal("echo \(keep) \(drop)", pressReturn: false)

        // Option+Delete should remove the whole trailing word (backward-kill-word
        // via zsh's zle), not just the last character.
        app.typeKey(.delete, modifierFlags: .option)

        surface.typeText("\r")
        Thread.sleep(forTimeInterval: 0.3)

        NSPasteboard.general.clearContents()
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.03))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
        app.typeKey("c", modifierFlags: .command)

        let deadline = Date().addingTimeInterval(5)
        var copied = ""
        while Date() < deadline {
            copied = NSPasteboard.general.string(forType: .string) ?? ""
            if copied.contains(keep) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertTrue(copied.contains(keep), "expected output to contain \(keep), got: \(copied)")
        XCTAssertFalse(
            copied.contains(drop),
            "Option+Delete should remove the whole word \(drop), but it (or part of it) survived: \(copied)"
        )
    }
}
