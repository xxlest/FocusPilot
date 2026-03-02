import SwiftUI

/// 收藏管理页面 Tab 枚举
private enum AppConfigTab: String, CaseIterable {
    case all = "全部"
    case running = "已打开"
    case favorites = "收藏"
}

/// 收藏管理页面
/// 三 Tab 过滤（全部/已打开/收藏）+ 运行状态标记 + 星标收藏切换
struct AppConfigView: View {
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    // 当前 Tab
    @State private var currentTab: AppConfigTab = .all
    // 搜索文本
    @State private var searchText = ""
    // 刷新触发器（App 启动/退出时递增）
    @State private var refreshTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab 切换
            Picker("", selection: $currentTab) {
                ForEach(AppConfigTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 4)

            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            .padding(.horizontal)
            .padding(.bottom, 8)

            // App 列表
            let apps = filteredApps
            if apps.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps, id: \.bundleID) { app in
                            appRow(app)
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Spacer(minLength: 0)

            // 底部收藏计数
            HStack {
                Spacer()
                Text("收藏数量: \(configStore.appConfigs.count)/\(Constants.maxApps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("收藏管理")
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.appStatusChanged)) { _ in
            refreshTrigger += 1
        }
        .onAppear {
            if appMonitor.installedApps.isEmpty {
                appMonitor.scanInstalledApps()
            }
        }
    }

    // MARK: - 空状态文案

    private var emptyText: String {
        if !searchText.isEmpty { return "无匹配结果" }
        switch currentTab {
        case .all:       return "无匹配结果"
        case .running:   return "没有正在运行的应用"
        case .favorites: return "尚未收藏任何应用"
        }
    }

    // MARK: - 按 Tab 过滤后的 App 列表

    private var filteredApps: [AppListItem] {
        let _ = refreshTrigger
        let favoriteIDs = Set(configStore.appConfigs.map(\.bundleID))

        // 一次性获取运行中 App bundleID 集合（替代逐个 isRunning() 系统调用）
        let runningIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
        )
        // 预构建已安装 App 字典（O(1) 查找替代 O(N) 线性扫描）
        let installedByID = Dictionary(
            uniqueKeysWithValues: appMonitor.installedApps.map { ($0.bundleID, $0) }
        )

        var items: [AppListItem]

        switch currentTab {
        case .all:
            // 全部已安装 App
            items = appMonitor.installedApps.map { installed in
                AppListItem(
                    bundleID: installed.bundleID,
                    name: installed.name,
                    icon: installed.icon,
                    isRunning: runningIDs.contains(installed.bundleID),
                    isFavorite: favoriteIDs.contains(installed.bundleID)
                )
            }
            // 补充：运行中但不在已安装列表里的 App
            let runningNSApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            for nsApp in runningNSApps {
                let bundleID = nsApp.bundleIdentifier!
                if installedByID[bundleID] == nil {
                    items.append(AppListItem(
                        bundleID: bundleID,
                        name: nsApp.localizedName ?? bundleID,
                        icon: nsApp.icon ?? NSImage(named: NSImage.applicationIconName)!,
                        isRunning: true,
                        isFavorite: favoriteIDs.contains(bundleID)
                    ))
                }
            }

        case .running:
            // 当前运行中 App
            let runningNSApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            items = runningNSApps.map { nsApp in
                let bundleID = nsApp.bundleIdentifier!
                let installed = installedByID[bundleID]
                return AppListItem(
                    bundleID: bundleID,
                    name: installed?.name ?? nsApp.localizedName ?? bundleID,
                    icon: installed?.icon ?? nsApp.icon ?? NSImage(named: NSImage.applicationIconName)!,
                    isRunning: true,
                    isFavorite: favoriteIDs.contains(bundleID)
                )
            }

        case .favorites:
            // 已收藏 App
            items = configStore.appConfigs.map { config in
                let installed = installedByID[config.bundleID]
                let icon: NSImage
                if let installedIcon = installed?.icon {
                    icon = installedIcon
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleID) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                } else {
                    icon = NSImage(named: NSImage.applicationIconName)!
                }
                return AppListItem(
                    bundleID: config.bundleID,
                    name: config.displayName,
                    icon: icon,
                    isRunning: runningIDs.contains(config.bundleID),
                    isFavorite: true
                )
            }
        }

        // 搜索过滤
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // 排序：运行中排前，组内按名称排序（收藏 Tab 保持配置顺序）
        if currentTab != .favorites {
            items.sort { a, b in
                if a.isRunning != b.isRunning {
                    return a.isRunning
                }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }

        return items
    }

    // MARK: - App 行

    private func appRow(_ app: AppListItem) -> some View {
        let atLimit = configStore.appConfigs.count >= Constants.maxApps

        return HStack(spacing: 8) {
            // 运行状态指示器
            Circle()
                .fill(app.isRunning ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            // 收藏星标按钮
            Button {
                toggleFavorite(app)
            } label: {
                Image(systemName: app.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(app.isFavorite ? .yellow : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(!app.isFavorite && atLimit)

            // App 图标
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)

            // App 名称
            Text(app.name)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if app.isFavorite {
                Button("从收藏中移除") {
                    configStore.removeApp(app.bundleID)
                }
            } else {
                Button("添加到收藏") {
                    configStore.addApp(app.bundleID, displayName: app.name)
                }
                .disabled(atLimit)
            }
        }
    }

    // MARK: - 收藏切换

    private func toggleFavorite(_ app: AppListItem) {
        if app.isFavorite {
            configStore.removeApp(app.bundleID)
        } else {
            configStore.addApp(app.bundleID, displayName: app.name)
        }
    }
}

// MARK: - 辅助类型

/// App 列表项（视图模型）
private struct AppListItem {
    let bundleID: String
    let name: String
    let icon: NSImage
    let isRunning: Bool
    let isFavorite: Bool
}
