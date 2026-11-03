import Foundation
import ServiceManagement

let repositoryURL = URL(string: "https://github.com/LLP2333/dockUnstick")!

enum Preferences {
    static let didChange = Notification.Name("PreferencesDidChange")

    /// Whether the menu bar icon is shown. Off by default; the main window is
    /// always reachable by opening the app again.
    static var showMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "showMenuBar") }
        set {
            UserDefaults.standard.set(newValue, forKey: "showMenuBar")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// Login item through SMAppService.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            log("login item: \(error.localizedDescription)")
        }
        // The user may still have to allow it under Login Items.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        log("login item status: \(service.status.rawValue)")
        NotificationCenter.default.post(name: Preferences.didChange, object: nil)
    }
}
