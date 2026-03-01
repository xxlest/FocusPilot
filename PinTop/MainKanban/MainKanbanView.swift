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
    @State private var showQuitConfirmation = false
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
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    // 退出按钮（固定在底部，不随 List 滚动）
                    Button(action: { showQuitConfirmation = true }) {
                        HStack {
                            Image(systemName: "power")
                            Text("退出 PinTop")
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .alert("退出 PinTop", isPresented: $showQuitConfirmation) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } message: {
                Text("是否确认退出 PinTop？退出后将取消所有窗口置顶。")
            }
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
