import Carbon
import Foundation

/// Global hot-key registration built on Carbon `RegisterEventHotKey`.
///
/// This needs no Accessibility permission and no third-party dependency.
/// A single Carbon event handler dispatches pressed hot keys to per-ID
/// actions stored in a lock-protected map. Shortcuts recorded in the UI
/// require at least two modifiers so the app never silently steals
/// single-modifier system shortcuts.
@MainActor
final class ShortcutManager: ObservableObject {
    typealias Action = @Sendable () -> Void

    private struct Registration {
        var hotKeyID: UInt32
        var hotKeyRef: EventHotKeyRef?
    }

    private var registrations: [String: Registration] = [:]
    private var handlerInstalled = false
    private var nextHotKeyID: UInt32 = 1

    // MARK: - Registration

    /// Register (or re-register) a named shortcut. Passing nil unregisters it.
    func setShortcut(_ shortcut: KeyboardShortcut?, named name: String, action: @escaping Action) {
        unregister(named: name)
        guard let shortcut else { return }
        installHandlerIfNeeded()

        let id = nextHotKeyID
        nextHotKeyID &+= 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x44535748), id: id) // "DSWH"
        let status = RegisterEventHotKey(shortcut.keyCode,
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            HotKeyDispatcher.shared.setAction(action, for: id)
            registrations[name] = Registration(hotKeyID: id, hotKeyRef: ref)
            AppLogger.shortcuts.info("Registered shortcut '\(name)': \(shortcut.displayLabel)")
        } else {
            AppLogger.shortcuts.error(
                "Failed to register shortcut '\(name)' (\(shortcut.displayLabel)): OSStatus \(status)")
        }
    }

    func unregister(named name: String) {
        guard let registration = registrations.removeValue(forKey: name) else { return }
        HotKeyDispatcher.shared.removeAction(for: registration.hotKeyID)
        if let ref = registration.hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    func unregisterAll() {
        for name in Array(registrations.keys) {
            unregister(named: name)
        }
    }

    // MARK: - Private

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         { _, event, _ -> OSStatus in
                                             HotKeyDispatcher.shared.dispatch(event: event)
                                             return noErr
                                         },
                                         1,
                                         &eventType,
                                         nil,
                                         nil)
        handlerInstalled = (status == noErr)
        if !handlerInstalled {
            AppLogger.shortcuts.error("Failed to install hot-key event handler: \(status)")
        }
    }
}

/// Thread-safe map from Carbon hot-key IDs to actions plus the dispatch
/// entry point called from the Carbon event handler (any thread).
/// Unchecked Sendable is safe here: every access goes through `lock`.
private final class HotKeyDispatcher: @unchecked Sendable {
    static let shared = HotKeyDispatcher()

    private let lock = NSLock()
    private var actions: [UInt32: ShortcutManager.Action] = [:]

    func setAction(_ action: @escaping ShortcutManager.Action, for id: UInt32) {
        lock.withLock { actions[id] = action }
    }

    func removeAction(for id: UInt32) {
        _ = lock.withLock { actions.removeValue(forKey: id) }
    }

    func dispatch(event: EventRef?) {
        var hotKeyID = EventHotKeyID()
        guard let event else { return }
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &hotKeyID)
        guard status == noErr else { return }
        let action = lock.withLock { actions[hotKeyID.id] }
        guard let action else { return }
        DispatchQueue.main.async { action() }
    }
}
