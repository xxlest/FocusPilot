## 架构评审报告

### 评审结论：通过

架构文档 `reports/phase1-architecture.md` 针对 V3.3 面板钉住交互重构的四项需求，设计清晰、变更范围可控，无 P0 问题。

---

### 检查结果

#### 完整性

- **核心场景覆盖**：四项需求（删除图钉按钮、悬浮球发光反馈、hover 回缩开关、钉住免疫回缩）均有对应的模块变更和验收用例
- **边界行为定义**：状态转换矩阵覆盖了 `isPanelPinned x autoRetractOnHover` 的全部 4 种组合，判断顺序明确（钉住优先 > 回缩开关 > 启动 timer）
- **失败路径**：对于纯 UI 层变更，失败路径主要体现在降级行为上。文档明确了 `autoRetractOnHover=false` 时面板保持显示直到用户主动操作（单击/快捷键/拖拽），覆盖充分
- **UC-5 中的拖拽行为**：架构未显式修改 `handleBallDragStarted`，但该方法已有 `isPanelPinned` 检查（AppDelegate.swift:141-145），未钉住时拖拽关闭面板的行为与 UC-5 描述一致

#### 一致性

- **接口契约对齐**：新增属性 `Preferences.autoRetractOnHover` 的默认值（`true`）在 Models.swift 声明和解码器中保持一致（已验证源码 Models.swift:210, 224）
- **通知复用**：复用 `panelPinStateChanged` 通知，发送方（QuickPanelWindow）和接收方（FloatingBallView）的契约未变更，一致性良好
- **命名统一**：`autoRetractOnHover` 在 Models、QuickPanelView.mouseExited、QuickPanelWindow.ballMouseExited、PreferencesView 四处使用一致的字段名
- **布局约束**：`openKanbanButton` 从左侧改为右侧（`trailingAnchor - 8`），`runningTabButton` 成为最左侧按钮（`leadingAnchor + 32`），与当前源码（QuickPanelView.swift:176-183）完全吻合

#### 过度设计检查

- **无新文件**：所有变更在现有文件中完成
- **无新通知**：复用现有通知机制
- **无不必要的抽象**：`pinGlowLayer` 作为 CALayer 直接内联在 FloatingBallView 中，参数硬编码而非抽取为 Constants，对于单一使用场景合理
- **模块数合理**：涉及 6 个文件的增量修改，变更集中且可控

#### 可测试性

- 8 个验收用例（UC-1 ~ UC-8）均可手动执行
- UC-1 验证布局、UC-3 验证发光效果、UC-4/5/6 验证状态矩阵、UC-7 验证尺寸同步、UC-8 验证持久化
- 用例覆盖了核心交互路径和边界条件

---

### P0 问题

无。

### P1 问题

**P1-1: 架构文档与最终实现存在偏差（已过时）**

架构设计的悬浮球钉住反馈为「红色发光边框环（pinGlowLayer）」，但根据 git 历史（commit `802d8e8`: "fix(ball): 钉住状态视觉改为右上角图钉角标，替换红色发光边框"），最终实现已改为右上角图钉角标方案。架构文档中 1.2 节接口契约（pinGlowLayer 相关）和 1.3 节 pinGlowLayer 规格与当前代码不符。

**建议**：在架构文档顶部添加「修订记录」section，标注视觉方案从红色发光改为图钉角标的变更。

**P1-2: 行号引用已失效**

文档中引用的具体行号（如"第 88-99 行"、"第 252-260 行"等）在代码变更后已不准确，降低了文档的参考价值。

**建议**：将行号引用替换为方法名/属性名引用（如"panelPinButton 属性声明"），避免行号漂移。

### P2 建议

**P2-1: UC-5 可补充"面板关闭方式"的完整枚举**

UC-5 列出了面板保持显示直到"单击悬浮球钉住/取消钉住、快捷键隐藏、拖拽悬浮球"三种关闭方式，但实际上还有"点击面板外区域"（如果面板未钉住时有此行为）。建议确认并补全关闭方式列表。

**P2-2: 状态转换矩阵可补充"面板不可见"初始状态**

当前矩阵假设面板已可见，未覆盖"面板不可见 → hover 进入悬浮球 → autoRetractOnHover=false"这一路径。虽然此场景下面板弹出后的行为由 mouseExited 控制（已正确处理），但在矩阵中显式列出可提升完整性。
