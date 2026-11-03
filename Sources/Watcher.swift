import AppKit

// MARK: - Fix

/// Replay the window server's own mouse-exited event to the Dock; the real cursor does not move.
func replayExit(cursor: CGPoint) -> Bool {
    guard let exit = ExitRecorder.lastExit?.copy(), let pid = dockPid() else { return false }
    exit.location = cursor
    exit.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    exit.postToPid(pid)
    return true
}

// MARK: - Watcher

/// Event-driven: no global pointer polling. A Space change starts one immediate
/// check and optional retries. Verification after replay is asynchronous so the
/// menu panel and the rest of the UI never block on `usleep`.
final class Watcher {
    private var fixing = false
    private var generation = 0
    private var pendingAfterFix = false
    private var lateExitWindow = 0
    private let trace = UserDefaults.standard.object(forKey: "trace") as? Bool ?? true

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.spaceChanged() }

        ExitRecorder.onExit = { [weak self] in self?.dockExitReceived() }
        ExitRecorder.ensureAttached()
        log("watching for Space changes (retries: \(Preferences.retryCount) x \(Preferences.retryInterval)s)")
    }

    private func spaceChanged() {
        AccessibilityPermission.checkNow()
        ExitRecorder.ensureAttached()
        generation += 1
        pendingAfterFix = false
        let current = generation

        // The Dock can publish its exit event slightly after the Space change.
        // Keep a short window for that event without polling the global mouse.
        lateExitWindow = current
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.lateExitWindow == current else { return }
            self.lateExitWindow = 0
        }

        if trace {
            log("space changed: cursor=\(cursorLocation()) \(snapshot()?.summary ?? "no dock")")
        }
        DispatchQueue.main.async { [weak self] in
            self?.check(round: 0, generation: current)
        }
    }

    private func dockExitReceived() {
        let current = lateExitWindow
        guard current > 0 else { return }
        lateExitWindow = 0
        // Give the Dock one run-loop turn to finish its own exit handling before
        // deciding that the event was dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.check(round: 0, generation: current)
        }
    }

    /// Round 0 is the first check; rounds after it are retries.
    private func check(round: Int, generation current: Int) {
        guard generation == current else { return }
        guard !fixing else {
            pendingAfterFix = true
            return
        }
        let retries = Preferences.retryCount
        if checkOnce(round: round, of: retries) || round >= retries { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Preferences.retryInterval) { [weak self] in
            self?.check(round: round + 1, generation: current)
        }
    }

    /// Returns whether the Dock is known to be fine: the cursor is away from it and it
    /// is not stuck, or it was stuck and the fix worked.
    private func checkOnce(round: Int, of retries: Int) -> Bool {
        guard let snap = snapshot() else { return false }
        let cursor = cursorLocation()
        let expectHide = hideExpected()
        if trace {
            log("check \(round)/\(retries): cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)")
        }
        // Still on the Dock: it will get its exit event later, unless the cursor
        // leaves while the Space transition is still running.
        if snap.contains(cursor) { return false }
        // Stuck: cursor is away, yet the Dock still hovers an item or stays shown
        // when it should have auto-hidden.
        guard !snap.hovered.isEmpty || (expectHide && snap.isShown) else { return true }
        return unstick(snap, cursor: cursor, expectHide: expectHide, generation: generation)
    }

    private func unstick(
        _ snap: DockSnapshot,
        cursor: CGPoint,
        expectHide: Bool,
        generation current: Int
    ) -> Bool {
        fixing = true
        log("stuck: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)")
        guard replayExit(cursor: cursor) else {
            log("fix: no recorded exit event to replay")
            FixStats.shared.record(fixed: false)
            finishFix(generation: current)
            return false
        }
        verifyFixed(expectHide: expectHide, attemptsRemaining: 15, generation: current)
        return false
    }

    /// Poll Dock accessibility state for at most 1.5 seconds, off the critical
    /// input path. Each run-loop turn keeps the UI responsive.
    private func verifyFixed(expectHide: Bool, attemptsRemaining: Int, generation current: Int) {
        guard attemptsRemaining > 0 else {
            log("fix: replayexit did not help -> \(snapshot()?.summary ?? "?")")
            FixStats.shared.record(fixed: false)
            finishFix(generation: current)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            if let snap = snapshot(),
               snap.hovered.isEmpty,
               !expectHide || !snap.isShown {
                log("fix: replayexit worked -> \(snap.summary)")
                FixStats.shared.record(fixed: true)
                self.finishFix(generation: current)
            } else {
                self.verifyFixed(
                    expectHide: expectHide,
                    attemptsRemaining: attemptsRemaining - 1,
                    generation: current
                )
            }
        }
    }

    private func finishFix(generation current: Int) {
        fixing = false
        guard pendingAfterFix || generation != current else { return }
        pendingAfterFix = false
        DispatchQueue.main.async { [weak self] in
            self?.check(round: 0, generation: self?.generation ?? current)
        }
    }
}
