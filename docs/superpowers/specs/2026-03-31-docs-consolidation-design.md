# 文档整合设计规格

> **日期**：2026-03-31
> **范围**：仅已实现功能（FocusPilot 本体 + Coder-Bridge/AI Tab，截至 V4.2）
> **目标**：将现有文档去重、明确边界，整合为三份互不重叠的主文档

---

## 1. 现状问题

| 问题 | 说明 |
|---|---|
| PRD 与 Architecture 重叠 ~30% | 数据模型、状态机、验收用例、边界场景在两份文档中重复出现 |
| 设计规范散落三处 | CLAUDE.md（设计基调 + 修改规则）、PRD（交互规格）、IconDesign.md（品牌图标）|
| 早期 Draft 与当前文档混放 | `Focus系列/` 下的 V1 PRD、FocusCC、IDE-Proxy、FocusByTime 独立 PRD 均为未实现的早期设计，与当前主文档并列容易混淆 |
| CLAUDE.md 承担过多角色 | 既是开发指南、又是设计规范、又是架构摘要，信息密度过高 |

---

## 2. 目标结构

```
docs/
├── PRD.md                  # 产品需求文档（~500 行）
├── Architecture.md         # 技术架构文档（~600 行）
├── DesignGuide.md          # 设计规范文档（~300 行，新建）
├── archive/                # 早期 Draft 归档（新建）
│   ├── FocusPilot-PRD-V1.md
│   ├── FocusPilot-总架构设计.md
│   ├── FocusCC/
│   │   ├── prd.md
│   │   ├── feasibility-analysis.md
│   │   ├── Claude Code 非交互调用封号风险调研报告.md
│   │   └── Opcode 项目技术分析文档...md
│   ├── ide-proxy/
│   │   ├── IDE-Proxy-设计梳理.md
│   │   ├── IDE-Proxy-技术架构与验证.md
│   │   └── cli_wrap.md
│   ├── focus-by-time/
│   │   └── FocusByTime-PRD.md
│   ├── acceptance-report.md
│   └── monetization-strategy.md
├── superpowers/            # 特性级设计历史（保留不动）
│   ├── specs/
│   └── plans/
├── cc的一些概念及操作/       # 知识文章（保留不动）
└── idea.md                 # 个人笔记（保留不动）
```

**IconDesign.md**：内容并入 DesignGuide.md 后删除。

---

## 3. 三份文档的边界定义

### 3.1 PRD — 回答「做什么、为谁做」

**读者**：产品决策、验收评审

**包含**：
1. 产品概述（定位、目标用户、核心痛点、竞品分析）
2. 产品架构概述（三层 UI 一句话说明 + 示意图）
3. 功能需求（以功能模块组织）
   - 3.1 悬浮球：外观规格表、交互方式表、AI 角标、拖拽约束
   - 3.2 快捷面板：触发与收起、面板布局、Tab 切换、固定/非固定模式交互差异、App 行/窗口行交互规则、窗口重命名、面板尺寸
   - 3.3 主看板：触发方式、窗口规格、关注管理、偏好设置
   - 3.4 全局快捷键
   - 3.5 FocusByTime 番茄钟（计时器栏、编辑弹窗、阶段转换、引导休息、状态机、进度环）
   - 3.6 AI Tab（Coder-Bridge 会话管理、会话生命周期、窗口绑定、HostKind 策略）
   - 3.7 辅助功能权限
   - 3.8 菜单栏图标、Dock 图标
4. 边界场景处理（按模块组织的表格）
5. 非功能需求（性能指标、兼容性、安全与隐私）
6. 里程碑历史（V1.0 ~ V4.2）
7. 验收标准（功能验收 + 性能验收）
8. 附录（快捷键速查、术语表）

**移出**：
- 数据模型 Swift 定义 → Architecture
- 状态转换矩阵 → Architecture
- 技术方案概要 → Architecture

### 3.2 Architecture — 回答「怎么实现」

