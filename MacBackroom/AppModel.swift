import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

enum AppShortcutAction: String, CaseIterable, Hashable, Identifiable {
    case switchLeft
    case switchRight
    case pasteTicketDate
    case pasteCompactDate

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .switchLeft:
            return "Switch Left"
        case .switchRight:
            return "Switch Right"
        case .pasteTicketDate:
            return "Paste 0410-🚧-"
        case .pasteCompactDate:
            return "Paste 260410"
        }
    }

    var systemImage: String {
        switch self {
        case .switchLeft:
            return "arrow.left.circle"
        case .switchRight:
            return "arrow.right.circle"
        case .pasteTicketDate:
            return "text.insert"
        case .pasteCompactDate:
            return "calendar"
        }
    }

    var detailText: String {
        switch self {
        case .switchLeft:
            return "Trigger a one-step switch to the previous Space."
        case .switchRight:
            return "Trigger a one-step switch to the next Space."
        case .pasteTicketDate:
            return "Pastes today's date as `MMdd-🚧-`."
        case .pasteCompactDate:
            return "Pastes today's date as `yyMMdd`."
        }
    }

    var defaultShortcut: HotKeyCenter.Shortcut {
        switch self {
        case .switchLeft:
            return .switchLeft
        case .switchRight:
            return .switchRight
        case .pasteTicketDate:
            return .pasteTicketDate
        case .pasteCompactDate:
            return .pasteCompactDate
        }
    }

    var defaultsKey: String {
        "shortcut.\(rawValue)"
    }
}

private enum PasteError: LocalizedError {
    case writeToPasteboardFailed
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .writeToPasteboardFailed:
            return "Unable to write the generated text to the pasteboard."
        case .eventCreationFailed:
            return "Unable to synthesize the paste keyboard event."
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
    @Published var preventEdgeOvershoot: Bool {
        didSet {
            UserDefaults.standard.set(preventEdgeOvershoot, forKey: Self.preventEdgeOvershootDefaultsKey)
        }
    }
    @Published private var shortcutBindings: [AppShortcutAction: HotKeyCenter.Shortcut]

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
    private var pendingPasteActionToken: UUID?
    private var preservedPasteboardString: String?
    private var shouldRestorePasteboardString = false
    private var pendingPasteRestoreToken: UUID?
    private var injectedPasteboardChangeCount: Int?

    init() {
        preventEdgeOvershoot = Self.loadPreventEdgeOvershootPreference()
        shortcutBindings = Self.loadShortcutBindings()
        refreshLaunchAtLoginState()
        configureWorkspaceObservers()
        beginAccessibilityFlow()
    }

