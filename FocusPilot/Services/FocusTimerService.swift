import Foundation

// MARK: - FocusByTime 计时器状态

enum FocusTimerPhase: String, Codable {
    case work   = "work"
    case rest   = "rest"
}

enum FocusTimerStatus {
    case idle       // 未启动
    case running    // 计时中
    case paused     // 暂停
}

// MARK: - FocusByTime 计时器服务

final class FocusTimerService: ObservableObject {
    static let shared = FocusTimerService()

    // MARK: - 状态（@Published 供 UI 绑定）

    @Published var status: FocusTimerStatus = .idle
    @Published var phase: FocusTimerPhase = .work
    @Published var remainingSeconds: Int = 0
    @Published var workMinutes: Int = 25
    @Published var restMinutes: Int = 5

    /// 当前阶段总秒数（用于计算进度）
    private(set) var totalSeconds: Int = 0

    /// 进度比例 0.0~1.0（剩余/总共）
    var progress: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return CGFloat(remainingSeconds) / CGFloat(totalSeconds)
    }

    /// 剩余时间格式化 "MM:SS"
    var displayTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 阶段显示文案
    var phaseLabel: String {
        switch phase {
        case .work: return "工作中"
        case .rest: return "休息中"
        }
    }

    private var timer: Timer?

    private init() {
        loadSettings()
    }

    // MARK: - 控制

    func start() {
        totalSeconds = phase == .work ? workMinutes * 60 : restMinutes * 60
        remainingSeconds = totalSeconds
        status = .running
        saveSettings()
        startTimer()
        notifyChanged()
    }

    func pause() {
        status = .paused
        timer?.invalidate()
        timer = nil
        notifyChanged()
    }

    func resume() {
        status = .running
        startTimer()
        notifyChanged()
    }

    func reset() {
        status = .idle
        phase = .work
        remainingSeconds = 0
        totalSeconds = 0
        timer?.invalidate()
        timer = nil
        notifyChanged()
    }

    /// 切换工作/休息时长（仅 idle 时可调）
    func setWorkMinutes(_ m: Int) {
        guard status == .idle else { return }
        workMinutes = max(1, min(m, 120))
        saveSettings()
    }

    func setRestMinutes(_ m: Int) {
        guard status == .idle else { return }
        restMinutes = max(1, min(m, 60))
        saveSettings()
    }

    // MARK: - 内部

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        notifyChanged()

        if remainingSeconds <= 0 {
            timer?.invalidate()
            timer = nil
            switchPhase()
        }
    }

    /// 阶段切换：发送通知让 UI 层弹对话框确认
    private func switchPhase() {
        if phase == .work {
            // 工作结束 → 暂停，等待 UI 弹对话框后调用 startRestPhase()
            status = .paused
            notifyChanged()
            NotificationCenter.default.post(name: Constants.Notifications.focusWorkCompleted, object: nil)
        } else {
            // 休息结束 → 回到 idle，等待 UI 弹对话框后调用 start()
            status = .idle
            phase = .work
            remainingSeconds = 0
            totalSeconds = 0
            notifyChanged()
            NotificationCenter.default.post(name: Constants.Notifications.focusRestCompleted, object: nil)
        }
    }

    /// 进入休息阶段（由 UI 对话框确认后调用）
    func startRestPhase() {
        phase = .rest
        totalSeconds = restMinutes * 60
        remainingSeconds = totalSeconds
        status = .running
        startTimer()
        notifyChanged()
    }

    // MARK: - 通知

    private func notifyChanged() {
        NotificationCenter.default.post(name: Constants.Notifications.focusTimerChanged, object: nil)
    }

    // MARK: - 持久化（工作/休息时长）

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Constants.Keys.focusTimerSettings),
           let settings = try? JSONDecoder().decode(FocusTimerSettings.self, from: data) {
            workMinutes = settings.workMinutes
            restMinutes = settings.restMinutes
        }
    }

    private func saveSettings() {
        let settings = FocusTimerSettings(workMinutes: workMinutes, restMinutes: restMinutes)
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Constants.Keys.focusTimerSettings)
        }
    }
}

// MARK: - 持久化模型

private struct FocusTimerSettings: Codable {
    let workMinutes: Int
    let restMinutes: Int
}
