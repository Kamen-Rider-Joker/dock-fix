import AppKit
import SwiftUI

final class MainModel: ObservableObject {
    @Published var trusted = false
    @Published var total = 0
    @Published var today = 0
    @Published var failed = 0
    @Published var lastFix: Date?
    @Published var history: [FixHistoryDay] = []
    @Published var menuBarIcon = MenuBarIconStyle.original
    @Published var launchAtLogin = false
    @Published var language = AppLanguage.system
    @Published var retryCount = 0
    @Published var retryInterval = 0.0
    @Published var loggingEnabled = false

    let showPermissions: () -> Void

    init(onShowPermissions: @escaping () -> Void) {
        showPermissions = onShowPermissions
        for name in [
            FixStats.didChange,
            AppLanguage.didChange,
            AccessibilityPermission.didChange,
            Preferences.didChange
        ] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        let stats = FixStats.shared
        trusted = AccessibilityPermission.isTrusted
        total = stats.total
        today = stats.today
        failed = stats.failed
        lastFix = stats.lastFix
        history = stats.recentHistory
        menuBarIcon = Preferences.menuBarIcon
        launchAtLogin = LaunchAtLogin.isEnabled
        language = AppLanguage.setting
        retryCount = Preferences.retryCount
        retryInterval = Preferences.retryInterval
        loggingEnabled = Preferences.loggingEnabled
    }

    var successRate: Int? {
        let attempts = total + failed
        guard attempts > 0 else { return nil }
        return Int((Double(total) / Double(attempts) * 100).rounded())
    }

    var rescueRank: String {
        switch total {
        case 0: return L("待命队员", "On standby")
        case 1..<10: return L("Dock 学徒", "Dock apprentice")
        case 10..<30: return L("空间旅人", "Space traveler")
        case 30..<100: return L("救援专家", "Rescue expert")
        default: return L("传说守卫", "Legendary guard")
        }
    }

    var streak: Int {
        history.reversed().prefix { $0.count > 0 }.count
    }
}

