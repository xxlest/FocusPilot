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

/// 阶段完成后待执行的动作（弹窗被自动关闭时保留）
enum FocusPendingAction {
    case none           // 无待处理动作
    case startRest      // 工作完成，等待用户确认开始休息
    case startWork      // 休息完成，等待用户确认继续工作
}

// MARK: - 引导休息类型

/// 休息恢复维度
enum RestCategory: String {
    case brain   = "brain"
    case eye     = "eye"
    case muscle  = "muscle"

    var displayName: String {
        switch self {
        case .brain:  return "脑"
        case .eye:    return "眼"
        case .muscle: return "肌肉"
        }
    }
}

/// 引导休息单步
struct RestStep {
    let sfSymbol: String
    let label: String
    let detail: String
    let durationSeconds: Int
    let category: RestCategory
}

/// 休息模式
enum RestMode {
    case free       // 自由休息（整段倒计时）
    case guided     // 引导休息（分步倒计时）
}

/// 引导休息强度
enum RestIntensity: String, Codable, CaseIterable {
    case light  = "light"
    case medium = "medium"
    case deep   = "deep"

    var displayName: String {
        switch self {
        case .light:  return "轻度恢复"
        case .medium: return "中度恢复"
        case .deep:   return "深度恢复"
        }
    }

    var description: String {
        switch self {
        case .light:  return "快速恢复，适合短休息"
        case .medium: return "均衡恢复，推荐选择"
        case .deep:   return "全面恢复，适合长休息"
        }
    }

    var totalMinutes: Int {
        let secs = steps.reduce(0) { $0 + $1.durationSeconds }
        return (secs + 59) / 60  // 向上取整
    }

    var steps: [RestStep] {
        switch self {
        case .light:  return Self.lightSteps
        case .medium: return Self.mediumSteps
        case .deep:   return Self.deepSteps
        }
    }

    // ~3 分钟
    private static let lightSteps: [RestStep] = [
        RestStep(sfSymbol: "eye",              label: "远眺放松",   detail: "看窗外远处，放松眼部肌肉",            durationSeconds: 30,  category: .eye),
        RestStep(sfSymbol: "wind",             label: "深呼吸",     detail: "吸 4s \u{2192} 屏 2s \u{2192} 呼 6s，重复 5 次",  durationSeconds: 60,  category: .brain),
        RestStep(sfSymbol: "figure.cooldown",  label: "颈部转动",   detail: "顺时针、逆时针各转 5 圈",            durationSeconds: 40,  category: .muscle),
        RestStep(sfSymbol: "drop.fill",        label: "喝水站立",   detail: "喝口水，站起来活动一下",              durationSeconds: 40,  category: .muscle),
    ]

    // ~5 分钟
    private static let mediumSteps: [RestStep] = [
        RestStep(sfSymbol: "eye.slash",        label: "闭眼远眺",   detail: "闭眼 60 秒，然后远眺 20 秒",         durationSeconds: 80,  category: .eye),
        RestStep(sfSymbol: "wind",             label: "深呼吸",     detail: "吸 4s \u{2192} 屏 2s \u{2192} 呼 6s，重复 8 次",  durationSeconds: 90,  category: .brain),
        RestStep(sfSymbol: "figure.cooldown",  label: "颈肩拉伸",   detail: "转头耸肩拉伸交替进行",                durationSeconds: 60,  category: .muscle),
        RestStep(sfSymbol: "figure.walk",      label: "起身走动",   detail: "离开座位走几步路",                    durationSeconds: 40,  category: .muscle),
        RestStep(sfSymbol: "drop.fill",        label: "补水远眺",   detail: "喝水，看窗外远处",                    durationSeconds: 30,  category: .eye),
    ]

    // ~8 分钟
    private static let deepSteps: [RestStep] = [
        RestStep(sfSymbol: "eye.slash",        label: "闭眼冥想",   detail: "闭眼放空，专注感受呼吸",              durationSeconds: 90,  category: .eye),
        RestStep(sfSymbol: "wind",             label: "腹式深呼吸", detail: "吸 4s \u{2192} 屏 4s \u{2192} 呼 8s，重复 10 次", durationSeconds: 120, category: .brain),
        RestStep(sfSymbol: "figure.cooldown",  label: "全身拉伸",   detail: "颈、肩、背、腰、腿依次拉伸",          durationSeconds: 90,  category: .muscle),
        RestStep(sfSymbol: "figure.walk",      label: "走动放松",   detail: "离开工位，走动活血",                  durationSeconds: 90,  category: .muscle),
        RestStep(sfSymbol: "eye",              label: "远眺绿植",   detail: "看远处绿色植物或窗外风景",            durationSeconds: 60,  category: .eye),
        RestStep(sfSymbol: "drop.fill",        label: "补水收尾",   detail: "喝水，调整坐姿准备复工",              durationSeconds: 30,  category: .muscle),
    ]
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
    @Published var pendingAction: FocusPendingAction = .none

    // MARK: - 引导休息状态

    @Published var restMode: RestMode = .free
    @Published var currentStepIndex: Int = 0
    var guidedSteps: [RestStep] = []
    var restIntensity: RestIntensity = .medium

    /// 当前阶段总秒数（用于计算进度）
    private(set) var totalSeconds: Int = 0

    /// 进度比例 0.0~1.0（剩余/总共）
    var progress: CGFloat {
        if restMode == .guided && phase == .rest && status != .idle {
            let total = guidedTotalSeconds
            guard total > 0 else { return 0 }
            return CGFloat(total - guidedElapsedSeconds) / CGFloat(total)
        }
        guard totalSeconds > 0 else { return 0 }
        return CGFloat(remainingSeconds) / CGFloat(totalSeconds)
    }

