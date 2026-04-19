# 你以为你会用 Claude Code？深入理解它的扩展体系

> 大多数人只用到了 Claude Code 10% 的能力。这篇文章帮你系统化理解它的底层设计——Plugins、Skills、Hooks、Agent Teams 到底是什么，以及它们如何协作。

---

## 一句话讲清 Claude Code 的设计哲学

如果要用一句话概括 Claude Code 和传统 IDE 插件的区别，那就是：

**传统插件用代码扩展能力，Claude Code 用自然语言扩展能力。**

这不是偷懒，而是刻意的设计选择。背后有三个核心原则：

**上下文即配置**——你写给 Claude 的 Markdown 文件就是它的"代码"。会写文档就能扩展它的行为，不需要学 API。

**按需加载**——上下文窗口是有限资源。不把所有规则塞进一个巨型提示词，而是拆成模块，只在需要时加载，用完释放。

**分层治理**——从企业到项目到个人，每一层都能设置规则和权限，高层的 deny 不可被低层覆盖。

理解了这三个原则，后面的所有概念都是自然推导出来的。

---

## 全景图：六大元素各司其职

Claude Code 的扩展体系由六大元素组成，它们的关系可以用一句话总结：

> CLAUDE.md 定义规矩，Skill 定义能力，Agent 定义角色，Hook 定义自动化，MCP 定义外部连接，Plugin 把它们打包分发。

先记住这句话，接下来逐个拆解。

---

## CLAUDE.md：项目的"宪法"

这是最基础也最重要的扩展点。

CLAUDE.md 是一个自然语言编写的指令文件，每次你和 Claude 对话时，它会自动加载到上下文中。相当于给 Claude 一份"入职手册"——你的技术栈、编码规范、项目架构，都写在里面。

它有三级作用域：

- **用户全局**（`~/.claude/CLAUDE.md`）：你的个人习惯，比如"永远用中文回复"
- **项目共享**（`./CLAUDE.md`）：团队规范，比如"使用 Conventional Commits"
- **子目录**（`./src/api/CLAUDE.md`）：模块特定规则

Claude 会从当前目录向上遍历，逐层加载所有 CLAUDE.md。项目级的可以提交到 Git，团队所有人的 Claude 都会遵守同样的规则。

**一个常见误区**：CLAUDE.md 不是越长越好。超过 200 行会被截断，而且信息越多，Claude 的"注意力"越分散。关键信息用简洁的条目列出来就好。

---

## Skill：可复用的任务模板

如果说 CLAUDE.md 是"始终生效的规矩"，那 Skill 就是"按需调用的能力"。

Skill 本质上是一段**结构化的提示词**。它住在一个文件夹里，通过 YAML frontmatter 声明自己的元数据——谁可以调用、何时触发、用什么工具。

举个例子，你每次提交代码都要手动执行一堆步骤：查看 diff、写 commit message、push。把这些步骤写成一个 Skill：

```yaml
# .claude/skills/commit/SKILL.md
---
name: commit
description: 规范化 Git 提交流程
argument-hint: "默认: commit+push | [no-push] 仅提交"
---
1. 运行 git diff --staged 查看变更
2. 生成 Conventional Commits 格式的提交信息
3. 执行 git commit
4. 若无 no-push 参数，执行 git push
```

之后你只需要输入 `/commit`，Claude 就按流程执行。输入 `/commit no-push` 就只提交不推送。

**Skill 有两种类型**：

- **任务型**：用户手动调用（`/commit`、`/brainstorm`），执行一套标准流程
- **参考型**：Claude 自动判断是否需要，静默注入知识（编码规范、API 文档）

**关于 frontmatter 中最重要的字段**：`description`。

Claude 通过 description 来判断"当前任务是否需要加载这个 Skill"。写不好 = 永远不会被自动触发。比如你写了个 Skill 叫 `code-review`，description 写成"代码审查"，太模糊了。Claude 不知道什么时候该用它。写成"审查代码质量和安全性。当检查 PR、审查代码变更时使用"就清晰多了。

---

## Plugin：可分发的能力包

当你写了几个好用的 Skill、定义了几个 Agent、配了一些 Hook，你会想："能不能打包分享给团队？"

这就是 Plugin 存在的意义——把 Skills、Agents、Hooks、MCP 配置打包成一个目录，通过 Marketplace 一键安装。

