# Claude Code 扩展体系 — 10 道面试题

> 覆盖设计哲学、Skill、Plugin、Hook、Agent、权限模型等维度，适合培训后考核或自测。

---

## 题目 1：设计哲学（概念理解）

**CLAUDE.md 和 Skill 都是 Markdown 文件，都能影响 Claude 的行为。它们的本质区别是什么？在什么场景下应该把内容放在 CLAUDE.md 而不是 Skill 中？**

**答案**：

本质区别在于**加载策略**：

- CLAUDE.md 是**始终加载**的——每次会话自动注入上下文，不可卸载
- Skill 是**按需加载**的——用户调用或 Claude 判断需要时才注入，用完释放

应该放在 CLAUDE.md 中的内容是**每次对话都需要 Claude 知道的信息**：项目架构、技术栈、编码规范、构建命令。这些是"基本国情"。

应该放在 Skill 中的内容是**特定任务才需要的流程或知识**：提交规范的详细步骤、代码审查的检查清单、部署流程。这些是"专项技能"。

如果把所有东西都塞进 CLAUDE.md，会浪费上下文窗口（200 行截断限制），还会增加"认知噪音"，降低 Claude 对关键信息的注意力。

---

## 题目 2：Skill（frontmatter 机制）

**一个 Skill 的 `description` 写得好不好，直接决定了它能不能被 Claude 自动触发。请解释自动触发的机制，并给出一个"好的 description"和一个"差的 description"的对比。**

**答案**：

自动触发机制：当 `disable-model-invocation` 为 `false`（默认值）时，Claude 在收到用户消息后，会扫描所有 Skill 的 `description` 字段，判断当前任务是否匹配。匹配则通过 Skill tool 加载并执行。

**差的 description**：
```yaml
description: 代码审查
```
问题：太模糊。Claude 不知道"什么时候算代码审查"——是用户说"帮我看看代码"的时候？还是写完代码之后？

**好的 description**：
```yaml
description: 审查代码质量和安全性。当用户要求检查 PR、审查代码变更、或 review 代码时使用。
```
好在哪里：明确描述了**功能**（审查质量和安全性）和**触发条件**（检查 PR、审查变更、review），Claude 能精准匹配用户意图。

---

## 题目 3：Skill vs Agent（选型判断）

**以下四个场景，分别应该用 Skill 还是 Agent？说明理由。**

1. 每次提交代码前自动生成 Conventional Commits 格式的 commit message
2. 让 Claude 对刚写完的 500 行代码做安全审查，但不希望审查过程的中间思考污染主会话
3. 给 Claude 注入公司内部 API 的调用约定，让它写代码时自动遵守
4. 同时让三个"Claude"分别开发前端、后端和测试模块

**答案**：

1. **Skill**。这是一个标准化流程（"按手册操作"），不需要独立上下文，主会话内执行即可。
2. **Agent**。需要独立上下文（不污染主会话），且可以限制为只读权限（`permissionMode: plan`），属于"换个人来做"。
3. **Skill**（参考型，`user-invocable: false`）。这是纯知识注入，不是一个任务。设为 `user-invocable: false` 后不出现在 `/` 菜单，Claude 自动判断是否需要加载。
4. **Agent Teams**。需要多个独立上下文并行工作，且可能需要 Worktree 隔离避免文件冲突。Subagent 不够——它是"派发-返回"的单向模式，不支持 Teammate 之间的直接通信和共享任务列表。

---

## 题目 4：Hook（事件类型与执行机制）

**Claude Code 的 Hook 退出码中，`0`、`2` 和其他值分别代表什么？如果一个 PreToolUse Hook 想要"不阻断操作，但给 Claude 注入一条警告信息"，应该怎么实现？**

**答案**：

退出码含义：
- `0`：允许操作继续
- `2`：**阻断操作**，阻止工具执行
- 其他（如 1）：允许继续，但记录为非关键警告

要实现"不阻断但注入警告"：退出码用 `0`（不阻断），同时将警告信息输出到 **stderr**。Claude 会看到 stderr 的内容作为上下文信息，但不会阻止工具执行。

