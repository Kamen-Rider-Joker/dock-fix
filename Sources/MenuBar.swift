import AppKit
import ServiceManagement

let repositoryURL = URL(string: "https://github.com/LLP2333/dockUnstick")!

/// Menu bar item: running state, fix statistics and a few actions.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onShowPermissions: () -> Void

    init(onShowPermissions: @escaping () -> Void) {
        self.onShowPermissions = onShowPermissions
        super.init()
        menu.delegate = self
        item.menu = menu
        refreshIcon()
        NotificationCenter.default.addObserver(forName: FixStats.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshIcon()
        }
    }

    func refreshIcon() {
        let symbol = AXIsProcessTrusted() ? "dock.arrow.down.rectangle" : "exclamationmark.triangle"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DockUnstick")
        item.button?.toolTip = "DockUnstick：已修复 \(FixStats.shared.total) 次"
    }

    // Rebuilt every time it opens so the numbers are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshIcon()
        menu.removeAllItems()
        let stats = FixStats.shared

        if AXIsProcessTrusted() {
            menu.addItem(label("DockUnstick 正在运行"))
        } else {
            menu.addItem(action("⚠️ 需要辅助功能权限…", #selector(showPermissions)))
        }
        menu.addItem(.separator())

        menu.addItem(label("已修复 \(stats.total) 次（今天 \(stats.today) 次）"))
        if let last = stats.lastFix {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            menu.addItem(label("上次修复：\(formatter.localizedString(for: last, relativeTo: Date()))"))
        }
        if stats.failed > 0 {
            menu.addItem(label("未能修复 \(stats.failed) 次"))
        }
        menu.addItem(.separator())

        let login = action("登录时自动启动", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(action("打开日志", #selector(openLog)))
        menu.addItem(action("重置统计", #selector(resetStats)))
        menu.addItem(action("项目主页", #selector(openRepository)))
        menu.addItem(.separator())
        menu.addItem(action("退出 DockUnstick", #selector(quit), key: "q"))
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showPermissions() { onShowPermissions() }
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            log("login item: \(error.localizedDescription)")
        }
        // The user may still have to allow it under Login Items.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        log("login item status: \(service.status.rawValue)")
    }

    @objc private func openLog() { NSWorkspace.shared.open(logURL) }
    @objc private func resetStats() { FixStats.shared.reset() }
    @objc private func openRepository() { NSWorkspace.shared.open(repositoryURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
