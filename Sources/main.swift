// DockUnstick: works around the Dock staying in its hover state (tooltip shown,
// no auto-hide) after swiping between full-screen Spaces with the cursor on an item.
//
// Usage (always launch through `open` so the app, not the terminal, owns the
// Accessibility permission):
//   open DockUnstick.app                       watch and fix (agent mode)
//   open DockUnstick.app --args --dump 8       dump Dock AX state after 8 seconds
//   open DockUnstick.app --args --tap 60       log events delivered to the Dock for 60 seconds
// Settings (defaults domain local.dockunstick):
//   strategies   array of replayexit | reenter | edge | restart, tried in order
//   trace        bool, log Dock state at every check (default true)
//   checkDelays  array of seconds after a Space change at which to check (default 0.6, 1.2, 2.0)
// Log: ~/Library/Logs/DockUnstick.log

import AppKit
import ApplicationServices

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/DockUnstick.log")

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter.withFraction.string(from: Date())) \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Accessibility helpers

func axAttr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func axNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyAttributeNames(element, &names)
    return (names as? [String]) ?? []
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let pos = axAttr(element, kAXPositionAttribute), let size = axAttr(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero, extent = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

/// Cursor position in the same top-left-origin space the AX API uses.
func cursorLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

/// Height of the primary display, i.e. the bottom edge in AX coordinates.
func primaryHeight() -> CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

struct DockItem {
    let title: String
    let frame: CGRect?
    let selected: Bool
}

struct DockSnapshot {
    let listFrame: CGRect?
    let items: [DockItem]
    var hovered: [DockItem] { items.filter(\.selected) }

    /// A hidden bottom Dock is parked just below the screen (y == screen height).
    var isShown: Bool {
        guard let frame = listFrame else { return false }
        return frame.minY < primaryHeight() - 1
    }

    func contains(_ point: CGPoint) -> Bool {
        listFrame?.insetBy(dx: -12, dy: -12).contains(point) ?? false
    }

    var summary: String {
        let y = listFrame.map { "\(Int($0.minY))" } ?? "nil"
        return "dockY=\(y) shown=\(isShown) hovered=\(hovered.map(\.title))"
    }
}

func dockApp() -> AXUIElement? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    return AXUIElementCreateApplication(dock.processIdentifier)
}

func dockList() -> AXUIElement? {
    guard let app = dockApp() else { return nil }
    let children = axAttr(app, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return children.first { (axAttr($0, kAXRoleAttribute) as? String) == kAXListRole }
}

func snapshot() -> DockSnapshot? {
    guard let list = dockList() else { return nil }
    let items = (axAttr(list, kAXChildrenAttribute) as? [AXUIElement] ?? []).map {
        DockItem(title: axAttr($0, kAXTitleAttribute) as? String ?? "?",
                 frame: axFrame($0),
                 selected: (axAttr($0, kAXSelectedAttribute) as? Bool) ?? false)
    }
    return DockSnapshot(listFrame: axFrame(list), items: items)
}

/// The Dock should hide on its own when auto-hide is on or the front window is full screen.
func hideExpected() -> Bool {
    if UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") == true { return true }
    guard let front = NSWorkspace.shared.frontmostApplication else { return false }
    let app = AXUIElementCreateApplication(front.processIdentifier)
    guard let window = axAttr(app, kAXFocusedWindowAttribute) else { return false }
    return (axAttr(window as! AXUIElement, "AXFullScreen") as? Bool) ?? false
}

func dump() {
    let cursor = cursorLocation()
    guard let list = dockList(), let snap = snapshot() else { log("dump: Dock list not found"); return }
    log("dump: cursor=\(cursor) \(snap.summary) hideExpected=\(hideExpected())")
    for element in axAttr(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        let values = axNames(element).compactMap { name -> String? in
            guard name != kAXChildrenAttribute, name != kAXParentAttribute, name != kAXTopLevelUIElementAttribute,
                  let value = axAttr(element, name) else { return nil }
            return "\(name)=\(value)"
        }
        log("dump:   \(values.joined(separator: " | "))")
    }
}

// MARK: - Fix strategies, tried in order until the Dock is no longer stuck

func postMove(to point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

/// Glide in a few steps so the Dock sees real motion instead of one coalesced jump.
func glide(from start: CGPoint, to end: CGPoint, steps: Int = 4, stepMicros: useconds_t = 12_000) {
    for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        postMove(to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        usleep(stepMicros)
    }
}

enum Strategy: String, CaseIterable {
    /// Replay the window server's own mouse-exited event to the Dock. No cursor movement.
    case replayexit
    /// Move onto the stuck (or nearest) item and back, giving the Dock a real enter/exit pair.
    case reenter
    /// Like reenter, but dwell on the item long enough for the Dock to fully register it.
    case edge
    /// Restart the Dock. Always works, but flickers.
    case restart

    func apply(_ snap: DockSnapshot, cursor: CGPoint) {
        let target = (snap.hovered.first ?? nearestItem(snap, to: cursor))?.frame
        switch self {
        case .replayexit:
            guard let exit = ExitRecorder.lastExit?.copy(), let pid = dockPid() else {
                log("replayexit: no recorded exit event")
                return
            }
            exit.location = cursor
            exit.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            exit.postToPid(pid)
        case .reenter:
            guard let target else { return }
            glide(from: cursor, to: CGPoint(x: target.midX, y: target.midY))
            usleep(60_000)
            glide(from: CGPoint(x: target.midX, y: target.midY), to: cursor)
        case .edge:
            guard let target else { return }
            let bottom = CGPoint(x: target.midX, y: primaryHeight() - 2)
            glide(from: cursor, to: bottom, steps: 6)
            usleep(250_000)
            glide(from: bottom, to: cursor, steps: 6)
        case .restart:
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").forEach { $0.forceTerminate() }
        }
    }

    private func nearestItem(_ snap: DockSnapshot, to cursor: CGPoint) -> DockItem? {
        snap.items.filter { $0.frame != nil }.min { abs($0.frame!.midX - cursor.x) < abs($1.frame!.midX - cursor.x) }
    }
}

func strategies() -> [Strategy] {
    let configured = UserDefaults.standard.stringArray(forKey: "strategies") ?? []
    let parsed = configured.compactMap(Strategy.init(rawValue:))
    return parsed.isEmpty ? Strategy.allCases : parsed
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
        log("watching for Space changes (strategies: \(strategies().map(\.rawValue)), checks at \(checkDelays)s)")
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
        for strategy in strategies() {
            strategy.apply(snap, cursor: cursor)
            if strategy == .restart { log("fix: restart (Dock relaunched)"); return }
            let fixed = waitUntilFixed(expectHide: expectHide)
            let moved = cursorLocation() != cursor ? " (cursor moved)" : ""
            log("fix: \(strategy.rawValue) \(fixed ? "worked" : "did not help")\(moved) -> \(snapshot()?.summary ?? "?")")
            if fixed { return }
        }
    }
}

// MARK: - Event tap on the Dock (diagnostic)

// Raw accessors so undocumented event types and fields can be read.
@_silgen_name("CGEventGetType") func rawEventType(_ event: CGEvent) -> UInt32
@_silgen_name("CGEventGetIntegerValueField") func rawIntegerField(_ event: CGEvent, _ field: UInt32) -> Int64

var tapPort: CFMachPort?
var movedCount = 0

/// Log every event the window server delivers to the Dock process, except plain
/// mouse-moved events, which are only counted. Listen-only: nothing is altered.
let tapCallback: CGEventTapCallBack = { _, _, event, _ in
    let type = rawEventType(event)
    if type == 0xFFFF_FFFE || type == 0xFFFF_FFFF {
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
        log("tap: re-enabled after type \(type)")
        return Unmanaged.passUnretained(event)
    }
    if type == CGEventType.mouseMoved.rawValue {
        movedCount += 1
        return Unmanaged.passUnretained(event)
    }
    let fields = (0..<256).compactMap { field -> String? in
        let value = rawIntegerField(event, UInt32(field))
        return value == 0 ? nil : "\(field):\(value)"
    }
    let data = (event.data as Data?)?.map { String(format: "%02x", $0) }.joined() ?? ""
    let loc = event.location
    log("tap: type=\(type) loc=(\(Int(loc.x)),\(Int(loc.y))) moved+\(movedCount) dock={\(snapshot()?.summary ?? "?")} fields=[\(fields.joined(separator: " "))] data=\(data)")
    movedCount = 0
    return Unmanaged.passUnretained(event)
}

func dockPid() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
}

