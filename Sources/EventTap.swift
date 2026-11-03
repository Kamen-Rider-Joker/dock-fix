import AppKit

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
