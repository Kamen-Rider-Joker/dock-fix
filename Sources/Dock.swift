import AppKit
import ApplicationServices

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

func dockPid() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
}
