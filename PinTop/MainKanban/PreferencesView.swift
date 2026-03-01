import SwiftUI
import ServiceManagement

/// 偏好设置页面
/// 快捷键配置、悬浮球外观、通用设置
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
        .navigationTitle("偏好设置")
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
                hotkeyRow(label: "Pin/Unpin 当前窗口", value: $configStore.preferences.hotkeyPinToggle)
                hotkeyRow(label: "悬浮球显隐", value: $configStore.preferences.hotkeyBallToggle)
            }
        }
    }

    /// 快捷键行：标签 + 当前值（只读显示）
    /// TODO: V1.1 支持自定义快捷键（需实现 NSEvent 监听 + keyCode 映射）
    private func hotkeyRow(label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .leading)

            Text(value.wrappedValue)
                .frame(width: 120)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - 悬浮球外观

    private var ballAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("悬浮球外观")
                .font(.headline)

            // 大小滑块
            HStack {
                Text("大小")
                    .frame(width: 80, alignment: .leading)
                Slider(
                    value: $configStore.preferences.ballSize,
                    in: Constants.Ball.minSize...Constants.Ball.maxSize,
                    step: 1
                )
                Text("\(Int(configStore.preferences.ballSize))px")
                    .frame(width: 50)
                    .foregroundStyle(.secondary)
            }

            // 透明度滑块
            HStack {
                Text("透明度")
                    .frame(width: 80, alignment: .leading)
                Slider(
                    value: $configStore.preferences.ballOpacity,
                    in: 0.3...1.0,
                    step: 0.05
                )
                Text("\(Int(configStore.preferences.ballOpacity * 100))%")
                    .frame(width: 50)
                    .foregroundStyle(.secondary)
            }

            // 颜色主题
            HStack {
                Text("颜色主题")
                    .frame(width: 80, alignment: .leading)
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

    // MARK: - 通用设置

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通用")
                .font(.headline)

            // 开机自启动
            Toggle("开机自启动", isOn: $configStore.preferences.launchAtLogin)
                .onChange(of: configStore.preferences.launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            // Pin 窗口边框颜色
            HStack {
                Text("Pin 窗口边框颜色")
                    .frame(width: 140, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(["blue", "red", "green", "orange", "purple", "yellow"], id: \.self) { colorName in
                        Circle()
                            .fill(borderColor(for: colorName))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(configStore.preferences.pinBorderColor == colorName ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                configStore.preferences.pinBorderColor = colorName
                            }
                    }
                }
                Spacer()
            }

            // Pin 操作音效
            Toggle("Pin 操作音效", isOn: $configStore.preferences.pinSoundEnabled)
        }
    }

    // MARK: - 辅助方法

    /// 将颜色名称映射为 SwiftUI Color
    private func borderColor(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        default: return .blue
        }
    }
}
