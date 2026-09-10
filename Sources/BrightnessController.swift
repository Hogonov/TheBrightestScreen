// SPDX-License-Identifier: GPL-3.0-only
import AppKit

final class BrightnessController {
    private final class Session {
        let id: CGDirectDisplayID
        let originalGamma: GammaTable
        let trigger: HDRTrigger
        var factor: Float = 1
        var readySince: Date?
        var lastIntegrityCheck = Date()
        var gammaConflictCount = 0
        var failure: String?

        init(screen: NSScreen) throws {
            id = screen.displayID
            originalGamma = try GammaTable.read(display: id)
            trigger = try HDRTrigger(screen: screen)
        }
    }

    private struct NativeState {
        let original: Float
        var didSetMaximum = false
    }

    let hardware = NativeBrightness()
    private var sessions: [CGDirectDisplayID: Session] = [:]
    private var nativeStates: [CGDirectDisplayID: NativeState] = [:]
    private var timer: Timer?
    private var blockedReasons = Set<String>()
    private var lastTick = Date()
    private var sessionErrors: [String] = []
    private(set) var enabled = false
    private(set) var status = "Готов к включению"
    var onChange: (() -> Void)?
    var amount: Double = 1 {
        didSet { amount = min(max(amount, 0), 1); tick(); onChange?() }
    }

    var supportedScreens: [NSScreen] { NSScreen.screens.filter(\.supportsBoost) }
    var boostedDisplayCount: Int { sessions.values.filter { $0.factor > 1.01 }.count }

    func enable() {
        guard !enabled else { return }
        let conflicts = NSWorkspace.shared.runningApplications.compactMap(\.localizedName).filter {
            ["BrightXDR", "BrightIntosh", "Vivid"].contains($0)
        }
        guard conflicts.isEmpty else {
            status = "Сначала закройте \(conflicts.joined(separator: ", "))"
            onChange?()
            return
        }
        guard !supportedScreens.isEmpty else {
            status = "Совместимый XDR-экран не найден"
            onChange?()
            return
        }
        enabled = true
        status = "Включаем HDR…"
        rebuildScreens()
        lastTick = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onChange?()
    }

    func maximize() {
        amount = 1
        enable()
        guard enabled else { return }
        for session in sessions.values where session.failure == nil {
            // Only write when the original value can be restored on exit.
            if var state = nativeStates[session.id] {
                state.didSetMaximum = hardware.write(session.id, value: 1) || state.didSetMaximum
                nativeStates[session.id] = state
            }
        }
        tick()
    }

    func disable() {
        enabled = false
        timer?.invalidate()
        timer = nil
        releaseSessions()
        for id in Array(nativeStates.keys) { restoreNativeBrightness(id) }
        status = "Обычная яркость"
        onChange?()
    }

    func suspend(_ reason: String) {
        blockedReasons.insert(reason)
        releaseSessions()
        if enabled { status = "Приостановлено"; onChange?() }
    }

    func resume(_ reason: String) {
        blockedReasons.remove(reason)
        guard enabled, blockedReasons.isEmpty else { return }
        rebuildScreens()
    }

    func screenParametersChanged() {
        guard enabled, blockedReasons.isEmpty else { return }
        rebuildScreens()
        tick()
    }

    func spaceChanged() {
        guard enabled, blockedReasons.isEmpty else { return }
        for screen in supportedScreens { sessions[screen.displayID]?.trigger.refresh(screen: screen) }
        tick()
    }

    private func restore(_ session: Session) {
        // Restore colour before releasing HDR; the reverse order clips SDR whites.
        if session.factor != 1 {
            let result = session.originalGamma.apply(display: session.id)
            if result != .success { NSLog("Brighter: gamma restore error %d", result.rawValue) }
            session.factor = 1
        }
        session.trigger.stop()
    }

    private func restoreNativeBrightness(_ id: CGDirectDisplayID) {
        guard let state = nativeStates.removeValue(forKey: id), state.didSetMaximum else { return }
        if BrightnessPolicy.shouldRestoreBrightness(current: hardware.read(id), original: state.original) {
            hardware.write(id, value: state.original)
        }
    }

    private func releaseSessions() {
        for session in sessions.values { restore(session) }
        sessions.removeAll()
    }

    private func rebuildScreens() {
        guard enabled, blockedReasons.isEmpty else { return }
        let screens = supportedScreens
        let ids = Set(screens.map(\.displayID))
        for id in Array(sessions.keys) where !ids.contains(id) {
            if let session = sessions.removeValue(forKey: id) { restore(session) }
            restoreNativeBrightness(id)
        }
        sessionErrors.removeAll()
        for screen in screens {
            if let session = sessions[screen.displayID] {
                session.trigger.refresh(screen: screen)
            } else {
                do {
                    sessions[screen.displayID] = try Session(screen: screen)
                    if nativeStates[screen.displayID] == nil, let value = hardware.read(screen.displayID) {
                        nativeStates[screen.displayID] = NativeState(original: value)
                    }
                }
                catch { sessionErrors.append(error.localizedDescription) }
            }
        }
    }

