import Foundation

/// Result of matching one saved preset entry against connected displays.
struct DisplayMatch: Hashable, Sendable {
    var presetEntry: PresetDisplayEntry
    var display: DisplayInfo
    /// 0...1 confidence score.
    var score: Double
}

/// Matches saved preset entries to currently connected displays.
///
/// Never relies on `CGDirectDisplayID` (unstable across sessions). Scores
/// each candidate pair from stable metadata and solves the assignment
/// greedily from best score downwards so every physical display is used at
/// most once. Ambiguous pairs below the confidence threshold are left
/// unmatched so the caller degrades gracefully instead of applying a
/// potentially wrong layout.
enum DisplayMatcher {
    /// Minimum score for a match to be accepted.
    static let acceptanceThreshold = 0.55

    static func match(preset: DisplayPreset,
                      against connected: [DisplayInfo]) -> [DisplayMatch] {
        var remaining = connected
        var matches: [DisplayMatch] = []

        let ordered = preset.displays.sorted { a, b in
            // Match the most distinctive entries first: non-built-in with a
            // serial number, then non-built-in, then built-in.
            specificity(of: a.fingerprint) > specificity(of: b.fingerprint)
        }

        for entry in ordered {
            var bestIndex: Int?
            var bestScore = 0.0
            for (index, display) in remaining.enumerated() {
                let score = score(preset: entry, candidate: display)
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }
            if let bestIndex, bestScore >= acceptanceThreshold {
                let display = remaining.remove(at: bestIndex)
                matches.append(DisplayMatch(presetEntry: entry, display: display, score: bestScore))
                AppLogger.matching.debug(
                    "Matched '\(entry.capturedName)' (score: \(String(format: "%.2f", bestScore))).")
            } else {
                AppLogger.matching.info(
                    "No confident match for saved display '\(entry.capturedName)'.")
            }
        }
        return matches
    }

    /// True when every saved display matched exactly one connected display.
    static func isCompleteMatch(_ matches: [DisplayMatch], preset: DisplayPreset) -> Bool {
        matches.count == preset.displays.count
    }

    /// Fingerprint-set signature of the connected displays, used to recognise
    /// the current setup and to detect reconnects.
    static func setupSignature(of displays: [DisplayInfo]) -> String {
        displays.map { $0.fingerprint.diagnosticKey }.sorted().joined(separator: "|")
    }

    // MARK: - Scoring

    private static func specificity(of fingerprint: DisplayFingerprint) -> Int {
        var value = 0
        if !fingerprint.isBuiltIn { value += 2 }
        if fingerprint.serialNumber != 0 { value += 2 }
        if !fingerprint.normalizedName.isEmpty { value += 1 }
        return value
    }

    /// Weighted similarity in 0...1. Weights favour identifiers that survive
    /// renames and re-plugs; the user-visible name is only a tiebreaker.
    static func score(preset entry: PresetDisplayEntry, candidate: DisplayInfo) -> Double {
        let a = entry.fingerprint
        let b = candidate.fingerprint
        var total = 0.0
        var weight = 0.0

        func add(_ w: Double, _ condition: Bool) {
            weight += w
            if condition { total += w }
        }

        // Built-in status is the strongest single signal.
        add(3.0, a.isBuiltIn == b.isBuiltIn)
        if a.isBuiltIn != b.isBuiltIn { return 0.0 }

        add(2.0, a.vendorID == b.vendorID)
        add(2.0, a.productID == b.productID)
        // Serial numbers are often 0; only reward non-zero agreement.
        if a.serialNumber != 0 || b.serialNumber != 0 {
            add(2.0, a.serialNumber != 0 && a.serialNumber == b.serialNumber)
        }
        // Physical size distinguishes same-model displays of different sizes.
        add(1.0, a.sizeMillimeters == b.sizeMillimeters)
        // Name is cosmetic: small bonus only.
        add(0.5, !a.normalizedName.isEmpty && a.normalizedName == b.normalizedName)

        guard weight > 0 else { return 0 }
        return total / weight
    }
}
