import AppKit
import Foundation

/// Keeps the grab script in Chrome's front tab and copies a failed in-page
/// clipboard write onto the system pasteboard.
///
/// The shortcut is Ctrl+Shift+K inside the page. kterm does not register a
/// global hotkey, so the chord does nothing in other apps. Chrome must allow
/// JavaScript from Apple Events (View → Developer).
@MainActor
final class ChromeGrab {
    static let shared = ChromeGrab()

    private let probe: String
    private var timer: Timer?
    private var warned = false
    private var loggedInjectError = false

    private init() {
        let script = Self.loadScript()
        let encoded = Data(script.utf8).base64EncodedString()
        // One line: AppleScript string literals cannot contain raw line breaks.
        probe = "(function(){try{if(!window.__ktermGrabInstalled){eval(atob(\"\(encoded)\"));}}catch(e){return \"ERR:\"+(e&&e.message?e.message:e);}var box=window.__ktermGrab;if(!box)return \"\";var result=box.result||\"\";box.result=\"\";return result;})()"
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.followFrontApp() }
        }
        center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.followFrontApp() }
        }
        followFrontApp()
    }

    private func followFrontApp() {
        guard Self.chromeIsFront else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        guard Self.chromeIsFront else { return }
        let outcome = ChromeScript.run(probe)
        if outcome.javascriptDisabled {
            warnJavaScriptDisabled()
            return
        }
        guard let text = outcome.text, !text.isEmpty else { return }
        if text.hasPrefix("ERR:") {
            if !loggedInjectError {
                loggedInjectError = true
                NSLog("kterm: chrome grab inject failed: \(text)")
            }
            return
        }
        guard text.hasPrefix("KTERM:") else { return }
        copyToPasteboard(String(text.dropFirst("KTERM:".count)))
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func warnJavaScriptDisabled() {
        guard !warned else { return }
        warned = true
        NotificationManager.post(
            title: "Chrome grab needs a setting",
            body: "In Chrome, turn on View → Developer → Allow JavaScript from Apple Events. Then press Ctrl+Shift+K on the page.")
    }

    private static var chromeIsFront: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome"
    }

    private static func loadScript() -> String {
        guard let url = Bundle.main.url(forResource: "grab", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty
        else {
            NSLog("kterm: grab.js missing from the app bundle")
            return ""
        }
        return text
    }
}

private enum ChromeScript {
    struct Outcome {
        var text: String?
        var javascriptDisabled: Bool
    }

    static func run(_ javascript: String) -> Outcome {
        let escaped = javascript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Google Chrome"
            if (count of windows) is 0 then return ""
            return execute active tab of front window javascript "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            let message = error?[NSAppleScript.errorMessage] as? String ?? ""
            let disabled = message.localizedCaseInsensitiveContains("javascript")
                && (message.localizedCaseInsensitiveContains("turned off")
                    || message.localizedCaseInsensitiveContains("allow javascript"))
            return Outcome(text: nil, javascriptDisabled: disabled)
        }
        return Outcome(text: result.stringValue ?? "", javascriptDisabled: false)
    }
}
