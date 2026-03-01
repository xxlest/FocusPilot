import SwiftUI
import UniformTypeIdentifiers

/// 快捷面板配置页面
/// 上方：已选应用区（拖拽排序，最多8个，支持收藏标记）
/// 下方：可选应用区（已激活/已安装 Tab 切换 + 搜索）
struct AppConfigView: View {
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    // 可选应用区 Tab
    @State private var selectedSourceTab: AppSourceTab = .running
    // 搜索文本
    @State private var searchText = ""
    // 刷新触发器（App 启动/退出时递增）
    @State private var refreshTrigger = 0
    // 当前拖拽中的应用配置
    @State private var draggedConfig: AppConfig?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                selectedAppsSection
                availableAppsSection
            }
            .padding()
        }
        .navigationTitle("快捷面板配置")
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.appStatusChanged)) { _ in
            refreshTrigger += 1
        }
        .onAppear {
            // 确保已安装 App 列表已扫描
            if appMonitor.installedApps.isEmpty {
                appMonitor.scanInstalledApps()
            }
        }
    }

    // MARK: - 已选应用区

    private var selectedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选应用")
                    .font(.headline)
                Spacer()
                Text("[\(configStore.appConfigs.count)/\(Constants.maxApps)]")
                    .foregroundStyle(.secondary)
            }

            // 拖拽排序列表
            if configStore.appConfigs.isEmpty {
                Text("尚未添加任何应用，请从下方选择")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            } else {
                VStack(spacing: 2) {
                    ForEach(configStore.appConfigs) { config in
                        selectedAppRow(config)
                            .opacity(draggedConfig?.id == config.id ? 0.5 : 1.0)
                            .onDrag {
                                draggedConfig = config
                                return NSItemProvider(object: config.bundleID as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: AppReorderDropDelegate(
                                targetConfig: config,
                                draggedConfig: $draggedConfig,
                                configStore: configStore
                            ))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    /// 已选应用行：拖拽手柄 + 图标 + 名称 + 收藏按钮 + 移除按钮
    private func selectedAppRow(_ config: AppConfig) -> some View {
        HStack(spacing: 8) {
            // 拖拽手柄
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)

            // App 图标
            appIcon(for: config.bundleID)
                .frame(width: 20, height: 20)

            // App 名称
            Text(config.displayName)
                .lineLimit(1)

            Spacer()

            // 收藏切换按钮
            Button {
                configStore.toggleFavorite(config.bundleID)
            } label: {
                Image(systemName: config.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(config.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            // 移除按钮
            Button {
                configStore.removeApp(config.bundleID)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 可选应用区

    private var availableAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可选应用")
                .font(.headline)

            // Tab 切换
            Picker("", selection: $selectedSourceTab) {
                Text("已激活 App").tag(AppSourceTab.running)
                Text("已安装 App").tag(AppSourceTab.installed)
            }
            .pickerStyle(.segmented)

            // 搜索框
            TextField("搜索应用...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            // 应用列表
            let apps = filteredAvailableApps
            if apps.isEmpty {
                Text("无匹配结果")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                VStack(spacing: 2) {
                    ForEach(apps, id: \.bundleID) { app in
                        availableAppRow(app)
                    }
                }
            }
        }
    }

    /// 过滤后的可选应用列表
    private var filteredAvailableApps: [AvailableApp] {
        // 引用 refreshTrigger 让 SwiftUI 在 App 状态变化时刷新
        let _ = refreshTrigger
        let apps: [AvailableApp]
        let selectedIDs = Set(configStore.appConfigs.map(\.bundleID))

        switch selectedSourceTab {
        case .running:
            // 直接从 NSWorkspace 获取所有运行中的 regular App（不限于已配置的）
            let runningNSApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            apps = runningNSApps.map { nsApp in
                let bundleID = nsApp.bundleIdentifier ?? ""
                return AvailableApp(
                    bundleID: bundleID,
                    name: nsApp.localizedName ?? bundleID,
                    isRunning: true,
                    isSelected: selectedIDs.contains(bundleID)
                )
            }
        case .installed:
            apps = appMonitor.installedApps.map { installed in
                let isRunning = appMonitor.runningApps.contains { $0.bundleID == installed.bundleID }
                return AvailableApp(
                    bundleID: installed.bundleID,
                    name: installed.name,
                    isRunning: isRunning,
                    isSelected: selectedIDs.contains(installed.bundleID)
                )
            }
        }

        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// 可选应用行：勾选 + 图标 + 名称 + 运行状态
    private func availableAppRow(_ app: AvailableApp) -> some View {
        HStack(spacing: 8) {
            // 勾选框
            Button {
                if app.isSelected {
                    configStore.removeApp(app.bundleID)
                } else if configStore.appConfigs.count < Constants.maxApps {
                    configStore.addApp(app.bundleID, displayName: app.name)
                }
            } label: {
                Image(systemName: app.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(app.isSelected ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!app.isSelected && configStore.appConfigs.count >= Constants.maxApps)

            // App 图标
            appIcon(for: app.bundleID)
                .frame(width: 20, height: 20)

            // App 名称
            Text(app.name)
                .lineLimit(1)

            Spacer()

            // 运行状态
            HStack(spacing: 4) {
                Circle()
                    .fill(app.isRunning ? .green : .gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(app.isRunning ? "运行中" : "未运行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - 辅助方法

    /// 获取 App 图标
    private func appIcon(for bundleID: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 辅助类型

/// 可选应用来源 Tab
enum AppSourceTab {
    case running
    case installed
}

/// 可选应用列表项（视图模型）
private struct AvailableApp {
    let bundleID: String
    let name: String
    let isRunning: Bool
    let isSelected: Bool
}

/// 已选应用拖拽排序代理
private struct AppReorderDropDelegate: DropDelegate {
    let targetConfig: AppConfig
    @Binding var draggedConfig: AppConfig?
    let configStore: ConfigStore

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedConfig,
              dragged.id != targetConfig.id,
              let fromIndex = configStore.appConfigs.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = configStore.appConfigs.firstIndex(where: { $0.id == targetConfig.id })
        else { return }

        withAnimation {
            var configs = configStore.appConfigs
            configs.move(fromOffsets: IndexSet(integer: fromIndex),
                         toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            configStore.reorderApps(configs.map(\.bundleID))
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedConfig = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

