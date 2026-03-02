import SwiftUI

/// 收藏管理页面
/// 系统 App 列表 + 运行状态标记 + 星标收藏切换
struct AppConfigView: View {
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var appMonitor = AppMonitor.shared

    // 搜索文本
    @State private var searchText = ""
    // 刷新触发器（App 启动/退出时递增）
    @State private var refreshTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.top)
            .padding(.bottom, 8)

            // App 列表
            let apps = sortedApps
            if apps.isEmpty {
                Text("无匹配结果")
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

    // MARK: - 排序后的 App 列表

    /// 运行中 App 排在前面，未运行的按名称排序
    private var sortedApps: [AppListItem] {
        let _ = refreshTrigger
        let favoriteIDs = Set(configStore.appConfigs.map(\.bundleID))

        // 收集所有已安装 App
        var items: [AppListItem] = appMonitor.installedApps.map { installed in
            let running = appMonitor.isRunning(installed.bundleID)
            return AppListItem(
                bundleID: installed.bundleID,
                name: installed.name,
                icon: installed.icon,
                isRunning: running,
                isFavorite: favoriteIDs.contains(installed.bundleID)
            )
        }

        // 补充：运行中但不在已安装列表里的 App（可能是非标准路径安装的）
        let installedIDs = Set(appMonitor.installedApps.map(\.bundleID))
        let runningNSApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        for nsApp in runningNSApps {
            let bundleID = nsApp.bundleIdentifier!
            if !installedIDs.contains(bundleID) {
                items.append(AppListItem(
                    bundleID: bundleID,
                    name: nsApp.localizedName ?? bundleID,
                    icon: nsApp.icon ?? NSImage(named: NSImage.applicationIconName)!,
                    isRunning: true,
                    isFavorite: favoriteIDs.contains(bundleID)
                ))
            }
        }

        // 搜索过滤
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // 排序：运行中排前，组内按名称排序
        items.sort { a, b in
            if a.isRunning != b.isRunning {
                return a.isRunning
            }
            return a.name.localizedCompare(b.name) == .orderedAscending
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
