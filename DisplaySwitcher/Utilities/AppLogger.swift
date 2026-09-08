import Foundation
import os

/// Structured local logging. Never logs display serial numbers at info level
/// or above; fingerprint details stay at debug level.
enum AppLogger {
    private static let subsystem = AppConstants.bundleIdentifier

    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let matching = Logger(subsystem: subsystem, category: "matching")
    static let configuration = Logger(subsystem: subsystem, category: "configuration")
    static let presets = Logger(subsystem: subsystem, category: "presets")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
