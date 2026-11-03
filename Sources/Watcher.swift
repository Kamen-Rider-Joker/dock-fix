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
/// cursor leaves the Dock during a Space transition, so a few one-off checks shortly
/// after each Space change are enough. If the cursor is still on the Dock then, the
/// Dock will get its normal exit event later.
final class Watcher {
    private var fixing = false
    private var generation = 0
    private let trace = UserDefaults.standard.object(forKey: "trace") as? Bool ?? true
    /// Seconds after a Space change at which the Dock is checked.
    private let checkDelays = UserDefaults.standard.array(forKey: "checkDelays") as? [Double] ?? [0.6, 1.2, 2.0]

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.spaceChanged() }
        ExitRecorder.ensureAttached()
        log("watching for Space changes (checks at \(checkDelays)s)")
    }

    private func spaceChanged() {
        ExitRecorder.ensureAttached()
        generation += 1
        let current = generation
        if trace { log("space changed: cursor=\(cursorLocation()) \(snapshot()?.summary ?? "no dock")") }
        for delay in checkDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // A newer Space change supersedes the pending checks.
                guard let self, self.generation == current else { return }
                self.check(after: delay)
            }
        }
    }

    private func check(after delay: Double) {
        guard !fixing, let snap = snapshot() else { return }
        let cursor = cursorLocation()
        let expectHide = hideExpected()
        if trace { log("check +\(delay)s: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)") }
        // Stuck: cursor is away, yet the Dock still hovers an item or stays shown
        // when it should have auto-hidden.
        guard !snap.contains(cursor), !snap.hovered.isEmpty || (expectHide && snap.isShown) else { return }
        unstick(snap, cursor: cursor, expectHide: expectHide)
    }

    private func unstick(_ snap: DockSnapshot, cursor: CGPoint, expectHide: Bool) {
        fixing = true
        defer { fixing = false }
        log("stuck: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)")
        guard replayExit(cursor: cursor) else {
            log("fix: no recorded exit event to replay")
            return
        }
        let fixed = waitUntilFixed(expectHide: expectHide)
        log("fix: replayexit \(fixed ? "worked" : "did not help") -> \(snapshot()?.summary ?? "?")")
    }
}
