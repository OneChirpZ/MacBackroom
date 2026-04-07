import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacBackroom")
                    .font(.headline)
                Text(appModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appModel.shouldShowAccessibilityBanner {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(appModel.accessibilityTitle, systemImage: "figure.wave.circle")
                        .font(.subheadline.weight(.medium))
                    Text(appModel.accessibilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Open Settings") {
                            appModel.openAccessibilitySettings()
                        }

                        Button("Prompt Again") {
                            appModel.requestAccessibilityAgain()
                        }
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Left: \(appModel.leftShortcutDescription)", systemImage: "arrow.left.circle")
                Label("Right: \(appModel.rightShortcutDescription)", systemImage: "arrow.right.circle")
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Prevent edge overshoot", isOn: $appModel.preventEdgeOvershoot)
                    .font(.caption)
                Text("Block extra left/right requests once the predicted remaining spaces on that side are exhausted.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { appModel.launchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    )
                )
                .font(.caption)
                .disabled(!appModel.canChangeLaunchAtLogin)
                Text(appModel.launchAtLoginStatusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Switch Left") {
                    appModel.switchLeft()
                }
                Button("Switch Right") {
                    appModel.switchRight()
                }
            }
            .disabled(!appModel.canSwitchSpaces)

            Button("Refresh Space Snapshot") {
                appModel.refreshSnapshot()
            }
            .disabled(!appModel.canSwitchSpaces)

            if appModel.displays.isEmpty {
                Text("No managed displays detected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(appModel.displays) { display in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Display \(display.shortIdentifier)")
                                .font(.subheadline.weight(.medium))
                            Text(display.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(display.spaceLine)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            appModel.refreshLaunchAtLoginState()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel.preview)
}
