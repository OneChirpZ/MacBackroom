import AppKit
import CoreVideo
import Foundation

typealias SLSConnectionID = UInt32
typealias SLSManagedSpaceID = UInt64

enum SpaceSwitchDirection {
    case left
    case right

    var indexDelta: Int {
        switch self {
        case .left:
            return -1
        case .right:
            return 1
        }
    }

    var label: String {
        switch self {
        case .left:
            return "left"
        case .right:
            return "right"
        }
    }

    var swipeSign: Double {
        switch self {
        case .left:
            return 1.0
        case .right:
            return -1.0
        }
    }

    var gestureDirection: SpaceSwitchDirection {
        switch self {
        case .left:
            return .right
        case .right:
            return .left
        }
    }
}

struct ManagedSpaceSnapshot: Identifiable {
    let id: SLSManagedSpaceID
    let type: Int
    let uuid: String?
    let isCurrent: Bool

    var badge: String {
        isCurrent ? "[\(id)]" : "\(id)"
    }
}

struct ManagedDisplaySnapshot: Identifiable {
    let id: String
    let currentSpaceID: SLSManagedSpaceID
    let spaces: [ManagedSpaceSnapshot]

    var shortIdentifier: String {
        String(id.prefix(8))
    }

    var summary: String {
        "Current \(currentSpaceID), \(spaces.count) switchable spaces"
    }

    var spaceLine: String {
        spaces.map(\.badge).joined(separator: "  ")
    }
}

private struct ManagedDisplaySwitchContext {
    let id: String
    let currentSpaceID: SLSManagedSpaceID
    let rawSpaceIDs: [SLSManagedSpaceID]
}

private struct ManagedDisplaySwitchResolution {
    let displayID: String?
    let currentSpaceID: SLSManagedSpaceID?
    let rawSpaceIDs: [SLSManagedSpaceID]
    let spaceCount: Int
    let currentIndex: Int
}

private struct OvershootGuardState {
    let displayID: String?
    let rawSpaceIDs: [SLSManagedSpaceID]
    var lastObservedActualIndex: Int
    var pendingDelta: Int

    func matches(_ resolution: ManagedDisplaySwitchResolution) -> Bool {
        displayID == resolution.displayID && rawSpaceIDs == resolution.rawSpaceIDs
    }

    func effectiveCurrentIndex(spaceCount: Int) -> Int {
        guard spaceCount > 0 else {
            return 0
        }

        return min(max(lastObservedActualIndex + pendingDelta, 0), spaceCount - 1)
    }
}

struct SpaceSwitchResult {
    let message: String
    let displayID: String?
    let targetSpaceID: SLSManagedSpaceID?
}

final class SpaceSwitcher {
    enum Error: LocalizedError {
        case noManagedDisplays
        case currentDisplayUnavailable
        case currentSpaceNotFound
        case boundaryReached
        case overshootPrevented(direction: SpaceSwitchDirection, remainingLeft: Int, remainingRight: Int)

        var errorDescription: String? {
            switch self {
            case .noManagedDisplays:
                return "SkyLight did not return any managed displays."
            case .currentDisplayUnavailable:
                return "Could not resolve the managed display under the cursor."
            case .currentSpaceNotFound:
                return "The current Space was not found in the managed display snapshot."
            case .boundaryReached:
                return "Already at the display edge; there is no adjacent Space in that direction."
            case let .overshootPrevented(direction, remainingLeft, remainingRight):
                return "Blocked extra \(direction.label) switch. Predicted remaining spaces: left \(remainingLeft), right \(remainingRight)."
            }
        }
    }

    private let skyLight = try! SkyLightBridge()
    private var overshootGuardState: OvershootGuardState?

    func snapshotDisplays() throws -> [ManagedDisplaySnapshot] {
        try skyLight.copyManagedDisplaySnapshots()
    }

