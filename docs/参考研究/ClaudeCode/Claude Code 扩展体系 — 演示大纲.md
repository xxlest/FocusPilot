# Claude Code 扩展体系 — 演示大纲

> 适用于 PPT/Keynote 制作，每张 Slide 标注标题、要点和讲解备注。
> 预估时长：45-60 分钟。

---

## Slide 1: 封面

**标题**: Claude Code 扩展体系深度解析

**副标题**: 从配置到分发 — 系统化理解 Plugins、Skills、Hooks 与 Agent Teams

**备注**: 开场说明受众假设：已有使用经验，想深入理解底层机制。

---

## Slide 2: 今天的旅程

**内容**:
1. 设计哲学：三个核心原则
2. 六大元素全景图
3. 深入四大核心：Skill → Plugin → Hook → Agent
4. MCP 概览
5. 动手路径

**备注**: 强调这不是入门教程，而是帮大家建立系统化认知。

---

## Slide 3: 设计哲学 — 上下文即配置

**标题**: Context as Config

**要点**:
- 传统 IDE 插件：用代码注册能力 + JSON Schema 定义接口
- Claude Code：**用自然语言 Markdown 文件**作为配置
- 会写 Markdown 就能扩展 Claude 的行为

**配图建议**: 左右对比图 — 传统插件代码 vs CLAUDE.md 自然语言

**备注**: 这不是偷懒，是刻意选择。自然语言比 JSON 能表达更复杂的意图。举例："如果用户没指定格式，默认用 Conventional Commits"——这句话用 JSON Schema 很难表达。

---

## Slide 4: 设计哲学 — 按需加载

**标题**: Load on Demand

**要点**:
- 上下文窗口是有限资源（~200K tokens）
- 不把所有规则塞进一个巨型提示词
- 分层策略：始终加载 / 按需注入 / 事件触发

**配图建议**: 漏斗图 — CLAUDE.md（始终）→ Skill（按需）→ Agent（派发时）→ Hook（事件时）

**备注**: 一个 Skill 可能有 200 行指令，但只有真正需要时才占用上下文。用完即释放。

---

## Slide 5: 设计哲学 — 分层治理

**标题**: Layered Governance

**要点**:
- 四层配置：企业托管 → 用户全局 → 项目共享 → 项目本地
- 高层 deny 不可被低层 allow 覆盖
- 安全策略的不可绕过性

**配图建议**: 金字塔图，从上到下四层

**备注**: 这是企业级使用的关键设计。CTO 可以在托管策略中禁止 `rm -rf`，任何项目的 settings 都无法覆盖。

---

## Slide 6: 六大元素全景图

**标题**: 扩展体系全景

**要点**:
```
Plugin = Skills + Agents + Hooks + MCP + LSP
```

**一句话总结**:
> CLAUDE.md 定义规矩，Skill 定义能力，Agent 定义角色，Hook 定义自动化，MCP 定义外部连接，Plugin 打包分发。

**配图建议**: 六边形架构图，中心是 Claude Code 运行时

**备注**: 先给全貌，再逐个深入。让大家有一个心理框架。

---

## Slide 7: CLAUDE.md — 项目的"宪法"

**要点**:
- 自然语言持久指令文件，每次会话自动加载
- 三级作用域：用户全局 / 项目共享 / 子目录
- 进阶：`@` 导入、`.claude/rules/` 路径限定规则
- 最佳实践：控制在 200 行以内

**代码示例**:
```markdown
# CLAUDE.md
- 回复语言使用中文
- Git 提交信息使用 Conventional Commits
- 禁止直接 push 到 main 分支
```

**备注**: CLAUDE.md 是最基础也最重要的扩展点。很多人把它写得太长或太短，关键是写 Claude 真正需要的上下文：架构、构建命令、编码规范。

---

## Slide 8: Skill — 可复用的任务模板

**标题**: Skill = 结构化的提示词

**要点**:
- 一个文件夹 + 一个 `SKILL.md`
- 两种类型：任务型（`/commit`）vs 参考型（自动注入知识）
- 与 CLAUDE.md 的区别：按需加载 vs 始终加载

**配图建议**: Skill 文件夹结构示意图

**备注**: 本质上 Skill 就是一段经过精心设计的提示词，但有了 frontmatter 就能控制：谁可以调用、何时触发、用什么工具。

---

## Slide 9: Skill Frontmatter 深度解析

**标题**: Frontmatter — 控制 Skill 的"元数据"

**要点**:

| 字段 | 关键理解 |
|------|---------|
| `description` | **最重要！** Claude 靠它判断是否自动触发 |
| `disable-model-invocation` | 防止 Claude 自作主张（部署类操作） |
| `user-invocable: false` | 纯知识注入，用户不需要知道它存在 |
| `argument-hint` | Tab 补全时的参数提示 |
| `context: fork` | 在子代理中运行，不污染主会话 |

