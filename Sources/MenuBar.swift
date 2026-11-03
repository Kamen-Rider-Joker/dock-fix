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
        for name in [FixStats.didChange, AppLanguage.didChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshIcon()
            }
        }
    }

    func refreshIcon() {
        let symbol = AXIsProcessTrusted() ? "dock.arrow.down.rectangle" : "exclamationmark.triangle"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DockUnstick")
        item.button?.toolTip = L("DockUnstick：已修复 \(FixStats.shared.total) 次", "DockUnstick: fixed \(FixStats.shared.total) times")
    }

    // Rebuilt every time it opens so the numbers are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshIcon()
        menu.removeAllItems()
        let stats = FixStats.shared

        if AXIsProcessTrusted() {
            menu.addItem(label(L("DockUnstick 正在运行", "DockUnstick is running")))
        } else {
            menu.addItem(action(L("⚠️ 需要辅助功能权限…", "⚠️ Accessibility permission needed…"), #selector(showPermissions)))
        }
        menu.addItem(.separator())

        menu.addItem(label(L("已修复 \(stats.total) 次（今天 \(stats.today) 次）", "Fixed \(stats.total) times (\(stats.today) today)")))
        if let last = stats.lastFix {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = AppLanguage.locale
            let ago = formatter.localizedString(for: last, relativeTo: Date())
            menu.addItem(label(L("上次修复：\(ago)", "Last fix: \(ago)")))
        }
        if stats.failed > 0 {
            menu.addItem(label(L("未能修复 \(stats.failed) 次", "Failed \(stats.failed) times")))
        }
        menu.addItem(.separator())

        let login = action(L("登录时自动启动", "Launch at Login"), #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(languageMenu())
        menu.addItem(action(L("打开日志", "Open Log"), #selector(openLog)))
        menu.addItem(action(L("重置统计", "Reset Statistics"), #selector(resetStats)))
        menu.addItem(action(L("项目主页", "Project Page"), #selector(openRepository)))
        menu.addItem(.separator())
        menu.addItem(action(L("退出 DockUnstick", "Quit DockUnstick"), #selector(quit), key: "q"))
    }

    private func languageMenu() -> NSMenuItem {
        let submenu = NSMenu()
        // Language names stay in their own language so either one can be found.
        let choices: [(AppLanguage, String)] = [(.system, L("跟随系统", "Same as System")), (.zh, "中文"), (.en, "English")]
        for (language, title) in choices {
            let choice = action(title, #selector(selectLanguage(_:)))
            choice.representedObject = language.rawValue
            choice.state = AppLanguage.setting == language ? .on : .off
            submenu.addItem(choice)
        }
        let item = NSMenuItem(title: L("语言", "Language"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
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

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        AppLanguage.setting = language
    }

    @objc private func openLog() { NSWorkspace.shared.open(logURL) }
    @objc private func resetStats() { FixStats.shared.reset() }
    @objc private func openRepository() { NSWorkspace.shared.open(repositoryURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
