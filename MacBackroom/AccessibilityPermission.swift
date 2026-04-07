import AppKit
import ApplicationServices
import Foundation

enum AccessibilityPermissionState: Equatable {
    case checking
    case waitingForGrant
    case restarting
    case authorized
}

enum AccessibilityPermission {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    static func relaunchCurrentApp() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-na", bundlePath]

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            NSApplication.shared.terminate(nil)
        }
    }
}
