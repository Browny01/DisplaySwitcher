import CoreGraphics
import Foundation

/// Errors raised while validating or applying a layout.
enum DisplayConfigurationError: LocalizedError, Equatable {
    case noDisplaysDetected
    case incompleteMatch(missing: [String])
    case ambiguousMatch
    case emptyPreset
    case configurationBeginFailed(CGError)
    case configurationApplyFailed(CGError)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .noDisplaysDetected:
            return "No connected displays were detected."
        case .incompleteMatch(let missing):
            return "Could not apply layout because \(missing.joined(separator: ", ")) \(missing.count == 1 ? "is" : "are") not connected."
        case .ambiguousMatch:
            return "Displays could not be matched unambiguously. The layout was not changed."
        case .emptyPreset:
            return "This preset contains no displays."
        case .configurationBeginFailed(let code):
            return "Could not start display reconfiguration (error \(code.rawValue))."
        case .configurationApplyFailed(let code):
            return "macOS rejected the display arrangement (error \(code.rawValue)). Your previous layout was kept."
        case .verificationFailed:
            return "The arrangement could not be verified after applying. Your previous layout may still be active."
        }
    }
}

/// One validated display move ready to apply.
struct PlannedDisplayMove: Sendable {
    var displayID: CGDirectDisplayID
    var displayName: String
    var targetOrigin: CGPoint
    var shouldBeMain: Bool
}

/// Full validated plan for applying a preset.
struct LayoutPlan: Sendable {
    var moves: [PlannedDisplayMove]
    var presetName: String
    /// Snapshot of origins before the change, for restore-on-failure.
    var rollbackOrigins: [CGDirectDisplayID: CGPoint]
}

/// Builds and applies display arrangements via Apple's Core Graphics display
/// configuration API (`CGBeginDisplayConfiguration` /
/// `CGConfigureDisplayOrigin` / `CGCompleteDisplayConfiguration`).
///
/// These APIs are long-standing but remain the only supported programmatic
/// way to reposition displays; there is deliberately no GUI scripting or
/// AppleScript here. All Quartz calls are isolated in this type so the app
/// can adapt if Apple ever ships a replacement API.
final class DisplayConfigurationService: Sendable {
    private let discovery: any DisplayDiscovering

    init(discovery: any DisplayDiscovering = CoreGraphicsDisplayDiscovery()) {
        self.discovery = discovery
    }

    // MARK: - Planning

    /// Match + validate a preset against currently connected displays.
    /// Throws without touching any system state when the mapping is unsafe.
    func plan(preset: DisplayPreset,
              connected: [DisplayInfo]? = nil) throws -> LayoutPlan {
        guard !preset.displays.isEmpty else { throw DisplayConfigurationError.emptyPreset }
        let current = connected ?? discovery.currentDisplays()
        guard !current.isEmpty else { throw DisplayConfigurationError.noDisplaysDetected }

        let matches = DisplayMatcher.match(preset: preset, against: current)

        // Every physical display may be used at most once; duplicates mean
        // the fingerprinting is ambiguous for this setup.
        let usedIDs = matches.map { $0.display.displayID }
        guard Set(usedIDs).count == usedIDs.count else {
            throw DisplayConfigurationError.ambiguousMatch
        }

        let missing = preset.displays
            .filter { entry in !matches.contains(where: { $0.presetEntry == entry }) }
            .map { $0.capturedName }
        guard missing.isEmpty else {
            throw DisplayConfigurationError.incompleteMatch(missing: missing)
        }

        // Preserve the saved relative arrangement exactly: compute each
        // entry's offset from the saved bounding-box origin, then anchor the
        // whole layout at the saved main display's *current* position. This
        // keeps relative offsets (including negative coordinates, gaps for
        // mixed sizes, portrait displays) intact without assuming anything
        // about where macOS currently places the global origin.
        let savedFrames = preset.displays.map { entry in
            CGRect(x: entry.origin.x, y: entry.origin.y,
                   width: entry.pointSize.width, height: entry.pointSize.height)
        }
        let savedBox = CoordinateUtilities.boundingBox(of: savedFrames)
        let offsets: [CGPoint] = savedFrames.map {
            CGPoint(x: $0.minX - savedBox.minX, y: $0.minY - savedBox.minY)
        }

        let anchorCurrentOrigin: CGPoint = {
            if let mainMatch = matches.first(where: { $0.presetEntry.wasMain }) {
                return mainMatch.display.origin.cgPoint
            }
            return matches.map { $0.display.origin.cgPoint }.first ?? .zero
        }()
        // Where the saved main sat inside its own layout determines how the
        // whole layout shifts so the main display stays put.
        let savedMainOffset: CGPoint = {
            if let idx = preset.displays.firstIndex(where: { $0.wasMain }) {
                return offsets[idx]
            }
            return .zero
        }()
        let layoutOrigin = CGPoint(x: anchorCurrentOrigin.x - savedMainOffset.x,
                                   y: anchorCurrentOrigin.y - savedMainOffset.y)

        var moves: [PlannedDisplayMove] = []
        for (index, entry) in preset.displays.enumerated() {
            guard let match = matches.first(where: { $0.presetEntry == entry }) else { continue }
            let target = CGPoint(x: layoutOrigin.x + offsets[index].x,
                                 y: layoutOrigin.y + offsets[index].y)
            moves.append(PlannedDisplayMove(
                displayID: match.display.displayID,
                displayName: match.display.name,
                targetOrigin: CGPoint(x: target.x.rounded(), y: target.y.rounded()),
                shouldBeMain: entry.wasMain
            ))
        }

        // Defensive: overlapping targets would produce an unusable desktop.
        // Each move gets the size of the display it will actually move to, so
        // stacked/offset arrangements never false-positive here.
        let frames = moves.map { move -> CGRect in
            let size = current.first(where: { $0.displayID == move.displayID })?.frame.size ?? .zero
            return CGRect(origin: move.targetOrigin, size: size)
        }
        if CoordinateUtilities.hasOverlaps(frames) {
            AppLogger.configuration.error("Planned layout contains overlaps; aborting.")
            throw DisplayConfigurationError.ambiguousMatch
        }

        let rollback = Dictionary(uniqueKeysWithValues:
            current.map { ($0.displayID, $0.origin.cgPoint) })
        return LayoutPlan(moves: moves, presetName: preset.name, rollbackOrigins: rollback)
    }

