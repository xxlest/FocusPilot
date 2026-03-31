import SwiftUI

/// 主看板导航项
enum KanbanTab: String, CaseIterable {
    case appConfig = "关注管理"
    case ballPanel = "悬浮球与面板"
    case preferences = "个性化"

    var icon: String {
        switch self {
        case .appConfig: return "square.grid.2x2"
        case .ballPanel: return "circle.circle"
        case .preferences: return "gearshape"
        }
    }
}

/// 主看板根视图
/// 自定义侧边栏布局（不使用 NavigationSplitView，避免系统生成多余按钮）
struct MainKanbanView: View {
    @State private var selectedTab: KanbanTab = .appConfig
    @State private var showSidebar = true
    @State private var scrollToMultiBind = false
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    /// 当前主题颜色（便捷访问）
    private var themeColors: ThemeColors { configStore.currentThemeColors }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航栏
            if showSidebar {
                sidebar
                    .frame(width: 180)
                themeColors.swSeparator.frame(width: 1)
            }
            // 右侧内容区
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(themeColors.swBackground)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FocusPilot.switchToPreferencesMultiBind"))) { _ in
            selectedTab = .preferences
            scrollToMultiBind = true
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 导航列表（自定义实现，避免系统 List 覆盖主题背景色）
            VStack(spacing: 3) {
                ForEach(KanbanTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .foregroundStyle(selectedTab == tab ? themeColors.swAccent : themeColors.swTextPrimary)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selectedTab == tab ? themeColors.swAccent.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

        }
        .background(themeColors.swSidebarBackground)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .appConfig:
            AppConfigView()
        case .ballPanel:
            BallPanelConfigView()
        case .preferences:
            PreferencesView(scrollToMultiBind: $scrollToMultiBind)
        }
    }
}