**读者**：工程开发、代码审查

**包含**：
1. 技术栈总览
2. 文件结构与模块职责（含行数、防过度设计自查）
3. 数据模型（完整 Swift struct/enum 定义，含版本变更注释）
4. 接口契约
   - ConfigStore、AppMonitor、WindowService、HotkeyManager、PermissionManager
   - FocusTimerService
   - CoderBridgeService（从当前代码提取，PRD 中 AI Tab 的实现对应）
   - Constants（通知名、UserDefaults Keys）
5. 模块间交互（通知流序列图）
   - FloatingBall → QuickPanel
   - QuickPanel → Services
   - MainKanban 交互
   - CoderBridge 事件流
6. 行为约束
   - 状态转换矩阵（悬浮球、快捷面板、窗口行高亮、FocusByTime、AI 会话生命周期）
   - 跨 App 窗口激活流程
   - 窗口关闭流程
   - 关闭应用流程
7. 关键设计决策（列表形式，每条 1-2 句话说明决策及理由）
8. 配置迁移记录
9. 版本变更说明（V3.2 ~ V4.2 关键变更日志）
10. 验收用例（技术级测试用例，与 PRD 验收标准对应但侧重实现细节）
11. 非目标声明
12. 文件清单与职责表

**移出**：
- 产品定位、目标用户描述 → PRD
- 视觉参数（色值、动画时长、间距数值）→ DesignGuide
- 主题刷新链路中的色值部分 → DesignGuide

### 3.3 DesignGuide — 回答「长什么样、怎么交互」

**读者**：UI 修改、视觉调整

**包含**：
1. 设计基调与哲学
   - 核心基调：干净 · 高级 · 克制 · 专业
   - 产品哲学：专注 x 禅意
2. 品牌图标设计（整合 IconDesign.md 全部内容）
   - 图标构成（渐变球体 + 禅圆 Enso）
   - 寓意关联
   - 技术实现指向
3. 视觉准则
   - 克制用色原则
   - 原生质感（毛玻璃、系统动画曲线、SF Symbols）
   - 层次分明（三级文字层次）
   - 精致细节
4. Notion 风格主题系统
   - 8 主题概览表（名称 + 明暗 + accent 色 + 适用场景）
   - ThemeColors 9 色槽完整色值表（每主题一行，含 hex 值）
   - 主题刷新链路（从 PreferencesView 到各模块的调用链）
5. 交互原则
   - 非侵入
   - 三层递进
   - 不打断工作流
   - 一致性
6. 动画规范
   - `Constants.Design.Anim` 参数表（micro/fast/normal + 时长 + 曲线 + 用途）
   - 面板弹出/收起动画参数
   - 悬浮球 hover 缩放参数
7. 间距规范
   - `Constants.Design.Spacing` 参数表（xs/sm/md/lg/xl + 数值 + 用途）
8. 修改时必须遵守的规则（从 CLAUDE.md 提取的 6 条硬性规则）

---

## 4. CLAUDE.md 调整

整合后 CLAUDE.md 中「设计基调与风格」整个 section 替换为指向三份文档的索引：

```markdown
## 文档体系

- **产品需求**：`docs/PRD.md` — 功能清单、交互规则、验收标准
- **技术架构**：`docs/Architecture.md` — 模块划分、接口契约、状态机
- **设计规范**：`docs/DesignGuide.md` — 视觉准则、主题色值、动画参数、修改规则

修改 UI 前必读 DesignGuide.md，修改业务逻辑前必读 Architecture.md。
```

CLAUDE.md 保留的内容：
- 项目概述（精简版，3-5 句话）
- 架构概要（文件结构 + 关键设计决策列表，作为快速索引）
- 构建命令（make build/install/clean）
- 开发规范（Teams 流程、PRD/Architecture 同步更新规则、commit 规则、make install 规则）
- 高频 Bug 防范
- 配置迁移历史（版本号列表，详情指向 Architecture.md）

