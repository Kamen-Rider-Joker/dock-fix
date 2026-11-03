import AppKit
import ApplicationServices

/// Owns the Accessibility permission flow so the app never opens duplicate
/// authorization windows and notices when access is granted while it is running.
enum AccessibilityPermission {
    static let didChange = Notification.Name("AccessibilityPermissionDidChange")

    private static let defaults = UserDefaults.standard
    private static let promptKey = "permission.systemPromptShown"
    private static var timer: Timer?
    private static var lastTrusted = AXIsProcessTrusted()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func startMonitoring() {
        evaluate()
        guard !lastTrusted, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            evaluate()
        }
    }

    /// Cheap status refresh at natural checkpoints such as a Space change.
    static func checkNow() {
        evaluate()
    }

    /// Show the system prompt once. Later requests go straight to the
    /// Accessibility list, which avoids repeatedly surfacing the same prompt.
    static func request() {
        guard !isTrusted else { return }
        if defaults.bool(forKey: promptKey) {
            openAccessibilitySettings()
        } else {
            defaults.set(true, forKey: promptKey)
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
        }
        startMonitoring()
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    private static func evaluate() {
        let trusted = isTrusted
        guard trusted != lastTrusted else { return }
        lastTrusted = trusted
        log("accessibility permission changed to \(trusted)")
        if trusted {
            timer?.invalidate()
            timer = nil
        }
        ExitRecorder.ensureAttached()
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
