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

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - 加载配置

    func load() {
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

    // MARK: - App 配置 CRUD

    func addApp(_ bundleID: String, displayName: String) {
        guard appConfigs.count < Constants.maxApps else { return }
        guard !appConfigs.contains(where: { $0.bundleID == bundleID }) else { return }
        let config = AppConfig(
            bundleID: bundleID,
            displayName: displayName,
            order: appConfigs.count,
            pinnedKeywords: []
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

    func updateKeywords(for bundleID: String, keywords: [String]) {
        if let index = appConfigs.firstIndex(where: { $0.bundleID == bundleID }) {
            appConfigs[index].pinnedKeywords = keywords
            save()
        }
    }

    // MARK: - 悬浮球位置

    func saveBallPosition(_ position: BallPosition) {
        ballPosition = position
        save()
    }
}