---

## 5. 内容去重对照表

| 当前重复内容 | PRD 保留 | Architecture 保留 | DesignGuide 保留 |
|---|---|---|---|
| 数据模型 Swift 定义 | 精简为自然语言描述 | 完整 Swift 代码 | - |
| 状态转换矩阵 | 状态机图（简化版，给产品看） | 完整表格（给开发看） | - |
| 验收标准 | 功能验收表（F01-F44） | 技术测试用例（TC-01~TC-12） | - |
| 边界场景 | 完整表格 | 通用边界行为表 | - |
| 主题色值 | 提到"8 色主题"不列色值 | 提到 ThemeColors 结构体定义 | 完整色值表 |
| 动画参数 | 提到"100ms ease-out"等规格 | - | 完整参数表 |
| 设计基调 | - | - | 完整描述 |
| 修改规则（6 条） | - | - | 完整规则 + 理由 |

---

## 6. 归档规则

### 移入 `docs/archive/` 的文件

| 当前路径 | 归档原因 |
|---|---|
| `Focus系列/focuspilot/FocusPilot-PRD-V1.md` | V1 早期 Draft，已被主 PRD 取代 |
| `Focus系列/focuspilot/FocusPilot-总架构设计.md` | 早期架构设计，已被主 Architecture 取代 |
| `Focus系列/FocusCC/*` | FocusCC 产品线未实现 |
| `Focus系列/ide-proxy/*` | IDE-Proxy 产品线未实现 |
| `Focus系列/focus-by-time/FocusByTime-PRD.md` | FocusByTime 已融入主 PRD |
| `Focus系列/IDE-Proxy-设计梳理.md` | 重复文件（ide-proxy/ 下已有） |
| `Focus系列/IDE-Proxy-技术架构与验证.md` | 重复文件 |
| `acceptance-report.md` | PinTop V1.1 验收报告，历史记录 |
| `monetization-strategy.md` | PinTop 商业化策略，历史记录 |
| `IconDesign.md` | 内容并入 DesignGuide.md 后归档 |

### 不动的文件

| 路径 | 原因 |
|---|---|
| `superpowers/specs/*` | 特性级设计历史，有参考价值 |
| `superpowers/plans/*` | 实施计划历史 |
| `cc的一些概念及操作/*` | 知识文章，非项目文档 |
| `idea.md` | 个人笔记 |

---

## 7. AI Tab 内容补充

当前 PRD 和 Architecture 中 AI Tab（Coder-Bridge）的内容不完整，需从以下来源补充：

| 来源 | 补充到 |
|---|---|
| CLAUDE.md 中 coder-bridge 相关设计决策 | Architecture §5 模块间交互、§7 关键设计决策 |
| `superpowers/specs/2026-03-28-coder-bridge-ai-tab-design.md` | PRD §3.6 功能描述 |
| `superpowers/specs/2026-03-29-coder-bridge-ai-tab-v2-design.md` | PRD §3.6 + Architecture §3 数据模型 |
| `superpowers/specs/2026-03-30-host-kind-binding-strategy.md` | PRD §3.6 HostKind 策略 + Architecture §6 行为约束 |
| 当前代码 `CoderSession.swift` + `CoderBridgeService.swift` | Architecture §4 接口契约 |

---

## 8. 执行顺序

1. **创建 `docs/archive/`** 并移动归档文件
2. **新建 `docs/DesignGuide.md`**：从 CLAUDE.md、PRD、IconDesign.md 提取设计内容
3. **重写 `docs/PRD.md`**：精简 + 补充 AI Tab + 移出技术内容
4. **重写 `docs/Architecture.md`**：精简 + 补充 CoderBridgeService 契约 + 移出设计内容
5. **更新 `CLAUDE.md`**：替换设计规范 section 为文档索引
6. **删除 `docs/IconDesign.md`**（已并入 DesignGuide）
7. **删除空的 `docs/Focus系列/` 目录**
