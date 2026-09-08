import CoreGraphics
import Foundation

/// Observes display connect/disconnect/reconfigure events via
/// `CGDisplayRegisterReconfigurationCallback` and notifies the app so the
/// menu refreshes and preset matching is recalculated.
///
/// Never modifies the layout on its own; automatic switching only happens
/// when the user explicitly enables it in settings.
@MainActor
final class DisplayChangeObserver: ObservableObject {
    /// Fired on the main actor after any display topology change settles.
    var onDisplaysChanged: (() -> Void)?

    private var isRegistered = false
    private var debounceWorkItem: DispatchWorkItem?

    static let shared = DisplayChangeObserver()

    private init() {}

    func start() {
        guard !isRegistered else { return }
        let error = CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            // Callback may arrive on any thread; hop to main for UI work.
            // Skip the "begin configuration" phase and react once settled.
            // Bit values from CGDisplayChangeSummaryFlags (CGDisplayConfiguration.h):
            // moved 1<<1, setMain 1<<2, setMode 1<<3, add 1<<4, remove 1<<5,
            // enabled 1<<8, disabled 1<<9, desktopShapeChanged 1<<12.
            let relevant = CGDisplayChangeSummaryFlags(rawValue: (1 << 1) | (1 << 2) | (1 << 3)
                | (1 << 4) | (1 << 5) | (1 << 8) | (1 << 9) | (1 << 12))
            guard flags.intersection(relevant).rawValue != 0 else { return }
            DispatchQueue.main.async {
                DisplayChangeObserver.shared.displaysChangedDebounced()
            }
        }, nil)
        if error == .success {
            isRegistered = true
            AppLogger.discovery.info("Display reconfiguration callback registered.")
        } else {
            AppLogger.discovery.error("Failed to register display callback: \(error.rawValue)")
        }
    }

    func stop() {
        // The callback is a non-capturing global-style closure; unregistration
        // requires the same function pointer, so we keep observation for the
        // lifetime of the process (appropriate for a menu-bar utility).
    }

    private func displaysChangedDebounced() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            AppLogger.discovery.info("Display topology changed; refreshing.")
            self?.onDisplaysChanged?()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }
}
