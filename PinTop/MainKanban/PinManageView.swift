import SwiftUI

/// 标记管理页面
/// 上方：已标记窗口（拖拽排序）
/// 下方：可标记窗口列表
struct PinManageView: View {
    @ObservedObject private var pinManager = PinManager.shared
    @ObservedObject private var appMonitor = AppMonitor.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pinnedSection
                availableWindowsSection
            }
            .padding()
        }
        .navigationTitle("置顶管理")
    }

    // MARK: - 已置顶窗口

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已置顶窗口")
                    .font(.headline)
                Spacer()
                Text("[\(pinManager.pinnedCount)]")
                    .foregroundStyle(.secondary)
            }

            if pinManager.pinnedWindows.isEmpty {
                Text("暂无置顶窗口，从下方勾选窗口进行置顶")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(pinManager.pinnedWindows.enumerated()), id: \.element.id) { index, window in
                        pinnedWindowRow(index: index + 1, window: window)
                    }
                    .onMove { source, destination in
                        var windows = pinManager.pinnedWindows
                        windows.move(fromOffsets: source, toOffset: destination)
                        pinManager.reorder(windows.map(\.id))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    /// 已置顶窗口行：序号 + 图钉 + App名 + 窗口标题 + Unpin按钮
    private func pinnedWindowRow(index: Int, window: PinnedWindow) -> some View {
        HStack(spacing: 8) {
            Text("\(index).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Image(systemName: "pin.fill")
                .foregroundStyle(.blue)
                .font(.caption)

            // App 名称
            let appName = appMonitor.runningApps.first { $0.bundleID == window.ownerBundleID }?.localizedName ?? window.ownerBundleID
            Text(appName)
                .fontWeight(.medium)
                .lineLimit(1)

            Text("-")
                .foregroundStyle(.secondary)

            // 窗口标题
            Text(window.title.isEmpty ? "（无标题）" : window.title)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer()

            // Unpin 按钮
            Button {
                pinManager.unpin(windowID: window.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 可置顶窗口

    private var availableWindowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可置顶窗口")
                .font(.headline)

            // 辅助功能未授权提示
            if !permissionManager.accessibilityGranted {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("需要辅助功能权限才能获取窗口标题和置顶窗口")
                            .font(.callout)
                        Spacer()
                        Button("前往设置") {
                            // 直接打开辅助功能设置面板
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("重新安装后，需要在系统设置中关闭再重新开启 Focus Copilot 的辅助功能权限")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.yellow.opacity(0.1)))
            }

            // 窗口列表
            let allWindows = appMonitor.runningApps.flatMap { app in
                app.windows.map { window in
                    (app: app, window: window)
                }
            }

            if allWindows.isEmpty {
                Text("当前没有可用的窗口")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                VStack(spacing: 2) {
                    ForEach(allWindows, id: \.window.id) { item in
                        availableWindowRow(app: item.app, window: item.window)
                    }
                }
            }
        }
        .opacity(permissionManager.accessibilityGranted ? 1.0 : 0.6)
    }

    /// 可置顶窗口行：勾选 + App名 + 窗口标题
    private func availableWindowRow(app: RunningApp, window: WindowInfo) -> some View {
        HStack(spacing: 8) {
            // 勾选框
            Button {
                pinManager.togglePin(window: window)
            } label: {
                Image(systemName: pinManager.isPinned(window.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(pinManager.isPinned(window.id) ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!permissionManager.accessibilityGranted)

            Text(app.localizedName)
                .fontWeight(.medium)
                .lineLimit(1)

            Text("-")
                .foregroundStyle(.secondary)

            Text(window.title.isEmpty ? "（无标题）" : window.title)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

