import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [ManagedDisplaySnapshot] = []
    @Published var statusMessage = "Checking Accessibility permission…"
    @Published var accessibilityState: AccessibilityPermissionState = .checking
    @Published var preventEdgeOvershoot: Bool {
        didSet {
            UserDefaults.standard.set(preventEdgeOvershoot, forKey: Self.preventEdgeOvershootDefaultsKey)
        }
    }

    let leftShortcutDescription = HotKeyCenter.Shortcut.switchLeft.displayString
    let rightShortcutDescription = HotKeyCenter.Shortcut.switchRight.displayString

    private static let preventEdgeOvershootDefaultsKey = "preventEdgeOvershoot"

    private var hotKeyCenter: HotKeyCenter?
    private var spaceSwitcher: SpaceSwitcher?
    private var permissionPollTimer: Timer?
    private var servicesConfigured = false

    init() {
        preventEdgeOvershoot = Self.loadPreventEdgeOvershootPreference()
        beginAccessibilityFlow()
    }

    private init(previewMode: Bool) {
        preventEdgeOvershoot = true
        if previewMode {
            accessibilityState = .authorized
            statusMessage = "Preview data"
            servicesConfigured = true
        } else {
            beginAccessibilityFlow()
        }
    }

    deinit {
        permissionPollTimer?.invalidate()
    }

    func switchLeft() {
        switchSpaces(.left)
    }

    func switchRight() {
        switchSpaces(.right)
    }

    func refreshSnapshot() {
        guard let spaceSwitcher else {
            displays = []
            return
        }

        do {
            displays = try spaceSwitcher.snapshotDisplays()
            if displays.isEmpty {
                statusMessage = "No managed displays returned by SkyLight."
            } else {
                statusMessage = "Snapshot refreshed for \(displays.count) display(s)."
            }
        } catch {
            displays = []
            statusMessage = "Snapshot failed: \(error.localizedDescription)"
        }
    }

    func requestAccessibilityAgain() {
        if AccessibilityPermission.isTrusted(prompt: true) {
            accessibilityState = .authorized
            configureServicesIfNeeded()
            return
        }

        accessibilityState = .waitingForGrant
        statusMessage = "Accessibility permission is required. Grant access in System Settings; the app will restart automatically."
        AccessibilityPermission.openSystemSettings()
        startPermissionPolling()
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    var canSwitchSpaces: Bool {
        accessibilityState == .authorized && spaceSwitcher != nil
    }

    var shouldShowAccessibilityBanner: Bool {
        accessibilityState != .authorized
    }

    var accessibilityTitle: String {
        switch accessibilityState {
        case .checking:
            return "Checking Accessibility"
        case .waitingForGrant:
            return "Accessibility Permission Required"
        case .restarting:
            return "Applying Permission"
        case .authorized:
            return "Accessibility Ready"
        }
    }

    var accessibilityMessage: String {
        switch accessibilityState {
        case .checking:
            return "MacBackroom is checking whether it can post the private Space-switch gesture."
        case .waitingForGrant:
            return "System Settings has been prompted. Grant Accessibility for this app; once detected, MacBackroom will relaunch and verify the permission on startup."
        case .restarting:
            return "Accessibility permission was granted. Restarting the app now so the private gesture path comes up with the new entitlement applied."
        case .authorized:
            return "Accessibility permission is active."
        }
    }

    private func switchSpaces(_ direction: SpaceSwitchDirection) {
        guard accessibilityState == .authorized else {
            statusMessage = "Accessibility permission is not active yet."
            requestAccessibilityAgain()
            return
        }

        guard let spaceSwitcher else {
            statusMessage = "Space switcher is unavailable."
            return
        }

        do {
            let result = try spaceSwitcher.switchSpace(direction, preventOvershoot: preventEdgeOvershoot)
            statusMessage = result.message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshSnapshot()
            }
        } catch let error as SpaceSwitcher.Error {
            statusMessage = error.errorDescription ?? "Space switch was blocked."
        } catch {
            statusMessage = "Switch failed: \(error.localizedDescription)"
        }
    }

    private func beginAccessibilityFlow() {
        if AccessibilityPermission.isTrusted(prompt: false) {
            accessibilityState = .authorized
            statusMessage = "Accessibility already granted. Initializing hotkeys…"
            configureServicesIfNeeded()
            return
        }

        accessibilityState = .waitingForGrant
        statusMessage = "Accessibility permission is required. Prompting System Settings now…"
        _ = AccessibilityPermission.isTrusted(prompt: true)
        AccessibilityPermission.openSystemSettings()
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollAccessibilityPermission()
            }
        }
    }

    private func pollAccessibilityPermission() {
        guard accessibilityState == .waitingForGrant else {
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
            return
        }

        guard AccessibilityPermission.isTrusted(prompt: false) else {
            return
        }

        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        accessibilityState = .restarting
        statusMessage = "Accessibility granted. Restarting to apply the permission…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            AccessibilityPermission.relaunchCurrentApp()
        }
    }

    private func configureServicesIfNeeded() {
        guard !servicesConfigured else { return }

        do {
            let switcher = SpaceSwitcher()
            let hotKeys = try HotKeyCenter()

            try hotKeys.register(shortcut: .switchLeft) { [weak self] in
                self?.switchLeft()
            }
            try hotKeys.register(shortcut: .switchRight) { [weak self] in
                self?.switchRight()
            }

            spaceSwitcher = switcher
            hotKeyCenter = hotKeys
            servicesConfigured = true
            statusMessage = "Hotkeys ready."
            refreshSnapshot()
        } catch {
            hotKeyCenter = nil
            spaceSwitcher = nil
            servicesConfigured = false
            statusMessage = "Startup failed: \(error.localizedDescription)"
        }
    }

    private static func loadPreventEdgeOvershootPreference() -> Bool {
        guard UserDefaults.standard.object(forKey: preventEdgeOvershootDefaultsKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: preventEdgeOvershootDefaultsKey)
    }
}

extension AppModel {
    static let preview: AppModel = {
        let model = AppModel(previewMode: true)
        if model.displays.isEmpty {
            model.displays = [
                ManagedDisplaySnapshot(
                    id: "PreviewDisplay",
                    currentSpaceID: 10,
                    spaces: [
                        ManagedSpaceSnapshot(id: 8, type: 0, uuid: nil, isCurrent: false),
                        ManagedSpaceSnapshot(id: 9, type: 0, uuid: nil, isCurrent: false),
                        ManagedSpaceSnapshot(id: 10, type: 0, uuid: nil, isCurrent: true),
                    ]
                )
            ]
            model.statusMessage = "Preview data"
        }
        return model
    }()
}
