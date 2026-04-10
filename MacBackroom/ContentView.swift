import SwiftUI
import Carbon.HIToolbox

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var recordingAction: AppShortcutAction?
    @State private var localKeyMonitor: Any?

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
                Text("Global Shortcuts")
                    .font(.subheadline.weight(.medium))

                ForEach(AppShortcutAction.allCases) { action in
                    shortcutRow(for: action)
                }

                if let recordingAction {
                    Text("Recording \(recordingAction.title). Press Esc to cancel.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
        .frame(width: 440)
        .onAppear {
            installKeyMonitorIfNeeded()
            appModel.refreshLaunchAtLoginState()
        }
        .onDisappear {
            cancelRecordingIfNeeded()
            removeKeyMonitor()
        }
    }

    @ViewBuilder
    private func shortcutRow(for action: AppShortcutAction) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(action.title, systemImage: action.systemImage)
                    .font(.caption.weight(.medium))
                Text(appModel.shortcutPreview(for: action))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(recordingAction == action ? "Press Shortcut" : appModel.shortcut(for: action).displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(recordingAction == action ? "Cancel" : "Edit") {
                toggleRecording(for: action)
            }
            .controlSize(.small)

            Button("Reset") {
                resetShortcut(for: action)
            }
            .controlSize(.small)
        }
    }

    private func toggleRecording(for action: AppShortcutAction) {
        if recordingAction == action {
            recordingAction = nil
            appModel.cancelShortcutRecording()
            return
        }

        recordingAction = action
        appModel.beginShortcutRecording(for: action)
    }

    private func resetShortcut(for action: AppShortcutAction) {
        recordingAction = nil
        _ = appModel.resetShortcut(for: action)
    }

    private func cancelRecordingIfNeeded() {
        guard recordingAction != nil else {
            return
        }

        recordingAction = nil
        appModel.cancelShortcutRecording()
    }

    private func installKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else {
            return
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecorderKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        guard let localKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }

    private func handleRecorderKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let action = recordingAction else {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape) {
            recordingAction = nil
            appModel.cancelShortcutRecording()
            return nil
        }

        if event.isARepeat || HotKeyCenter.Shortcut.isModifierOnlyKeyCode(UInt32(event.keyCode)) {
            return nil
        }

        guard let shortcut = HotKeyCenter.Shortcut(event: event) else {
            NSSound.beep()
            return nil
        }

        if appModel.updateShortcut(shortcut, for: action) {
            recordingAction = nil
        } else {
            NSSound.beep()
        }

        return nil
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel.preview)
}