    func switchSpace(_ direction: SpaceSwitchDirection, preventOvershoot: Bool) throws -> SpaceSwitchResult {
        let resolution = try skyLight.resolveCurrentDisplaySwitchResolution()
        guard resolution.spaceCount > 0 else {
            throw Error.noManagedDisplays
        }

        let effectiveCurrentIndex: Int
        if preventOvershoot {
            effectiveCurrentIndex = synchronizeOvershootGuard(with: resolution)
        } else {
            overshootGuardState = nil
            effectiveCurrentIndex = resolution.currentIndex
        }

        let targetIndex = effectiveCurrentIndex + direction.indexDelta
        guard targetIndex >= 0, targetIndex < resolution.spaceCount else {
            if preventOvershoot {
                throw Error.overshootPrevented(
                    direction: direction,
                    remainingLeft: effectiveCurrentIndex,
                    remainingRight: max(resolution.spaceCount - effectiveCurrentIndex - 1, 0)
                )
            }
            throw Error.boundaryReached
        }

        if preventOvershoot {
            reserveOvershootGuard(direction: direction, for: resolution)
        }

        do {
            try skyLight.enqueueSwipeGesture(direction.gestureDirection, spaceCount: resolution.spaceCount)
        } catch {
            if preventOvershoot {
                rollbackOvershootGuard(direction: direction, for: resolution)
            }
            throw error
        }

        let displayLabel = resolution.displayID.map { String($0.prefix(8)) } ?? "Main"
        let transition: String
        if
            resolution.rawSpaceIDs.indices.contains(effectiveCurrentIndex),
            resolution.rawSpaceIDs.indices.contains(targetIndex)
        {
            transition = "\(resolution.rawSpaceIDs[effectiveCurrentIndex]) -> \(resolution.rawSpaceIDs[targetIndex])"
        } else {
            transition = "index \(effectiveCurrentIndex) -> \(targetIndex)"
        }

        let targetSpaceID = resolution.rawSpaceIDs.indices.contains(targetIndex) ? resolution.rawSpaceIDs[targetIndex] : nil

        return SpaceSwitchResult(
            message: "Posted HID swipe for \(displayLabel): \(transition).",
            displayID: resolution.displayID,
            targetSpaceID: targetSpaceID
        )
    }

    func currentSpaceID(on displayID: String?) throws -> SLSManagedSpaceID? {
        let contexts = try skyLight.copyManagedDisplaySwitchContexts()
        if let displayID {
            return contexts.first(where: { $0.id == displayID })?.currentSpaceID
        }

        return contexts.first(where: { $0.id == "Main" })?.currentSpaceID ?? contexts.first?.currentSpaceID
    }

    func invalidatePredictedSpaceState() {
        overshootGuardState = nil
    }

    func prepareForSleep() {
        overshootGuardState = nil
        skyLight.resetGestureDriver()
    }

    private func synchronizeOvershootGuard(with resolution: ManagedDisplaySwitchResolution) -> Int {
        if var state = overshootGuardState, state.matches(resolution) {
            let actualMovement = resolution.currentIndex - state.lastObservedActualIndex
            if actualMovement != 0 {
                if state.pendingDelta != 0,
                   actualMovement.signum() == state.pendingDelta.signum(),
                   abs(actualMovement) <= abs(state.pendingDelta)
                {
                    state.pendingDelta -= actualMovement
                } else {
                    state.pendingDelta = 0
                }
            }

            state.lastObservedActualIndex = resolution.currentIndex
            overshootGuardState = state
        } else {
            overshootGuardState = OvershootGuardState(
                displayID: resolution.displayID,
                rawSpaceIDs: resolution.rawSpaceIDs,
                lastObservedActualIndex: resolution.currentIndex,
                pendingDelta: 0
            )
        }

        return overshootGuardState?.effectiveCurrentIndex(spaceCount: resolution.spaceCount) ?? resolution.currentIndex
    }

    private func reserveOvershootGuard(direction: SpaceSwitchDirection, for resolution: ManagedDisplaySwitchResolution) {
        guard var state = overshootGuardState, state.matches(resolution) else {
            return
        }

        state.pendingDelta += direction.indexDelta
        state.pendingDelta = clampPendingDelta(state.pendingDelta, for: resolution)
        overshootGuardState = state
    }

    private func rollbackOvershootGuard(direction: SpaceSwitchDirection, for resolution: ManagedDisplaySwitchResolution) {
        guard var state = overshootGuardState, state.matches(resolution) else {
            return
        }

        state.pendingDelta -= direction.indexDelta
        state.pendingDelta = clampPendingDelta(state.pendingDelta, for: resolution)
        overshootGuardState = state
    }

    private func clampPendingDelta(_ pendingDelta: Int, for resolution: ManagedDisplaySwitchResolution) -> Int {
        let maxLeftDelta = -resolution.currentIndex
        let maxRightDelta = max(resolution.spaceCount - resolution.currentIndex - 1, 0)
        return min(max(pendingDelta, maxLeftDelta), maxRightDelta)
    }
}

