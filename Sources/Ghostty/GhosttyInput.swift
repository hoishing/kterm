import AppKit
import GhosttyKit

/// Translate AppKit modifier flags into libghostty's mods bitmask.
/// Adapted from Ghostty's `Ghostty.ghosttyMods`.
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let raw = flags.rawValue
    if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
    return ghostty_input_mods_e(mods)
}

/// Convert libghostty's mods bitmask back into AppKit modifier flags.
/// Adapted from Ghostty's `Ghostty.eventModifierFlags`.
func ghosttyEventModifierFlags(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
    var flags = NSEvent.ModifierFlags(rawValue: 0)
    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
    return flags
}

/// Build a `ghostty_input_key_s` from an NSEvent (without text/composing, which
/// the caller sets). The keycode passed to libghostty is the native macOS
/// virtual keycode, which libghostty maps internally.
///
/// `translationMods`, when given, should come from
/// `ghostty_surface_key_translation_mods` and reflects which modifiers configs
/// like `macos-option-as-alt` say were consumed producing `text` -- e.g. with
/// `macos-option-as-alt` set, Option is NOT consumed, so it stays available for
/// libghostty to encode as an Alt/ESC prefix (needed for Option+Delete to be
/// word-delete instead of a plain backspace).
/// Adapted from Ghostty's `NSEvent.ghosttyKeyEvent`.
func ghosttyKeyEvent(
    _ event: NSEvent, action: ghostty_input_action_e,
    translationMods: NSEvent.ModifierFlags? = nil
) -> ghostty_input_key_s {
    var key = ghostty_input_key_s()
    key.action = action
    key.keycode = UInt32(event.keyCode)
    key.text = nil
    key.composing = false
    key.mods = ghosttyMods(event.modifierFlags)
    // control/command never contribute to text translation; assume the rest do.
    key.consumed_mods = ghosttyMods((translationMods ?? event.modifierFlags).subtracting([.control, .command]))
    key.unshifted_codepoint = 0
    if event.type == .keyDown || event.type == .keyUp {
        if let chars = event.characters(byApplyingModifiers: []),
           let scalar = chars.unicodeScalars.first {
            key.unshifted_codepoint = scalar.value
        }
    }
    return key
}

extension NSEvent {
    /// The text to send to libghostty for a key event, filtering out control
    /// characters (libghostty encodes those itself) and function-key PUA values.
    /// Adapted from Ghostty's `NSEvent.ghosttyCharacters`.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        }
        return characters
    }
}
