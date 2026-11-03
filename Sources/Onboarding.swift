import AppKit
import SwiftUI

/// Explains why Accessibility is needed, walks through granting it, and notices
/// the moment it is granted.
final class PermissionWindowController {
    private var window: NSWindow?
    private var timer: Timer?
    private let model = PermissionModel()
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: makeContent())
            window.title = "DockUnstick"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.granted = AXIsProcessTrusted()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startPolling()
    }

    private func makeContent() -> NSViewController {
        NSHostingController(rootView: PermissionView(model: model, openSettings: openSettings, close: { [weak self] in self?.close() }))
    }

    /// Re-render in the new language if the window is open.
    func languageChanged() {
        window?.contentViewController = makeContent()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.model.granted, AXIsProcessTrusted() else { return }
            self.model.granted = true
            self.timer?.invalidate()
            log("accessibility granted")
            self.onGranted()
        }
    }

    private func openSettings() {
        // Prompting also adds DockUnstick to the Accessibility list.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func close() {
        timer?.invalidate()
        window?.close()
    }
}

final class PermissionModel: ObservableObject {
    @Published var granted = false
}

struct PermissionView: View {
    @ObservedObject var model: PermissionModel
    let openSettings: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("DockUnstick 需要辅助功能权限", "DockUnstick needs Accessibility permission")).font(.title2.bold())
                    Text(L("用于修复切换全屏空间后 Dock 卡住、不自动收回的问题。",
                           "It fixes the Dock getting stuck and not hiding after switching full-screen Spaces."))
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox(L("权限用途", "What it is used for")) {
                VStack(alignment: .leading, spacing: 6) {
                    bullet(L("读取 Dock 的状态，判断它是否卡住", "Reading the Dock's state to tell whether it is stuck"))
                    bullet(L("接收发给 Dock 的“鼠标离开”事件，在它丢失时补发一次",
                             "Receiving the Dock's \"mouse exited\" events and re-sending one the Dock dropped"))
                    bullet(L("不读取屏幕内容、不移动鼠标、不联网", "It never reads the screen, moves the cursor or goes online"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox(L("授权步骤", "How to grant it")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("1. 点击下方「打开系统设置」", "1. Click \"Open System Settings\" below"))
                    Text(L("2. 在「辅助功能」列表中打开 DockUnstick 的开关", "2. Turn on DockUnstick in the Accessibility list"))
                    Text(L("3. 如果开关已打开、这里仍显示等待：用 − 删除 DockUnstick，再用 + 重新添加（更新程序后常见）",
                           "3. If it is already on but this window keeps waiting, remove DockUnstick with − and add it again with + (common after an update)"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                if model.granted {
                    Label(L("已授权，DockUnstick 正在运行", "Granted. DockUnstick is running"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button(L("完成", "Done"), action: close).keyboardShortcut(.defaultAction)
                } else {
                    Label(L("等待授权…", "Waiting for permission…"), systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("打开系统设置", "Open System Settings"), action: openSettings).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "checkmark").labelStyle(.titleAndIcon)
    }
}
