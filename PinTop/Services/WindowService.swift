import AppKit
import ApplicationServices

// 窗口操作底层服务
class WindowService {
    static let shared = WindowService()

    // CGS Private API 函数指针（可能在某些 macOS 版本上不可用）
    let cgsMainConnectionIDFunc: (@convention(c) () -> Int32)?
    let cgsSetWindowLevelFunc: (@convention(c) (Int32, CGWindowID, Int32) -> CGError)?
    private let cgsOrderWindow: (@convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> CGError)?

    // _AXUIElementGetWindow 私有 API：从 AXUIElement 获取 CGWindowID
    private let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)?

    // 窗口标题缓存：AX/CG 权限丢失时用上次成功获取的标题兜底
    private var titleCache: [CGWindowID: String] = [:]

    // 日志格式化器（避免每次调用 debugLog 都创建新实例）
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    // 持久日志文件句柄
    private var logFileHandle: FileHandle?
    private static let logPath = "/tmp/focuscopilot-debug.log"

    /// 诊断日志（写入 /tmp，方便排查窗口切换问题）
    func debugLog(_ message: String) {
        let msg = "[\(Self.dateFormatter.string(from: Date()))] \(message)\n"
        guard let data = msg.data(using: .utf8) else { return }

        if logFileHandle == nil {
            if !FileManager.default.fileExists(atPath: Self.logPath) {
                FileManager.default.createFile(atPath: Self.logPath, contents: nil)
            }
            logFileHandle = FileHandle(forWritingAtPath: Self.logPath)
            logFileHandle?.seekToEndOfFile()
        }

        logFileHandle?.write(data)
    }

    private init() {
        // 动态加载 SkyLight 框架获取 Private API
        let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

        if let sym = dlsym(skylight, "CGSMainConnectionID") {
            cgsMainConnectionIDFunc = unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)
        } else if let fallback = dlsym(cg, "_CGSDefaultConnection") {
            cgsMainConnectionIDFunc = unsafeBitCast(fallback, to: (@convention(c) () -> Int32).self)
        } else {
            cgsMainConnectionIDFunc = nil
        }

        if let sym = dlsym(skylight, "CGSSetWindowLevel") {
            cgsSetWindowLevelFunc = unsafeBitCast(sym, to: (@convention(c) (Int32, CGWindowID, Int32) -> CGError).self)
        } else if let sym = dlsym(cg, "CGSSetWindowLevel") {
            cgsSetWindowLevelFunc = unsafeBitCast(sym, to: (@convention(c) (Int32, CGWindowID, Int32) -> CGError).self)
        } else {
            cgsSetWindowLevelFunc = nil
        }

        if let sym = dlsym(skylight, "CGSOrderWindow") {
            cgsOrderWindow = unsafeBitCast(sym, to: (@convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> CGError).self)
        } else if let sym = dlsym(cg, "CGSOrderWindow") {
            cgsOrderWindow = unsafeBitCast(sym, to: (@convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> CGError).self)
        } else {
            cgsOrderWindow = nil
        }

        // 加载 _AXUIElementGetWindow（多路径尝试，兼容不同 macOS 版本）
        let axSearchHandles: [UnsafeMutableRawPointer?] = [
            UnsafeMutableRawPointer(bitPattern: -2),  // RTLD_DEFAULT: 搜索所有已加载库
            dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY),
            dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
        ]
        var axSym: UnsafeMutableRawPointer? = nil
        for handle in axSearchHandles {
            if let sym = dlsym(handle, "_AXUIElementGetWindow") {
                axSym = sym
                break
            }
        }
        if let sym = axSym {
            axGetWindow = unsafeBitCast(sym, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
        } else {
            axGetWindow = nil
        }
    }

    // MARK: - AX 可用性检测

    /// AX API 实际可用性缓存（避免每次 reloadData 都做探测）
    private var axApiAvailable: Bool?
    private var axApiCheckTime: Date = .distantPast

    /// 检查 AX API 是否真正可用（不仅检查权限标志，还验证实际调用能否成功）
    /// 结果缓存 3 秒，避免频繁探测
    func isAXApiAvailable() -> Bool {
        // 缓存 3 秒内有效
        if let cached = axApiAvailable, Date().timeIntervalSince(axApiCheckTime) < 3.0 {
            return cached
        }
        let result = probeAXApi()
        axApiAvailable = result
        axApiCheckTime = Date()
        return result
    }

    /// 清除 AX 可用性缓存（权限变化时调用）
    func invalidateAXCache() {
        axApiAvailable = nil
    }

    /// 实际探测 AX API：尝试获取任意运行中 App 的 AX 窗口列表
    private func probeAXApi() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            if err == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
                // 进一步验证：尝试获取第一个窗口的标题
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(windows[0], kAXTitleAttribute as CFString, &titleRef)
                // 即使标题为空也算成功（有些窗口确实没有标题），关键是 AX 调用本身不报错
                return true
            }
        }
        return false
    }

    // MARK: - AX 窗口 → CGWindowID 映射

    /// 从 AXUIElement 获取 CGWindowID
    private func getCGWindowID(from axWindow: AXUIElement) -> CGWindowID? {
        guard let axGetWindow = axGetWindow else { return nil }
        var windowID: CGWindowID = 0
        let err = axGetWindow(axWindow, &windowID)
        return err == .success ? windowID : nil
    }

    /// 构建 CGWindowID → AX 标题的映射表
    /// 当 _AXUIElementGetWindow 不可用时，回退到位置匹配
    private func buildAXTitleMap(for pid: pid_t, cgWindows: [[String: Any]]) -> [CGWindowID: String] {
        // 每次调用时实时检查权限状态（避免缓存值过期）
        guard AXIsProcessTrusted() else { return [:] }

        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard let axWindows = windowsRef as? [AXUIElement] else { return [:] }

        var map: [CGWindowID: String] = [:]
        var unmappedAX: [(title: String, position: CGPoint, size: CGSize)] = []

        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            if let wid = getCGWindowID(from: axWindow) {
                map[wid] = title
            } else {
                // 无法获取 CGWindowID，收集位置信息用于回退匹配
                var posRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
                var origin = CGPoint.zero
                if let posVal = posRef {
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
                }
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
                var sz = CGSize.zero
                if let sizeVal = sizeRef {
                    AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
                }
                unmappedAX.append((title, origin, sz))
            }
        }

        // 位置匹配回退（仅当有未映射窗口时）
        if !unmappedAX.isEmpty {
            let tolerance: CGFloat = 10
            var remaining = unmappedAX
            for info in cgWindows {
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID == pid,
                      let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                      let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let layer = info[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      map[windowID] == nil
                else { continue }

                let cgX = boundsDict["X"] ?? 0
                let cgY = boundsDict["Y"] ?? 0
                let cgW = boundsDict["Width"] ?? 0
                let cgH = boundsDict["Height"] ?? 0

                if let idx = remaining.firstIndex(where: {
                    abs($0.position.x - cgX) < tolerance &&
                    abs($0.position.y - cgY) < tolerance &&
                    abs($0.size.width - cgW) < tolerance &&
                    abs($0.size.height - cgH) < tolerance
                }) {
                    map[windowID] = remaining[idx].title
                    remaining.remove(at: idx)
                }
            }
        }

        return map
    }

    // MARK: - 标题解析

    /// 解析窗口标题，四级兜底：AX 标题 → CG 标题 → 缓存 → "(无标题)"
    /// AX 权限丢失时，CG 标题（kCGWindowName）不需要辅助功能权限即可获取
    private func resolveTitle(windowID: CGWindowID, axTitle: String?, cgTitle: String?) -> String {
        // 第 1 级：AX API 标题
        if let ax = axTitle, !ax.isEmpty {
            titleCache[windowID] = ax
            return ax
        }
        // 第 2 级：CG 标题（kCGWindowName）
        if let cg = cgTitle, !cg.isEmpty {
            titleCache[windowID] = cg
            return cg
        }
        // 第 3 级：缓存
        if let cached = titleCache[windowID] {
            return cached
        }
        return "(无标题)"
    }

    // MARK: - 窗口枚举

    /// 获取指定 App 的窗口列表
    func listWindows(for bundleID: String) -> [WindowInfo] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return []
        }
        return listWindows(for: app.processIdentifier)
    }

    /// 获取指定 PID 的窗口列表
    func listWindows(for pid: pid_t) -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""

        // 通过 AX API 构建精确的 CGWindowID → 标题映射（支持位置匹配回退）
        let axTitleMap = buildAXTitleMap(for: pid, cgWindows: windowList)

        return windowList.compactMap { info -> WindowInfo? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { return nil }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            let cgTitle = info[kCGWindowName as String] as? String
            let title = resolveTitle(windowID: windowID, axTitle: axTitleMap[windowID], cgTitle: cgTitle)

            return WindowInfo(
                id: windowID,
                ownerBundleID: bundleID,
                ownerPID: pid,
                title: title,
                bounds: bounds,
                isMinimized: false,
                isFullScreen: false
            )
        }
    }

    /// 获取所有可见窗口
    func listAllWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // 按 PID 分组缓存 AX 标题映射
        var axCache: [pid_t: [CGWindowID: String]] = [:]

        return windowList.compactMap { info -> WindowInfo? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { return nil }

            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // 获取 AX 标题（按 PID 缓存，支持位置匹配回退）
            if axCache[ownerPID] == nil {
                axCache[ownerPID] = buildAXTitleMap(for: ownerPID, cgWindows: windowList)
            }

            let cgTitle = info[kCGWindowName as String] as? String
            let title = resolveTitle(windowID: windowID, axTitle: axCache[ownerPID]?[windowID], cgTitle: cgTitle)

            return WindowInfo(
                id: windowID,
                ownerBundleID: bundleID,
                ownerPID: ownerPID,
                title: title,
                bounds: bounds,
                isMinimized: false,
                isFullScreen: false
            )
        }
    }

    // MARK: - 窗口操作（需要辅助功能权限）

    /// 激活窗口并前置（通过 CGWindowID 精确匹配 AX 窗口）
    func activateWindow(_ window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else {
            NSLog("[FocusCopilot] activateWindow: 找不到 PID %d 对应的进程", window.ownerPID)
            return
        }

        debugLog("activateWindow: 激活窗口 \(window.id) (\(window.title)) PID=\(window.ownerPID) app=\(app.localizedName ?? "?")")

        // 确保 App 不在隐藏状态
        if app.isHidden {
            app.unhide()
        }

        // 激活 App：先 yieldActivation 让出激活权，再 activate 目标
        // macOS 14+ 中 activate() 要求调用方是前台 App，nonactivatingPanel 不满足此条件
        // yieldActivation 告诉系统"我把前台权让给目标 App"，解决 activate 返回 false 的问题
        NSApp.yieldActivation(to: app)
        let activated = app.activate()
        debugLog("activateWindow: app.activate() 返回 \(activated)")

        // 通过 AX API 提升窗口
        raiseWindowViaAX(window)

        // 延迟 150ms 再次 AXRaise（等待系统完成 App 激活后再提升，确保 Electron 等应用响应）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.raiseWindowViaAX(window)
            // 再次确保 App 处于激活状态
            NSApp.yieldActivation(to: app)
            app.activate()
        }

        // 延迟 300ms 二次兜底重试（跨 App 场景：检查目标 App 是否已成为活跃应用）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.ownerPID {
                self?.debugLog("activateWindow: 300ms 兜底重试 wid=\(window.id)")
                NSApp.yieldActivation(to: app)
                app.activate()
                self?.raiseWindowViaAX(window)
            }
        }
    }

    /// 通过 AX API 提升指定窗口（内部方法）
    private func raiseWindowViaAX(_ window: WindowInfo) {
        guard AXIsProcessTrusted() else {
            debugLog("raiseWindowViaAX: AX 权限未授权")
            return
        }

        let axApp = AXUIElementCreateApplication(window.ownerPID)
        var windowsRef: CFTypeRef?
        let axErr = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard let axWindows = windowsRef as? [AXUIElement] else {
            debugLog("raiseWindowViaAX: 获取 AX 窗口列表失败 err=\(axErr.rawValue)")
            return
        }

        // 优先通过 CGWindowID 精确匹配
        for axWindow in axWindows {
            if let wid = getCGWindowID(from: axWindow), wid == window.id {
                let raiseErr = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                debugLog("raiseWindowViaAX: CGWindowID 精确匹配成功 wid=\(wid) raiseErr=\(raiseErr.rawValue)")
                return
            }
        }

        // 回退：位置匹配
        let tolerance: CGFloat = 10
        for axWindow in axWindows {
            var posRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
            var origin = CGPoint.zero
            if let posVal = posRef {
                AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
            }

            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if let sizeVal = sizeRef {
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            }

            if abs(window.bounds.origin.x - origin.x) < tolerance &&
               abs(window.bounds.origin.y - origin.y) < tolerance &&
               abs(window.bounds.width - size.width) < tolerance &&
               abs(window.bounds.height - size.height) < tolerance {
                let raiseErr = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                debugLog("raiseWindowViaAX: 位置匹配成功 raiseErr=\(raiseErr.rawValue)")
                return
            }
        }

        debugLog("raiseWindowViaAX: 未找到匹配的 AX 窗口（CGWindowID=\(window.id), axWindows.count=\(axWindows.count)）")
    }

    /// 激活 App（不需要辅助功能权限）
    func activateApp(_ bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        if app.isHidden {
            app.unhide()
        }
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    // MARK: - 窗口层级控制（CGS Private API）

    /// 设置窗口层级
    func setWindowLevel(_ windowID: CGWindowID, level: Int32) {
        guard let cgsMainConnectionID = cgsMainConnectionIDFunc else {
            NSLog("[FocusCopilot] setWindowLevel: CGSMainConnectionID 函数指针为 nil，无法设置窗口层级")
            return
        }
        guard let cgsSetWindowLevel = cgsSetWindowLevelFunc else {
            NSLog("[FocusCopilot] setWindowLevel: CGSSetWindowLevel 函数指针为 nil，无法设置窗口层级")
            return
        }

        let cid = cgsMainConnectionID()
        let result = cgsSetWindowLevel(cid, windowID, level)

        if result != .success {
            NSLog("[FocusCopilot] setWindowLevel: CGSSetWindowLevel 返回错误 %d（windowID=%d, level=%d）", result.rawValue, windowID, level)
        }

        // 验证：读回窗口实际 layer，确认是否生效（精确查询单个窗口，避免枚举全部窗口）
        if let windowList = CGWindowListCreateDescriptionFromArray([windowID] as CFArray) as? [[String: Any]],
           let info = windowList.first,
           let actualLayer = info[kCGWindowLayer as String] as? Int32 {
            if actualLayer != level {
                NSLog("[FocusCopilot] setWindowLevel: 窗口 %d 层级验证不一致（期望 %d，实际 %d），尝试 AXRaise 回退", windowID, level, actualLayer)
                // CGS API 未生效，通过 AX API 回退提升窗口
                axRaiseWindow(windowID)
            }
        }

        // 强制将窗口排序到所有窗口之上
        orderWindowAbove(windowID)
    }

    /// 将窗口提升到所有窗口之上
    func orderWindowAbove(_ windowID: CGWindowID) {
        guard let cgsMainConnectionID = cgsMainConnectionIDFunc,
              let cgsOrderWindow = cgsOrderWindow else { return }
        let cid = cgsMainConnectionID()
        let result = cgsOrderWindow(cid, windowID, 1, 0) // 1 = kCGSOrderAbove, 0 = above all
        if result != .success {
            NSLog("[FocusCopilot] orderWindowAbove: CGSOrderWindow 失败 %d", result.rawValue)
        }
    }

    /// 通过 AX API 提升窗口到前台（CGS 失败时的回退方案）
    func axRaiseWindow(_ windowID: CGWindowID) {
        guard AXIsProcessTrusted() else { return }
        // 查找窗口所属进程
        guard let windowList = CGWindowListCreateDescriptionFromArray([windowID] as CFArray) as? [[String: Any]],
              let info = windowList.first,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return }
        // 通过 CGWindowID 匹配 AX 窗口并执行 Raise
        if let axWindow = findAXWindow(pid: pid, windowID: windowID) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
    }

    // MARK: - AXUIElement 操作

    /// 获取 App 的 AX 元素
    func getAXElement(for pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// 获取窗口的 AX 元素
    func getAXWindows(for pid: pid_t) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        return windowsRef as? [AXUIElement] ?? []
    }

    /// 查找匹配 CGWindowID 的 AX 窗口（支持位置匹配回退）
    func findAXWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let windows = getAXWindows(for: pid)
        // 优先通过 CGWindowID 精确匹配
        for window in windows {
            if let wid = getCGWindowID(from: window), wid == windowID {
                return window
            }
        }
        // 回退：通过窗口位置匹配
        guard let cgBounds = getCGWindowBounds(windowID) else { return nil }
        let tolerance: CGFloat = 10
        for window in windows {
            var posRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
            var origin = CGPoint.zero
            if let posVal = posRef {
                AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
            }
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if let sizeVal = sizeRef {
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            }
            if abs(cgBounds.origin.x - origin.x) < tolerance &&
               abs(cgBounds.origin.y - origin.y) < tolerance &&
               abs(cgBounds.width - size.width) < tolerance &&
               abs(cgBounds.height - size.height) < tolerance {
                return window
            }
        }
        return nil
    }

    /// 通过 CGWindowID 获取窗口位置大小
    private func getCGWindowBounds(_ windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCreateDescriptionFromArray([windowID] as CFArray) as? [[String: Any]],
              let info = list.first,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        return CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
    }

    /// 查找匹配标题的 AX 窗口
    func findAXWindow(pid: pid_t, title: String) -> AXUIElement? {
        let windows = getAXWindows(for: pid)
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == title {
                return window
            }
        }
        return nil
    }

    /// 移动窗口
    func moveWindow(_ axWindow: AXUIElement, to point: CGPoint) {
        var pos = point
        let value = AXValueCreate(.cgPoint, &pos)!
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value)
    }

    /// 调整窗口大小
    func resizeWindow(_ axWindow: AXUIElement, to size: CGSize) {
        var sz = size
        let value = AXValueCreate(.cgSize, &sz)!
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, value)
    }

    /// 设置窗口位置和大小
    func setWindowFrame(_ axWindow: AXUIElement, frame: CGRect) {
        moveWindow(axWindow, to: frame.origin)
        resizeWindow(axWindow, to: frame.size)
    }
}
