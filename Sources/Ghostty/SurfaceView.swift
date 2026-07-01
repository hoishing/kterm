import AppKit
import Carbon.HIToolbox
import SwiftUI
import GhosttyKit

/// The AppKit view that hosts a single libghostty terminal surface. libghostty
/// attaches its own `CAMetalLayer` to this view and renders into it; our job is
/// to forward keyboard, mouse, focus, and size/scale events.
///
/// A condensed version of the input handling in Ghostty's own
/// `SurfaceView_AppKit.swift`, keeping the pieces required for correct typing
/// (including IME / dead keys) and dropping app-specific features.
final class SurfaceView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?

    /// Called when libghostty reports a new title for this surface.
    var onTitleChange: ((String) -> Void)?
    /// Called when libghostty reports a new working directory for this surface.
    var onPwdChange: ((String) -> Void)?
    /// Called when the underlying shell process exits / surface requests close.
    var onClose: (() -> Void)?

    // IME / key-input state.
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    init(app: ghostty_app_t) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 480))

        var cfg = ghostty_surface_config_new()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()))
        cfg.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        self.surface = ghostty_surface_new(app, &cfg)

        postsFrameChangedNotifications = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let surface {
            // Must free on the main actor; capture the raw value so we don't
            // retain self.
            let s = surface
            DispatchQueue.main.async { ghostty_surface_free(s) }
        }
    }

    // MARK: - Geometry / focus

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard surface != nil else { return }
        updateScale()
        updateSize()
        if window != nil { window?.makeFirstResponder(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
        updateSize()
    }

    private func updateScale() {
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    private func updateSize() {
        guard let surface else { return }
        let backing = convertToBacking(bounds.size)
        guard backing.width > 0, backing.height > 0 else { return }
        ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
    }

    override func becomeFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, true) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return super.resignFirstResponder()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Accumulate any text produced by IME / interpretKeyEvents.
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let markedBefore = markedText.length > 0

        interpretKeyEvents([event])

        // Push preedit state to libghostty.
        syncPreedit(clearIfNeeded: markedBefore)

        if let acc = keyTextAccumulator, !acc.isEmpty {
            for text in acc {
                _ = sendKey(action, event: event, text: text, composing: false)
            }
        } else {
            _ = sendKey(action, event: event,
                        text: event.ghosttyCharacters,
                        composing: markedText.length > 0 || markedBefore)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = sendKey(GHOSTTY_ACTION_RELEASE, event: event, text: nil, composing: false)
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch Int(event.keyCode) {
        case kVK_CapsLock: mod = GHOSTTY_MODS_CAPS.rawValue
        case kVK_Shift, kVK_RightShift: mod = GHOSTTY_MODS_SHIFT.rawValue
        case kVK_Control, kVK_RightControl: mod = GHOSTTY_MODS_CTRL.rawValue
        case kVK_Option, kVK_RightOption: mod = GHOSTTY_MODS_ALT.rawValue
        case kVK_Command, kVK_RightCommand: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        if hasMarkedText() { return }
        let mods = ghosttyMods(event.modifierFlags)
        let action: ghostty_input_action_e =
            (mods.rawValue & mod != 0) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        _ = sendKey(action, event: event, text: nil, composing: false)
    }

    @discardableResult
    private func sendKey(_ action: ghostty_input_action_e, event: NSEvent,
                         text: String?, composing: Bool) -> Bool {
        guard let surface else { return false }
        var key = ghosttyKeyEvent(event, action: action)
        key.composing = composing

        // Only forward UTF-8 text when it isn't a lone control character;
        // libghostty encodes control characters itself.
        if let text, !text.isEmpty, let c = text.utf8.first, c >= 0x20 {
            return text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key(surface, key)
            }
        }
        return ghostty_surface_key(surface, key)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) { mouseButton(.press, .left, event) }
    override func mouseUp(with event: NSEvent) { mouseButton(.release, .left, event) }
    override func rightMouseDown(with event: NSEvent) { mouseButton(.press, .right, event) }
    override func rightMouseUp(with event: NSEvent) { mouseButton(.release, .right, event) }
    override func otherMouseDown(with event: NSEvent) { mouseButton(.press, .middle, event) }
    override func otherMouseUp(with event: NSEvent) { mouseButton(.release, .middle, event) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    private enum BtnState { case press, release }
    private enum Btn { case left, right, middle }

    private func mouseButton(_ state: BtnState, _ btn: Btn, _ event: NSEvent) {
        guard let surface else { return }
        if state == .press { window?.makeFirstResponder(self) }
        let cState: ghostty_input_mouse_state_e = state == .press ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE
        let cBtn: ghostty_input_mouse_button_e = switch btn {
            case .left: GHOSTTY_MOUSE_LEFT
            case .right: GHOSTTY_MOUSE_RIGHT
            case .middle: GHOSTTY_MOUSE_MIDDLE
        }
        _ = ghostty_surface_mouse_button(surface, cState, cBtn, ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, ghosttyMods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        var modsBits: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            x *= 2; y *= 2
            modsBits |= 1 // precision bit
        }
        ghostty_surface_mouse_scroll(surface, x, y, ghostty_input_scroll_mods_t(modsBits))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil))
    }

    // MARK: - NSTextInputClient

    func hasMarkedText() -> Bool { markedText.length > 0 }
    func markedRange() -> NSRange { markedText.length > 0 ? NSRange(0..<markedText.length) : NSRange() }
    func selectedRange() -> NSRange { NSRange() }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = NSMutableAttributedString(attributedString: v)
        case let v as String: markedText = NSMutableAttributedString(string: v)
        default: break
        }
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        let chars: String
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(chars)
            return
        }
        guard let surface else { return }
        let len = chars.utf8CString.count
        if len > 1 {
            chars.withCString { ghostty_surface_text(surface, $0, UInt(len - 1)) }
        }
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x = 0.0, y = 0.0, w = 0.0, h = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x, y: bounds.height - y, width: w, height: h)
        let winRect = convert(viewRect, to: nil)
        return window?.convertToScreen(winRect) ?? winRect
    }

    override func doCommand(by selector: Selector) {
        // Swallow unhandled commands so AppKit doesn't NSBeep. Key encoding is
        // already handled by ghostty_surface_key in keyDown.
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ghostty_surface_preedit(surface, $0, UInt(len - 1)) }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}
