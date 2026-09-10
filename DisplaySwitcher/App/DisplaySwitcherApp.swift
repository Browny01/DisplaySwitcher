import SwiftUI

/// The SwiftUI menu-bar app. Entry point is `DisplaySwitcherMain`, which
/// handles CLI invocations before this scene runs.
struct DisplaySwitcherApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Settings {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)
    }
}