```bash
#!/bin/bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE" == *"legacy"* ]]; then
  echo "警告：正在修改遗留代码，请确保有充分测试覆盖" >&2
fi
exit 0  # 不阻断
```

---

## 题目 5：Hook（高级类型）

**Hook 有四种类型：`command`、`http`、`prompt`、`agent`。请解释 `prompt` 和 `agent` 类型的区别，并给出一个适合用 `prompt` 而不是 `agent` 的场景。**

**答案**：

| | `prompt` | `agent` |
|--|----------|---------|
| 执行方式 | 单轮 LLM 评估 | 多轮子代理，可使用工具 |
| 能力 | 只能基于输入信息判断 | 可以读文件、跑命令、多步推理 |
| 速度 | 快（单次调用） | 慢（多轮对话） |
| 成本 | 低 | 高 |

适合用 `prompt` 的场景：**Stop 事件的完成度检查**。

```json
{
  "type": "prompt",
  "prompt": "检查 Claude 的最终回复是否完整回答了用户问题。如果有遗漏返回 {\"ok\": false, \"reason\": \"...\"}"
}
```

这里只需要基于已有的对话上下文做判断，不需要额外读文件或执行命令，单轮 LLM 足矣。如果换成验证"所有单元测试是否通过"，就需要 `agent` 类型——因为它要实际运行 `npm test` 并分析结果。

---

## 题目 6：Plugin（结构规范）

**以下 Plugin 目录结构有三个错误，请指出并说明如何修正。**

```
my-plugin/
├── .claude-plugin/
│   ├── plugin.json
│   └── hooks.json        # (1)
├── skills/
│   └── deploy/
│       └── SKILL.md
├── agents/               # (2) 在 plugin.json 中声明为 "agents": ["./agents/"]
└── hooks/
    └── hooks.json        # (3) 在 plugin.json 中声明为 "hooks": "./hooks/hooks.json"
```

**答案**：

**错误 1**：`hooks.json` 放在了 `.claude-plugin/` 目录内。
**修正**：`.claude-plugin/` 内只能放 `plugin.json`，其他所有内容必须在插件根目录。将 hooks.json 移到 `hooks/` 目录下。

**错误 2**：`agents` 字段使用了目录路径 `"./agents/"`。
**修正**：`agents` 必须指向具体的 `.md` 文件，不支持目录扫描。改为 `"agents": ["./agents/reviewer.md", "./agents/tester.md"]`。

**错误 3**：`hooks/hooks.json` 在 plugin.json 中被显式声明了。
**修正**：`hooks/hooks.json` 会被自动发现和加载，重复声明会导致 "duplicate hooks" 错误。删除 plugin.json 中的 `"hooks"` 字段即可。

---

## 题目 7：权限模型（安全设计）

**在 Claude Code 的分层配置中，企业管理员在托管策略中设置了 `"deny": ["Bash(rm -rf *)"]`。一个项目的 `.claude/settings.json` 中设置了 `"allow": ["Bash(rm -rf /tmp/*)"]`。请问这个 allow 规则能否生效？为什么？**

**答案**：

**不能生效。**

Claude Code 的权限模型遵循"deny 不可覆盖"原则：任何层级的 `deny` 都无法被其他层级（包括更低层级）的 `allow` 覆盖。

优先级链路是：`企业托管策略 > 用户全局 > 项目共享 > 项目本地`。虽然项目级的 allow 试图放行 `rm -rf /tmp/*`，但它被企业级的 deny 规则 `rm -rf *` 模式匹配覆盖了。

这是安全设计的核心——保证安全策略的不可绕过性。管理员设定的禁令，任何下游配置都无法解除。

---

## 题目 8：Agent Teams（架构理解）

**Subagent 和 Agent Teams 都能实现"多个 Claude 并行工作"。请从上下文管理、通信方式和适用场景三个维度，解释它们的核心区别。如果你要做一个"让三个 Agent 分别调研三个竞品"的任务，应该选哪个？为什么？**

**答案**：

