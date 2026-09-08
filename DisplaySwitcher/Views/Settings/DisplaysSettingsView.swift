import SwiftUI

/// Live view of detected displays. Technical IDs stay in an Advanced
/// disclosure so normal users are not overwhelmed.
struct DisplaysSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Displays")
                    .font(.headline)
                Spacer()
                Button("Refresh") { appState.displayManager.refresh() }
            }

            if appState.displayManager.connectedDisplays.isEmpty {
                ContentUnavailableView(
                    "No displays detected",
                    systemImage: "display.slash",
                    description: Text("Connect a display and press Refresh."))
            } else {
                LayoutPreviewView(displays: appState.displayManager.connectedDisplays)

                ForEach(appState.displayManager.connectedDisplays) { display in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            Text(display.name).font(.headline)
                            if display.isMain {
                                Text("Main")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            if display.isMirrored {
                                Text("Mirrored").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(display.isBuiltIn ? "Built-in" : "External")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(display.friendlyResolution) · \(Int(display.pointSize.width))×\(Int(display.pointSize.height)) pt · \(refreshLabel(display)) · \(Int(display.rotationDegrees))° rotation · \(String(format: "%.0f", display.origin.x)), \(String(format: "%.0f", display.origin.y))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if showAdvanced {
                            Text("Vendor 0x\(String(display.fingerprint.vendorID, radix: 16)) · Product 0x\(String(display.fingerprint.productID, radix: 16)) · Unit \(display.unitNumber) · match key \(display.fingerprint.diagnosticKey)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }

                Toggle("Show technical identifiers", isOn: $showAdvanced)
                    .font(.caption)
            }
            Spacer()
        }
    }

    private func refreshLabel(_ display: DisplayInfo) -> String {
        display.refreshRateHz > 0 ? "\(String(format: "%.0f", display.refreshRateHz)) Hz" : "refresh unknown"
    }
}
