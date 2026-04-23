import AppKit
import Combine
import SwiftUI

private struct DockPreferences {
    var spaceSwitchAnimationDisabled: Bool
    var autohideDelay: Double
    var autohideTimeModifier: Double
}

private enum DockPreferencesError: LocalizedError {
    case writeFailed(String)
    case commandFailed(command: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let key):
            return "Unable to save Dock preference `\(key)`."
        case .commandFailed(let command, let detail):
            if detail.isEmpty {
                return "`\(command)` failed."
            }

            return "`\(command)` failed: \(detail)"
        }
    }
}

private enum DockPreferencesStore {
    private static let domain = "com.apple.dock" as CFString
    private static let spaceSwitchAnimationDisabledKey = "workspaces-swoosh-animation-off"
    private static let autohideDelayKey = "autohide-delay"
    private static let autohideTimeModifierKey = "autohide-time-modifier"

    static func load() -> DockPreferences {
        DockPreferences(
            spaceSwitchAnimationDisabled: boolValue(forKey: spaceSwitchAnimationDisabledKey, defaultValue: false),
            autohideDelay: doubleValue(forKey: autohideDelayKey, defaultValue: 0),
            autohideTimeModifier: doubleValue(forKey: autohideTimeModifierKey, defaultValue: 0.4)
        )
    }

    static func save(_ preferences: DockPreferences) throws {
        try set(preferences.spaceSwitchAnimationDisabled, forKey: spaceSwitchAnimationDisabledKey)
        try set(preferences.autohideDelay, forKey: autohideDelayKey)
        try set(preferences.autohideTimeModifier, forKey: autohideTimeModifierKey)
    }

    static func restartDock() throws {
        try runCommand(executablePath: "/usr/bin/killall", arguments: ["Dock"])
    }

    private static func boolValue(forKey key: String, defaultValue: Bool) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else {
            return defaultValue
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let string = value as? String {
            let normalizedString = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes"].contains(normalizedString)
        }

        return defaultValue
    }