struct MainView: View {
    @ObservedObject var model: MainModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .center
            )

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        rescueCard
                        weekCard
                        repairPacingCard
                        settingsCard
                        footer
                    }
                    .padding(18)
                }
            }
        }
        .frame(width: 410, height: 650)
        .confirmationDialog(
            L("要清空全部救援记录吗？", "Reset all rescue statistics?"),
            isPresented: $confirmReset
        ) {
            Button(L("重置统计", "Reset Statistics"), role: .destructive) {
                FixStats.shared.reset()
            }
            Button(L("取消", "Cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("DockUnstick")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                statusPill
            }

            Spacer()

            if !model.trusted {
                Button(L("授权…", "Grant…"), action: model.showPermissions)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button {
                    LaunchAtLogin.set(!model.launchAtLogin)
                } label: {
                    Image(systemName: model.launchAtLogin ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 25, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.launchAtLogin ? Color.accentColor : Color.secondary)
                .accessibilityLabel(L("登录时自动启动", "Launch at login"))
                .accessibilityValue(model.launchAtLogin ? L("已开启", "On") : L("已关闭", "Off"))
                .help(L(model.launchAtLogin ? "关闭登录时启动" : "登录时自动启动",
                        model.launchAtLogin ? "Disable launch at login" : "Launch at login"))
            }
        }
    }

    private var statusPill: some View {
        let color = model.trusted ? Color.green : Color.orange
        let text = model.trusted
            ? L("后台守护中", "Watching in the background")
            : L("需要辅助功能权限", "Accessibility needed")
        return Label(text, systemImage: model.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var rescueCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(L("今日 Dock 救援", "Today's Dock rescues"), dot: .blue)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(model.today)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(L("次", "fixes"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(rescueMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.13))
                    Circle()
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                        .padding(7)
                    Image(systemName: rescueSymbol)
                        .font(.system(size: 27, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 74, height: 74)
            }

            HStack(spacing: 10) {
                Label(model.rescueRank, systemImage: "rosette")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())

                Spacer()

                if model.streak > 1 {
                    Label(L("连续 \(model.streak) 天", "\(model.streak)-day streak"), systemImage: "flame.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack(spacing: 12) {
                metric(L("累计救援", "Total"), "\(model.total)")
                Divider().frame(height: 26)
                metric(L("成功率", "Success"), model.successRate.map { "\($0)%" } ?? "—")
                Divider().frame(height: 26)
                metric(L("上次修复", "Last fix"), lastFixText)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.07))
        }
        .animation(motion, value: model.today)
        .animation(motion, value: model.total)
    }

    private var weekCard: some View {
        panel(
            gradient: [Color.green.opacity(0.15), Color.mint.opacity(0.055)],
            stroke: Color.green.opacity(0.14)
        ) {
            HStack {
                sectionHeader(L("这周战报", "This week"), dot: .green)
                Spacer()
                Text(L("\(weekTotal) 次接住", "\(weekTotal) rescues"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(model.history) { day in
                    VStack(spacing: 4) {
                        Text(day.count > 0 ? "\(day.count)" : "·")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.primary.opacity(0.055))
                            Capsule()
                                .fill(isToday(day) ? Color.accentColor : Color.secondary.opacity(0.42))
                                .frame(height: barHeight(for: day.count))
                        }
                        .frame(width: 18, height: 43)

                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 10, weight: isToday(day) ? .semibold : .regular))
                            .foregroundStyle(isToday(day) ? Color.accentColor : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(day.date.formatted(date: .abbreviated, time: .omitted)): \(L("\(day.count) 次修复", "\(day.count) fixes"))"
                    )
                }
            }
            .frame(height: 72, alignment: .bottom)
            .animation(motion, value: model.history.map(\.count))
        }
    }

    private var settingsCard: some View {
        panel(
            gradient: [Color.purple.opacity(0.14), Color.blue.opacity(0.045)],
            stroke: Color.purple.opacity(0.13)
        ) {
            HStack {
                sectionHeader(L("个性化设置", "Personalization"), dot: .purple)
                Spacer()
            }

            settingsRow(L("菜单栏图标", "Menu bar icon"), systemImage: "menubar.rectangle") {
                Menu {
                    ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                        Button {
                            Preferences.menuBarIcon = style
                        } label: {
                            Label {
                                Text(style == model.menuBarIcon ? "\(style.title)  ✓" : style.title)
                            } icon: {
                                Image(nsImage: style.menuPreview)
                            }
                        }
                        // Keep the project's original icon visually separate
                        // from the optional playful alternatives.
                        if style == .original {
                            Divider()
                        }
                    }
                } label: {
                    Label {
                        Text(model.menuBarIcon.title)
                            .lineLimit(1)
                    } icon: {
                        Image(nsImage: model.menuBarIcon.menuPreview)
                    }
                }
                .menuStyle(.borderlessButton)
            }

            settingsRow(L("语言", "Language"), systemImage: "character.bubble") {
                Menu {
                    Button(L("跟随系统", "Same as System")) { AppLanguage.setting = .system }
                    Button("中文") { AppLanguage.setting = .zh }
                    Button("English") { AppLanguage.setting = .en }
                } label: {
                    Text(languageTitle)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
            }

            settingsRow(L("记录日志", "Write logs"), systemImage: "doc.text.magnifyingglass") {
                Toggle("", isOn: Binding(
                    get: { model.loggingEnabled },
                    set: { Preferences.loggingEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var repairPacingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(L("修复节奏", "Repair pacing"), dot: .orange)
                Spacer()
                Text(L("自动检查", "Automatic checks"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            retries
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.15), Color.pink.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.15))
        }
    }

    private var retries: some View {
        VStack(alignment: .leading, spacing: 8) {
            slider(
                L("检查次数", "Checks"),
                systemImage: "arrow.triangle.2.circlepath",
                value: Binding(
                    get: { Double(model.retryCount) },
                    set: { Preferences.retryCount = Int($0.rounded()) }
                ),
                range: Double(Preferences.retryCountRange.lowerBound)...Double(Preferences.retryCountRange.upperBound),
                step: 1,
                text: L("\(model.retryCount) 次", "\(model.retryCount)")
            )
            slider(
                L("检查间隔", "Interval"),
                systemImage: "timer",
                value: Binding(
                    get: { model.retryInterval },
                    set: { Preferences.retryInterval = $0 }
                ),
                range: Preferences.retryIntervalRange,
                step: 0.1,
                text: L("\(String(format: "%.1f", model.retryInterval)) 秒",
                        "\(String(format: "%.1f", model.retryInterval)) s")
            )
            Text(L("切换 Space 后会立即检查；需要时再按这个节奏确认。",
                   "The Dock is checked immediately after a Space switch, then again only if needed."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                NSWorkspace.shared.open(logURL)
            } label: {
                Label(L("日志", "Log"), systemImage: "doc.text.magnifyingglass")
            }

            Button {
                NSWorkspace.shared.open(repositoryURL)
            } label: {
                Label(L("主页", "Project"), systemImage: "safari")
            }

            Spacer()

            Menu {
                Button(L("重置统计", "Reset Statistics")) { confirmReset = true }
                Divider()
                Button(L("退出 DockUnstick", "Quit DockUnstick")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    private func slider(
        _ title: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        text: String
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(text)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }

    private func panel<Content: View>(
        gradient: [Color],
        stroke: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(stroke)
        }
    }

    private func sectionHeader(_ title: String, dot: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    private func settingsRow<Control: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            control()
                .frame(width: 166, alignment: .trailing)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1)
    }

    private var languageTitle: String {
        switch model.language {
        case .system: return L("跟随系统", "Same as System")
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    private var rescueSymbol: String {
        if !model.trusted { return "lock.shield.fill" }
        return model.today > 0 ? "checkmark.seal.fill" : "shield.fill"
    }

    private var rescueMessage: String {
        if !model.trusted {
            return L("开启辅助功能后，我来替你盯着 Dock。", "Grant access and I'll keep an eye on the Dock.")
        }
        switch model.today {
        case 0:
            return L("今天风平浪静，Dock 很安分。", "All calm today. The Dock is behaving.")
        case 1...2:
            return L("稳稳接住，没有让它赖着不走。", "Caught it cleanly, no lingering.")
        default:
            return L("Dock 今天有点黏人，交给我。", "The Dock is clingy today. I've got it.")
        }
    }

    private var weekTotal: Int {
        model.history.reduce(0) { $0 + $1.count }
    }

    private func barHeight(for count: Int) -> CGFloat {
        let maximum = max(1, model.history.map(\.count).max() ?? 0)
        return max(4, 43 * CGFloat(count) / CGFloat(maximum))
    }

    private func isToday(_ day: FixHistoryDay) -> Bool {
        Calendar.current.isDateInToday(day.date)
    }

    private var lastFixText: String {
        guard let last = model.lastFix else { return L("暂无", "Never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.locale
        return formatter.localizedString(for: last, relativeTo: Date())
    }
}
