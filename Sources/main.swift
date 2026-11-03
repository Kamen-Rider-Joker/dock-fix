// DockUnstick: works around the Dock staying in its hover state (tooltip shown,
// no auto-hide) after swiping between full-screen Spaces with the cursor on an item.
//
// Usage (always launch through `open` so the app, not the terminal, owns the
// Accessibility permission):
//   open DockUnstick.app                       watch and fix, with an anchored menu bar panel
//   open DockUnstick.app --args --dump 8       dump Dock AX state after 8 seconds
//   open DockUnstick.app --args --tap 60       log events delivered to the Dock for 60 seconds
// Settings (defaults domain local.dockunstick):
//   trace        bool, log Dock state at every check (default true)
//   retryCount   int, checks after the first while the Dock isn't confirmed fine (default 3, 0-5)
//   retryInterval  seconds between those checks (default 0.5, 0.1-1)
// Log: ~/Library/Logs/DockUnstick.log

import AppKit
import ApplicationServices

// MARK: - Entry point

/// Agent mode: the Space watcher and the menu bar panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private let watcher = Watcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = KeyCommands.shared.makeMainMenu()
        AccessibilityPermission.startMonitoring()
        ExitRecorder.ensureAttached()
        menuBar = MenuBarController(onShowPermissions: AccessibilityPermission.request)
        watcher.start()
    }

    /// Opening the app again (e.g. double-clicking it while it runs) reveals the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.showPanel()
        return false
    }

}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
log("start pid=\(getpid()) accessibilityTrusted=\(AXIsProcessTrusted()) args=\(CommandLine.arguments.dropFirst())")

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
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