    private static func doubleValue(forKey key: String, defaultValue: Double) -> Double {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else {
            return defaultValue
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String, let doubleValue = Double(string) {
            return doubleValue
        }

        return defaultValue
    }

    private static func set(_ value: Bool, forKey key: String) throws {
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), domain)
        try synchronize(key: key)
    }

    private static func set(_ value: Double, forKey key: String) throws {
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), domain)
        try synchronize(key: key)
    }

    private static func synchronize(key: String) throws {
        guard CFPreferencesAppSynchronize(domain) else {
            throw DockPreferencesError.writeFailed(key)
        }
    }

    private static func runCommand(executablePath: String, arguments: [String]) throws {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let command = ([executablePath] + arguments).joined(separator: " ")
            throw DockPreferencesError.commandFailed(command: command, detail: detail)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [ManagedDisplaySnapshot] = []
    @Published var statusMessage = "Checking Accessibility permission…"
    @Published var accessibilityState: AccessibilityPermissionState = .checking
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginStatusMessage = ""
    @Published var dockSpaceSwitchAnimationDisabled = false
    @Published var dockAutohideDelay = 0.0
    @Published var dockAutohideTimeModifier = 0.4
    @Published var dockControlsStatusMessage = ""
    @Published var preventEdgeOvershoot: Bool {
        didSet {
            UserDefaults.standard.set(preventEdgeOvershoot, forKey: Self.preventEdgeOvershootDefaultsKey)
        }
    }

    let leftShortcutDescription = HotKeyCenter.Shortcut.switchLeft.displayString
    let rightShortcutDescription = HotKeyCenter.Shortcut.switchRight.displayString

    private static let preventEdgeOvershootDefaultsKey = "preventEdgeOvershoot"

    private let launchAtLoginManager = LaunchAtLoginManager()
    private var hotKeyCenter: HotKeyCenter?
    private var spaceSwitcher: SpaceSwitcher?
    private var permissionPollTimer: Timer?
    private var workspaceObservers: Set<AnyCancellable> = []
    private var servicesConfigured = false
    private var awaitingWakeRecoveryVerification = false
    private var pendingWakeVerification: SpaceSwitchResult?
    private var hasTriggeredWakeRecovery = false

    init() {
        preventEdgeOvershoot = Self.loadPreventEdgeOvershootPreference()
        loadDockPreferences()
        refreshLaunchAtLoginState()
        configureWorkspaceObservers()
        beginAccessibilityFlow()
    }

    private init(previewMode: Bool) {
        preventEdgeOvershoot = true
        dockSpaceSwitchAnimationDisabled = true
        dockAutohideDelay = 0
        dockAutohideTimeModifier = 0.4
        dockControlsStatusMessage = "Preview Dock controls"
        launchAtLoginStatusMessage = "Preview data"
        if previewMode {
            accessibilityState = .authorized
            statusMessage = "Preview data"
            servicesConfigured = true
        } else {
            refreshLaunchAtLoginState()
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
        refreshSnapshot(announceStatus: true)
    }

    func reloadDockPreferences() {
        loadDockPreferences()
        dockControlsStatusMessage = "Dock preferences reloaded."
    }

    func applyDockPreferencesAndRestart() {
        let preferences = DockPreferences(
            spaceSwitchAnimationDisabled: dockSpaceSwitchAnimationDisabled,
            autohideDelay: dockAutohideDelay,
            autohideTimeModifier: dockAutohideTimeModifier
        )

        do {
            try DockPreferencesStore.save(preferences)
            try DockPreferencesStore.restartDock()
            dockControlsStatusMessage = "Dock preferences applied and Dock restarted."
        } catch {
            dockControlsStatusMessage = "Dock update failed: \(error.localizedDescription)"
        }
    }

    func restartDock() {
        do {
            try DockPreferencesStore.restartDock()
            dockControlsStatusMessage = "Dock restarted."
        } catch {
            dockControlsStatusMessage = "Dock restart failed: \(error.localizedDescription)"
        }
    }

    private func refreshSnapshot(announceStatus: Bool) {
        guard let spaceSwitcher else {
            displays = []
            return
        }

        do {
            displays = try spaceSwitcher.snapshotDisplays()
            if !announceStatus {
                return
            }

            if displays.isEmpty {
                statusMessage = "No managed displays returned by SkyLight."
            } else {
                statusMessage = "Snapshot refreshed for \(displays.count) display(s)."
            }
        } catch {
            displays = []
            if announceStatus {
                statusMessage = "Snapshot failed: \(error.localizedDescription)"
            }
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

    func refreshLaunchAtLoginState() {
        applyLaunchAtLoginState(launchAtLoginManager.currentState())
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        guard !isEnabled || LaunchAtLoginManager.isInstalledInApplicationsFolder else {
            applyLaunchAtLoginState(launchAtLoginManager.currentState())
            statusMessage = "Install MacBackroom in Applications before enabling launch at login."
            return
        }

        do {
            applyLaunchAtLoginState(try launchAtLoginManager.setEnabled(isEnabled))
            statusMessage = isEnabled ? "Launch at login enabled." : "Launch at login disabled."
        } catch {
            applyLaunchAtLoginState(launchAtLoginManager.currentState())
            statusMessage = "Launch at login update failed: \(error.localizedDescription)"
        }
    }

    var canSwitchSpaces: Bool {
        accessibilityState == .authorized && spaceSwitcher != nil
    }

    var canChangeLaunchAtLogin: Bool {
        LaunchAtLoginManager.isInstalledInApplicationsFolder || launchAtLoginEnabled
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
            pendingWakeVerification = result.targetSpaceID == nil ? nil : result
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshSnapshot()
                self?.verifyWakeRecoveryIfNeeded(expectedResult: result)
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

    private func loadDockPreferences() {
        let preferences = DockPreferencesStore.load()
        dockSpaceSwitchAnimationDisabled = preferences.spaceSwitchAnimationDisabled
        dockAutohideDelay = preferences.autohideDelay
        dockAutohideTimeModifier = preferences.autohideTimeModifier
        dockControlsStatusMessage = "Dock preferences loaded."
    }

    private func applyLaunchAtLoginState(_ state: LaunchAtLoginState) {
        launchAtLoginEnabled = state.isEnabled
        launchAtLoginStatusMessage = state.detailMessage
    }

    private func configureWorkspaceObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWillSleep()
                }
            }
            .store(in: &workspaceObservers)

        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleDidWake()
                }
            }
            .store(in: &workspaceObservers)

        workspaceCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleActiveSpaceDidChange()
                }
            }
            .store(in: &workspaceObservers)
    }

    private func handleWillSleep() {
        pendingWakeVerification = nil
        awaitingWakeRecoveryVerification = false
        hasTriggeredWakeRecovery = false
        spaceSwitcher?.prepareForSleep()
    }

    private func handleDidWake() {
        awaitingWakeRecoveryVerification = true
        pendingWakeVerification = nil
        hasTriggeredWakeRecovery = false

        guard AccessibilityPermission.isTrusted(prompt: false) else {
            accessibilityState = .waitingForGrant
            statusMessage = "Accessibility needs to be rechecked after wake."
            startPermissionPolling()
            return
        }

        accessibilityState = .authorized
        rebuildServicesAfterWake()
    }

    private func handleActiveSpaceDidChange() {
        guard let spaceSwitcher else {
            return
        }

        // System-driven Space jumps invalidate our local edge prediction immediately.
        spaceSwitcher.invalidatePredictedSpaceState()
        refreshSnapshot(announceStatus: false)
    }

    private func rebuildServicesAfterWake() {
        spaceSwitcher?.prepareForSleep()
        hotKeyCenter = nil
        spaceSwitcher = nil
        servicesConfigured = false
        statusMessage = "Mac woke from sleep. Reinitializing hotkeys and gesture driver…"
        configureServicesIfNeeded()
    }

    private func verifyWakeRecoveryIfNeeded(expectedResult: SpaceSwitchResult) {
        guard pendingWakeVerification?.targetSpaceID == expectedResult.targetSpaceID,
              pendingWakeVerification?.displayID == expectedResult.displayID else {
            return
        }

        defer { pendingWakeVerification = nil }

        guard awaitingWakeRecoveryVerification else {
            return
        }

        guard let targetSpaceID = expectedResult.targetSpaceID else {
            return
        }

        let currentSpaceID = try? spaceSwitcher?.currentSpaceID(on: expectedResult.displayID)
        guard currentSpaceID != targetSpaceID else {
            awaitingWakeRecoveryVerification = false
            hasTriggeredWakeRecovery = false
            return
        }

        guard !hasTriggeredWakeRecovery else {
            statusMessage = "Swipe was posted after wake, but the current Space still did not change."
            return
        }

        hasTriggeredWakeRecovery = true
        statusMessage = "Space switching did not recover after wake. Relaunching MacBackroom to rebuild the gesture path…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AccessibilityPermission.relaunchCurrentApp()
        }
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