    /// 剩余时间格式化 "MM:SS"
    var displayTime: String {
        if restMode == .guided && phase == .rest && status != .idle {
            let remaining = max(0, guidedTotalSeconds - guidedElapsedSeconds)
            let m = remaining / 60
            let s = remaining % 60
            return String(format: "%02d:%02d", m, s)
        }
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 当前步骤剩余时间格式化 "MM:SS"
    var stepDisplayTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 阶段显示文案
    var phaseLabel: String {
        switch phase {
        case .work: return "工作中"
        case .rest:
            if restMode == .guided, let step = currentStep {
                return step.label
            }
            return "休息中"
        }
    }

    /// 当前引导步骤
    var currentStep: RestStep? {
        guard restMode == .guided, currentStepIndex < guidedSteps.count else { return nil }
        return guidedSteps[currentStepIndex]
    }

    /// 引导休息总秒数
    var guidedTotalSeconds: Int {
        guidedSteps.reduce(0) { $0 + $1.durationSeconds }
    }

    /// 引导休息已过秒数
    var guidedElapsedSeconds: Int {
        let completedSeconds = guidedSteps.prefix(currentStepIndex).reduce(0) { $0 + $1.durationSeconds }
        let currentStepTotal = currentStep?.durationSeconds ?? 0
        let currentStepElapsed = currentStepTotal - remainingSeconds
        return completedSeconds + currentStepElapsed
    }

    private var timer: Timer?

    private init() {
        loadSettings()
    }

    // MARK: - 控制

    func start() {
        pendingAction = .none
        restMode = .free
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
        pendingAction = .none
        status = .idle
        phase = .work
        remainingSeconds = 0
        totalSeconds = 0
        restMode = .free
        guidedSteps = []
        currentStepIndex = 0
        timer?.invalidate()
        timer = nil
        notifyChanged()
    }

    /// 切换工作/休息时长（仅 idle 时可调）
    func setWorkMinutes(_ m: Int) {
        guard status == .idle else { return }
        workMinutes = max(1, m)
        saveSettings()
    }

    func setRestMinutes(_ m: Int) {
        guard status == .idle else { return }
        restMinutes = max(1, m)
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
            if restMode == .guided && phase == .rest && currentStepIndex < guidedSteps.count - 1 {
                // 引导模式：前进到下一步骤
                currentStepIndex += 1
                let step = guidedSteps[currentStepIndex]
                totalSeconds = step.durationSeconds
                remainingSeconds = totalSeconds
                NotificationCenter.default.post(name: Constants.Notifications.focusGuidedStepChanged, object: nil)
                notifyChanged()
            } else {
                timer?.invalidate()
                timer = nil
                switchPhase()
            }
        }
    }

    /// 阶段切换：设置 pendingAction 并发送通知让 UI 层弹对话框确认
    private func switchPhase() {
        if phase == .work {
            // 工作结束 → 暂停，等待用户确认开始休息
            status = .paused
            pendingAction = .startRest
            notifyChanged()
            NotificationCenter.default.post(name: Constants.Notifications.focusWorkCompleted, object: nil)
        } else {
            // 休息结束 → 回到 idle，等待用户确认继续工作
            status = .idle
            phase = .work
            remainingSeconds = 0
            totalSeconds = 0
            restMode = .free
            guidedSteps = []
            currentStepIndex = 0
            pendingAction = .startWork
            notifyChanged()
            NotificationCenter.default.post(name: Constants.Notifications.focusRestCompleted, object: nil)
        }
    }

    /// 进入自由休息阶段（由 UI 对话框确认后调用）
    func startRestPhase() {
        pendingAction = .none
        restMode = .free
        phase = .rest
        totalSeconds = restMinutes * 60
        remainingSeconds = totalSeconds
        status = .running
        startTimer()
        notifyChanged()
    }

    /// 进入引导休息阶段（由 UI 强度选择后调用）
    func startGuidedRest(intensity: RestIntensity) {
        pendingAction = .none
        restMode = .guided
        restIntensity = intensity
        guidedSteps = intensity.steps
        currentStepIndex = 0
        phase = .rest

        let step = guidedSteps[0]
        totalSeconds = step.durationSeconds
        remainingSeconds = totalSeconds
        status = .running
        saveIntensity()
        startTimer()
        notifyChanged()
    }

    // MARK: - 通知

    private func notifyChanged() {
        NotificationCenter.default.post(name: Constants.Notifications.focusTimerChanged, object: nil)
    }

    // MARK: - 持久化（工作/休息时长 + 强度偏好）

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Constants.Keys.focusTimerSettings),
           let settings = try? JSONDecoder().decode(FocusTimerSettings.self, from: data) {
            workMinutes = settings.workMinutes
            restMinutes = settings.restMinutes
        }
        if let raw = defaults.string(forKey: Constants.Keys.focusRestIntensity),
           let intensity = RestIntensity(rawValue: raw) {
            restIntensity = intensity
        }
    }

    private func saveSettings() {
        let settings = FocusTimerSettings(workMinutes: workMinutes, restMinutes: restMinutes)
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Constants.Keys.focusTimerSettings)
        }
    }

    private func saveIntensity() {
        UserDefaults.standard.set(restIntensity.rawValue, forKey: Constants.Keys.focusRestIntensity)
    }
}

// MARK: - 持久化模型

private struct FocusTimerSettings: Codable {
    let workMinutes: Int
    let restMinutes: Int
}