| 维度 | Subagent | Agent Teams |
|------|----------|-------------|
| 上下文 | 共享父会话上下文（结果汇总回主会话） | 完全独立的上下文窗口 |
| 通信 | 单向——仅向主 Agent 报告结果 | 双向——Teammate 之间可直接通信（`@name`），有共享任务列表 |
| 适用场景 | 快速委派、结果汇总（搜索、分析） | 复杂并行工作、需要协调讨论 |

竞品调研任务应该选 **Subagent**。理由：

1. 三个调研任务是**独立的**，不需要 Agent 之间互相沟通
2. 最终结果需要**汇总回主会话**做对比分析，Subagent 天然支持这种"派发-返回"模式
3. Subagent 的 Token 成本更低（结果汇总 vs 独立上下文）
4. 不需要共享任务列表或互相通信

Agent Teams 更适合的场景是：前端/后端/测试同时开发同一个功能，需要互相对接口、协调 schema 变更。

---

## 题目 9：Hook 事件全景（综合应用）

**请设计一套 Hook 配置，实现以下三个需求：**

1. Claude 每次执行 Bash 命令前，如果命令包含 `sudo`，阻断执行
2. Claude 每次编辑 `.swift` 文件后，自动运行 `swiftformat`
3. Claude 完成回答时，发送 macOS 桌面通知

**答案**：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r \".tool_input.command // empty\"); if echo \"$CMD\" | grep -q \"sudo\"; then echo \"禁止使用 sudo\" >&2; exit 2; fi; exit 0'"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'INPUT=$(cat); FILE=$(echo \"$INPUT\" | jq -r \".tool_input.file_path // empty\"); if [[ \"$FILE\" == *.swift ]]; then swiftformat \"$FILE\" 2>/dev/null; fi; exit 0'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude 已完成回答\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

关键点：
- PreToolUse + matcher `Bash` + 退出码 `2` 实现阻断
- PostToolUse + matcher `Edit|Write` + 在脚本内判断 `.swift` 后缀
- Stop + 空 matcher（匹配所有）+ `osascript` 发送 macOS 通知

---

## 题目 10：全局视角（综合设计）

**你的团队有以下需求：**

- **所有成员**都必须使用 ESLint + Prettier 格式化代码
- **新人**在提交前需要 Claude 自动做一次代码审查
- **技术负责人**可以跳过审查直接提交
- 团队有一套内部 API 调用规范，希望 Claude 写代码时自动遵守
- 以上配置需要**一键分发给新成员**

**请设计方案，说明每个需求分别用哪个元素实现，以及整体如何打包。**

**答案**：

| 需求 | 元素 | 实现方式 |
|------|------|---------|
| ESLint + Prettier | **Hook**（PostToolUse） | matcher 匹配 `Edit\|Write`，脚本中按后缀执行对应格式化工具 |
| 新人代码审查 | **Agent** + **Skill** | 定义 `reviewer` Agent（只读权限），在 `/commit` Skill 中加入"提交前派发 reviewer"的步骤 |
| 技术负责人跳过审查 | **Skill 参数** | `/commit skip-review`，Skill 中判断 `$ARGUMENTS` 包含 `skip-review` 则跳过审查步骤 |
| 内部 API 规范 | **Skill**（参考型） | `user-invocable: false`，description 写明触发条件，Claude 在写 API 代码时自动加载 |
| 一键分发 | **Plugin** | 把以上所有内容打包到 Plugin 目录中 |

**Plugin 目录结构**：

```
team-workflow/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── commit/
│   │   └── SKILL.md          # 提交流程（含可选审查）
│   └── api-conventions/
│       └── SKILL.md          # 内部 API 规范（参考型）
├── agents/
│   └── reviewer.md            # 代码审查代理
└── hooks/
    └── hooks.json             # PostToolUse 自动格式化
```

新成员只需 `claude plugin install team-workflow` 即可获得全套工作流。

**权限分级**的另一种实现思路：不依赖 Skill 参数，而是在 Hook 中通过环境变量判断角色。在用户级 `settings.json` 中设置 `"env": {"TEAM_ROLE": "lead"}`，Hook 脚本中读取 `$TEAM_ROLE` 决定是否执行审查。这样更隐式，不依赖用户记得传参数。
