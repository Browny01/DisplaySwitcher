import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp` (macOS 13+). Requires the app
/// to be code-signed to take effect; in unsigned local builds the call fails
/// gracefully and the setting simply does not persist at the system level.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isRegistered = false
    @Published private(set) var lastErrorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            isRegistered = SMAppService.mainApp.status == .enabled
        } else {
            isRegistered = false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        lastErrorMessage = nil
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                refresh()
            } catch {
                lastErrorMessage = error.localizedDescription
                AppLogger.ui.error("Launch-at-login change failed: \(error.localizedDescription)")
                refresh()
            }
        } else {
            lastErrorMessage = "Launch at login requires macOS 13 or newer."
        }
    }
}
