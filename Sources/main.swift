// DockUnstick: works around the Dock staying in its hover state (tooltip shown,
// no auto-hide) after swiping between full-screen Spaces with the cursor on an item.
//
// Usage (always launch through `open` so the app, not the terminal, owns the
// Accessibility permission):
//   open DockUnstick.app                       menu bar app: watch and fix (agent mode)
//   open DockUnstick.app --args --dump 8       dump Dock AX state after 8 seconds
//   open DockUnstick.app --args --tap 60       log events delivered to the Dock for 60 seconds
// Settings (defaults domain local.dockunstick):
//   trace        bool, log Dock state at every check (default true)
//   checkDelays  array of seconds after a Space change at which to check (default 0.6, 1.2, 2.0)
// Log: ~/Library/Logs/DockUnstick.log

import AppKit
import ApplicationServices

// MARK: - Entry point

/// Agent mode: menu bar item plus the Space watcher.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var permissions: PermissionWindowController?
    private let watcher = Watcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(onShowPermissions: { [weak self] in self?.permissions?.show() })
        permissions = PermissionWindowController(onGranted: { [weak self] in
            ExitRecorder.ensureAttached()
            self?.menuBar?.refreshIcon()
        })
        NotificationCenter.default.addObserver(forName: AppLanguage.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.permissions?.languageChanged()
        }
        watcher.start()
        if !AXIsProcessTrusted() { permissions?.show() }
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
