# PinTop V1.2 增量架构文档

## 范围评估

- 场景类型: B（已有项目增量开发 + Bug 修复）
- 规模: M
- 项目类型: macOS 桌面应用（AppKit + SwiftUI）
- 启用标签: [前端]

## 需求清单

| # | 类型 | 描述 | 优先级 |
|---|------|------|--------|
| 1 | Feature | 浮球右键菜单（退出、显隐、打开看板） | P0 |
| 2 | Bug | 权限灰色（codesign 后 TCC 失效） | P0 |
| 3 | Bug | 快捷面板二级窗口"无标题"（与 #2 同源） | P0 |
| 4 | UI | 浮球视觉优化 | P1 |

## 影响分析

### 根因分析：权限 + 无标题

**问题链**：
```
make install → codesign --force --sign - → CDHash 变化
→ TCC 数据库中旧 CDHash 条目失效
→ AXIsProcessTrusted() 返回 false
→ buildAXTitleMap() guard 短路返回空 dict
→ resolveTitle() 全部走到最后一级 "(无标题)"
→ PinManageView 的 permissionManager.accessibilityGranted 为 false → UI 灰色
```

**修复策略**：多层防御
1. **Makefile 层**：安装前杀旧进程 + 安装后提示重新授权
2. **App 层**：启动时检测权限失效 → 自动弹系统授权对话框 + 启动轮询（已有）
3. **UI 层**：改进 PinManageView 提示文案，明确说明"重新安装后需要在系统设置中关闭再开启辅助功能权限"
4. **标题层**：增强 resolveTitle，CG 标题作为第二级来源（AX 失败时仍可显示部分标题）

### 需修改的文件

| 文件 | 修改内容 |
|------|----------|
| `FloatingBallView.swift` | 新增 rightMouseDown + 右键菜单 + 视觉优化 |
| `AppDelegate.swift` | 监听浮球右键菜单通知 |
| `PermissionManager.swift` | 增强启动时权限检测提示 |
| `PinManageView.swift` | 改进权限提示文案 |
| `WindowService.swift` | resolveTitle 增加 CG 标题作为第二级来源 |
| `Makefile` | 安装前杀旧进程 + 安装后提示 |

### 回归风险点
- 浮球右键菜单可能与单击/双击/拖拽事件冲突 → 右键独立通道，不影响
- resolveTitle 增加 CG 标题层级 → 需确保不引入新的标题冲突

## 模块修改详情

### 1. FloatingBallView - 右键菜单

**接口契约**：
- FloatingBallView → AppDelegate：通过通知
  - `FloatingBall.contextMenu.quit` → menuQuit()
  - `FloatingBall.contextMenu.toggleBall` → toggleFloatingBall()
  - `FloatingBall.contextMenu.openKanban` → showMainKanban()

**实现方式**：
- 重写 `rightMouseDown(with:)` 构建 NSMenu
- 菜单项：打开主看板 / 显示隐藏悬浮球 / 分割线 / 退出 PinTop
- 退出使用 `NSApplication.shared.terminate(nil)` 直接调用（无需通知）

### 2. FloatingBallView - 视觉优化

**优化方向**：
- 增加微妙的呼吸脉搏动画（idle 状态时的轻微光晕变化）
- 改进渐变配色（更柔和的高光和阴影）
- 有 Pin 窗口时图标使用更醒目的颜色

### 3. PermissionManager - 权限增强

**新增行为**：
- 启动时若权限未授予，输出日志提醒
- backgroundCheckTimer 权限恢复时同时触发 UI 刷新通知

### 4. WindowService - 标题增强

**resolveTitle 新层级**：
```
1. AX 标题（最可靠）
2. CG 标题（kCGWindowName，部分应用支持）
3. titleCache 缓存（权限短暂丢失时）
4. "(无标题)"
```

### 5. Makefile - 安装流程优化

**新增步骤**：
```makefile
install: build
    # 杀掉旧进程
    pkill -x PinTop 2>/dev/null; sleep 1
    # 复制 + 签名
    ...
    # 提示用户
    @echo "⚠️  首次安装或重新安装后，需要在系统设置中重新授权辅助功能权限"
    @echo "   路径：系统设置 → 隐私与安全性 → 辅助功能 → 关闭 PinTop → 重新开启"
```

## 验收用例

### TC-01: 浮球右键菜单
- 前置条件：PinTop 运行中，浮球可见
- 操作步骤：右键点击浮球
- 预期结果：弹出菜单，包含"打开主看板"、"显示/隐藏悬浮球"、分割线、"退出 PinTop"
- 覆盖类型：正常路径

### TC-02: 通过右键菜单退出
- 前置条件：TC-01 通过
- 操作步骤：右键菜单 → 点击"退出 PinTop"
- 预期结果：应用正常退出，进程不残留
- 覆盖类型：正常路径

### TC-03: 权限授权后 UI 恢复
- 前置条件：辅助功能权限已授予
- 操作步骤：打开主看板 → 置顶管理
- 预期结果：可置顶窗口列表正常显示（不灰色），窗口标题不为"无标题"
- 覆盖类型：正常路径

### TC-04: 窗口标题正常显示
- 前置条件：辅助功能权限已授予
- 操作步骤：hover 浮球 → 快捷面板展开 → 查看多窗口 App 的窗口列表
- 预期结果：窗口标题正确显示（非"无标题"或"（无标题）"）
- 覆盖类型：正常路径

### TC-05: 浮球视觉效果
- 前置条件：PinTop 运行中
- 操作步骤：观察浮球外观
- 预期结果：浮球具有现代感的视觉效果
- 覆盖类型：正常路径

### TC-06: 右键菜单不干扰拖拽
- 前置条件：PinTop 运行中
- 操作步骤：左键拖拽浮球移动位置
- 预期结果：拖拽正常，不弹出右键菜单
- 覆盖类型：边界

## 非目标

- 不实现 DMG 打包
- 不优化内存占用
- 不修改面板 CPU 性能问题
