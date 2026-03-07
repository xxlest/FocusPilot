import SwiftUI

/// 悬浮球与面板配置页面
struct BallPanelConfigView: View {
    @ObservedObject private var configStore = ConfigStore.shared
    @State private var cachedLogo: NSImage?
    @State private var cachedTheme: AppTheme?

    private var themeColors: ThemeColors { configStore.currentThemeColors }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ballSection
                panelSection
            }
            .padding()
        }
        .background(themeColors.swBackground)
        .onAppear { updateLogoIfNeeded() }
        .onChange(of: configStore.preferences.appTheme) { _ in updateLogoIfNeeded() }
        .onDisappear {
            configStore.save()
        }
    }

    private var ballLogo: NSImage {
        cachedLogo ?? FloatingBallView.brandLogo(size: 20, gradientColors: configStore.preferences.appTheme.ballGradientColors)
    }

    private func updateLogoIfNeeded() {
        let theme = configStore.preferences.appTheme
        guard theme != cachedTheme else { return }
        cachedTheme = theme
        cachedLogo = FloatingBallView.brandLogo(size: 20, gradientColors: theme.ballGradientColors)
    }

    // MARK: - 悬浮球

    private var ballSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("悬浮球")
                .font(.headline)
                .foregroundStyle(themeColors.swTextPrimary)

            // 显隐切换
            HStack(spacing: 8) {
                Image(nsImage: ballLogo)
                    .interpolation(.high)
                    .opacity(configStore.isBallVisible ? 1.0 : 0.4)

                Toggle("显示悬浮球", isOn: Binding(
                    get: { configStore.isBallVisible },
                    set: { _ in
                        NotificationCenter.default.post(
                            name: Constants.Notifications.ballToggle,
                            object: nil
                        )
                    }
                ))
                .tint(themeColors.swAccent)
            }

            // 大小
            HStack {
                Text("大小")
                    .foregroundStyle(themeColors.swTextSecondary)
                    .frame(width: 110, alignment: .leading)
                Slider(
                    value: $configStore.preferences.ballSize,
                    in: Constants.Ball.minSize...Constants.Ball.maxSize,
                    step: 1
                )
                .tint(themeColors.swAccent)
                Text("\(Int(configStore.preferences.ballSize))px")
                    .frame(width: 50)
                    .foregroundStyle(themeColors.swTextTertiary)
            }

            // 透明度
            HStack {
                Text("透明度")
                    .foregroundStyle(themeColors.swTextSecondary)
                    .frame(width: 110, alignment: .leading)
                Slider(
                    value: $configStore.preferences.ballOpacity,
                    in: 0.3...1.0,
                    step: 0.01
                )
                .tint(themeColors.swAccent)
                Text("\(Int(round(configStore.preferences.ballOpacity * 100)))%")
                    .frame(width: 50)
                    .foregroundStyle(themeColors.swTextTertiary)
            }
        }
    }

    // MARK: - 快捷面板

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷面板")
                .font(.headline)
                .foregroundStyle(themeColors.swTextPrimary)

            // 透明度
            HStack {
                Text("透明度")
                    .foregroundStyle(themeColors.swTextSecondary)
                    .frame(width: 110, alignment: .leading)
                Slider(
                    value: $configStore.preferences.panelOpacity,
                    in: 0.3...1.0,
                    step: 0.01
                )
                .tint(themeColors.swAccent)
                Text("\(Int(round(configStore.preferences.panelOpacity * 100)))%")
                    .frame(width: 50)
                    .foregroundStyle(themeColors.swTextTertiary)
            }

            // 弹出动画速度
            HStack {
                Text("弹出动画")
                    .foregroundStyle(themeColors.swTextSecondary)
                    .frame(width: 110, alignment: .leading)
                Slider(
                    value: $configStore.preferences.panelAnimationSpeed,
                    in: 0.1...0.6,
                    step: 0.05
                )
                .tint(themeColors.swAccent)
                Text("\(Int(configStore.preferences.panelAnimationSpeed * 1000))ms")
                    .frame(width: 50)
                    .foregroundStyle(themeColors.swTextTertiary)
            }

            // hover 自动收起
            Toggle("hover 离开后自动收起面板", isOn: $configStore.preferences.autoRetractOnHover)
                .tint(themeColors.swAccent)
        }
    }
}
