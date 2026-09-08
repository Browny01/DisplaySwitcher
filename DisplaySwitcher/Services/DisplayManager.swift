import CoreGraphics
import Foundation

/// Coordinates detection, matching, and switching. UI layers talk to this
/// type; it owns no UI itself.
@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var connectedDisplays: [DisplayInfo] = []
    @Published private(set) var lastError: DisplayConfigurationError?
    @Published private(set) var isApplying = false

    private let discovery: any DisplayDiscovering
    private let configurationService: DisplayConfigurationService
    private let notificationService: NotificationService

    init(discovery: any DisplayDiscovering = CoreGraphicsDisplayDiscovery(),
         notificationService: NotificationService = NotificationService()) {
        self.discovery = discovery
        self.configurationService = DisplayConfigurationService(discovery: discovery)
        self.notificationService = notificationService
        refresh()
    }

    var mainDisplay: DisplayInfo? {
        connectedDisplays.first(where: { $0.isMain })
    }

    func refresh() {
        connectedDisplays = discovery.currentDisplays()
        AppLogger.discovery.debug("Refreshed: \(self.connectedDisplays.count) displays.")
    }

    /// Capture the current arrangement as preset entries.
    func captureCurrentEntries() -> [PresetDisplayEntry] {
        let current = discovery.currentDisplays()
        connectedDisplays = current
        return current.map { display in
            PresetDisplayEntry(from: display,
                               modeID: discovery.displayModeID(for: display.displayID))
        }
    }

    /// Validate + apply a preset, with pre-switch snapshot for rollback.
    func applyPreset(_ preset: DisplayPreset, settings: AppSettings) async -> Bool {
        isApplying = true
        lastError = nil
        defer { isApplying = false }

        do {
            let plan = try configurationService.plan(preset: preset)
            let rollback = configurationService.snapshotOrigins()
            var planWithRollback = plan
            planWithRollback = LayoutPlan(moves: plan.moves,
                                          presetName: plan.presetName,
                                          rollbackOrigins: rollback)
            try configurationService.apply(planWithRollback)
            // Re-read state and verify every display landed where planned.
            refresh()
            if !verify(plan: planWithRollback) {
                lastError = .verificationFailed
                AppLogger.configuration.error("Post-apply verification failed.")
                return false
            }
            if settings.notificationsEnabled {
                notificationService.show(
                    title: AppConstants.appName,
                    body: "\(preset.name) layout applied")
            }
            return true
        } catch let error as DisplayConfigurationError {
            lastError = error
            AppLogger.configuration.error("Apply failed: \(error.localizedDescription)")
            if settings.notificationsEnabled {
                notificationService.show(title: AppConstants.appName,
                                         body: error.localizedDescription)
            }
            return false
        } catch {
            AppLogger.configuration.error("Unexpected apply error: \(error.localizedDescription)")
            return false
        }
    }

    /// Which saved preset (if any) matches the currently connected setup and
    /// arrangement.
    func recognisedPreset(in presets: [DisplayPreset]) -> DisplayPreset? {
        for preset in presets {
            let matches = DisplayMatcher.match(preset: preset, against: connectedDisplays)
            guard DisplayMatcher.isCompleteMatch(matches, preset: preset) else { continue }
            // Arrangement check: current origins must equal saved origins up
            // to a global translation.
            let savedFrames = preset.displays.map { entry in
                CGRect(x: entry.origin.x, y: entry.origin.y,
                       width: entry.pointSize.width, height: entry.pointSize.height)
            }
            let currentFramesByFingerprint: [DisplayFingerprint: CGRect] = Dictionary(
                uniqueKeysWithValues: connectedDisplays.map { ($0.fingerprint, $0.frame) })
            let savedOffsets = CoordinateUtilities.relativeOffsets(of: savedFrames)
            let currentFrames = matches.map { $0.display.frame }
            // Pair saved offsets with current ones via fingerprint.
            var aligned = true
            for (index, entry) in preset.displays.enumerated() {
                guard let currentFrame = currentFramesByFingerprint[entry.fingerprint] else {
                    aligned = false
                    break
                }
                let box = CoordinateUtilities.boundingBox(of: currentFrames)
                let rel = CGPoint(x: currentFrame.minX - box.minX,
                                  y: currentFrame.minY - box.minY)
                if abs(rel.x - savedOffsets[index].x) > 1.5
                    || abs(rel.y - savedOffsets[index].y) > 1.5 {
                    aligned = false
                    break
                }
            }
            if aligned { return preset }
        }
        return nil
    }

    // MARK: - Private

    private func verify(plan: LayoutPlan) -> Bool {
        // Quartz documents that it may "adjust" requested origins to remove
        // gaps or overlaps when committing, so allow a few points of drift.
        let tolerance = 6.0
        let origins = Dictionary(uniqueKeysWithValues:
            discovery.currentDisplays().map { ($0.displayID, $0.origin.cgPoint) })
        for move in plan.moves {
            guard let actual = origins[move.displayID] else { return false }
            if abs(actual.x - move.targetOrigin.x) > tolerance
                || abs(actual.y - move.targetOrigin.y) > tolerance {
                return false
            }
        }
        return true
    }
}
