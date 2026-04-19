# FocusPilot 智能眼镜完整方案

> 日期：2026-04-11
> 适用范围：FocusPilot 语音输入、可穿戴设备接入、智能眼镜产品路线与技术落地
> 配套调研：[智能眼镜开发者能力调研报告.md](/Users/bruce/Workspace/2-Code/01-work/FocusPilot/docs/专题研究/智能眼镜/智能眼镜开发者能力调研报告.md)

---

## 一、结论先行

对 FocusPilot 来说，智能眼镜不是一个应该先从“硬件适配”切入的方向，而应该被定义为：

**把 FocusPilot 升级为一个可接入可穿戴语音输入的工作流中枢，智能眼镜只是其中一个入口。**

所以最优路线不是：

1. 先选一副眼镜
2. 研究它的 SDK
3. 把音频推到 Mac

而是：

1. 先做 FocusPilot 的统一语音输入桥
2. 证明语音输入对 FocusPilot 用户有高频价值
3. 再接入最合适的眼镜硬件

这意味着第一阶段的目标不是“做一个眼镜版 FocusPilot”，而是“做一个对眼镜友好的 FocusPilot”。

## 二、为什么不能直接按调研报告开做

调研报告已经很好地回答了“哪些眼镜可开发、哪些链路可行”，但还不足以直接指导产品立项。主要原因有三个：

### 1. 它证明了技术可接，没有证明产品值得做

报告对 PCM、LC3、BLE、手机中继这些技术路径判断基本成立，但 FocusPilot 真正需要回答的是：

- 用户为什么不用 AirPods 或系统听写？
- 语音输入进来以后，应该直接执行动作，还是先进入收件箱？
- 眼镜带来的增益，究竟是更快、更隐蔽，还是更低打断？

这些问题不先回答，硬件适配越深入，走偏的成本越高。

### 2. 它默认“语音转文字就够了”，但 FocusPilot 需要的是“语音转工作流”

对 FocusPilot 来说，真正有价值的不是把一句话变成文本，而是把一句话变成下面几类动作之一：

- 创建 Todo
- 切换应用或窗口
- 给当前 AI 会话发指令
- 记录稍后处理事项
- 进入安全的 Inbox 等待二次整理

如果只是“转写后丢给某个输入框”，那这个能力很难形成产品壁垒。

### 3. 它还没有把硬件选型和业务优先级绑定起来

开发者开放度不等于 FocusPilot 的最佳优先级。

对 FocusPilot 来说，正确排序应当是：

- 最快验证价值：系统语音 / iPhone Shortcut / 蓝牙耳机
- 最快验证眼镜技术原型：Brilliant Frame
- 最接近消费形态试点：Rokid
- 最后再考虑：Even G1、MentraOS、HUD 扩展

## 三、FocusPilot 应该怎么变

### 1. 从窗口管理器升级为工作流路由器

当前 FocusPilot 的核心能力是：

- 悬浮球常驻入口
- 快捷面板切换
- App / 窗口前置
- AI 会话管理

要承接智能眼镜输入，它还需要新增一个系统级能力：

**接收一句语音，理解它属于哪类意图，并把它送到正确的动作执行器。**

这一步比适配哪副眼镜更重要。

### 2. 新增统一语音输入桥

建议新增 `InputBridgeService`，作为所有外部语音来源的统一入口。

它负责接入：

- 系统语音输入
- iPhone Shortcut
- 任意蓝牙耳机/麦克风
- Brilliant Frame 的 BLE 守护进程
- Rokid Android Companion App
- 后续其他眼镜/手机中继来源

它不关心底层设备细节，只接收统一事件。

建议事件模型：

```json
{
  "source": "system_dictation | iphone_shortcut | brilliant_frame | rokid_android",
  "mode": "free_dictation | command | push_to_ai | quick_note",
  "target": "inbox | todo | app_switch | ai_session | global",
  "text": "切到 Cursor",
  "confidence": 0.93,
  "locale": "zh-CN",
  "timestamp": "2026-04-11T10:00:00+08:00",
  "device_id": "frame-dev-01"
}
```

### 3. 新增语音意图路由

建议补三层能力：

- `VoiceIntentRouter`
- `VoiceActionExecutor`
- `VoiceFeedbackService`

分别负责：

- 识别这句语音是什么类型
- 调用 Todo、窗口切换、AI 会话等现有服务
- 给用户回显处理结果

### 4. 新增安全落点 Inbox

如果语音命令不够确定，不能直接执行高风险动作。

所以需要一个默认安全落点：

- `Inbox`
- `Quick Capture`

所有无法高置信自动执行的输入，都先落到这里。

### 5. 给 AI 会话增加反向输入能力

现有 [`CoderBridgeService.swift`](/Users/bruce/Workspace/2-Code/01-work/FocusPilot/FocusPilot/Services/CoderBridgeService.swift) 已经实现了“外部 AI 会话状态进入 FocusPilot”。

下一步建议补一个反向桥，让 FocusPilot 能将语音文本推回当前活跃 AI 会话。这样智能眼镜输入的最高价值场景就成立了：

- “给当前 Codex 发一句话”
- “让 Claude 先别重构，先补测试”
- “给这个会话追加一个 TODO”

## 四、最好的产品方案

### 产品定位

**FocusPilot Glass Input = FocusPilot 的免打断语音入口。**

不是独立 App，不是眼镜上的复杂界面，也不是只做语音转写工具。

