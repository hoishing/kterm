import XCTest

/// End-to-end check that the `kterm-font-ligatures` config toggle is parsed and
/// takes effect. The terminal is rendered by libghostty as one opaque surface,
/// so individual ligature glyphs aren't reachable through the accessibility
/// tree; instead the app (when launched with `KTERM_UITEST_CONFIG`) exposes the
/// parsed setting via a hidden probe whose identifier is `config.fontLigatures.on`
/// or `config.fontLigatures.off` (see `RootView`).
final class FontLigatureTests: KtermUITestCase {
    private var configPath = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The per-test config file is written and the app launched inside each
        // test, so a test can pick the toggle value it needs first.
        configPath = "/tmp/kterm-e2e-ligature-\(UInt32.random(in: 0..<UInt32.max)).config"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: configPath)
        try super.tearDownWithError()
    }

    func testLigaturesOffByDefault() throws {
        // An empty config: the toggle is absent, so ligatures default to off.
        launch(config: "")
        assertLigatures(on: false)
    }

    func testLigaturesEnabledWhenToggledOn() throws {
        launch(config: "kterm-font-ligatures = true\n")
        assertLigatures(on: true)
    }

    func testLigaturesStayOffWhenToggledOff() throws {
        launch(config: "kterm-font-ligatures = false\n")
        assertLigatures(on: false)
    }

    /// Writes `config` to the injected path and launches the app against it.
    private func launch(config: String) {
        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
        app = XCUIApplication()
        app.launchEnvironment["KTERM_UITEST_CONFIG"] = configPath
        app.launch()
        waitForShellReady()
    }

    /// Asserts the probe for the expected ligature state exists (and its
    /// opposite doesn't).
    private func assertLigatures(on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expected = probe(on ? "on" : "off")
        XCTAssertTrue(expected.waitForExistence(timeout: 5),
                      "expected ligatures \(on ? "on" : "off")", file: file, line: line)
        XCTAssertFalse(probe(on ? "off" : "on").exists,
                       "opposite ligature probe should be absent", file: file, line: line)
    }

    private func probe(_ state: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "config.fontLigatures.\(state)").firstMatch
    }
}