private final class SkyLightBridge {
    enum Error: LocalizedError {
        case failedToOpenFramework
        case missingSymbol(String)
        case badManagedDisplayPayload
        case displayLinkUnavailable
        case gestureBusy
        case eventConstructionFailed(Int64)

        var errorDescription: String? {
            switch self {
            case .failedToOpenFramework:
                return "Could not open SkyLight."
            case let .missingSymbol(symbol):
                return "SkyLight symbol \(symbol) is missing."
            case .badManagedDisplayPayload:
                return "SkyLight returned an unexpected managed display payload."
            case .displayLinkUnavailable:
                return "Could not create a display link for the synthetic swipe driver."
            case .gestureBusy:
                return "A swipe gesture is already being posted."
            case let .eventConstructionFailed(phase):
                return "Could not construct private swipe event for phase 0x\(String(phase, radix: 16))."
            }
        }
    }

    private typealias MainConnectionIDFn = @convention(c) () -> SLSConnectionID
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (SLSConnectionID) -> Unmanaged<CFArray>?
    private typealias CopyBestManagedDisplayForPointFn = @convention(c) (SLSConnectionID, CGPoint) -> Unmanaged<CFString>?
    private typealias GetCurrentCursorLocationFn = @convention(c) (SLSConnectionID, UnsafeMutablePointer<CGPoint>) -> Void

    private enum SwipeEvent {
        static let preludeType = unsafeBitCast(UInt32(0x1D), to: CGEventType.self)
        static let type = unsafeBitCast(UInt32(0x1E), to: CGEventType.self)
        static let subtypeField = unsafeBitCast(UInt32(0x6E), to: CGEventField.self)
        static let gestureField = unsafeBitCast(UInt32(0x7B), to: CGEventField.self)
        static let progressField = unsafeBitCast(UInt32(0x7C), to: CGEventField.self)
        static let preludeValueField = unsafeBitCast(UInt32(0x71), to: CGEventField.self)
        static let velocityField = unsafeBitCast(UInt32(0x81), to: CGEventField.self)
        static let phaseField = unsafeBitCast(UInt32(0x84), to: CGEventField.self)

        static let preludeSubtype: Int64 = 0x08
        static let preludePhase: Int64 = 0x04
        static let swipeSubtype: Int64 = 0x17
        static let swipeGestureKind: Int64 = 1
        static let beginPhase: Int64 = 0x1
        static let changePhase: Int64 = 0x2
        static let endPhase: Int64 = 0x4
        static let cancelPhase: Int64 = 0x8
        static let mayBeginPhase: Int64 = 0x80
        static let endVelocityDivisor = 10_000.0
    }

    private struct GestureState {
        let direction: SpaceSwitchDirection
        let gestureKind: Int64
        let targetProgress: Double
        let signedLimit: Double
        var normalizedProgress: Double
        var baseStep: Double
        var velocityScale: Double
        var changeGateArmed: Bool
    }

    private enum GestureTuning {
        static let initialNormalizedProgress = 1.0 / 1024.0
        static let initialBaseStep = 1.0
        static let targetProgress = 1.0
        static let changeDivisor = 4.0
        static let decayFactor = 0.8855
        static let changeProgressOffset = 0.00001
    }

    private let handle: UnsafeMutableRawPointer
    private let mainConnectionIDFn: MainConnectionIDFn
    private let copyManagedDisplaySpacesFn: CopyManagedDisplaySpacesFn
    private let copyBestManagedDisplayForPointFn: CopyBestManagedDisplayForPointFn
    private let getCurrentCursorLocationFn: GetCurrentCursorLocationFn
    private let gestureLock = NSLock()
    private var displayLink: CVDisplayLink
    private var gestureInFlight = false
    private var gestureState: GestureState?

    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else {
            throw Error.failedToOpenFramework
        }

        self.handle = handle
        mainConnectionIDFn = try Self.load("SLSMainConnectionID", from: handle, as: MainConnectionIDFn.self)
        copyManagedDisplaySpacesFn = try Self.load("SLSCopyManagedDisplaySpaces", from: handle, as: CopyManagedDisplaySpacesFn.self)
        copyBestManagedDisplayForPointFn = try Self.load("SLSCopyBestManagedDisplayForPoint", from: handle, as: CopyBestManagedDisplayForPointFn.self)
        getCurrentCursorLocationFn = try Self.load("SLSGetCurrentCursorLocation", from: handle, as: GetCurrentCursorLocationFn.self)

