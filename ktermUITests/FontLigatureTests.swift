import XCTest

/// End-to-end check that the `kterm-font-ligatures` config toggle is parsed and
/// takes effect. The terminal is rendered by libghostty as one opaque surface,
/// so individual ligature glyphs aren't reachable through the accessibility
/// tree; instead the app (when launched with `KTERM_UITEST_CONFIG`) exposes the
/// parsed setting via a hidden `config.fontLigatures` probe (see `RootView`).
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
        XCTAssertEqual(ligatureProbe.value as? String, "off",
                       "ligatures should be off when the toggle is unset")
    }

    func testLigaturesEnabledWhenToggledOn() throws {
        launch(config: "kterm-font-ligatures = true\n")
        XCTAssertEqual(ligatureProbe.value as? String, "on",
                       "kterm-font-ligatures = true should enable ligatures")
    }

    func testLigaturesStayOffWhenToggledOff() throws {
        launch(config: "kterm-font-ligatures = false\n")
        XCTAssertEqual(ligatureProbe.value as? String, "off",
                       "kterm-font-ligatures = false should keep ligatures off")
    }

    /// Writes `config` to the injected path and launches the app against it.
    private func launch(config: String) {
        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
        app = XCUIApplication()
        app.launchEnvironment["KTERM_UITEST_CONFIG"] = configPath
        app.launch()
        waitForShellReady()
    }

    private var ligatureProbe: XCUIElement {
        let probe = app.descendants(matching: .any)
            .matching(identifier: "config.fontLigatures").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "ligature probe never appeared")
        return probe
    }
}
