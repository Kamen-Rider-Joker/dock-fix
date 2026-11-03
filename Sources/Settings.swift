import Foundation
import ServiceManagement

let repositoryURL = URL(string: "https://github.com/LLP2333/dockUnstick")!

enum Preferences {
    static let didChange = Notification.Name("PreferencesDidChange")

    static var menuBarIcon: MenuBarIconStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: "menuBarIcon") ?? ""
            return MenuBarIconStyle(rawValue: raw) ?? .original
        }
        set {
            guard newValue != menuBarIcon else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarIcon")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// File logging is opt-in. Diagnostic command-line modes bypass this flag.
    static var loggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "loggingEnabled") }
        set {
            guard newValue != loggingEnabled else { return }
            UserDefaults.standard.set(newValue, forKey: "loggingEnabled")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static let retryCountRange = 0...5
    static let retryIntervalRange = 0.1...1.0

    /// How many times the Dock is checked again after the first check, when that
    /// check could not confirm the Dock is fine. Read at every Space change.
    static var retryCount: Int {
        get { (UserDefaults.standard.object(forKey: "retryCount") as? Int ?? 3).clamped(to: retryCountRange) }
        set {
            let value = newValue.clamped(to: retryCountRange)
            guard value != retryCount else { return }
            UserDefaults.standard.set(value, forKey: "retryCount")
            log("retry count: \(value)")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Seconds between those checks, in steps of 0.1.
    static var retryInterval: Double {
        get { (UserDefaults.standard.object(forKey: "retryInterval") as? Double ?? 0.5).clamped(to: retryIntervalRange) }
        set {
            let value = ((newValue * 10).rounded() / 10).clamped(to: retryIntervalRange)
            guard value != retryInterval else { return }
            UserDefaults.standard.set(value, forKey: "retryInterval")
            log("retry interval: \(value)s")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
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
