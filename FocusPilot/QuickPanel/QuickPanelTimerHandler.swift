import AppKit

// MARK: - FocusByTime 计时器 UI 与弹窗（extension QuickPanelView）

extension QuickPanelView {

    // MARK: - FocusByTime UI 更新

    func updateTimerUI() {
        let timer = FocusTimerService.shared
        let colors = ConfigStore.shared.currentThemeColors
        let isIdle = timer.status == .idle
        let hasPending = timer.pendingAction != .none
        let isGuided = timer.restMode == .guided && timer.phase == .rest

        // 先隐藏所有元素，按状态按需显示
        timerPhaseIcon.isHidden = true
        timerActionLabel.isHidden = true
        timerTimeLabel.isHidden = true
        timerContentStack.isHidden = true
        timerProgressBg.isHidden = true
        timerProgressFill.isHidden = true
        timerStepLabel.isHidden = true
        timerIdleFocusLabel.isHidden = true
        timerIdleRestLabel.isHidden = true
        timerIdleSeparator.isHidden = true

        // pending 状态：弹窗被失焦自动关闭，等待用户点击栏确认
        if hasPending {
            timerActionLabel.isHidden = false

            switch timer.pendingAction {
            case .startRest:
                timerActionLabel.stringValue = "工作完成 · 开始休息"
                timerActionLabel.textColor = NSColor.systemGreen
                timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
                bottomSeparator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
            case .startWork:
                timerActionLabel.stringValue = "休息结束 · 继续工作"
                timerActionLabel.textColor = colors.nsAccent
                timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
                bottomSeparator.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.3).cgColor
            case .none:
                break
            }
            return
        }

