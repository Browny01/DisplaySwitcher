import SwiftUI

@main
struct DisplaySwitcherApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Settings {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)
    }
}