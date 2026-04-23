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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Dock Controls")
                    .font(.subheadline.weight(.medium))

                Toggle("Disable Space switch animation", isOn: $appModel.dockSpaceSwitchAnimationDisabled)
                    .font(.caption)

                dockTimingRow(
                    title: "Autohide delay",
                    value: $appModel.dockAutohideDelay,
                    range: 0...2,
                    step: 0.05
                )

                dockTimingRow(
                    title: "Autohide animation duration",
                    value: $appModel.dockAutohideTimeModifier,
                    range: 0...2,
                    step: 0.05
                )

                HStack(spacing: 10) {
                    Button {
                        appModel.applyDockPreferencesAndRestart()
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle")
                    }

                    Button {
                        appModel.restartDock()
                    } label: {
                        Label("Restart Dock", systemImage: "arrow.clockwise")
                    }

                    Button {
                        appModel.reloadDockPreferences()
                    } label: {
                        Label("Reload", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .controlSize(.small)

                Text(appModel.dockControlsStatusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .frame(width: 440)
        .onAppear {
            appModel.refreshLaunchAtLoginState()
        }
    }

    @ViewBuilder
    private func dockTimingRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                Spacer(minLength: 8)
                Text("\(value.wrappedValue, specifier: "%.2f")s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step)
                Stepper(title, value: value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel.preview)
}
