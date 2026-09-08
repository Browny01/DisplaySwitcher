import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            PresetsSettingsView(appState: appState)
                .tabItem { Label("Presets", systemImage: "rectangle.on.rectangle") }
            DisplaysSettingsView(appState: appState)
                .tabItem { Label("Displays", systemImage: "display") }
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }
            ShortcutsSettingsView(appState: appState)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(minWidth: 560, minHeight: 420)
        .padding()
    }
}
