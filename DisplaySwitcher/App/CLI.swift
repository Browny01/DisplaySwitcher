import AppKit
import Foundation

/// CLI companion. The app binary doubles as a command-line tool: when it is
/// launched with a recognised command it performs the operation headlessly
/// (no menu-bar icon) and exits, otherwise the normal SwiftUI app runs.
///
///     /Applications/DisplaySwitcher.app/Contents/MacOS/DisplaySwitcher list
///     display-switcher apply "Desk"
///     display-switcher save "Gaming"
///     display-switcher status
///     display-switcher next | previous
enum CLI {
    static let version: String = {
        // Bundle.main resolves by executable name, so it can fail when the
        // CLI is invoked through the `display-switcher` symlink. Fall back to
        // the /Applications bundle in that case.
        if let fromMain = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !fromMain.isEmpty {
            return fromMain
        }
        let appBundle = Bundle(path: "/Applications/\(AppConstants.appName).app")
        return appBundle?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()

    private static let commands: Set<String> = [
        "list", "apply", "save", "status", "next", "previous", "--help", "-h", "--version", "-V",
    ]

    /// Returns true (and exits the process) when the command line requests
    /// headless CLI operation.
    static func handleIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, commands.contains(command) else { return }
        // The whole engine is @MainActor and CLI main runs on the main
        // thread, so executing synchronously here is safe and deadlock-free.
        MainActor.assumeIsolated { run(args) }
        print("unreachable")
    }

    @MainActor
    private static func run(_ args: [String]) -> Never {
        let code: Int32
        do {
            switch args[0] {
            case "list":
                let presets = AutomationEngine.presets()
                if presets.isEmpty {
                    print("No presets saved. Save one first:\n  \(name) save \"My Layout\"")
                } else {
                    print("Presets (\(presets.count)):")
                    for preset in presets {
                        print("• \(preset.name) (\(preset.displayCount) displays)")
                    }
                }
                code = 0
            case "apply":
                guard args.count > 1 else {
                    throw AutomationEngineError.usage("Usage: \(name) apply \"Preset Name\"")
                }
                let presetName = args.dropFirst().joined(separator: " ")
                try AutomationEngine.apply(named: presetName)
                print("Applied \"\(presetName)\".")
                code = 0
            case "save":
                guard args.count > 1 else {
                    throw AutomationEngineError.usage("Usage: \(name) save \"Preset Name\"")
                }
                let presetName = args.dropFirst().joined(separator: " ")
                let preset = try AutomationEngine.save(named: presetName)
                print("Saved \"\(preset.name)\" with \(preset.displayCount) displays.")
                code = 0
            case "status":
                print(AutomationEngine.statusLines())
                code = 0
            case "next":
                try AutomationEngine.cycle(direction: 1)
                print("Switched to next preset.")
                code = 0
            case "previous":
                try AutomationEngine.cycle(direction: -1)
                print("Switched to previous preset.")
                code = 0
            case "--version", "-V":
                print("\(AppConstants.appName) \(version)")
                code = 0
            case "--help", "-h":
                print(helpText)
                code = 0
            default:
                throw AutomationEngineError.usage("Unknown command: \(args[0])")
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            code = 1
        }
        exit(code)
    }

    private static let name: String = {
        let command = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "DisplaySwitcher"
        return command == "DisplaySwitcher" ? "display-switcher" : command
    }()

    private static var helpText: String {
        """
        \(AppConstants.appName) \(version) — manage display presets from the command line

        Usage: \(name) <command> [args]

        Commands:
          list                  List saved presets
          apply "<name>"        Apply a saved preset
          save "<name>"         Save the current layout as a preset
          status                Show connected displays and matching preset
          next                  Switch to the next preset
          previous              Switch to the previous preset
          --version, -V         Show version
          --help, -h            Show this help

        With no arguments the menu-bar app is launched instead.
        """
    }
}