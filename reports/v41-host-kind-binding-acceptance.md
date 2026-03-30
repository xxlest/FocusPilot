# V4.1 窗口绑定策略分化 — 验收报告

> 日期：2026-03-30

## 1. 验收用例结果

| 用例 | 结果 | 验证方式 | 备注 |
|------|------|---------|------|
| TC-01: IDE 多 session 共享窗口 | PASS | 代码路径审查 | hostKind=.ide → isAutoWindowConflicted 返回 false → 多 session 共享正常 |
| TC-02: Terminal 独占绑定 | PASS | 代码路径审查 | 各自 autoWindowID 不同 → 各自激活 |
| TC-03: Terminal 冲突拦截 | PASS | 代码路径审查 | autoConflicted → 红 ✕ + 绑定引导 |
| TC-04: 旧版 coder-bridge 兼容 | PASS | 代码路径审查 | hostKind 默认 "terminal" → 行为不变 |
| TC-05: IDE session 未绑定状态 | PASS | 代码路径审查 | .missing → 红 ✕（IDE 不豁免未绑定） |
| TC-06: 右键菜单绑定（IDE vs Terminal） | PASS | 代码路径审查 | IDE 跳过冲突确认 / Terminal 显示替换确认 |
| TC-07: IDE session 窗口消失退化 | PASS | 代码路径审查 | windowExists false → 清空 → missing → 绑定引导 |

## 2. 架构符合度

- 实际代码与架构文档完全一致
- 所有 15 个变更项（A-O + I2）均按设计实现
- BindingState 统一 helper 消除了三处重复判断
- 两条绑定入口行为符合设计（隐式拦截 / 显式确认替换）
- 评审中发现的 3 个 P1 问题已全部修正

## 3. 非目标确认

- 未实现新宿主接入（HostAppMapping 未修改）
- 未实现渲染阶段 windowExists 检测
- 未修改 Session 生命周期管理
- 未修改分组显示/排序/清理逻辑

## 4. 已知问题清单

- P2: shell 脚本空格分隔的字符串拆分理论上可能受 TERM_PROGRAM 含空格影响（实际不会发生，所有已知值均为无空格常量）

## 5. 交付物清单

| 文件 | 职责 |
|------|------|
| `coder-bridge/lib/coder-bridge/core/registry.sh` | hostKind 上报（变更 A/B/C） |
| `FocusPilot/Models/CoderSession.swift` | HostKind 枚举 + 字段（变更 D/E） |
| `FocusPilot/Services/CoderBridgeService.swift` | BindingState helper + 策略分流（变更 F/G/H/I/I2/J/K） |
| `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift` | UI 标记 + 窗口切换 + 绑定引导（变更 L/M/N） |
| `FocusPilot/QuickPanel/QuickPanelMenuHandler.swift` | 右键菜单绑定（变更 O） |
| `docs/superpowers/specs/2026-03-30-host-kind-binding-strategy.md` | 架构设计文档 |