### 最值得做的四个场景

1. 快速捕获
   - 例子：`记一下，下午三点前确认 demo`
   - 结果：进入 Todo 或 Inbox

2. 快速调度
   - 例子：`切到 Cursor`
   - 结果：前置对应 App / 窗口

3. 快速 AI 协作
   - 例子：`给当前 Codex 会话发一句：先补测试`
   - 结果：投递给当前活跃 AI 会话

4. 稍后处理
   - 例子：`记个稍后处理：研究 Claude Code hook`
   - 结果：安全落到 Inbox

### 最小反馈闭环

无论输入源来自耳机、系统语音还是眼镜，用户都必须拿到一致反馈：

- 开始采集
- 正在识别
- 已路由到哪里
- 成功 / 失败
- 失败后如何补救

建议第一阶段反馈方式：

- 悬浮球状态变化
- 顶部 toast
- Quick Panel 最近一次语音结果回显

HUD 回显留到后续阶段。

## 五、最好的技术方案

### 总体架构

```text
Wearable / System Mic / Phone Companion
          |
          v
  Voice Source Adapter
          |
          v
   InputBridgeService
          |
          +--> ASR Adapter
          +--> VoiceIntentRouter
          +--> VoiceActionExecutor
          +--> VoiceFeedbackService
```

### 与现有架构的最佳结合方式

FocusPilot 现有工程里，最接近的先例是 [`CoderBridgeService.swift`](/Users/bruce/Workspace/2-Code/01-work/FocusPilot/FocusPilot/Services/CoderBridgeService.swift)。

所以智能眼镜方案不要自成体系，应该沿用相同模式：

- 外部来源事件进入本地 Service
- Service 做标准化和路由
- 再驱动 UI 和动作执行

这条路线和现有架构兼容性最高，改动最小，也最容易维护。

### FocusPilot 侧建议新增的模块

- `FocusPilot/Services/InputBridgeService.swift`
- `FocusPilot/Models/VoiceInputEvent.swift`
- `FocusPilot/Services/VoiceIntentRouter.swift`
- `FocusPilot/Services/VoiceActionExecutor.swift`
- `FocusPilot/Services/VoiceFeedbackService.swift`

## 六、最好的硬件路线

### P0：先不押眼镜，先做价值验证

输入源：

- 系统语音
- iPhone Shortcut
- 任意蓝牙耳机

目标：

- 证明用户真的愿意用语音驱动 FocusPilot
- 找出最高频的 3 个语音场景
- 验证延迟和识别率是否优于手动操作

这是最值得先做的阶段。

### P1：Brilliant Frame 做技术原型

推荐原因：

- Mac 直连 BLE，链路最短
- 开源、无申请门槛
- 适合快速测端到端延迟和可用性

不推荐一上来做消费包装，只推荐拿它做技术原型。

### P2：Rokid 做消费形态试点

推荐原因：

- 外观和产品形态更接近普通用户想象中的智能眼镜
- 有 HUD，能做简短状态回显
- 国内生态和文档可获得性更高

主要问题：

- 强依赖 Android 手机中继
- 需要申请开发者资格
- 常驻与功耗风险更高

所以它更适合 P2，而不是 P0/P1。

### 暂缓路线

以下路线现在不适合优先投入：

- Even G1：LC3 解码和逆向成本偏高
- MentraOS：太早平台化，增加云中转复杂度
- Ray-Ban Meta：大陆不可用，且无 macOS 路线
- 小米 AI 眼镜：完全封闭

## 七、实施计划

### Phase 0：统一输入桥

交付：

- 本地 `POST /inject`
- 事件标准化
- 意图路由
- Inbox / Todo / App Switch / AI Session 四类动作
- 最小反馈闭环

验收：

- 端到端小于 2 秒
- 成功率大于 90%
- 至少 3 个高频场景连用一周

### Phase 1：Brilliant Frame 原型

交付：

- Mac BLE 守护进程
- 本地 ASR
- 输入桥打通
- 记录延迟、掉包、误识别

### Phase 2：Rokid 试点

交付：

- Android Companion App
- 手机中继
- HUD 简短反馈
- 稳定性与功耗验证

### Phase 3：HUD 与 Agent 化

交付：

- 眼镜状态回显
- AI 会话摘要
- 轻量提醒与确认

## 八、文档整合建议

建议保留两份文档，但角色不同：

1. [`FocusPilot-智能眼镜完整方案.md`](/Users/bruce/Workspace/2-Code/01-work/FocusPilot/docs/专题研究/智能眼镜/FocusPilot-智能眼镜完整方案.md)
   - 作为主文档
   - 面向产品决策、架构设计、实施规划

2. [`智能眼镜开发者能力调研报告.md`](/Users/bruce/Workspace/2-Code/01-work/FocusPilot/docs/专题研究/智能眼镜/智能眼镜开发者能力调研报告.md)
   - 作为附录调研
   - 面向硬件能力、SDK 开放度、选型证据

这样最清晰：主文档讲“应该怎么做”，调研报告讲“为什么这样选”。

## 九、最终建议

最终判断是：

**能做，而且值得做。**

但前提是你把它当成 FocusPilot 的输入能力升级项目，而不是一个先从眼镜硬件适配出发的项目。

一句话总结：

**先做统一语音输入桥，再接智能眼镜；先验证工作流价值，再验证硬件形态。**
