import AppKit
import ApplicationServices

// 窗口操作底层服务
class WindowService {
    static let shared = WindowService()

    // CGS Private API 函数指针（可能在某些 macOS 版本上不可用）
    private let cgsMainConnectionID: (@convention(c) () -> Int32)?
    private let cgsSetWindowLevel: (@convention(c) (Int32, CGWindowID, Int32) -> CGError)?

    // _AXUIElementGetWindow 私有 API：从 AXUIElement 获取 CGWindowID
    private let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)?

    private init() {
        // 动态加载 SkyLight 框架获取 Private API
        let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

        if let sym = dlsym(skylight, "CGSMainConnectionID") {
            cgsMainConnectionID = unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)
        } else if let fallback = dlsym(cg, "_CGSDefaultConnection") {
            cgsMainConnectionID = unsafeBitCast(fallback, to: (@convention(c) () -> Int32).self)
        } else {
            cgsMainConnectionID = nil
        }

        if let sym = dlsym(skylight, "CGSSetWindowLevel") {
            cgsSetWindowLevel = unsafeBitCast(sym, to: (@convention(c) (Int32, CGWindowID, Int32) -> CGError).self)
        } else if let sym = dlsym(cg, "CGSSetWindowLevel") {
            cgsSetWindowLevel = unsafeBitCast(sym, to: (@convention(c) (Int32, CGWindowID, Int32) -> CGError).self)
        } else {
            cgsSetWindowLevel = nil
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
                  layer == 0  // 只获取普通窗口层级
            else { return nil }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // 精确匹配：通过 CGWindowID 直接查 AX 标题
            let axTitle = axTitleMap[windowID]
            let cgTitle = info[kCGWindowName as String] as? String ?? ""
            let title: String
            if let ax = axTitle, !ax.isEmpty {
                title = ax
            } else if !cgTitle.isEmpty {
                title = cgTitle
            } else {
                title = "(无标题)"
            }
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
            let axTitle = axCache[ownerPID]?[windowID]
            let cgTitle = info[kCGWindowName as String] as? String ?? ""
            let title: String
            if let ax = axTitle, !ax.isEmpty {
                title = ax
            } else if !cgTitle.isEmpty {
                title = cgTitle
            } else {
                title = "(无标题)"
            }

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
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

        // 先激活 App
        app.activate()

        // 通过 AX API 提升窗口
        guard AXIsProcessTrusted() else { return }

        let axApp = AXUIElementCreateApplication(window.ownerPID)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard let axWindows = windowsRef as? [AXUIElement] else { return }

        // 优先通过 CGWindowID 精确匹配
        for axWindow in axWindows {
            if let wid = getCGWindowID(from: axWindow), wid == window.id {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
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
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }
    }

    /// 激活 App（不需要辅助功能权限）
    func activateApp(_ bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
    }

    // MARK: - 窗口层级控制（CGS Private API）

    /// 设置窗口层级
    func setWindowLevel(_ windowID: CGWindowID, level: Int32) {
        guard let cgsMainConnectionID = cgsMainConnectionID,
              let cgsSetWindowLevel = cgsSetWindowLevel else { return }
        let cid = cgsMainConnectionID()
        _ = cgsSetWindowLevel(cid, windowID, level)
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
