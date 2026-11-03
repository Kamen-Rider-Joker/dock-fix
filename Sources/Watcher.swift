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
/// cursor leaves the Dock during a Space transition, so one check right after each
/// Space change is enough. If the cursor is still on the Dock then, the Dock will get
/// its normal exit event later.
final class Watcher {
    private var fixing = false
    private let trace = UserDefaults.standard.object(forKey: "trace") as? Bool ?? true

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.spaceChanged() }
        ExitRecorder.ensureAttached()
        log("watching for Space changes")
    }

    private func spaceChanged() {
        ExitRecorder.ensureAttached()
        if trace { log("space changed: cursor=\(cursorLocation()) \(snapshot()?.summary ?? "no dock")") }
        DispatchQueue.main.async { [weak self] in self?.check() }
    }

    private func check() {
        guard !fixing, let snap = snapshot() else { return }
        let cursor = cursorLocation()
        let expectHide = hideExpected()
        if trace { log("check: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)") }
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
            FixStats.shared.record(fixed: false)
            return
        }
        let fixed = waitUntilFixed(expectHide: expectHide)
        log("fix: replayexit \(fixed ? "worked" : "did not help") -> \(snapshot()?.summary ?? "?")")
        FixStats.shared.record(fixed: fixed)
    }
}
