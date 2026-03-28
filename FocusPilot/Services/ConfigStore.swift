import Foundation
import Combine

// 用户配置持久化服务
class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var appConfigs: [AppConfig] = []
    @Published var preferences: Preferences = Preferences()
    @Published var ballPosition: BallPosition = .default
    @Published var onboardingCompleted: Bool = false
    @Published var windowRenames: [String: String] = [:]
    var sessionPreferences: [String: CoderSessionPreference] = [:]
    @Published var panelSize: PanelSize = .default
    /// 快捷面板上次选择的 Tab（持久化，面板关闭再打开时恢复）
    @Published var lastPanelTab: String = QuickPanelTab.running.rawValue

    /// 悬浮球可见性（运行时状态，不持久化）
    @Published var isBallVisible: Bool = true

    /// 当前主题颜色集（便捷访问）
    var currentThemeColors: ThemeColors {
        preferences.appTheme.colors
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - 加载配置

    func load() {
        // 从旧 bundle ID (PinTop) 自动迁移配置
        migrateFromPinTop()

        // V3.1 迁移：移除非关注的 appConfigs，仅保留 isFavorite==true 的
        migrateToV31()

        if let data = defaults.data(forKey: Constants.Keys.appConfigs),
           let configs = try? decoder.decode([AppConfig].self, from: data) {
            appConfigs = configs
        }
        if let data = defaults.data(forKey: Constants.Keys.preferences),
           let prefs = try? decoder.decode(Preferences.self, from: data) {
            preferences = prefs
        }
        if let data = defaults.data(forKey: Constants.Keys.ballPosition),
           let pos = try? decoder.decode(BallPosition.self, from: data) {
            ballPosition = pos
        }
        onboardingCompleted = defaults.bool(forKey: Constants.Keys.onboardingCompleted)
        if let data = defaults.data(forKey: Constants.Keys.windowRenames),
           let renames = try? decoder.decode([String: String].self, from: data) {
            windowRenames = renames
        }
        if let data = defaults.data(forKey: Constants.Keys.panelSize),
           let size = try? decoder.decode(PanelSize.self, from: data) {
            panelSize = size
        }
        lastPanelTab = defaults.string(forKey: Constants.Keys.lastPanelTab) ?? QuickPanelTab.running.rawValue
        if let data = defaults.data(forKey: Constants.Keys.sessionPreferences),
           let prefs = try? decoder.decode([String: CoderSessionPreference].self, from: data) {
            sessionPreferences = prefs
        }
    }

    // MARK: - 保存配置

    func save() {
        if let data = try? encoder.encode(appConfigs) {
            defaults.set(data, forKey: Constants.Keys.appConfigs)
        }
        if let data = try? encoder.encode(preferences) {
            defaults.set(data, forKey: Constants.Keys.preferences)
        }
        if let data = try? encoder.encode(ballPosition) {
            defaults.set(data, forKey: Constants.Keys.ballPosition)
        }
        defaults.set(onboardingCompleted, forKey: Constants.Keys.onboardingCompleted)
        if let data = try? encoder.encode(windowRenames) {
            defaults.set(data, forKey: Constants.Keys.windowRenames)
        }
        if let data = try? encoder.encode(panelSize) {
            defaults.set(data, forKey: Constants.Keys.panelSize)
        }
        defaults.set(lastPanelTab, forKey: Constants.Keys.lastPanelTab)
    }

    // MARK: - 配置迁移（PinTop → FocusCopilot）

    /// 从旧 bundle ID (com.pintop.PinTop) 自动迁移配置到新 bundle ID
    /// 仅在新配置为空时执行一次迁移
    private func migrateFromPinTop() {
        // 如果新配置已有数据，跳过迁移
        if defaults.data(forKey: Constants.Keys.appConfigs) != nil {
            return
        }

        // 尝试读取旧 bundle ID 的 UserDefaults
        guard let oldDefaults = UserDefaults(suiteName: "com.pintop.PinTop") else { return }

        let oldKeyMap: [(old: String, new: String)] = [
            ("PinTop.appConfigs", Constants.Keys.appConfigs),
            ("PinTop.preferences", Constants.Keys.preferences),
            ("PinTop.ballPosition", Constants.Keys.ballPosition),
            ("PinTop.windowRenames", Constants.Keys.windowRenames),
            ("PinTop.panelSize", Constants.Keys.panelSize),
        ]

        var migrated = false
        for (oldKey, newKey) in oldKeyMap {
            if let data = oldDefaults.data(forKey: oldKey) {
                defaults.set(data, forKey: newKey)
                migrated = true
            }
        }

        if let completed = oldDefaults.object(forKey: "PinTop.onboardingCompleted") as? Bool {
            defaults.set(completed, forKey: Constants.Keys.onboardingCompleted)
            migrated = true
        }

        if migrated {
            NSLog("[FocusCopilot] 已从 PinTop 迁移配置")
        }
    }

    // MARK: - V3.1 数据迁移（移除非关注 App）

    /// 将旧数据中仅 isFavorite==true 的 App 保留为关注，其余移除
    private func migrateToV31() {
        let migrationKey = "FocusCopilot.v31Migrated"
        guard !defaults.bool(forKey: migrationKey) else { return }

        // 用临时结构解码旧数据（含 isFavorite 字段）
        struct OldAppConfig: Decodable {
            let bundleID: String
            let displayName: String
            let order: Int
            let isFavorite: Bool

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bundleID = try container.decode(String.self, forKey: .bundleID)
                displayName = try container.decode(String.self, forKey: .displayName)
                order = try container.decode(Int.self, forKey: .order)
                isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
            }

            private enum CodingKeys: String, CodingKey {
                case bundleID, displayName, order, isFavorite
            }
        }

        if let data = defaults.data(forKey: Constants.Keys.appConfigs),
           let oldConfigs = try? decoder.decode([OldAppConfig].self, from: data) {
            let favorites = oldConfigs.filter { $0.isFavorite }
            let newConfigs = favorites.enumerated().map { index, old in
                AppConfig(bundleID: old.bundleID, displayName: old.displayName, order: index)
            }
            if let newData = try? encoder.encode(newConfigs) {
                defaults.set(newData, forKey: Constants.Keys.appConfigs)
            }
            NSLog("[FocusCopilot] V3.1 迁移完成：保留 \(newConfigs.count) 个关注 App")
        }

        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - App 配置 CRUD

    func addApp(_ bundleID: String, displayName: String) {
        guard appConfigs.count < Constants.maxApps else { return }
        guard !appConfigs.contains(where: { $0.bundleID == bundleID }) else { return }
        let config = AppConfig(
            bundleID: bundleID,
            displayName: displayName,
            order: appConfigs.count
        )
        appConfigs.append(config)
        save()
        // 通知 QuickPanel 刷新（关注数据变更）
        NotificationCenter.default.post(name: Constants.Notifications.appStatusChanged, object: nil)
    }

    func removeApp(_ bundleID: String) {
        appConfigs.removeAll { $0.bundleID == bundleID }
        // 重新排序
        for i in appConfigs.indices {
            appConfigs[i].order = i
        }
        save()
        // 通知 QuickPanel 刷新（关注数据变更）
        NotificationCenter.default.post(name: Constants.Notifications.appStatusChanged, object: nil)
    }

    func reorderApps(_ ids: [String]) {
        var reordered: [AppConfig] = []
        for (index, id) in ids.enumerated() {
            if var config = appConfigs.first(where: { $0.bundleID == id }) {
                config.order = index
                reordered.append(config)
            }
        }
        appConfigs = reordered
        save()
    }

    /// 检查指定 App 是否已关注（在 appConfigs 中即为关注）
    func isFavorite(_ bundleID: String) -> Bool {
        appConfigs.contains { $0.bundleID == bundleID }
    }

    // MARK: - 面板 Tab 记忆

    /// 快速保存面板 Tab（轻量单字段写入，不触发全量 save）
    func saveLastPanelTab(_ tab: QuickPanelTab) {
        guard lastPanelTab != tab.rawValue else { return }
        lastPanelTab = tab.rawValue
        defaults.set(tab.rawValue, forKey: Constants.Keys.lastPanelTab)
    }

    // MARK: - 单字段保存（避免全量序列化）

    /// 仅保存悬浮球位置
    func saveBallPosition() {
        if let data = try? encoder.encode(ballPosition) {
            defaults.set(data, forKey: Constants.Keys.ballPosition)
        }
    }

    /// 仅保存面板大小
    func savePanelSize() {
        if let data = try? encoder.encode(panelSize) {
            defaults.set(data, forKey: Constants.Keys.panelSize)
        }
    }

    /// 仅保存窗口重命名
    func saveWindowRenames() {
        if let data = try? encoder.encode(windowRenames) {
            defaults.set(data, forKey: Constants.Keys.windowRenames)
        }
    }

    /// 仅保存 AI 会话偏好
    func saveSessionPreferences() {
        if let data = try? encoder.encode(sessionPreferences) {
            defaults.set(data, forKey: Constants.Keys.sessionPreferences)
        }
    }

    func updateSessionPreference(key: String, displayName: String) {
        if var pref = sessionPreferences[key] {
            pref.displayName = displayName
            sessionPreferences[key] = pref
        } else {
            sessionPreferences[key] = CoderSessionPreference(key: key, displayName: displayName)
        }
        saveSessionPreferences()
    }
}