        if isIdle {
            // idle：左右双入口（开始专注 | 休息）
            timerIdleFocusLabel.isHidden = false
            timerIdleRestLabel.isHidden = false
            timerIdleSeparator.isHidden = false
            timerIdleFocusLabel.stringValue = "▶  开始专注"
            timerIdleFocusLabel.textColor = colors.nsAccent
            timerIdleRestLabel.stringValue = "☕  休息"
            timerIdleRestLabel.textColor = NSColor.systemGreen
            timerIdleSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.6).cgColor
            timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
            bottomSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.9).cgColor
        } else {
            // running / paused：SF Symbol 图标 + 大号时间 + 进度条
            let isPaused = timer.status == .paused
            timerContentStack.isHidden = false
            timerPhaseIcon.isHidden = false
            timerTimeLabel.isHidden = false
            timerProgressBg.isHidden = false
            timerProgressFill.isHidden = false

            // 引导模式：显示步骤标签，内容组下移
            if isGuided, let step = timer.currentStep {
                timerStepLabel.isHidden = false
                timerStepLabel.stringValue = "\(step.label) · \(timer.currentStepIndex + 1)/\(timer.guidedSteps.count)"
                timerStepLabel.textColor = isPaused ? colors.nsTextTertiary : NSColor.systemGreen
                timerContentStackCenterY?.constant = 2
            } else {
                timerContentStackCenterY?.constant = -2
            }

            if isPaused {
                let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
                let icon = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "已暂停")
                timerPhaseIcon.image = icon?.withSymbolConfiguration(iconConfig)
                timerPhaseIcon.contentTintColor = colors.nsTextTertiary
                timerTimeLabel.textColor = colors.nsTextTertiary
                timerProgressFill.layer?.backgroundColor = colors.nsTextTertiary.cgColor
                timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
                bottomSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.9).cgColor
            } else {
                let phaseColor = timer.phase == .work ? colors.nsAccent : NSColor.systemGreen
                let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)

                if isGuided, let step = timer.currentStep {
                    // 引导模式：使用当前步骤的 SF Symbol
                    let icon = NSImage(systemSymbolName: step.sfSymbol, accessibilityDescription: step.label)
                    timerPhaseIcon.image = icon?.withSymbolConfiguration(iconConfig)
                } else {
                    let iconName = timer.phase == .work ? "laptopcomputer" : "cup.and.saucer.fill"
                    let iconDesc = timer.phase == .work ? "工作中" : "休息中"
                    let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: iconDesc)
                    timerPhaseIcon.image = icon?.withSymbolConfiguration(iconConfig)
                }

                timerPhaseIcon.contentTintColor = phaseColor
                timerTimeLabel.textColor = colors.nsTextPrimary
                timerProgressFill.layer?.backgroundColor = phaseColor.cgColor
                if timer.phase == .work {
                    timerBar.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.12).cgColor
                    bottomSeparator.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.3).cgColor
                } else {
                    timerBar.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
                    bottomSeparator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
                }
            }

            // 引导模式显示步骤剩余时间，自由模式显示总剩余时间
            timerTimeLabel.stringValue = isGuided ? timer.stepDisplayTime : timer.displayTime
            let progressWidth = timerProgressBg.bounds.width * timer.progress
            timerProgressFillWidth?.constant = max(0, progressWidth)
            timerProgressBg.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - 计时器栏 hover 效果

    func updateTimerBarHover() {
        let colors = ConfigStore.shared.currentThemeColors
        let timer = FocusTimerService.shared

        if isTimerBarHovered {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Constants.Design.Anim.micro
                let isNeutral = timer.status == .idle || timer.pendingAction != .none || timer.status == .paused
                if isNeutral {
                    timerBar.animator().layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.14).cgColor
                } else if timer.phase == .work {
                    timerBar.animator().layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.18).cgColor
                } else {
                    timerBar.animator().layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
                }
            }
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
            updateTimerUI()
        }
    }

    // MARK: - FocusByTime 对话框

    /// 构建休息选择 accessory view（引导休息 radio + 自由休息 radio）
    func buildRestSelectionAccessoryView() -> (container: NSView, helper: WorkCompleteHelper, hoverInfo: HoverInfoView) {
        let timer = FocusTimerService.shared
        let containerWidth: CGFloat = 320
        let intensities = RestIntensity.allCases
        let radioRowH: CGFloat = 22
        let descRowH: CGFloat = 16
        let groupH = radioRowH + descRowH
        let groupGap: CGFloat = 4
        let sepH: CGFloat = 12
        let freeRowH: CGFloat = 22
        let freeDescH: CGFloat = 16
        let infoRowH: CGFloat = 20
        let totalH = CGFloat(intensities.count) * groupH + CGFloat(intensities.count - 1) * groupGap + sepH + freeRowH + freeDescH + 4 + infoRowH
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: totalH))

        // --- 底部 ⓘ 了解更多 ---
        let colors = ConfigStore.shared.currentThemeColors
        let accentColor = colors.nsAccent
        let tipTitleColor = accentColor.blended(withFraction: 0.35, of: .secondaryLabelColor) ?? accentColor
        let tipTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let tipBodyFont = NSFont.systemFont(ofSize: 11)
        let tipBodyColor = NSColor.secondaryLabelColor
        let tA: [NSAttributedString.Key: Any] = [.font: tipTitleFont, .foregroundColor: tipTitleColor]
        let bA: [NSAttributedString.Key: Any] = [.font: tipBodyFont, .foregroundColor: tipBodyColor]

        let popContent = NSMutableAttributedString()
        popContent.append(NSAttributedString(string: "三维恢复的科学依据\n\n", attributes: tA))
        popContent.append(NSAttributedString(string: "\u{1f441} 眼睛恢复\n", attributes: tA))
        popContent.append(NSAttributedString(string: "持续近距离用眼使睫状肌紧张痉挛，闭眼休息 + 远眺（6 米以上）能快速放松睫状肌、缓解干眼和视觉疲劳。每 20-30 分钟远眺 20 秒是眼科推荐的 20-20-20 法则。\n\n", attributes: bA))
        popContent.append(NSAttributedString(string: "\u{1f9e0} 大脑恢复\n", attributes: tA))
        popContent.append(NSAttributedString(string: "前额叶皮层主导专注与决策，持续 20-50 分钟后活力自然衰退。深呼吸能激活副交感神经，降低皮质醇水平，让前额叶「重启」。硬撑只会陷入伪工作状态。\n\n", attributes: bA))
        popContent.append(NSAttributedString(string: "\u{1f4aa} 肌肉恢复\n", attributes: tA))
        popContent.append(NSAttributedString(string: "久坐导致髋屈肌缩短、核心失活、腰椎压力增大。骨盆后倾激活深层核心，猫牛拉伸脊柱，夹臀锁定骨盆中立位。三级强度对应不同姿态需求：坐着 → 站立 → 全链路。\n\n", attributes: bA))
        popContent.append(NSAttributedString(string: "\u{26d4} 禁忌\n", attributes: tA))
        popContent.append(NSAttributedString(string: "别刷短视频、别看社交消息。它们会消耗注意力残留，让大脑无法真正恢复，反而加重疲劳感。", attributes: bA))

        let hoverInfo = HoverInfoView(
            frame: NSRect(x: 0, y: 0, width: containerWidth, height: infoRowH),
            text: "\u{24d8} 了解三维恢复（眼睛 · 大脑 · 肌肉）的科学依据",
            popoverAttributedContent: popContent
        )
        container.addSubview(hoverInfo)

        // --- 分隔线下方：自由休息 radio ---
        let freeY = infoRowH + 4
        let freeRadio = NSButton(radioButtonWithTitle: "自由休息    \(timer.restMinutes) 分钟",
                                 target: nil, action: nil)
        freeRadio.font = .systemFont(ofSize: 12)
        freeRadio.frame = NSRect(x: 2, y: freeY + freeDescH, width: containerWidth - 4, height: freeRowH)
        freeRadio.tag = intensities.count  // tag = 3（区别于引导 0/1/2）
        container.addSubview(freeRadio)

        let freeDesc = NSTextField(labelWithString: "不跟步骤，按自己节奏恢复")
        freeDesc.font = .systemFont(ofSize: 11)
        freeDesc.textColor = .secondaryLabelColor
        freeDesc.frame = NSRect(x: 22, y: freeY, width: containerWidth - 24, height: freeDescH)
        container.addSubview(freeDesc)

        // --- 分隔线 ---
        let sepY = freeY + freeRowH + freeDescH + sepH / 2 - 0.5
        let sepLine = NSView(frame: NSRect(x: 0, y: sepY, width: containerWidth, height: 1))
        sepLine.wantsLayer = true
        sepLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        container.addSubview(sepLine)

        // --- 引导休息 radio（轻度/标准/深度）---
        var radioButtons: [NSButton] = []
        let guidedBaseY = sepY + sepH / 2
        for (i, intensity) in intensities.enumerated() {
            let y = guidedBaseY + CGFloat(intensities.count - 1 - i) * (groupH + groupGap)
            let btn = NSButton(radioButtonWithTitle: "\(intensity.displayName)    ~\(intensity.totalMinutes) 分钟",
                               target: nil, action: nil)
            btn.font = .systemFont(ofSize: 12, weight: .medium)
            btn.frame = NSRect(x: 2, y: y + descRowH, width: containerWidth - 4, height: radioRowH)
            btn.tag = i
            container.addSubview(btn)
            radioButtons.append(btn)

            let desc = NSTextField(labelWithString: intensity.description)
            desc.font = .systemFont(ofSize: 11)
            desc.textColor = .secondaryLabelColor
            desc.frame = NSRect(x: 22, y: y, width: containerWidth - 24, height: descRowH)
            container.addSubview(desc)
        }
        radioButtons.append(freeRadio)

        // Helper 处理 radio 互斥
        let helper = WorkCompleteHelper(
            guidedCount: intensities.count,
            radioButtons: radioButtons
        )
        for btn in radioButtons {
            btn.target = helper
            btn.action = #selector(WorkCompleteHelper.radioSelected(_:))
        }

        // 根据休息时长自动匹配引导强度（1:1 对应：5min→轻度，7min→标准，10min→深度）
        let matchedIntensity: RestIntensity
        switch timer.restMinutes {
        case ...5:  matchedIntensity = .light
        case 6...8: matchedIntensity = .standard
        default:    matchedIntensity = .deep
        }
        let defaultIndex = intensities.firstIndex(of: matchedIntensity) ?? 1
        radioButtons[defaultIndex].state = .on
        helper.selectedTag = defaultIndex

        return (container, helper, hoverInfo)
    }

    @objc func handleWorkCompleted() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let timer = FocusTimerService.shared
            let alert = NSAlert()

            alert.messageText = "工作完成！"
            alert.informativeText = "已专注 \(timer.workMinutes) 分钟，选择恢复方式"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "直接结束")
            alert.addButton(withTitle: "开始休息")

            // 主操作按钮（开始休息）靠右 → 第二个按钮着绿色
            if alert.buttons.count > 1 {
                alert.buttons[1].bezelColor = NSColor.systemGreen
                alert.buttons[1].keyEquivalent = "\r"  // 回车键绑定到"开始休息"
                alert.buttons[0].keyEquivalent = ""     // 取消"直接结束"的默认回车
            }

            let (container, helper, hoverInfo) = self.buildRestSelectionAccessoryView()
            alert.accessoryView = container
            alert.window.initialFirstResponder = nil
            self.prepareAlert(alert)

            // 失焦自动关闭
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            hoverInfo.cleanup()
            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            let intensities = RestIntensity.allCases
            if result == .alertSecondButtonReturn {
                // "开始休息"按钮
                let tag = helper.selectedTag
                if tag < intensities.count {
                    timer.startGuidedRest(intensity: intensities[tag])
                } else {
                    timer.startRestPhase()
                }
            } else if result == .alertFirstButtonReturn {
                // "直接结束"
                timer.reset()
            } else {
                // 失焦自动关闭：保留 pending
                timer.pendingAction = .startRest
                self.updateTimerUI()
            }
            _ = helper
        }
    }

    @objc func handleRestCompleted() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let timer = FocusTimerService.shared
            let alert = NSAlert()

            alert.messageText = "充电完毕"
            alert.informativeText = "准备好下一轮 \(timer.workMinutes) 分钟专注了吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始专注")
            alert.addButton(withTitle: "稍后再说")

            // 主按钮着色（accent 蓝）
            let accentColor = ConfigStore.shared.currentThemeColors.nsAccent
            if let primaryBtn = alert.buttons.first {
                primaryBtn.bezelColor = accentColor
            }

            self.prepareAlert(alert)

            // 失焦自动关闭（pendingAction 保留，计时器栏提供快捷操作）
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            if result == .alertFirstButtonReturn {
                // 回到 idle 状态，弹出时长选择弹窗（与初始"开始专注"一致）
                timer.reset()
                self.updateTimerUI()
                self.timerEditTapped()
            } else {
                // 失焦自动关闭 / 稍后再说：重新设置 pendingAction，计时器栏显示快捷操作
                timer.pendingAction = .startWork
                self.updateTimerUI()
            }
        }
    }

    // MARK: - FocusByTime 计时器栏点击

    @objc func handleTimerBarTapped(_ gesture: NSClickGestureRecognizer) {
        let timer = FocusTimerService.shared

        // 优先处理 pending 动作
        switch timer.pendingAction {
        case .startRest:
            handleWorkCompleted()
            return
        case .startWork:
            handleRestCompleted()
            return
        case .none:
            break
        }

        switch timer.status {
        case .idle:
            // 左半边 = 开始专注，右半边 = 休息
            let location = gesture.location(in: timerBar)
            if location.x > timerBar.bounds.midX {
                restDirectTapped()
            } else {
                timerEditTapped()
            }
        case .running, .paused:
            showRunningActionSheet()
        }
    }

    /// 运行/暂停中点击栏 → 弹出操作面板（暂停/继续 + 停止，休息时附加休息指南）
    func showRunningActionSheet() {
        let timer = FocusTimerService.shared
        let isPaused = timer.status == .paused
        let isRest = timer.phase == .rest
        let isGuided = timer.restMode == .guided && isRest

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()

            if isGuided {
                // 引导模式：显示当前步骤信息
                let stepInfo = timer.currentStep.map { "\($0.label) · 步骤 \(timer.currentStepIndex + 1)/\(timer.guidedSteps.count)" } ?? "引导休息"
                if isPaused {
                    alert.messageText = "已暂停 · \(stepInfo)"
                    alert.informativeText = timer.currentStep?.detail ?? "准备好了就继续"
                } else {
                    alert.messageText = "引导休息 · \(stepInfo)"
                    alert.informativeText = timer.currentStep?.detail ?? "跟随引导恢复状态"
                }
                // 附加步骤列表
                alert.accessoryView = self.buildGuidedStepListView()
            } else {
                let totalDisplay = String(format: "%02d:%02d", timer.totalSeconds / 60, timer.totalSeconds % 60)
                if isPaused {
                    alert.messageText = "已暂停 · \(timer.displayTime) / \(totalDisplay)"
                    alert.informativeText = "准备好了就继续"
                } else if isRest {
                    alert.messageText = "休息中 · \(timer.displayTime) / \(totalDisplay)"
                    alert.informativeText = "让身体和大脑充分恢复"
                } else {
                    alert.messageText = "工作中 · \(timer.displayTime) / \(totalDisplay)"
                    alert.informativeText = "保持专注，你做得很好"
                }
                // 自由休息中附加休息指南
                if isRest {
                    alert.accessoryView = self.buildRestGuideView()
                }
            }
            alert.alertStyle = .informational

            if isPaused {
                alert.addButton(withTitle: "继续")
                if let primaryBtn = alert.buttons.first {
                    primaryBtn.bezelColor = ConfigStore.shared.currentThemeColors.nsAccent
                }
            } else {
                alert.addButton(withTitle: "暂停")
            }
            alert.addButton(withTitle: "停止")

            self.prepareAlert(alert)

            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            if result == .alertFirstButtonReturn {
                if isPaused {
                    timer.resume()
                } else {
                    timer.pause()
                }
            } else if result == .alertSecondButtonReturn {
                timer.reset()
            }
        }
    }

    /// 构建科学休息指南视图（三维单行摘要，用于自由休息操作面板）
    func buildRestGuideView() -> NSView {
        let items: [(String, String, String)] = [
            ("\u{1f441}", "眼睛恢复", "闭眼休息 + 远眺，放松睫状肌"),
            ("\u{1f9e0}", "大脑恢复", "深呼吸放空，让前额叶皮层恢复活力"),
            ("\u{1f4aa}", "肌肉恢复", "拉伸激活核心肌群，缓解久坐损伤"),
            ("\u{26d4}",  "禁忌",     "别刷短视频、别看社交消息"),
        ]
        let lineHeight: CGFloat = 20
        let padding: CGFloat = 10
        let containerH = CGFloat(items.count) * lineHeight + padding * 2
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: containerH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.04).cgColor
        container.layer?.cornerRadius = 8

        for (i, item) in items.enumerated() {
            let y = containerH - padding - CGFloat(i + 1) * lineHeight
            let label = NSTextField(labelWithString: "\(item.0)  \(item.1)  \(item.2)")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .labelColor
            label.frame = NSRect(x: padding, y: y, width: 280, height: lineHeight)
            container.addSubview(label)
        }

        return container
    }

    /// 构建引导休息步骤列表视图（用于运行中查看进度）
    func buildGuidedStepListView() -> NSView {
        let timer = FocusTimerService.shared
        let steps = timer.guidedSteps
        let currentIndex = timer.currentStepIndex
        let isPaused = timer.status == .paused

        let lineHeight: CGFloat = 22
        let detailHeight: CGFloat = 16
        let padding: CGFloat = 10
        let titleH: CGFloat = 20
        // 当前步骤多一行 detail
        let contentH = CGFloat(steps.count) * lineHeight + detailHeight
        let containerH = titleH + contentH + padding * 2 + 4
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: containerH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.04).cgColor
        container.layer?.cornerRadius = 8

        // 标题：强度 + 动态剩余总时间
        let remaining = max(0, timer.guidedTotalSeconds - timer.guidedElapsedSeconds)
        let titleStr: String
        if isPaused {
            titleStr = "\(timer.restIntensity.displayName) · 已暂停"
        } else {
            let rm = remaining / 60
            let rs = remaining % 60
            let remainStr = rs > 0 ? "\(rm)m\(String(format: "%02d", rs))s" : "\(rm)m"
            titleStr = "\(timer.restIntensity.displayName) · \(remainStr)"
        }
        let title = NSTextField(labelWithString: titleStr)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: padding, y: containerH - padding - titleH, width: 280, height: titleH)
        container.addSubview(title)

        var currentY = containerH - padding - titleH - 4
        for (i, step) in steps.enumerated() {
            currentY -= lineHeight
            let mins = step.durationSeconds / 60
            let secs = step.durationSeconds % 60
            let timeStr: String
            if i == currentIndex {
                // 当前步骤显示剩余时间
                let sr = timer.remainingSeconds
                let srm = sr / 60
                let srs = sr % 60
                timeStr = srm > 0 ? "\(srm)m\(srs > 0 ? String(format: "%02d", srs) + "s" : "")" : "\(srs)s"
            } else {
                timeStr = mins > 0 ? "\(mins)m\(secs > 0 ? String(format: "%02d", secs) + "s" : "")" : "\(secs)s"
            }
            let prefix: String
            let font: NSFont
            let color: NSColor
            if i < currentIndex {
                prefix = "\u{2713}"  // ✓
                font = .systemFont(ofSize: 11)
                color = .tertiaryLabelColor
            } else if i == currentIndex {
                prefix = isPaused ? "\u{23f8}" : "\u{25b6}\u{fe0f}"  // ⏸ or ▶️
                font = .systemFont(ofSize: 11, weight: .semibold)
                color = isPaused ? .secondaryLabelColor : NSColor.systemGreen
            } else {
                prefix = "\u{25cb}"  // ○
                font = .systemFont(ofSize: 11)
                color = .secondaryLabelColor
            }
            let label = NSTextField(labelWithString: "\(prefix)  \(step.label) · \(timeStr)")
            label.font = font
            label.textColor = color
            label.frame = NSRect(x: padding + 2, y: currentY, width: 278, height: lineHeight)
            container.addSubview(label)

            // 当前步骤下方显示 detail 副文案
            if i == currentIndex {
                currentY -= detailHeight
                let detail = NSTextField(labelWithString: step.detail)
                detail.font = .systemFont(ofSize: 10.5)
                detail.textColor = .secondaryLabelColor
                detail.frame = NSRect(x: padding + 20, y: currentY, width: 260, height: detailHeight)
                container.addSubview(detail)
            }
        }

        return container
    }

    /// idle 状态点击"休息" → 直接选择休息方式并开始
    func restDirectTapped() {
        let timer = FocusTimerService.shared
        guard timer.status == .idle else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "选择休息方式"
            alert.informativeText = "放下工作，让身体和大脑充分恢复"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "开始休息")

            // 主操作按钮（开始休息）着绿色
            if alert.buttons.count > 1 {
                alert.buttons[1].bezelColor = NSColor.systemGreen
                alert.buttons[1].keyEquivalent = "\r"
                alert.buttons[0].keyEquivalent = "\u{1b}"
            }

            let (container, helper, hoverInfo) = self.buildRestSelectionAccessoryView()
            alert.accessoryView = container
            alert.window.initialFirstResponder = nil
            self.prepareAlert(alert)

            // 失焦自动关闭
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            hoverInfo.cleanup()
            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            let intensities = RestIntensity.allCases
            if result == .alertSecondButtonReturn {
                // "开始休息"按钮 → 独立休息模式
                let tag = helper.selectedTag
                if tag < intensities.count {
                    timer.startStandaloneGuidedRest(intensity: intensities[tag])
                } else {
                    timer.startStandaloneRestFree()
                }
            }
            // 取消或失焦关闭：回到 idle，无需处理
            _ = helper
        }
    }

    @objc func timerEditTapped() {
        let timer = FocusTimerService.shared
        guard timer.status == .idle else { return }

        // 异步弹窗，避免 nonactivatingPanel 按钮回调中同步 activate 导致
        // didResignActiveNotification 在同一事件循环触发，使弹窗被立即关闭
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()

            alert.messageText = "开始专注"
            alert.informativeText = "选择匹配当前任务的节奏，让每段时间都有效"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始")
            let cancelBtn = alert.addButton(withTitle: "取消")
            cancelBtn.keyEquivalent = "\u{1b}"

            // 主按钮着色（accent 蓝）
            let colors = ConfigStore.shared.currentThemeColors
            if let primaryBtn = alert.buttons.first {
                primaryBtn.bezelColor = colors.nsAccent
            }

            // 构建 accessory view（预设方案 radio → 分隔线 → 自定义 radio + 输入 → ⓘ 提示）
            let presets: [(String, Int, Int)] = [
                ("深度专注", 25, 5),
                ("常规节奏", 35, 7),
                ("轻度脑力", 50, 10),
            ]
            let containerWidth: CGFloat = 300
            let presetRowH: CGFloat = 24
            let presetsH = CGFloat(presets.count) * presetRowH
            let sepH: CGFloat = 12
            let customRadioH: CGFloat = 22
            let customInputH: CGFloat = 26
            let infoRowH: CGFloat = 18
            let totalH = presetsH + sepH + customRadioH + customInputH + 6 + infoRowH
            let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: totalH))

            // --- 底部 ⓘ 了解更多（hover 弹出 Popover）---
            let accentColor = colors.nsAccent
            let tipTitleColor = accentColor.blended(withFraction: 0.35, of: .secondaryLabelColor) ?? accentColor
            let tipTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let tipBodyFont = NSFont.systemFont(ofSize: 11)
            let tipBodyColor = NSColor.secondaryLabelColor
            let tA: [NSAttributedString.Key: Any] = [.font: tipTitleFont, .foregroundColor: tipTitleColor]
            let bA: [NSAttributedString.Key: Any] = [.font: tipBodyFont, .foregroundColor: tipBodyColor]

            let popContent = NSMutableAttributedString()
            popContent.append(NSAttributedString(string: "\u{1f4cb} 方案说明\n\n", attributes: tA))
            popContent.append(NSAttributedString(string: "深度专注（25+5）\n", attributes: tA))
            popContent.append(NSAttributedString(string: "经典番茄钟节奏。适合需要高度集中的任务，如编码调试、论文写作、方案设计、深度阅读。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "常规节奏（35+7）\n", attributes: tA))
            popContent.append(NSAttributedString(string: "平衡专注与疲劳恢复。适合日常工作节奏，如邮件处理、文档整理、会议纪要、代码审查。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "轻度脑力（50+10）\n", attributes: tA))
            popContent.append(NSAttributedString(string: "适合低认知负荷的长周期任务，如资料浏览、数据录入、素材收集、笔记归档。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "\u{1f9e0} 为什么要定时休息？\n", attributes: tA))
            popContent.append(NSAttributedString(string: "前额叶皮层主导专注与决策，持续 20-50 分钟后活力自然衰退。定时休息让它恢复，硬撑只会陷入「伪工作」。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "\u{26a1} 为什么不能过度消耗？\n", attributes: tA))
            popContent.append(NSAttributedString(string: "透支会拖慢前额叶的恢复节奏，一次硬撑的代价往往是半天的低效。", attributes: bA))

            let hoverInfo = HoverInfoView(
                frame: NSRect(x: 0, y: 0, width: containerWidth, height: infoRowH),
                text: "\u{24d8} 了解各方案的适用场景与科学依据",
                popoverAttributedContent: popContent
            )
            container.addSubview(hoverInfo)

            // --- 自定义 radio + 输入区域 ---
            let customInputY: CGFloat = infoRowH + 4
            let customRadioY = customInputY + customInputH + 2
            let stepperSize: CGFloat = 22
            let stepperFont = NSFont.systemFont(ofSize: 12, weight: .medium)

            // 自定义 radio 按钮
            let customRadio = NSButton(radioButtonWithTitle: "自定义",
                                       target: nil, action: nil)
            customRadio.font = .systemFont(ofSize: 12)
            customRadio.frame = NSRect(x: 2, y: customRadioY, width: containerWidth - 4, height: customRadioH)
            customRadio.tag = presets.count  // tag = 3
            container.addSubview(customRadio)

            // 自定义输入（缩进 22px，与 radio 文字对齐）
            let inputIndent: CGFloat = 22

            let workLabel = NSTextField(labelWithString: "工作")
            workLabel.font = .systemFont(ofSize: 11)
            workLabel.frame = NSRect(x: inputIndent, y: customInputY, width: 28, height: customInputH)
            container.addSubview(workLabel)

            let workMinusBtn = NSButton(frame: NSRect(x: inputIndent + 30, y: customInputY + 2, width: stepperSize, height: stepperSize))
            workMinusBtn.title = "\u{2212}"
            workMinusBtn.bezelStyle = .circular
            workMinusBtn.font = stepperFont
            container.addSubview(workMinusBtn)

            let workVisibleField = NSTextField(string: "\(timer.workMinutes)")
            workVisibleField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            workVisibleField.alignment = .center
            workVisibleField.frame = NSRect(x: inputIndent + 54, y: customInputY + 2, width: 34, height: 20)
            container.addSubview(workVisibleField)

            let workPlusBtn = NSButton(frame: NSRect(x: inputIndent + 90, y: customInputY + 2, width: stepperSize, height: stepperSize))
            workPlusBtn.title = "+"
            workPlusBtn.bezelStyle = .circular
            workPlusBtn.font = stepperFont
            container.addSubview(workPlusBtn)

            let restLabel = NSTextField(labelWithString: "休息")
            restLabel.font = .systemFont(ofSize: 11)
            restLabel.frame = NSRect(x: inputIndent + 124, y: customInputY, width: 28, height: customInputH)
            container.addSubview(restLabel)

            let restMinusBtn = NSButton(frame: NSRect(x: inputIndent + 154, y: customInputY + 2, width: stepperSize, height: stepperSize))
            restMinusBtn.title = "\u{2212}"
            restMinusBtn.bezelStyle = .circular
            restMinusBtn.font = stepperFont
            container.addSubview(restMinusBtn)

            let restVisibleField = NSTextField(string: "\(timer.restMinutes)")
            restVisibleField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            restVisibleField.alignment = .center
            restVisibleField.frame = NSRect(x: inputIndent + 178, y: customInputY + 2, width: 34, height: 20)
            container.addSubview(restVisibleField)

            let restPlusBtn = NSButton(frame: NSRect(x: inputIndent + 214, y: customInputY + 2, width: stepperSize, height: stepperSize))
            restPlusBtn.title = "+"
            restPlusBtn.bezelStyle = .circular
            restPlusBtn.font = stepperFont
            container.addSubview(restPlusBtn)

            // --- helper 初始化（绑定可见输入框 + 自定义 radio）---
            let helper = TimerEditHelper(workField: workVisibleField, restField: restVisibleField, workStep: 1, restStep: 1)

            // --- 分隔线（预设 ↔ 自定义）---
            let sepY = customRadioY + customRadioH + sepH / 2 - 0.5
            let sepLine = NSView(frame: NSRect(x: 0, y: sepY, width: containerWidth, height: 1))
            sepLine.wantsLayer = true
            sepLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
            container.addSubview(sepLine)

            // --- 推荐方案区域（顶部，单行 radio）---
            var radioButtons: [NSButton] = []
            let presetBaseY = totalH
            for (i, preset) in presets.enumerated() {
                let y = presetBaseY - CGFloat(i + 1) * presetRowH
                let btn = NSButton(radioButtonWithTitle: "\(preset.0)    \(preset.1) min 工作 \u{00b7} \(preset.2) min 休息",
                                   target: helper, action: #selector(TimerEditHelper.presetSelected(_:)))
                btn.font = NSFont.systemFont(ofSize: 12)
                btn.frame = NSRect(x: 2, y: y + 2, width: containerWidth - 4, height: 20)
                btn.tag = i
                container.addSubview(btn)
                radioButtons.append(btn)
            }
            // 自定义 radio 加入 radioButtons 数组（互斥管理）
            radioButtons.append(customRadio)
            customRadio.target = helper
            customRadio.action = #selector(TimerEditHelper.customSelected(_:))

            helper.presets = presets
            helper.radioButtons = radioButtons

            // 默认选中匹配当前时长的方案，无匹配则选中自定义
            if let matchIndex = presets.firstIndex(where: { $0.1 == timer.workMinutes && $0.2 == timer.restMinutes }) {
                radioButtons[matchIndex].state = .on
            } else {
                customRadio.state = .on
            }

            // +/- 按钮事件（切换到自定义 radio）
            workMinusBtn.target = helper
            workMinusBtn.action = #selector(TimerEditHelper.decreaseWork)
            workPlusBtn.target = helper
            workPlusBtn.action = #selector(TimerEditHelper.increaseWork)
            restMinusBtn.target = helper
            restMinusBtn.action = #selector(TimerEditHelper.decreaseRest)
            restPlusBtn.target = helper
            restPlusBtn.action = #selector(TimerEditHelper.increaseRest)

            // 输入框编辑时切换到自定义 radio
            workVisibleField.delegate = helper
            restVisibleField.delegate = helper

            alert.accessoryView = container
            alert.window.initialFirstResponder = nil
            self.prepareAlert(alert)

            // 失焦自动取消编辑弹窗（仅编辑弹窗，阶段提示弹窗不受影响）
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            // 清理
            hoverInfo.cleanup()
            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            if result == .alertFirstButtonReturn {
                // 保存时长并启动计时
                let workVal = Int(workVisibleField.stringValue) ?? timer.workMinutes
                let restVal = Int(restVisibleField.stringValue) ?? timer.restMinutes
                timer.setWorkMinutes(workVal)
                timer.setRestMinutes(restVal)
                self.updateTimerUI()
                timer.start()
            }
            _ = helper
        }
    }
}

// MARK: - 工作完成弹窗 radio 辅助

class WorkCompleteHelper: NSObject {
    let guidedCount: Int
    let radioButtons: [NSButton]
    var selectedTag: Int = 0

    init(guidedCount: Int, radioButtons: [NSButton]) {
        self.guidedCount = guidedCount
        self.radioButtons = radioButtons
    }

    @objc func radioSelected(_ sender: NSButton) {
        selectedTag = sender.tag
        // 互斥：关闭其他 radio
        for btn in radioButtons where btn !== sender {
            btn.state = .off
        }
        sender.state = .on
    }
}

// MARK: - 计时器编辑对话框辅助（+/- 按钮事件）

class TimerEditHelper: NSObject, NSTextFieldDelegate {
    let workField: NSTextField
    let restField: NSTextField
    let workStep: Int
    let restStep: Int
    var presets: [(String, Int, Int)] = []
    var radioButtons: [NSButton] = []

    init(workField: NSTextField, restField: NSTextField, workStep: Int, restStep: Int) {
        self.workField = workField
        self.restField = restField
        self.workStep = workStep
        self.restStep = restStep
    }

    /// 取消所有预设 radio，选中"自定义"（数组最后一个）
    private func selectCustomRadio() {
        for btn in radioButtons { btn.state = .off }
        radioButtons.last?.state = .on
    }

    @objc func decreaseWork() {
        let cur = Int(workField.stringValue) ?? 0
        workField.stringValue = "\(max(1, cur - workStep))"
        selectCustomRadio()
    }

    @objc func increaseWork() {
        let cur = Int(workField.stringValue) ?? 0
        workField.stringValue = "\(cur + workStep)"
        selectCustomRadio()
    }

    @objc func decreaseRest() {
        let cur = Int(restField.stringValue) ?? 0
        restField.stringValue = "\(max(1, cur - restStep))"
        selectCustomRadio()
    }

    @objc func increaseRest() {
        let cur = Int(restField.stringValue) ?? 0
        restField.stringValue = "\(cur + restStep)"
        selectCustomRadio()
    }

    @objc func presetSelected(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < presets.count else { return }
        let preset = presets[idx]
        workField.stringValue = "\(preset.1)"
        restField.stringValue = "\(preset.2)"
        // 手动互斥：取消其他 radio
        for btn in radioButtons where btn !== sender { btn.state = .off }
        sender.state = .on
    }

    @objc func customSelected(_ sender: NSButton) {
        // 手动互斥：取消预设 radio
        for btn in radioButtons where btn !== sender { btn.state = .off }
        sender.state = .on
    }

    // MARK: - NSTextFieldDelegate（手动输入时切换到自定义 radio）

    func controlTextDidChange(_ obj: Notification) {
        selectCustomRadio()
    }
}

// MARK: - 悬停弹出信息提示视图

final class HoverInfoView: NSView {
    private let label: NSTextField
    private var popover: NSPopover?
    private var hoverTimer: Timer?
    private let popoverContent: NSAttributedString

    init(frame: NSRect, text: String, popoverAttributedContent: NSAttributedString) {
        self.label = NSTextField(labelWithString: text)
        self.popoverContent = popoverAttributedContent
        super.init(frame: frame)

        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = bounds
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    // 在视图进入窗口后动态管理 tracking area
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        label.textColor = .labelColor
        hoverTimer?.invalidate()
        // Timer 必须加入 .common mode 才能在 NSAlert modal 中触发
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.showPopover()
        }
        RunLoop.current.add(timer, forMode: .common)
        hoverTimer = timer
    }

    override func mouseExited(with event: NSEvent) {
        label.textColor = .secondaryLabelColor
        hoverTimer?.invalidate()
        hoverTimer = nil
        popover?.close()
        popover = nil
    }

    private func showPopover() {
        guard popover == nil, window != nil else { return }

        let textField = NSTextField(wrappingLabelWithString: "")
        textField.attributedStringValue = popoverContent
        textField.isSelectable = false
        textField.preferredMaxLayoutWidth = 300
        let size = textField.intrinsicContentSize
        textField.frame = NSRect(x: 12, y: 12, width: size.width, height: size.height)

        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 24, height: size.height + 24))
        vc.view.addSubview(textField)

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .semitransient
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = pop
    }

    func cleanup() {
        hoverTimer?.invalidate()
        popover?.close()
    }
}