    // MARK: - Applying

    /// Apply a validated plan atomically. Displays are repositioned in a
    /// single `CGBegin/CompleteDisplayConfiguration` transaction; on failure
    /// the previous arrangement is restored best-effort.
    func apply(_ plan: LayoutPlan) throws {
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success else {
            throw DisplayConfigurationError.configurationBeginFailed(beginError)
        }

        var failed = false
        var lastError: CGError = .success
        // Configure the future main display first; macOS derives several
        // behaviours from configuration order.
        let ordered = plan.moves.sorted { $0.shouldBeMain && !$1.shouldBeMain }
        for move in ordered {
            let error = CGConfigureDisplayOrigin(
                config,
                move.displayID,
                Int32(move.targetOrigin.x),
                Int32(move.targetOrigin.y)
            )
            if error != .success {
                failed = true
                lastError = error
                AppLogger.configuration.error(
                    "CGConfigureDisplayOrigin failed for '\(move.displayName)': \(error.rawValue)")
                break
            }
        }

        if failed {
            CGCancelDisplayConfiguration(config)
            throw DisplayConfigurationError.configurationApplyFailed(lastError)
        }

        // NOTE: there is no public API to designate the main display; macOS
        // decides it from the arrangement (menu-bar placement). The saved
        // main flag is therefore honoured by keeping that display's position
        // stable (see plan(preset:)) and documented in the README.
        //
        // `permanently` (2) persists like a change made in System Settings.
        let completeError = CGCompleteDisplayConfiguration(config, CGConfigureOption(rawValue: 2))
        guard completeError == .success else {
            AppLogger.configuration.error(
                "CGCompleteDisplayConfiguration failed: \(completeError.rawValue)")
            try? restore(origins: plan.rollbackOrigins)
            throw DisplayConfigurationError.configurationApplyFailed(completeError)
        }

        AppLogger.configuration.info("Applied layout '\(plan.presetName)'.")
    }

    /// Best-effort restore of a previous arrangement (used on apply failure).
    func restore(origins: [CGDirectDisplayID: CGPoint]) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for (id, origin) in origins {
            guard CGDisplayIsOnline(id) != 0 else { continue }
            let error = CGConfigureDisplayOrigin(config, id, Int32(origin.x), Int32(origin.y))
            if error != .success {
                CGCancelDisplayConfiguration(config)
                return
            }
        }
        _ = CGCompleteDisplayConfiguration(config, CGConfigureOption(rawValue: 2))
    }

    /// Snapshot of current origins for pre-switch rollback.
    func snapshotOrigins() -> [CGDirectDisplayID: CGPoint] {
        Dictionary(uniqueKeysWithValues:
            discovery.currentDisplays().map { ($0.displayID, $0.origin.cgPoint) })
    }
}