    private func tick() {
        guard enabled, blockedReasons.isEmpty else { return }
        let now = Date()
        let resumedAfterGap = now.timeIntervalSince(lastTick) > 2
        lastTick = now
        var messages = sessionErrors
        for screen in supportedScreens {
            guard let session = sessions[screen.displayID] else { continue }
            if let failure = session.failure { messages.append(failure); continue }
            let edr = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            let freshFrame = session.trigger.metalView.lastFrameAt.map { now.timeIntervalSince($0) < 2 } ?? false
            let hdrReady = freshFrame && edr > BrightnessPolicy.hdrThreshold &&
                CGDisplayIsAsleep(session.id) == 0 && !resumedAfterGap
            if hdrReady {
                if session.readySince == nil { session.readySince = now }
            } else { session.readySince = nil }
            let stable = session.readySince.map { now.timeIntervalSince($0) >= 0.5 } ?? false
            let target = stable ? BrightnessPolicy.factor(headroom: edr, amount: amount) : 1
            let next = BrightnessPolicy.nextFactor(current: session.factor, target: target)
            if abs(next - session.factor) > 0.001 {
                let result = session.originalGamma.scaled(by: next).apply(display: session.id)
                guard result == .success else {
                    session.failure = "Ошибка изменения яркости: \(result.rawValue)"
                    restore(session)
                    messages.append(session.failure!)
                    continue
                }
                session.factor = next
                session.lastIntegrityCheck = now
            } else if next > 1.01, now.timeIntervalSince(session.lastIntegrityCheck) > 2 {
                session.lastIntegrityCheck = now
                let current = try? GammaTable.read(display: session.id)
                let matches = current?.approximatelyEquals(session.originalGamma.scaled(by: session.factor),
                                                            tolerance: 0.025) ?? false
                session.gammaConflictCount = matches ? 0 : session.gammaConflictCount + 1
                if session.gammaConflictCount >= 3 {
                    session.failure = "macOS или другая программа сбрасывает гамму. Выключите и повторите."
                    restore(session)
                } else if !matches {
                    // WindowServer may reset gamma when EDR engages or display
                    // parameters change. Recover isolated resets, but do not
                    // compete indefinitely with another colour-control app.
                    NSLog("Brighter: gamma reset, observed %.4f expected %.4f, retry %d",
                          current?.red.last ?? -1, session.originalGamma.red.last! * session.factor,
                          session.gammaConflictCount)
                    let result = session.originalGamma.scaled(by: session.factor).apply(display: session.id)
                    if result != .success {
                        session.failure = "macOS отклонила восстановление усиления"
                        restore(session)
                    }
                }
            }
        }
        let newStatus: String
        if !messages.isEmpty { newStatus = messages.joined(separator: "; ") }
        else if sessions.isEmpty { newStatus = "Совместимый XDR-экран не найден" }
        else if boostedDisplayCount == 0 { newStatus = amount == 0 ? "Усиление: 0%" : "Ожидаем доступную HDR-яркость…" }
        else {
            let needsKeys = sessions.values.contains { (hardware.read($0.id) ?? 0) < 0.995 }
            newStatus = needsKeys ? "XDR включён · F2 — ярче" : "Максимум системы · XDR включён"
        }
        if status != newStatus { status = newStatus; onChange?() }
    }

    func verifyAppliedGamma() -> Bool {
        !sessions.isEmpty && sessions.values.allSatisfy { session in
            guard session.factor > 1.01, let current = try? GammaTable.read(display: session.id) else { return false }
            return current.approximatelyEquals(session.originalGamma.scaled(by: session.factor))
        }
    }

    func diagnosticLines() -> [String] {
        var lines = ["enabled=\(enabled) amount=\(amount) boosted=\(boostedDisplayCount)", "status=\(status)"]
        for screen in NSScreen.screens {
            let id = screen.displayID
            let gamma = try? GammaTable.read(display: id)
            lines.append("display=\(id) name=\(screen.localizedName) supported=\(screen.supportsBoost) native=\(hardware.read(id).map(String.init(describing:)) ?? "unavailable") EDR=\(screen.maximumExtendedDynamicRangeColorComponentValue) potential=\(screen.maximumPotentialExtendedDynamicRangeColorComponentValue) gammaSamples=\(gamma?.red.count ?? 0) gammaMax=\(gamma?.red.last ?? -1)")
            if let session = sessions[id] {
                lines.append("trigger=\(session.trigger.frame) drawable=\(session.trigger.metalView.drawableSize) frames=\(session.trigger.metalView.completedFrames) factor=\(session.factor)")
            }
        }
        return lines
    }
}
