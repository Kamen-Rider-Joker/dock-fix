import AppKit
import SwiftUI

/// The window shown when DockUnstick is opened: status, fix statistics and settings.
final class MainWindowController {
    private var window: NSWindow?
    private var timer: Timer?
    private let model: MainModel

    init(onShowPermissions: @escaping () -> Void) {
        model = MainModel(onShowPermissions: onShowPermissions)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(model: model)))
            window.title = "DockUnstick"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Keeps the permission state and "last fix" time current while open.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.window?.isVisible == true { self.model.refresh() } else { self.timer?.invalidate() }
        }
    }
}

final class MainModel: ObservableObject {
    @Published var trusted = false
    @Published var total = 0
    @Published var today = 0
    @Published var failed = 0
    @Published var lastFix: Date?
    @Published var showMenuBar = false
    @Published var launchAtLogin = false
    @Published var language = AppLanguage.system
    @Published var retryCount = 0
    @Published var retryInterval = 0.0

    let showPermissions: () -> Void

    init(onShowPermissions: @escaping () -> Void) {
        showPermissions = onShowPermissions
        for name in [FixStats.didChange, AppLanguage.didChange, Preferences.didChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let stats = FixStats.shared
        trusted = AXIsProcessTrusted()
        total = stats.total
        today = stats.today
        failed = stats.failed
        lastFix = stats.lastFix
        showMenuBar = Preferences.showMenuBar
        launchAtLogin = LaunchAtLogin.isEnabled
        language = AppLanguage.setting
        retryCount = Preferences.retryCount
        retryInterval = Preferences.retryInterval
    }
}

struct MainView: View {
    @ObservedObject var model: MainModel

    // GroupBoxes rather than a Form: a Form scrolls and reports no height of its
    // own, which collapses it to nothing inside the window.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GroupBox(L("修复统计", "Statistics")) {
                VStack(spacing: 8) {
                    row(L("累计修复", "Total fixes"), "\(model.total)")
                    row(L("今天", "Today"), "\(model.today)")
                    row(L("上次修复", "Last fix"), lastFixText)
                    if model.failed > 0 {
                        row(L("未能修复", "Failed"), "\(model.failed)")
                    }
                    HStack {
                        Spacer()
                        Button(L("重置统计", "Reset Statistics")) { FixStats.shared.reset() }
                    }
                }
                .padding(8)
            }
            GroupBox(L("设置", "Settings")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(L("在菜单栏显示图标", "Show icon in menu bar"), isOn: Binding(
                        get: { model.showMenuBar },
                        set: { Preferences.showMenuBar = $0 }))
                    Toggle(L("登录时自动启动", "Launch at login"), isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { LaunchAtLogin.set($0) }))
                    // Language names stay in their own language so either one can be found.
                    Picker(L("语言", "Language"), selection: Binding(
                        get: { model.language },
                        set: { AppLanguage.setting = $0 })) {
                        Text(L("跟随系统", "Same as System")).tag(AppLanguage.system)
                        Text("中文").tag(AppLanguage.zh)
                        Text("English").tag(AppLanguage.en)
                    }
                    .fixedSize()
                    retries
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            footer
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Sliders write as they move, so a change applies from the next Space switch.
    private var retries: some View {
        VStack(alignment: .leading, spacing: 4) {
            slider(L("重试次数", "Retries"),
                   value: Binding(get: { Double(model.retryCount) }, set: { Preferences.retryCount = Int($0.rounded()) }),
                   range: Double(Preferences.retryCountRange.lowerBound)...Double(Preferences.retryCountRange.upperBound),
                   step: 1,
                   text: L("\(model.retryCount) 次", "\(model.retryCount)"))
            slider(L("重试间隔", "Interval"),
                   value: Binding(get: { model.retryInterval }, set: { Preferences.retryInterval = $0 }),
                   range: Preferences.retryIntervalRange,
                   step: 0.1,
                   text: L("\(String(format: "%.1f", model.retryInterval)) 秒", "\(String(format: "%.1f", model.retryInterval)) s"))
            Text(L("切换 Space 后立即检查 Dock；没能确认 Dock 正常（鼠标还在 Dock 上或修复没生效）时，按间隔再检查",
                   "The Dock is checked right after a Space switch, and again at this interval while it can't be confirmed fine (cursor still on it, or a fix didn't take)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("DockUnstick").font(.title2.bold())
                if model.trusted {
                    Label(L("正在运行，会自动修复卡住的 Dock", "Running. A stuck Dock is fixed automatically"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(L("需要辅助功能权限", "Accessibility permission needed"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button(L("授权…", "Grant…"), action: model.showPermissions)
                }
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button(L("打开日志", "Open Log")) { NSWorkspace.shared.open(logURL) }
            Button(L("项目主页", "Project Page")) { NSWorkspace.shared.open(repositoryURL) }
            Spacer()
            Button(L("退出 DockUnstick", "Quit DockUnstick")) { NSApp.terminate(nil) }
        }
    }

    private var lastFixText: String {
        guard let last = model.lastFix else { return L("暂无", "Never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.locale
        return formatter.localizedString(for: last, relativeTo: Date())
    }
}
