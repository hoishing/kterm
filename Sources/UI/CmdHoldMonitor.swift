import AppKit
import Observation

/// Watches for the ⌘ key being held alone for `holdDelay` and flips
/// `isShowing` on, so the sidebar can reveal each row's ⌘-digit shortcut
/// while the user reads them. Releasing ⌘, pressing any other key, or the
/// app losing focus cancels/hides immediately.
///
/// A trimmed-down port of cmux's `WindowScopedShortcutHintModifierMonitor`,
/// without its per-window scoping or feature-flag plumbing (kterm has a
/// single window and always wants this on).
@Observable
@MainActor
final class CmdHoldMonitor {
    private(set) var isShowing = false

    /// How long ⌘ must be held alone before the hint appears.
    private let holdDelay: TimeInterval

    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var resignObserver: Any?
    private var pendingShowGeneration = 0

    init(holdDelay: TimeInterval = 0.5) {
        self.holdDelay = holdDelay
    }

    func start() {
        guard flagsMonitor == nil else { return }

        // NSEvent's local-monitor handler always runs on the main thread,
        // but its type isn't actor-isolated, so hop back onto MainActor
        // explicitly before touching any of our state.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor [weak self] in self?.handleFlagsChanged(event) }
            return event
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // An actual keystroke means the user is using a shortcut, not
            // waiting to be shown one — cancel/hide immediately.
            Task { @MainActor [weak self] in
                self?.cancelPending()
                self?.isShowing = false
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.cancelPending()
                self?.isShowing = false
            }
        }
    }

    /// Removes the event monitors/observer. Safe to call more than once;
    /// intentionally not done in `deinit`, since `@MainActor` classes can't
    /// touch actor-isolated state from deinit's nonisolated context.
    func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        flagsMonitor = nil
        keyDownMonitor = nil
        resignObserver = nil
        cancelPending()
        isShowing = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        if mods == [.command] {
            queueShow()
        } else {
            cancelPending()
            isShowing = false
        }
    }

    private func queueShow() {
        pendingShowGeneration += 1
        let generation = pendingShowGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay) { [weak self] in
            guard let self, generation == self.pendingShowGeneration else { return }
            self.isShowing = true
        }
    }

    private func cancelPending() {
        pendingShowGeneration += 1
    }
}
