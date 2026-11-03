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

/// Fixed means: no hovered item, and if the Dock should auto-hide, it actually hides within ~1.5s.
func waitUntilFixed(expectHide: Bool) -> Bool {
    for _ in 0..<15 {
        usleep(100_000)
        guard let snap = snapshot() else { continue }
        if snap.hovered.isEmpty && (!expectHide || !snap.isShown) { return true }
    }
    return false
}

// MARK: - Watcher

/// Event-driven: no polling and no mouse monitoring. The bug only happens when the
/// cursor leaves the Dock during a Space transition, so the Dock is checked right
/// after each Space change. When that check cannot confirm the Dock is fine (the
/// cursor is still on it, or a fix did not take), it is checked again up to
/// Preferences.retryCount times, Preferences.retryInterval apart.
final class Watcher {
    private var fixing = false
    private var generation = 0
    private let trace = UserDefaults.standard.object(forKey: "trace") as? Bool ?? true

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.spaceChanged() }
        ExitRecorder.ensureAttached()
        log("watching for Space changes (retries: \(Preferences.retryCount) x \(Preferences.retryInterval)s)")
    }

    private func spaceChanged() {
        ExitRecorder.ensureAttached()
        generation += 1
        let current = generation
        if trace { log("space changed: cursor=\(cursorLocation()) \(snapshot()?.summary ?? "no dock")") }
        DispatchQueue.main.async { [weak self] in self?.check(round: 0, generation: current) }
    }

    /// Round 0 is the first check; rounds after it are retries.
    private func check(round: Int, generation current: Int) {
        // A newer Space change supersedes the pending checks.
        guard generation == current, !fixing else { return }
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
        if trace { log("check \(round)/\(retries): cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)") }
        // Still on the Dock: it will get its exit event later, unless the cursor
        // leaves while the Space transition is still running.
        if snap.contains(cursor) { return false }
        // Stuck: cursor is away, yet the Dock still hovers an item or stays shown
        // when it should have auto-hidden.
        guard !snap.hovered.isEmpty || (expectHide && snap.isShown) else { return true }
        return unstick(snap, cursor: cursor, expectHide: expectHide)
    }

    private func unstick(_ snap: DockSnapshot, cursor: CGPoint, expectHide: Bool) -> Bool {
        fixing = true
        defer { fixing = false }
        log("stuck: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)")
        guard replayExit(cursor: cursor) else {
            log("fix: no recorded exit event to replay")
            FixStats.shared.record(fixed: false)
            return false
        }
        let fixed = waitUntilFixed(expectHide: expectHide)
        log("fix: replayexit \(fixed ? "worked" : "did not help") -> \(snapshot()?.summary ?? "?")")
        FixStats.shared.record(fixed: fixed)
        return fixed
    }
}
