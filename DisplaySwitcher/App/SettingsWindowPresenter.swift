import AppKit

/// Opens the SwiftUI Settings scene and brings it in front.
///
/// Menu-bar-only apps (`LSUIElement`) don't auto-activate when a window
/// opens; we send the standard `showSettingsWindow:` action to the main
/// menu, then activate the app and order the window key.
@MainActor
enum SettingsWindowPresenter {
    static func present() {
        // The SwiftUI `Settings` scene registers under this AppKit action on
        // the main menu (File ▸ Settings…, ⌘,).
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        Task {
            // Poll briefly for the asynchronously-created NSWindow so we can
            // bring it forward reliably.
            for _ in 0..<10 {
                if let window = settingsWindow() {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    window.center()
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "Settings" || $0.title.contains("Settings") }
    }
}