**备注**: 很多人的 Skill 写了但从不被自动触发，90% 是因为 description 写得不好。Claude 需要通过 description 判断"当前任务是否需要这个 Skill"。

---

## Slide 10: Skill 调用机制

**标题**: 从 `/commit` 到执行完毕

**配图建议**: 流程图

```
用户输入 /commit no-push
    ↓
查找名为 "commit" 的 Skill
    ↓
读取 SKILL.md，替换 $ARGUMENTS → "no-push"
    ↓
注入当前上下文
    ↓
Claude 按指令执行
    ↓
完毕，Skill 释放上下文
```

**备注**: 自动触发时流程类似，只是第一步变成 Claude 扫描所有 Skill 的 description 来匹配。

---

## Slide 11: Plugin — 可分发的能力包

**标题**: Plugin = Skills + Agents + Hooks + MCP 的打包

**要点**:
- 命名空间：`/plugin-name:skill-name`，不会冲突
- 版本管理：`plugin.json` 中声明
- 一键安装：`claude plugin install`
- Marketplace 分发

**与散装文件对比**:
| 散装 | Plugin |
|------|--------|
| 手动拷贝 | 一键安装 |
| 可能冲突 | 命名空间隔离 |
| 无版本 | 语义化版本 |

**备注**: Plugin 解决的核心问题是"分发"。一个团队的最佳实践，怎么让其他团队也能用？

---

## Slide 12: Plugin 目录结构

**标题**: Plugin 的物理结构

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json       ← 只放这一个文件！
├── skills/               ← 技能集合
├── agents/               ← 自定义代理
├── hooks/
│   └── hooks.json        ← 自动发现，不需要声明
├── .mcp.json             ← MCP 服务器
└── settings.json         ← 默认设置
```

**三个易错点**:
1. `.claude-plugin/` 内只放 `plugin.json`
2. `hooks.json` 自动加载，重复声明会报错
3. `agents` 必须指向具体文件，不支持目录路径

**备注**: 这三个坑是新手最常踩的。

---

## Slide 13: Marketplace 机制

**标题**: 插件的发现与分发

**要点**:
- 官方 Marketplace：内置，包含精选插件
- 自定义 Marketplace：配置 GitHub/GitLab 仓库
- 插件来源：本地路径 / GitHub / Git / npm
- 缓存在 `~/.claude/plugins/cache/`

**配图建议**: 流程图 — 搜索 → 选择 → 安装 → 缓存 → 启用

**备注**: 目前生态还在早期，但已经有一些高质量的社区插件，比如 superpowers、everything-claude-code。

---

## Slide 14: Hooks — 事件驱动的守护者

**标题**: Hook = 生命周期拦截器

**要点**:
- 在 Claude 动作的前后插入检查/转换/记录
- 类比 CI/CD 的 pre-commit hook
- 21 种事件类型，4 种 Hook 类型
- 退出码 0 = 继续，2 = 阻断

**备注**: Hook 不改变 Claude 的思考过程，而是在"动作层"做拦截。

---

## Slide 15: Hook 事件类型全览

**标题**: 21 种事件，覆盖完整生命周期

**分组展示**:

| 分类 | 事件 | 典型用途 |
|------|------|---------|
| 会话 | SessionStart/End, InstructionsLoaded | 环境初始化 |
| 用户 | UserPromptSubmit, PermissionRequest | 输入验证 |
| 工具 | Pre/PostToolUse, PostToolUseFailure | **安全检查、自动格式化** |
| 响应 | Stop, Notification | **质量门控、桌面通知** |
| 团队 | SubagentStart/Stop, TeammateIdle, TaskCompleted | 团队协调 |
| 上下文 | PreCompact, PostCompact, ConfigChange | 上下文保护 |
| Worktree | WorktreeCreate/Remove | Git 隔离 |
| MCP | Elicitation, ElicitationResult | 用户输入代理 |

**备注**: 重点讲 PreToolUse（安全）、PostToolUse（自动化）、Stop（质量门控）、Notification（通知）这四个最常用的。

---

## Slide 16: 四种 Hook 类型

**标题**: 从 Shell 脚本到 AI 子代理

| 类型 | 执行方式 | 适用场景 |
|------|---------|---------|
| `command` | Shell 脚本 | 文件检查、格式化 |
| `http` | POST 到端点 | 远程审计、团队通知 |
| `prompt` | 单轮 LLM | 质量检查 |
| `agent` | 多轮子代理 | 复杂测试验证 |

**备注**: `prompt` 和 `agent` 类型意味着你可以用 AI 来检查 AI 的输出。比如用一个 prompt hook 在 Stop 时检查"任务是否真的完成了"。

---

## Slide 17: Hook 实战 — 三个经典案例

**案例 1**: 阻止编辑 `.env`（PreToolUse + command）
**案例 2**: 编辑后自动 Prettier（PostToolUse + command）
**案例 3**: AI 质量门控（Stop + prompt）

**备注**: 现场演示或截图展示实际效果。重点是退出码 2 = 阻断的机制。

---

## Slide 18: Agent 体系 — Subagent

**标题**: 子代理 = 独立上下文的专门助手

**要点**:
- 与 Skill 的区别：Skill 注入主会话 vs Agent 独立窗口
- 三种内置类型：Explore（快速搜索）、Plan（只读研究）、General（全能）
- 自定义 Agent：定义角色、限制工具、指定模型

**配图建议**: 主 Claude 指挥多个 Subagent 的示意图

**备注**: 经验法则 — "按手册操作"用 Skill，"换个人来做"用 Agent。

---

## Slide 19: Agent 权限模型

**标题**: 五种权限模式

| 模式 | 行为 | 场景 |
|------|------|------|
| `default` | 弹窗确认 | 日常开发 |
| `acceptEdits` | 自动接受编辑 | 信任任务 |
| `plan` | 只读 | 方案设计 |
| `dontAsk` | 自动拒绝 | CI/CD |
| `bypassPermissions` | 跳过检查 | 沙盒（慎用） |

**备注**: 权限从 Team Lead 继承，但可以为单个 Agent 覆盖。deny 规则不可被覆盖。

---

## Slide 20: Agent Teams（实验性）

**标题**: 从单兵作战到团队协作

**要点**:
- Subagent 是"派发-返回"，Teams 是"并行协作"
- 核心组件：Team Lead + Teammates + 共享任务列表 + 邮箱通信
- 每个 Teammate 是独立 Claude 实例
- 支持直接互相通信（`@teammate-name`）

**对比表**:
| | Subagent | Teams |
|--|----------|-------|
| 上下文 | 共享 | 独立 |
| 通信 | 仅报告 | 双向 |
| 适用 | 快速任务 | 复杂并行 |

**备注**: 需要 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 启用。团队 3-5 人最有效。

---

## Slide 21: Worktree 隔离

**标题**: Git Worktree — 多 Agent 的并行安全网

**要点**:
- 每个 Agent 在独立 Git 分支上工作
- 避免文件冲突
- 完成后自动清理（无修改时）

**配图建议**:
```
主仓库 ─── worktree-auth（Agent A）
       ├── worktree-api（Agent B）
       └── worktree-test（Agent C）
