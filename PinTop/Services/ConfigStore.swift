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
    @Published var panelSize: PanelSize = .default

    /// 悬浮球可见性（运行时状态，不持久化）
    @Published var isBallVisible: Bool = true

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - 加载配置

    func load() {
        // 从旧 bundle ID (PinTop) 自动迁移配置
        migrateFromPinTop()

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

    // MARK: - App 配置 CRUD

    func addApp(_ bundleID: String, displayName: String) {
        guard appConfigs.count < Constants.maxApps else { return }
        guard !appConfigs.contains(where: { $0.bundleID == bundleID }) else { return }
        let config = AppConfig(
            bundleID: bundleID,
            displayName: displayName,
            order: appConfigs.count,
            isFavorite: false
        )
        appConfigs.append(config)
        save()
    }

    func removeApp(_ bundleID: String) {
        appConfigs.removeAll { $0.bundleID == bundleID }
        // 重新排序
        for i in appConfigs.indices {
            appConfigs[i].order = i
        }
        save()
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

    /// 切换指定 App 的收藏状态
    func toggleFavorite(_ bundleID: String) {
        if let index = appConfigs.firstIndex(where: { $0.bundleID == bundleID }) {
            appConfigs[index].isFavorite.toggle()
            save()
            // 通知 QuickPanel 刷新（收藏 Tab 数据源变更）
            NotificationCenter.default.post(name: Constants.Notifications.appStatusChanged, object: nil)
        }
    }

    /// 收藏的 App 配置列表
    var favoriteAppConfigs: [AppConfig] {
        appConfigs.filter { $0.isFavorite }
    }

    // MARK: - 悬浮球位置

    func saveBallPosition(_ position: BallPosition) {
        ballPosition = position
        save()
    }
}