        var displayLinkRef: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&displayLinkRef)
        guard status == kCVReturnSuccess, let displayLinkRef else {
            throw Error.displayLinkUnavailable
        }

        displayLink = displayLinkRef
        CVDisplayLinkSetOutputCallback(
            displayLinkRef,
            Self.displayLinkCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    deinit {
        CVDisplayLinkStop(displayLink)
        dlclose(handle)
    }

    func copyManagedDisplaySnapshots() throws -> [ManagedDisplaySnapshot] {
        let payload = copyManagedDisplaySpacesFn(mainConnectionID())?.takeRetainedValue()
        guard let entries = payload as? [[String: Any]] else {
            throw Error.badManagedDisplayPayload
        }

        return entries.compactMap(Self.makeManagedDisplaySnapshot(from:))
    }

    func copyManagedDisplaySwitchContexts() throws -> [ManagedDisplaySwitchContext] {
        let payload = copyManagedDisplaySpacesFn(mainConnectionID())?.takeRetainedValue()
        guard let entries = payload as? [[String: Any]] else {
            throw Error.badManagedDisplayPayload
        }

        return entries.compactMap(Self.makeManagedDisplaySwitchContext(from:))
    }

    func bestManagedDisplayIdentifier(at point: CGPoint) throws -> String? {
        copyBestManagedDisplayForPointFn(mainConnectionID(), point)?.takeRetainedValue() as String?
    }

    func resolveCurrentDisplaySwitchResolution() throws -> ManagedDisplaySwitchResolution {
        let payload = copyManagedDisplaySpacesFn(mainConnectionID())?.takeRetainedValue()
        guard let entries = payload as? [[String: Any]] else {
            throw Error.badManagedDisplayPayload
        }

        let cursorPoint = currentCursorLocation()
        let preferredDisplayID = copyBestManagedDisplayForPointFn(mainConnectionID(), cursorPoint)?.takeRetainedValue() as String?
        return Self.resolveSwitchResolution(from: entries, preferredDisplayID: preferredDisplayID)
    }

    func enqueueSwipeGesture(_ direction: SpaceSwitchDirection, spaceCount: Int) throws {
        let signedLimit = signedLimitForAdjacentSwitch(direction: direction, spaceCount: spaceCount)
        let initialProgress = signedLimit * GestureTuning.initialNormalizedProgress
        var interruptedGestureKind: Int64?
        var interrupted = false

        gestureLock.lock()
        if gestureInFlight {
            interruptedGestureKind = gestureState?.gestureKind ?? SwipeEvent.swipeGestureKind
            interrupted = true
        }
        gestureInFlight = true
        gestureState = GestureState(
            direction: direction,
            gestureKind: SwipeEvent.swipeGestureKind,
            targetProgress: GestureTuning.targetProgress,
            signedLimit: signedLimit,
            normalizedProgress: GestureTuning.initialNormalizedProgress,
            baseStep: GestureTuning.initialBaseStep,
            velocityScale: 1.0,
            changeGateArmed: true
        )
        gestureLock.unlock()

        if let interruptedGestureKind, interrupted {
            if CVDisplayLinkIsRunning(displayLink) {
                CVDisplayLinkStop(displayLink)
            }
            try? postSwipeFrame(
                phase: SwipeEvent.cancelPhase,
                gestureKind: interruptedGestureKind,
                progress: 0,
                velocity: 0
            )
            do {
                try postSwipeFrame(
                    phase: SwipeEvent.beginPhase,
                    gestureKind: SwipeEvent.swipeGestureKind,
                    progress: initialProgress,
                    velocity: nil
                )
            } catch {
                finishGesture()
                throw error
            }
        } else {
            do {
                try postPreludeEvent()
                try postSwipeFrame(
                    phase: SwipeEvent.mayBeginPhase,
                    gestureKind: SwipeEvent.swipeGestureKind,
                    progress: 0,
                    velocity: nil
                )
                try postSwipeFrame(
                    phase: SwipeEvent.beginPhase,
                    gestureKind: SwipeEvent.swipeGestureKind,
                    progress: initialProgress,
                    velocity: nil
                )
            } catch {
                finishGesture()
                throw error
            }
        }

        if !CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStart(displayLink)
        }
    }

    func resetGestureDriver() {
        finishGesture()
    }

    private func mainConnectionID() -> SLSConnectionID {
        mainConnectionIDFn()
    }

    private func currentCursorLocation() -> CGPoint {
        var cursor = CGPoint.zero
        getCurrentCursorLocationFn(mainConnectionID(), &cursor)
        return cursor
    }

    private func signedLimitForAdjacentSwitch(direction: SpaceSwitchDirection, spaceCount: Int) -> Double {
        let denominator = max(spaceCount - 1, 1)
        let multiplier = Double(spaceCount) / Double(denominator)
        return direction.swipeSign * max(1.0, multiplier)
    }

    private func postPreludeEvent() throws {
        guard let event = CGEvent(source: nil) else {
            throw Error.eventConstructionFailed(0x1D)
        }

        var cursor = CGPoint.zero
        getCurrentCursorLocationFn(mainConnectionID(), &cursor)

        event.type = SwipeEvent.preludeType
        event.location = cursor
        event.setIntegerValueField(SwipeEvent.subtypeField, value: SwipeEvent.preludeSubtype)
        event.setIntegerValueField(SwipeEvent.phaseField, value: SwipeEvent.preludePhase)
        event.setDoubleValueField(SwipeEvent.preludeValueField, value: 0)
        event.post(tap: .cgSessionEventTap)
    }

    private func postSwipeFrame(
        phase: Int64,
        gestureKind: Int64,
        progress: Double,
        velocity: Double?
    ) throws {
        guard let event = CGEvent(source: nil) else {
            throw Error.eventConstructionFailed(phase)
        }

        event.type = SwipeEvent.type
        event.setIntegerValueField(SwipeEvent.subtypeField, value: SwipeEvent.swipeSubtype)
        event.setIntegerValueField(SwipeEvent.gestureField, value: gestureKind)
        event.setIntegerValueField(SwipeEvent.phaseField, value: phase)
        event.setDoubleValueField(SwipeEvent.progressField, value: progress)

        if let velocity {
            event.setDoubleValueField(SwipeEvent.velocityField, value: velocity)
        }

        event.post(tap: .cgSessionEventTap)
    }

    private func handleDisplayLinkTick() -> CVReturn {
        var completion: (progress: Double, velocity: Double, gestureKind: Int64)?
        var change: (progress: Double, gestureKind: Int64)?

        gestureLock.lock()
        guard var state = gestureState else {
            gestureLock.unlock()
            return kCVReturnSuccess
        }

        if state.changeGateArmed {
            state.changeGateArmed = false
            gestureState = state
            change = (
                progress: state.normalizedProgress * state.signedLimit,
                gestureKind: state.gestureKind
            )
            gestureLock.unlock()
        } else if state.normalizedProgress == state.targetProgress {
            let finalProgress = state.normalizedProgress * state.signedLimit
            completion = (
                progress: finalProgress,
                velocity: finalProgress / SwipeEvent.endVelocityDivisor,
                gestureKind: state.gestureKind
            )
            gestureState = nil
            gestureInFlight = false
            gestureLock.unlock()
        } else {
            let proposedProgress = state.normalizedProgress + ((state.baseStep / GestureTuning.changeDivisor) * state.velocityScale)
            let nextNormalizedProgress = clampProgress(
                proposedProgress,
                from: state.normalizedProgress,
                toward: state.targetProgress
            )

            state.normalizedProgress = nextNormalizedProgress
            state.velocityScale *= GestureTuning.decayFactor
            gestureState = state
            change = (
                progress: (nextNormalizedProgress + GestureTuning.changeProgressOffset) * state.signedLimit,
                gestureKind: state.gestureKind
            )
            gestureLock.unlock()
        }

        do {
            if let change {
                try postSwipeFrame(
                    phase: SwipeEvent.changePhase,
                    gestureKind: change.gestureKind,
                    progress: change.progress,
                    velocity: nil
                )
            }

            if let completion {
                try postSwipeFrame(
                    phase: SwipeEvent.endPhase,
                    gestureKind: completion.gestureKind,
                    progress: completion.progress,
                    velocity: completion.velocity
                )
                CVDisplayLinkStop(displayLink)
            }
        } catch {
            finishGesture()
        }

        return kCVReturnSuccess
    }

    private func clampProgress(_ proposed: Double, from current: Double, toward target: Double) -> Double {
        if current <= target {
            return min(proposed, target)
        }
        return max(proposed, target)
    }

    private func finishGesture() {
        gestureLock.lock()
        gestureState = nil
        gestureInFlight = false
        gestureLock.unlock()
        CVDisplayLinkStop(displayLink)
    }

    private static let displayLinkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
        guard let userInfo else {
            return kCVReturnError
        }

        let bridge = Unmanaged<SkyLightBridge>.fromOpaque(userInfo).takeUnretainedValue()
        return bridge.handleDisplayLinkTick()
    }

    private static func load<T>(_ symbolName: String, from handle: UnsafeMutableRawPointer, as type: T.Type) throws -> T {
        guard let symbol = dlsym(handle, symbolName) else {
            throw Error.missingSymbol(symbolName)
        }

        return unsafeBitCast(symbol, to: type)
    }

    private nonisolated static func makeManagedDisplaySnapshot(from entry: [String: Any]) -> ManagedDisplaySnapshot? {
        guard let displayID = entry["Display Identifier"] as? String else {
            return nil
        }

        guard let currentSpaceID = spaceID(from: entry["Current Space"]) else {
            return nil
        }

        let spaces = (entry["Spaces"] as? [[String: Any]] ?? [])
            .compactMap(makeManagedSpaceSnapshot)

        return ManagedDisplaySnapshot(
            id: displayID,
            currentSpaceID: currentSpaceID,
            spaces: spaces.map {
                ManagedSpaceSnapshot(
                    id: $0.id,
                    type: $0.type,
                    uuid: $0.uuid,
                    isCurrent: $0.id == currentSpaceID
                )
            }
        )
    }

    private nonisolated static func makeManagedDisplaySwitchContext(from entry: [String: Any]) -> ManagedDisplaySwitchContext? {
        guard let displayID = entry["Display Identifier"] as? String else {
            return nil
        }

        guard let currentSpaceID = spaceID(from: entry["Current Space"]) else {
            return nil
        }

        let rawSpaceIDs = (entry["Spaces"] as? [[String: Any]] ?? []).compactMap { spaceID(from: $0) }
        guard !rawSpaceIDs.isEmpty else {
            return nil
        }

        return ManagedDisplaySwitchContext(
            id: displayID,
            currentSpaceID: currentSpaceID,
            rawSpaceIDs: rawSpaceIDs
        )
    }

    private nonisolated static func resolveSwitchResolution(
        from entries: [[String: Any]],
        preferredDisplayID: String?
    ) -> ManagedDisplaySwitchResolution {
        for entry in entries {
            guard let displayID = entry["Display Identifier"] as? String else {
                continue
            }

            if let preferredDisplayID {
                guard displayID == preferredDisplayID else {
                    continue
                }
            } else if displayID != "Main" {
                continue
            }

            guard
                let currentSpaceID = managedSpaceID(from: entry["Current Space"]),
                let spaces = entry["Spaces"] as? [[String: Any]]
            else {
                continue
            }

            let rawSpaceIDs = spaces.compactMap { managedSpaceID(from: $0) }
            guard !rawSpaceIDs.isEmpty else {
                continue
            }

            let currentIndex = rawSpaceIDs.firstIndex(of: currentSpaceID) ?? 0
            return ManagedDisplaySwitchResolution(
                displayID: displayID,
                currentSpaceID: currentSpaceID,
                rawSpaceIDs: rawSpaceIDs,
                spaceCount: rawSpaceIDs.count,
                currentIndex: currentIndex
            )
        }

        return ManagedDisplaySwitchResolution(
            displayID: preferredDisplayID,
            currentSpaceID: nil,
            rawSpaceIDs: [],
            spaceCount: 2,
            currentIndex: 0
        )
    }

    private nonisolated static func makeManagedSpaceSnapshot(from entry: [String: Any]) -> ManagedSpaceSnapshot? {
        guard let id = spaceID(from: entry) else {
            return nil
        }

        let type = (entry["type"] as? NSNumber)?.intValue ?? 0
        // Keep ordinary desktops and fullscreen spaces. Skip nested wall/tile helper spaces.
        guard type == 0 || type == 4 else {
            return nil
        }

        return ManagedSpaceSnapshot(
            id: id,
            type: type,
            uuid: entry["uuid"] as? String,
            isCurrent: false
        )
    }

    private nonisolated static func spaceID(from payload: Any?) -> SLSManagedSpaceID? {
        guard let dictionary = payload as? [String: Any] else {
            return nil
        }

        if let value = dictionary["id64"] as? NSNumber {
            return value.uint64Value
        }
        if let value = dictionary["ManagedSpaceID"] as? NSNumber {
            return value.uint64Value
        }
        return nil
    }

    private nonisolated static func managedSpaceID(from payload: Any?) -> SLSManagedSpaceID? {
        guard
            let dictionary = payload as? [String: Any],
            let value = dictionary["ManagedSpaceID"] as? NSNumber
        else {
            return nil
        }

        return value.uint64Value
    }
}
