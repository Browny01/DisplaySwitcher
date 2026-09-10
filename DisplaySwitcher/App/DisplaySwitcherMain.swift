import Foundation
import SwiftUI

/// Process entry point. Headless CLI commands run first and exit; otherwise
/// the SwiftUI menu-bar app takes over.
@main
enum DisplaySwitcherMain {
    static func main() {
        CLI.handleIfRequested()
        DisplaySwitcherApp.main()
    }
}