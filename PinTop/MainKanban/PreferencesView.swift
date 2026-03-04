import SwiftUI
import ServiceManagement

/// 偏好设置页面
/// 快捷键配置、外观设置、通用设置
struct PreferencesView: View {
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hotkeySection
                ballAppearanceSection
                generalSection
            }
            .padding()
        }
        .navigationTitle("")
        .onDisappear {
            configStore.save()
        }
    }

    // MARK: - 快捷键配置

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.headline)

            VStack(spacing: 8) {
                hotkeyRow(label: "显示/隐藏", config: $configStore.preferences.hotkeyToggle)
            }
        }
    }

    /// 快捷键行：标签 + 可点击录制的快捷键按钮
    private func hotkeyRow(label: String, config: Binding<HotkeyConfig>) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)

            HotkeyRecorderButton(config: config)

            Spacer()
        }
    }

    // MARK: - 外观

    private var ballAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观")
                .font(.headline)

            // 悬浮球颜色风格
            HStack {
                Text("悬浮球颜色")
                    .frame(width: 100, alignment: .leading)

                // 预置颜色圆点 + 自定义
                HStack(spacing: 6) {
                    ForEach(BallColorStyle.allCases.filter { $0 != .custom }, id: \.self) { style in
                        let isSelected = configStore.preferences.ballColorStyle == style
                        Circle()
                            .fill(Color(nsColor: style.gradientColors.medium))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                    .padding(2)
                            )
                            .shadow(color: isSelected ? Color.accentColor.opacity(0.5) : .clear, radius: 3)
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                            .onTapGesture {
                                configStore.preferences.ballColorStyle = style
                            }
                            .help(style.rawValue)
                    }

                    // 自定义颜色：圆形色块 + 点击弹出取色器
                    let isCustomSelected = configStore.preferences.ballColorStyle == .custom
                    ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isCustomSelected ? Color.white : Color.clear, lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(isCustomSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                .padding(2)
                        )
                        .shadow(color: isCustomSelected ? Color.accentColor.opacity(0.5) : .clear, radius: 3)
                        .help("自定义颜色")
                }
                Spacer()
            }

            // 悬浮球大小滑块
            HStack {
                Text("悬浮球大小")
                    .frame(width: 100, alignment: .leading)
                Slider(
                    value: $configStore.preferences.ballSize,
                    in: Constants.Ball.minSize...Constants.Ball.maxSize,
                    step: 1
                )
                Text("\(Int(configStore.preferences.ballSize))px")
                    .frame(width: 50)
                    .foregroundStyle(.secondary)
            }

            // 悬浮球透明度滑块
            HStack {
                Text("悬浮球透明度")
                    .frame(width: 100, alignment: .leading)
                Slider(
                    value: $configStore.preferences.ballOpacity,
                    in: 0.3...1.0,
                    step: 0.05
                )
                Text("\(Int(configStore.preferences.ballOpacity * 100))%")
                    .frame(width: 50)
                    .foregroundStyle(.secondary)
            }

            // 面板透明度滑块
            HStack {
                Text("面板透明度")
                    .frame(width: 100, alignment: .leading)
                Slider(
                    value: $configStore.preferences.panelOpacity,
                    in: 0.3...1.0,
                    step: 0.05
                )
                Text("\(Int(configStore.preferences.panelOpacity * 100))%")
                    .frame(width: 50)
                    .foregroundStyle(.secondary)
            }

            // 颜色主题
            HStack {
                Text("颜色主题")
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $configStore.preferences.colorTheme) {
                    ForEach(ColorTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
            }
        }
    }

    // MARK: - 自定义颜色绑定

    private var customColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                if let nsColor = NSColor.fromHex(configStore.preferences.ballCustomColorHex) {
                    return Color(nsColor: nsColor)
                }
                return Color.orange
            },
            set: { newColor in
                let nsColor = NSColor(newColor)
                configStore.preferences.ballCustomColorHex = nsColor.hexString
                configStore.preferences.ballColorStyle = .custom
            }
        )
    }

    // MARK: - 通用设置

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通用")
                .font(.headline)

            Toggle("hover 离开后自动收起面板", isOn: $configStore.preferences.autoRetractOnHover)

            // 开机自启动
            Toggle("开机自启动", isOn: $configStore.preferences.launchAtLogin)
                .onChange(of: configStore.preferences.launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }
        }
    }
}

// MARK: - 快捷键录制按钮

/// 点击进入录制模式，按下任意键组合完成录制
struct HotkeyRecorderButton: View {
    @Binding var config: HotkeyConfig
    @State private var isRecording = false
    /// 持有当前监听器引用（视图销毁时清理，防止泄漏）
    @State private var activeMonitor: Any?

    var body: some View {
        Button(action: { startRecording() }) {
            Text(isRecording ? "按下快捷键..." : config.displayString)
                .frame(width: 120)
                .padding(.vertical, 4)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .cornerRadius(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(isRecording ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onDisappear {
            // 视图销毁时清理未完成的监听器（防止泄漏）
            if let m = activeMonitor {
                NSEvent.removeMonitor(m)
                activeMonitor = nil
                isRecording = false
            }
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        // 安装 NSEvent 本地监听器，捕获下一个键盘事件
        activeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // 获取修饰键（至少需要一个修饰键）
            let carbonMods = HotkeyConfig.carbonModifiers(from: event.modifierFlags)
            guard carbonMods != 0 else {
                // Esc 单独按下时取消录制
                if event.keyCode == 0x35 {
                    self.isRecording = false
                    if let m = self.activeMonitor { NSEvent.removeMonitor(m) }
                    self.activeMonitor = nil
                    return nil
                }
                return nil // 忽略无修饰键的按键
            }

            // 录制成功
            self.config = HotkeyConfig(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
            self.isRecording = false
            if let m = self.activeMonitor { NSEvent.removeMonitor(m) }
            self.activeMonitor = nil
            return nil // 吃掉该事件
        }
    }
}
