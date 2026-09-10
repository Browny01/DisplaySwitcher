import Foundation

/// Notification names so the AppKit `NSStatusItem` menu can rebuild when
/// displays or presets change.
extension Notification.Name {
    static let displayManagerDidRefresh = Notification.Name("displayManagerDidRefresh")
    static let presetManagerDidChange = Notification.Name("presetManagerDidChange")
}

/// Central place for app-wide naming so the app can be renamed easily later.
enum AppConstants {
    static let appName = "DisplaySwitcher"
    static let bundleIdentifier = "com.displayswitcher.DisplaySwitcher"
    static let presetsFileName = "presets.json"
    static let settingsKey = "com.displayswitcher.settings"
    static let presetsSchemaVersion = 1
    static let githubURL = URL(string: "https://github.com/Browny01/DisplaySwitcher")!
}
