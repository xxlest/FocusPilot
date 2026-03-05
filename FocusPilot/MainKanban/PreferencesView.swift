import SwiftUI
import ServiceManagement

/// 偏好设置页面
/// 快捷键配置、主题选择、外观设置、通用设置
struct PreferencesView: View {
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hotkeySection
                themeSection
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
                hotkeyRow(label: "主看板", config: $configStore.preferences.hotkeyKanban)
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

    // MARK: - 主题选择

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("主题")
                .font(.headline)

            // 浅色主题
            Text("浅色")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.lightThemes, id: \.self) { theme in
                    themeCard(theme)
                }
            }

            // 深色主题
            Text("深色")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.darkThemes, id: \.self) { theme in
                    themeCard(theme)
                }
            }
        }
    }

    /// 主题卡片预览
    private func themeCard(_ theme: AppTheme) -> some View {
        let isSelected = configStore.preferences.appTheme == theme
        let colors = theme.colors

        return VStack(spacing: 0) {
            // 预览区域
            VStack(alignment: .leading, spacing: 4) {
                // 模拟文本行
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.swTextPrimary)
                    .frame(width: 60, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.swTextSecondary)
                    .frame(width: 45, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.swTextTertiary)
                    .frame(width: 35, height: 3)

                HStack(spacing: 4) {
                    // 强调色圆点
                    Circle()
                        .fill(colors.swAccent)
                        .frame(width: 8, height: 8)
                    // 收藏星标色
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(colors.swFavoriteStar)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.swBackground)

            // 主题名称
            Text(theme.displayName)
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? colors.swAccent : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? colors.swAccent.opacity(0.3) : .clear, radius: 4)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onTapGesture {
            configStore.preferences.appTheme = theme
        }
    }

    // MARK: - 外观

    private var ballAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观")
                .font(.headline)

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

            // 面板弹出动画速度滑块
            HStack {
                Text("弹出动画")
                    .frame(width: 100, alignment: .leading)
                Slider(
                    value: $configStore.preferences.panelAnimationSpeed,
                    in: 0.1...0.6,
                    step: 0.05
                )
                Text("\(Int(configStore.preferences.panelAnimationSpeed * 1000))ms")
                    .frame(width: 50)
                    .foregroundStyle(.secondary)
            }
        }
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