/// Attach a listen-only tap to the events the window server delivers to the Dock.
func makeDockTap(mask: CGEventMask, callback: CGEventTapCallBack) -> (port: CFMachPort, pid: pid_t)? {
    guard let pid = dockPid(),
          let port = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap, options: .listenOnly,
                                             eventsOfInterest: mask, callback: callback, userInfo: nil)
    else { return nil }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    return (port, pid)
}

func startDockTap() {
    guard let tap = makeDockTap(mask: CGEventMask.max, callback: tapCallback) else {
        // Usually Accessibility is not granted yet; retry until it is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { startDockTap() }
        return
    }
    tapPort = tap.port
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { _ in log("tap: space changed cursor=\(cursorLocation()) dock={\(snapshot()?.summary ?? "?")}") }
    log("tap: listening to events delivered to Dock pid \(tap.pid)")
}

// MARK: - Exit-event recorder

/// Window-server tracking events for the Dock: 8 = mouse entered, 9 = mouse exited.
let mouseEnteredType: UInt32 = 8
let mouseExitedType: UInt32 = 9

/// Keeps a copy of the last mouse-exited event the window server sent the Dock, so it
/// can be replayed when the Dock dropped it. Only types 8/9 are tapped, so this is cheap.
enum ExitRecorder {
    static var lastExit: CGEvent?
    private static var port: CFMachPort?
    private static var pid: pid_t?

    private static let callback: CGEventTapCallBack = { _, _, event, _ in
        switch rawEventType(event) {
        case mouseExitedType: ExitRecorder.lastExit = event.copy()
        case 0xFFFF_FFFE, 0xFFFF_FFFF: if let port = ExitRecorder.port { CGEvent.tapEnable(tap: port, enable: true) }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }

    /// (Re)attach when not attached yet or the Dock was relaunched.
    static func ensureAttached() {
        guard pid == nil || pid != dockPid() else { return }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        let mask = CGEventMask(1) << mouseEnteredType | CGEventMask(1) << mouseExitedType
        guard let tap = makeDockTap(mask: mask, callback: callback) else { log("recorder: could not tap the Dock"); return }
        port = tap.port
        pid = tap.pid
        lastExit = nil
        log("recorder: tapping tracking events of Dock pid \(tap.pid)")
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
log("start pid=\(getpid()) accessibilityTrusted=\(trusted) args=\(CommandLine.arguments.dropFirst())")

let args = CommandLine.arguments
if let index = args.firstIndex(of: "--dump") {
    let delay = index + 1 < args.count ? Double(args[index + 1]) ?? 5 : 5
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        dump()
        exit(0)
    }
    app.run()
} else if let index = args.firstIndex(of: "--tap") {
    let duration = index + 1 < args.count ? Double(args[index + 1]) ?? 60 : 60
    startDockTap()
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        log("tap: done")
        exit(0)
    }
    app.run()
} else {
    let watcher = Watcher()
    watcher.start()
    app.run()
}
