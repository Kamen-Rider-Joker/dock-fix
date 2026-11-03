import AppKit

/// This background app shows no menu bar, but key equivalents still go through the
/// main menu: ⌘Q and ⌘W close the front window and leave DockUnstick running.
final class KeyCommands: NSObject {
    static let shared = KeyCommands()

    func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        for key in ["q", "w"] {
            let item = NSMenuItem(title: "Close Window", action: #selector(closeFrontWindow(_:)), keyEquivalent: key)
            item.target = self
            appMenu.addItem(item)
        }
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        return mainMenu
    }

    @objc func closeFrontWindow(_ sender: Any?) {
        let window = NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.styleMask.contains(.closable) }
        window?.performClose(sender)
    }
}
