// DockUnstick: works around the Dock staying in its hover state (tooltip shown,
// no auto-hide) after swiping between full-screen Spaces with the cursor on an item.
//
// Usage (always launch through `open` so the app, not the terminal, owns the
// Accessibility permission):
//   open DockUnstick.app                       watch and fix (agent mode)
//   open DockUnstick.app --args --dump 8       dump Dock AX state after 8 seconds
// Settings (defaults domain local.dockunstick):
//   strategies  array of reenter | edge | restart, tried in order
//   trace       bool, log Dock state every tick while watching (default true)
//   awayDelay   seconds the cursor must be away before the Dock counts as stuck (default 0.5)
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
    /// Move onto the stuck (or nearest) item and back, giving the Dock a real enter/exit pair.
    case reenter
    /// Like reenter, but dwell on the item long enough for the Dock to fully register it.
    case edge
    /// Restart the Dock. Always works, but flickers.
    case restart

    func apply(_ snap: DockSnapshot, cursor: CGPoint) {
        let target = (snap.hovered.first ?? nearestItem(snap, to: cursor))?.frame
        switch self {
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

/// After every Space change, watch the Dock for a few seconds (longer while the
/// cursor is still on the Dock) and fix it if it stays stuck.
final class Watcher {
    private var timer: Timer?
    private var deadline = Date.distantPast
    private var awaySince: Date?
    private var fixing = false
    private let trace = UserDefaults.standard.object(forKey: "trace") as? Bool ?? true
    /// How long the cursor must be away before a hovering/shown Dock counts as stuck.
    /// A healthy Dock hides about 0.4s after the cursor leaves.
    private let awayDelay = UserDefaults.standard.object(forKey: "awayDelay") as? Double ?? 0.5

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.watch() }
        log("watching for Space changes (strategies: \(strategies().map(\.rawValue)))")
    }

    private func watch() {
        if trace { log("space changed: cursor=\(cursorLocation()) \(snapshot()?.summary ?? "no dock")") }
        deadline = Date().addingTimeInterval(5)
        awaySince = nil
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard !fixing, let snap = snapshot() else { return }
        let cursor = cursorLocation()
        let expectHide = hideExpected()
        if trace { log("tick: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)") }

        if snap.contains(cursor) {
            awaySince = nil
            deadline = max(deadline, Date().addingTimeInterval(5))
        } else if awaySince == nil {
            awaySince = Date()
        }

        // Stuck: cursor has been away for a while, yet the Dock still hovers an item
        // or stays shown when it should have auto-hidden.
        let away = awaySince.map { Date().timeIntervalSince($0) } ?? 0
        let hovering = !snap.hovered.isEmpty
        let lingering = expectHide && snap.isShown
        if away >= awayDelay && (hovering || lingering) {
            unstick(snap, cursor: cursor, expectHide: expectHide)
            awaySince = Date()
            deadline = Date().addingTimeInterval(3)
        }

        if Date() > deadline {
            timer?.invalidate()
            timer = nil
        }
    }

    private func unstick(_ snap: DockSnapshot, cursor: CGPoint, expectHide: Bool) {
        fixing = true
        defer { fixing = false }
        log("stuck: cursor=(\(Int(cursor.x)),\(Int(cursor.y))) \(snap.summary) hideExpected=\(expectHide)")
        for strategy in strategies() {
            strategy.apply(snap, cursor: cursor)
            if strategy == .restart { log("fix: restart (Dock relaunched)"); return }
            if waitUntilFixed(expectHide: expectHide) {
                log("fix: \(strategy.rawValue) worked -> \(snapshot()?.summary ?? "?")")
                return
            }
            log("fix: \(strategy.rawValue) did not help -> \(snapshot()?.summary ?? "?")")
        }
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
} else {
    let watcher = Watcher()
    watcher.start()
    app.run()
}
