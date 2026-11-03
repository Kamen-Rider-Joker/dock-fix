import AppKit
import SwiftUI

/// The status item is the app's only primary surface. Clicking it reveals an
/// anchored, transient panel instead of creating a regular application window.
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let model: MainModel
    private var refreshTimer: Timer?

    init(onShowPermissions: @escaping () -> Void) {
        model = MainModel(onShowPermissions: onShowPermissions)
        super.init()

        let statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageOnly
        item = statusItem

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 410, height: 650)
        popover.contentViewController = NSHostingController(rootView: MainView(model: model))

        refreshIcon()
        for name in [
            FixStats.didChange,
            AppLanguage.didChange,
            AccessibilityPermission.didChange,
            Preferences.didChange
        ] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.model.refresh()
                self?.refreshIcon()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    func showPanel() {
        guard let button = item?.button else { return }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startRefreshTimer()
        log("menu panel: opened")
    }

    func refreshIcon() {
        guard let button = item?.button else { return }
        button.image = Preferences.menuBarIcon.image()
        button.toolTip = L(
            "DockUnstick：已修复 \(FixStats.shared.total) 次",
            "DockUnstick: fixed \(FixStats.shared.total) times"
        )
        button.setAccessibilityLabel(L("打开 DockUnstick", "Open DockUnstick"))
    }

    func popoverDidClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.model.refresh()
        }
    }
}
