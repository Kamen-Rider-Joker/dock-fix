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
            let view = PermissionView(model: model, openSettings: openSettings, close: { [weak self] in self?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
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
                    Text("DockUnstick 需要辅助功能权限").font(.title2.bold())
                    Text("用于修复切换全屏空间后 Dock 卡住、不自动收回的问题。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("权限用途") {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("读取 Dock 的状态，判断它是否卡住")
                    bullet("接收发给 Dock 的“鼠标离开”事件，在它丢失时补发一次")
                    bullet("不读取屏幕内容、不移动鼠标、不联网")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("授权步骤") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 点击下方「打开系统设置」")
                    Text("2. 在「辅助功能」列表中打开 DockUnstick 的开关")
                    Text("3. 如果开关已打开、这里仍显示等待：用 − 删除 DockUnstick，再用 + 重新添加（更新程序后常见）")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                if model.granted {
                    Label("已授权，DockUnstick 正在运行", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("完成", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Label("等待授权…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开系统设置", action: openSettings).keyboardShortcut(.defaultAction)
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