```

**备注**: Worktree 是 Agent Teams 并行工作的基础设施。

---

## Slide 22: MCP — 连接外部世界（概览）

**标题**: Model Context Protocol

**要点**:
- 让 Claude 调用外部工具的标准协议
- 三种传输：http（推荐）/ stdio（本地）/ sse（弃用）
- 快速接入：`claude mcp add --transport http github https://mcp.github.com`
- 可在 Plugin 中打包分发

**备注**: MCP 的详细原理不展开，重点是它在扩展体系中的定位——"外部连接层"。

---

## Slide 23: 完整案例串联

**标题**: 一个功能从需求到上线

```
接收需求 → CLAUDE.md 加载上下文
    → /brainstorm（Skill）设计方案
    → /write-plan（Skill）生成计划
    → Agent Teams 并行开发
        → PostToolUse Hook 自动 lint
        → PreToolUse Hook 安全检查
        → MCP 查 GitHub issue
    → /commit（Skill）提交代码
```

**配图建议**: 流程图，标注每一步用到的元素

**备注**: 这是一个真实的开发流程，展示所有元素如何协作。

---

## Slide 24: 动手路径

**标题**: 6 步上手

1. 创建 CLAUDE.md（5 分钟）
2. 写一个 Skill（10 分钟）
3. 配一个 Hook（10 分钟）
4. 写一个 Agent（10 分钟）
5. 打包成 Plugin（15 分钟）
6. 逛 Marketplace（5 分钟）

**备注**: 鼓励现场动手，或者作为课后作业。

---

## Slide 25: 总结与 Q&A

**核心记忆点**:
- 三个原则：上下文即配置 / 按需加载 / 分层治理
- 六大元素：CLAUDE.md / Skill / Agent / Hook / MCP / Plugin
- 经验法则："按手册操作"用 Skill，"换个人来做"用 Agent
- Plugin 是分发的载体，不是新概念

**配图建议**: 全景架构图（回到 Slide 6）

**备注**: 留 10-15 分钟 Q&A。常见问题：Skill 和 Agent 怎么选、Hook 怎么调试、Plugin 怎么发布。
