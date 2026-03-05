import SwiftUI

/// 主看板导航项
enum KanbanTab: String, CaseIterable {
    case appConfig = "收藏管理"
    case preferences = "偏好设置"

    var icon: String {
        switch self {
        case .appConfig: return "square.grid.2x2"
        case .preferences: return "gearshape"
        }
    }
}

/// 主看板根视图
/// 自定义侧边栏布局（不使用 NavigationSplitView，避免系统生成多余按钮）
struct MainKanbanView: View {
    @State private var selectedTab: KanbanTab = .appConfig
    @State private var showQuitConfirmation = false
    @State private var showSidebar = true
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航栏
            if showSidebar {
                sidebar
                    .frame(width: 180)
                Divider()
            }
            // 右侧内容区
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("切换侧边栏")
            }
        }
        .alert("退出 Focus Copilot", isPresented: $showQuitConfirmation) {
            Button("取消", role: .cancel) { }
            Button("退出", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text("是否确认退出 Focus Copilot？")
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 导航列表
            List(KanbanTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)

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
            .padding(.bottom, 4)
        }
        .background(ConfigStore.shared.currentThemeColors.swBackground)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .appConfig:
            AppConfigView()
        case .preferences:
            PreferencesView()
        }
    }
}
