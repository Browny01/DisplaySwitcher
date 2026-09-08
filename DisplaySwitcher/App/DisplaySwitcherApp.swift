import SwiftUI

@main
struct DisplaySwitcherApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Menu-bar utility: no dock icon (LSUIElement), UI lives in the menu
        // plus the settings window below.
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label(AppConstants.appName, systemImage: "display.2")
        }
        .menuBarExtraStyle(.menu)

        Window("\(AppConstants.appName) Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)
    }
}
