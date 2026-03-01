import SwiftUI

/// 主看板导航项
enum KanbanTab: String, CaseIterable {
    case appConfig = "快捷面板配置"
    case preferences = "偏好设置"

    var icon: String {
        switch self {
        case .appConfig: return "square.grid.2x2"
        case .preferences: return "gearshape"
        }
    }
}

/// 主看板根视图
/// 左侧导航栏(180px) + 右侧内容区
struct MainKanbanView: View {
    @State private var selectedTab: KanbanTab = .appConfig
    @State private var showQuitConfirmation = false
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    var body: some View {
        NavigationSplitView {
            // 左侧导航栏
            List(KanbanTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    // 底部双按钮：左=悬浮球显隐，右=退出
                    HStack(spacing: 0) {
                        // 左半：悬浮球显隐切换
                        Button(action: {
                            NotificationCenter.default.post(
                                name: Constants.Notifications.ballToggle,
                                object: nil
                            )
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: configStore.isBallVisible ? "eye" : "eye.slash")
                                Text(configStore.isBallVisible ? "悬浮球 隐藏" : "悬浮球 显示")
                            }
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)

                        Divider().frame(height: 16)

                        // 右半：退出
                        Button(action: { showQuitConfirmation = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "power")
                                Text("退出")
                            }
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .alert("退出 Focus Copilot", isPresented: $showQuitConfirmation) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } message: {
                Text("是否确认退出 Focus Copilot？")
            }
        } detail: {
            // 右侧内容区
            switch selectedTab {
            case .appConfig:
                AppConfigView()
            case .preferences:
                PreferencesView()
            }
        }
    }
}