Plugin 的目录结构长这样：

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json       # 插件元数据（只放这一个文件！）
├── skills/               # 技能集合
├── agents/               # 自定义代理
├── hooks/
│   └── hooks.json        # 会被自动发现，不需要在 plugin.json 声明
├── .mcp.json             # MCP 服务器配置
└── README.md
```

**Plugin 解决的核心问题是分发**。散装的 Skill 文件需要手动拷贝、容易冲突；Plugin 有命名空间（`/plugin-name:skill-name`）、有版本管理、有一键安装卸载。

**三个新手最常踩的坑**：
1. `.claude-plugin/` 目录内只放 `plugin.json`，其他东西放在插件根目录
2. `hooks/hooks.json` 会被自动发现，如果又在 plugin.json 里声明一次会报错
3. `agents` 字段必须指向具体的 `.md` 文件，不支持目录路径

Marketplace 是插件的发现和分发中心。除了官方 Marketplace，你也可以搭建自己的，只需要一个 GitHub 仓库加一个 `marketplace.json`。

---

## Hook：事件驱动的守护者

前面讲的 CLAUDE.md、Skill、Agent 都是在**指令层**影响 Claude 的行为。Hook 不一样，它在**动作层**做拦截。

Hook 是在 Claude Code 生命周期的特定节点自动执行的逻辑。比如：

- 每次 Claude 要执行 Shell 命令**之前**，检查是不是危险命令（`PreToolUse`）
- 每次 Claude 编辑文件**之后**，自动运行 Prettier 格式化（`PostToolUse`）
- Claude 说"任务完成了"的时候，用另一个 AI 检查是不是真的完成了（`Stop`）

Claude Code 支持 **21 种**事件类型，覆盖从会话开始到结束的完整生命周期。最常用的四个：

| 事件 | 触发时机 | 典型用途 |
|------|---------|---------|
| `PreToolUse` | 工具执行前 | 安全检查、阻止危险操作 |
| `PostToolUse` | 工具执行后 | 自动格式化、自动 lint |
| `Stop` | Claude 完成回答 | 质量门控、完成度检查 |
| `Notification` | 需要通知用户 | 桌面提醒、声音警告 |

Hook 有四种类型：`command`（Shell 脚本）、`http`（远程端点）、`prompt`（单轮 LLM 判断）、`agent`（多轮子代理验证）。

**最有意思的是 `prompt` 和 `agent` 类型**——你可以用 AI 来检查 AI 的输出。比如在 Stop 事件上挂一个 prompt hook："检查所有任务是否完成。如果有遗漏，返回 `{ok: false, reason: '...'}`"。Claude 说完了但实际没完，hook 会把它打回去继续做。

退出码的约定很简单：**0 = 继续，2 = 阻断**。其他退出码视为非关键错误，记录但不阻断。

---

## Agent 体系：从子代理到团队协作

### Subagent（子代理）

子代理是拥有**独立上下文窗口**的专门助手。主 Claude 可以把任务委派给它，完成后接收结果。

和 Skill 的区别一句话说清：**Skill 是"按手册操作"，Agent 是"换个人来做"**。

Skill 注入到主会话内，共享上下文；Agent 开一个新窗口，有自己的工具权限和上下文。主会话不会被 Agent 的中间过程污染。

你可以自定义 Agent，比如一个代码审查员：

```yaml
# .claude/agents/reviewer.md
---
name: reviewer
description: 代码质量审查专家
tools: Read, Grep, Glob
model: sonnet
permissionMode: plan    # 只读，不修改代码
---
你是代码审查员。检查安全漏洞、DRY 违反和测试覆盖。
```

主 Claude 写完代码后，自动派发 reviewer 检查，形成"双重校验"。

### 五种权限模式

每个 Agent 可以独立设置权限：

- **default**：遇到权限问题弹窗确认
- **acceptEdits**：自动接受文件编辑
- **plan**：只读模式，不执行不修改
- **dontAsk**：自动拒绝未预批准的操作
- **bypassPermissions**：跳过所有检查（慎用）

### Agent Teams（实验性）

如果 Subagent 是"派发-返回"的单向模式，Agent Teams 就是**多个独立会话的并行协作**。

启用后（需要设置环境变量），你可以创建一个团队：Team Lead 分配任务，多个 Teammate 在各自独立的上下文中并行工作，彼此之间可以直接通信。

```
Team Lead（主会话）
    ├── Teammate A：前端开发（独立上下文）
    ├── Teammate B：后端 API（独立上下文）
    └── Teammate C：测试编写（独立上下文）
```

Teammate 之间可以发消息（`@teammate-a 请把接口文档发给我`），也可以广播（`broadcast: 数据库 schema 已更新`）。

每个 Teammate 可以使用 **Git Worktree** 隔离——在独立的 Git 分支上工作，避免文件冲突。完成后如果没有修改，worktree 自动清理。

**Teams 的最佳实践**：3-5 人最有效；每个 Teammate 负责不同的文件集；从边界清晰的任务开始。

---

## MCP：连接外部世界

MCP（Model Context Protocol）是让 Claude 调用外部工具的标准协议。通过它，Claude 可以连接 GitHub、数据库、浏览器等外部服务。

一行命令接入：

```bash
claude mcp add --transport http github https://mcp.github.com
```

接入后 Claude 就能直接调用 GitHub API 查看 issue、创建 PR。MCP 也可以在 Plugin 中打包分发。

这里不展开原理，只需要知道它在扩展体系中的定位——**外部连接层**。

---

## 所有元素如何协作：一个真实场景

用"给项目加用户登录功能"串联所有元素：

```
1. CLAUDE.md 自动加载项目上下文（技术栈、规范）
2. /brainstorm（Skill）和你讨论方案 → 确认用 JWT
3. /write-plan（Skill）生成分步计划
4. Agent Teams 并行开发：
   - Teammate A 写 auth 模块
   - Teammate B 写 API 端点
   - Teammate C 写测试
5. 每次编辑文件 → PostToolUse Hook 自动 lint
6. 每次 Bash 执行 → PreToolUse Hook 检查危险命令
7. 需要查 issue → MCP 连接 GitHub
8. /commit（Skill）提交代码
```

六大元素各司其职，无缝协作。

---

## 总结

**三个原则**：上下文即配置 / 按需加载 / 分层治理

**六大元素**：CLAUDE.md（规矩）→ Skill（能力）→ Agent（角色）→ Hook（自动化）→ MCP（外部连接）→ Plugin（打包分发）

**两个经验法则**：
- "按手册操作"用 Skill，"换个人来做"用 Agent
- 不确定是否需要一个 Hook？如果你发现自己每次都在手动做同一件事，那就需要

**动手路径**：先写 CLAUDE.md → 再写一个 Skill → 配一个 Hook → 定义一个 Agent → 打包成 Plugin → 逛 Marketplace 找灵感。

Claude Code 的扩展体系设计得非常优雅——所有配置都是 Markdown 和 JSON，没有编译、没有 SDK、没有运行时依赖。这意味着学习成本极低，但能力上限极高。

你距离用好它，只差一个 CLAUDE.md 的距离。
