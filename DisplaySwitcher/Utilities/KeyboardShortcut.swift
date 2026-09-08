import Carbon
import Foundation

/// A global keyboard shortcut stored with Carbon modifier flags so it can be
/// registered with `RegisterEventHotKey` without Accessibility permission.
struct KeyboardShortcut: Codable, Hashable, Sendable {
    /// Carbon virtual key code (kVK_* from HIToolbox/Events.h).
    var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    var displayLabel: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.label(for: keyCode))
        return parts.joined()
    }

    // MARK: - Key code catalogue

    /// Small curated catalogue (letters, digits, F-keys, a few symbols) used
    /// by the shortcut recorder UI.
    static let catalogue: [(label: String, keyCode: UInt32)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5),
        ("Z", 6), ("X", 7), ("C", 8), ("V", 9), ("B", 11), ("Q", 12),
        ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17),
        ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23),
        ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29),
        ("]", 30), ("O", 31), ("U", 32), ("[", 33), ("I", 34), ("P", 35),
        ("L", 37), ("J", 38), ("'", 39), ("K", 40), (";", 41), ("\\", 42),
        (",", 43), ("/", 44), ("N", 45), ("M", 46), (".", 47),
        ("Tab", 48), ("Space", 49), ("Return", 36), ("Escape", 53),
        ("Delete", 51), ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118),
        ("F5", 96), ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101),
        ("F10", 109), ("F11", 103), ("F12", 111),
        ("↑", 126), ("↓", 125), ("←", 123), ("→", 124),
    ]

    static func label(for keyCode: UInt32) -> String {
        catalogue.first(where: { $0.keyCode == keyCode })?.label
            ?? "Key \(keyCode)"
    }

    /// macOS reserves plain single-modifier shortcuts aggressively; require
    /// at least two modifiers so we never silently steal system shortcuts.
    var usesSafeModifierCombination: Bool {
        var count = 0
        for flag in [UInt32(cmdKey), UInt32(optionKey), UInt32(controlKey), UInt32(shiftKey)] {
            if carbonModifiers & flag != 0 { count += 1 }
        }
        return count >= 2
    }
}
