import AppKit

/// Opens the SwiftUI Settings scene and brings it in front.
///
/// Menu-bar-only apps (`LSUIElement`) don't auto-activate when a window
/// opens; we re-trigger the standard "Settings…" menu action, then activate
/// the app and order the window key.
@MainActor
enum SettingsWindowPresenter {
    static func present() {
        performSettingsAction()
        Task {
            // Poll briefly for the asynchronously-created NSWindow so we can
            // bring it forward reliably.
            for _ in 0..<20 {
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

    /// Sends the exact same action the standard menu bar's "Settings…" item
    /// triggers, so the SwiftUI `Settings` scene opens identically to a user
    /// click. `NSApp.sendAction(showSettingsWindow:)` alone is unreliable on
    /// recent macOS, so we invoke the installed menu item directly.
    private static func performSettingsAction() {
        if let (index, item) = mainMenuSettingsItem() {
            item.menu?.performActionForItem(at: index)
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private static func mainMenuSettingsItem() -> (index: Int, item: NSMenuItem)? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for (index, subItem) in submenu.items.enumerated()
            where subItem.action != nil &&
                  subItem.title.localizedCaseInsensitiveContains("settings") {
                return (index, subItem)
            }
        }
        return nil
    }

    /// The SwiftUI Settings window's title follows its selected tab
    /// ("Presets", "General", …), so matching on "Settings" alone is not
    /// enough.
    static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard !(window is NSPanel) else { return false }
            let title = window.title
            let knownTitles = ["Settings", "General", "Presets", "About"]
            return knownTitles.contains { title.localizedCaseInsensitiveContains($0) }
        }
    }
}