    private init(previewMode: Bool) {
        preventEdgeOvershoot = true
        shortcutBindings = Dictionary(uniqueKeysWithValues: AppShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
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

    func shortcut(for action: AppShortcutAction) -> HotKeyCenter.Shortcut {
        shortcutBindings[action] ?? action.defaultShortcut
    }

    func shortcutPreview(for action: AppShortcutAction) -> String {
        switch action {
        case .pasteTicketDate:
            return Self.ticketDateString(from: Date())
        case .pasteCompactDate:
            return Self.compactDateString(from: Date())
        case .switchLeft, .switchRight:
            return action.detailText
        }
    }

    func beginShortcutRecording(for action: AppShortcutAction) {
        suspendHotKeys()
        statusMessage = "Recording \(action.title). Press a key combination, or Esc to cancel."
    }

    func cancelShortcutRecording() {
        resumeHotKeys()
        statusMessage = "Shortcut recording cancelled."
    }

    @discardableResult
    func updateShortcut(_ proposedShortcut: HotKeyCenter.Shortcut, for action: AppShortcutAction) -> Bool {
        let newShortcut = HotKeyCenter.Shortcut(
            keyCode: proposedShortcut.keyCode,
            modifiers: proposedShortcut.modifiers,
            keyDisplay: proposedShortcut.keyDisplay
        )

        guard !newShortcut.modifiers.isEmpty else {
            statusMessage = "Shortcut must include at least one modifier key."
            return false
        }

        if let conflict = AppShortcutAction.allCases.first(where: {
            $0 != action && shortcut(for: $0).hasSameTrigger(as: newShortcut)
        }) {
            statusMessage = "\(newShortcut.displayString) is already used by \(conflict.title)."
            return false
        }

        let previousBindings = shortcutBindings
        var candidateBindings = shortcutBindings
        candidateBindings[action] = newShortcut

        do {
            try applyHotKeys(candidateBindings)
        } catch {
            try? applyHotKeys(previousBindings)
            statusMessage = "Shortcut update failed: \(error.localizedDescription)"
            return false
        }

        shortcutBindings = candidateBindings
        persistShortcut(newShortcut, for: action)
        statusMessage = "Shortcut updated: \(action.title) → \(newShortcut.displayString)"
        return true
    }

    @discardableResult
    func resetShortcut(for action: AppShortcutAction) -> Bool {
        updateShortcut(action.defaultShortcut, for: action)
    }

    func refreshSnapshot() {
        refreshSnapshot(announceStatus: true)
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

            spaceSwitcher = switcher
            hotKeyCenter = hotKeys
            try applyHotKeys(shortcutBindings)
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

    private func applyHotKeys(_ bindings: [AppShortcutAction: HotKeyCenter.Shortcut]) throws {
        guard let hotKeyCenter else {
            return
        }

        let registrations = AppShortcutAction.allCases.map { action in
            return HotKeyCenter.Registration(shortcut: bindings[action] ?? action.defaultShortcut) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleShortcutAction(action)
                }
            }
        }

        try hotKeyCenter.replaceAll(with: registrations)
    }

    private func suspendHotKeys() {
        hotKeyCenter?.unregisterAll()
    }

    private func resumeHotKeys() {
        do {
            try applyHotKeys(shortcutBindings)
        } catch {
            statusMessage = "Failed to restore hotkeys: \(error.localizedDescription)"
        }
    }

    private func handleShortcutAction(_ action: AppShortcutAction) {
        switch action {
        case .switchLeft:
            switchLeft()
        case .switchRight:
            switchRight()
        case .pasteTicketDate:
            pasteDateString(Self.ticketDateString(from: Date()))
        case .pasteCompactDate:
            pasteDateString(Self.compactDateString(from: Date()))
        }
    }

    private func pasteDateString(_ value: String) {
        let token = UUID()
        pendingPasteActionToken = token
        waitForModifierReleaseAndPaste(value, token: token, remainingAttempts: 40)
    }

    private func pasteTextAtCurrentCursor(_ value: String) throws {
        let pasteboard = NSPasteboard.general
        preservePasteboardStringIfNeeded(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            clearPendingPasteboardRestore()
            throw PasteError.writeToPasteboardFailed
        }

        let restoreToken = UUID()
        pendingPasteRestoreToken = restoreToken
        injectedPasteboardChangeCount = pasteboard.changeCount

        do {
            try postPasteCommand()
        } catch {
            restorePasteboardSnapshotIfPossible()
            throw error
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            Task { @MainActor [weak self] in
                self?.restorePasteboardIfNeeded(token: restoreToken)
            }
        }
    }

    private func preservePasteboardStringIfNeeded(_ pasteboard: NSPasteboard) {
        if pendingPasteRestoreToken != nil, pasteboard.changeCount != injectedPasteboardChangeCount {
            clearPendingPasteboardRestore()
        }

        guard pendingPasteRestoreToken == nil else {
            return
        }

        shouldRestorePasteboardString = pasteboard.types?.contains(.string) == true
        preservedPasteboardString = shouldRestorePasteboardString ? pasteboard.string(forType: .string) : nil
    }

    private func restorePasteboardIfNeeded(token: UUID) {
        guard pendingPasteRestoreToken == token else {
            return
        }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == injectedPasteboardChangeCount else {
            clearPendingPasteboardRestore()
            return
        }

        restorePasteboardSnapshotIfPossible()
    }

    private func restorePasteboardSnapshotIfPossible() {
        guard shouldRestorePasteboardString else {
            clearPendingPasteboardRestore()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let preservedPasteboardString {
            _ = pasteboard.setString(preservedPasteboardString, forType: .string)
        }

        clearPendingPasteboardRestore()
    }

    private func clearPendingPasteboardRestore() {
        preservedPasteboardString = nil
        shouldRestorePasteboardString = false
        pendingPasteRestoreToken = nil
        injectedPasteboardChangeCount = nil
    }

    private func postPasteCommand() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw PasteError.eventCreationFailed
        }

        guard
            let commandDownEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
            ),
            let keyDownEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let keyUpEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            ),
            let commandUpEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
            )
        else {
            throw PasteError.eventCreationFailed
        }

        commandDownEvent.post(tap: .cghidEventTap)
        usleep(20_000)
        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
        usleep(20_000)
        commandUpEvent.post(tap: .cghidEventTap)
    }

    private func waitForModifierReleaseAndPaste(_ value: String, token: UUID, remainingAttempts: Int) {
        guard pendingPasteActionToken == token else {
            return
        }

        if recordableModifiersAreReleased() || remainingAttempts <= 0 {
            pendingPasteActionToken = nil

            do {
                try pasteTextAtCurrentCursor(value)
                statusMessage = "Pasted \(value)"
            } catch {
                statusMessage = "Paste failed: \(error.localizedDescription)"
            }

            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            Task { @MainActor [weak self] in
                self?.waitForModifierReleaseAndPaste(value, token: token, remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    private func recordableModifiersAreReleased() -> Bool {
        let modifierKeyCodes: [CGKeyCode] = [
            CGKeyCode(kVK_Command),
            CGKeyCode(kVK_RightCommand),
            CGKeyCode(kVK_Control),
            CGKeyCode(kVK_RightControl),
            CGKeyCode(kVK_Option),
            CGKeyCode(kVK_RightOption),
            CGKeyCode(kVK_Shift),
            CGKeyCode(kVK_RightShift)
        ]

        return modifierKeyCodes.allSatisfy { keyCode in
            !CGEventSource.keyState(.combinedSessionState, key: keyCode)
        }
    }

    private func persistShortcut(_ shortcut: HotKeyCenter.Shortcut, for action: AppShortcutAction) {
        let defaults = UserDefaults.standard

        if shortcut.hasSameTrigger(as: action.defaultShortcut), shortcut.keyDisplay == action.defaultShortcut.keyDisplay {
            defaults.removeObject(forKey: action.defaultsKey)
            return
        }

        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }

        defaults.set(data, forKey: action.defaultsKey)
    }

    private static func loadShortcutBindings() -> [AppShortcutAction: HotKeyCenter.Shortcut] {
        Dictionary(uniqueKeysWithValues: AppShortcutAction.allCases.map { action in
            (action, loadShortcut(for: action))
        })
    }

    private static func loadShortcut(for action: AppShortcutAction) -> HotKeyCenter.Shortcut {
        guard
            let data = UserDefaults.standard.data(forKey: action.defaultsKey),
            let shortcut = try? JSONDecoder().decode(HotKeyCenter.Shortcut.self, from: data)
        else {
            return action.defaultShortcut
        }

        return shortcut
    }

    private static func ticketDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMdd"
        return "\(formatter.string(from: date))-🚧-"
    }

    private static func compactDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
    }

    private static func loadPreventEdgeOvershootPreference() -> Bool {
        guard UserDefaults.standard.object(forKey: preventEdgeOvershootDefaultsKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: preventEdgeOvershootDefaultsKey)
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
