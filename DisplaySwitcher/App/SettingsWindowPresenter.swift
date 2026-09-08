import AppKit
import SwiftUI

/// Opens the settings window and brings it in front.
///
/// Normal apps automatically activate when a window opens; menu-bar apps
/// (`LSUIElement`) do not, which is why the settings window previously
/// appeared behind other apps. We open the scene, then make the window key
/// and activate the app explicitly.
@MainActor
enum SettingsWindowPresenter {
    static func present(openWindow: OpenWindowAction) {
        openWindow(id: "settings")
        Task {
            // The SwiftUI Window scene creates its NSWindow asynchronously
            // after openWindow; poll briefly for it.
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
        NSApp.windows.first { window in
            window.identifier?.rawValue == "settings"
                || window.title == "\(AppConstants.appName) Settings"
        }
    }
}