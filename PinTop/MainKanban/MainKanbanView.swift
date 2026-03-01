import SwiftUI

/// 主看板导航项
enum KanbanTab: String, CaseIterable {
    case appConfig = "快捷面板配置"
    case pinManage = "置顶管理"
    case preferences = "偏好设置"

    var icon: String {
        switch self {
        case .appConfig: return "square.grid.2x2"
        case .pinManage: return "pin.fill"
        case .preferences: return "gearshape"
        }
    }
}

/// 主看板根视图
/// 左侧导航栏(180px) + 右侧内容区
struct MainKanbanView: View {
    @State private var selectedTab: KanbanTab = .appConfig
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var pinManager = PinManager.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    var body: some View {
        NavigationSplitView {
            // 左侧导航栏
            List(KanbanTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            // 右侧内容区
            switch selectedTab {
            case .appConfig:
                AppConfigView()
            case .pinManage:
                PinManageView()
            case .preferences:
                PreferencesView()
            }
        }
    }
}
