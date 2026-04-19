# Claude Code 扩展体系深度解析

> 面向有使用经验的开发者，系统化理解 Claude Code 的底层设计与扩展机制。

---

## 一、设计哲学：三个核心原则

### 1.1 上下文即配置（Context as Config）

传统 IDE 插件用代码注册能力、用 JSON Schema 定义接口。Claude Code 反其道而行——用**自然语言 Markdown 文件**作为配置。

这不是偷懒，而是刻意的设计选择：

- **降低门槛**：不需要学 API，会写 Markdown 就能扩展 Claude 的行为
- **语义丰富**：自然语言比 JSON 能表达更复杂的意图（"如果用户没指定格式，默认用 Conventional Commits"）
- **即时生效**：改完文件，下次对话立刻生效，不需要编译或重启

### 1.2 按需加载（Load on Demand）

Claude 的上下文窗口是有限资源。把所有规则塞进一个巨型系统提示词，既浪费 Token 又增加"认知噪音"。

Claude Code 的策略是**分层加载**：

| 层次 | 加载时机 | 示例 |
|------|---------|------|
| CLAUDE.md | 始终加载 | 项目架构、编码规范 |
| Skill | 用户调用或 Claude 判断需要时 | `/commit`、`/brainstorm` |
| Agent | 被主 Claude 派发时 | 代码审查、并行开发 |
| Hook | 事件触发时 | 文件编辑后自动格式化 |

这意味着一个 Skill 的 200 行指令，只有在真正需要时才占用上下文窗口。

### 1.3 分层治理（Layered Governance）

从组织到项目到个人，每一层都能设置指令、权限和钩子：

```
企业托管策略（managed-settings.json）    ← 最高优先级，不可覆盖
    ↓
用户全局（~/.claude/settings.json）
    ↓
项目共享（.claude/settings.json）        ← 可提交到 Git
    ↓
项目本地（.claude/settings.local.json）  ← gitignored
```

**关键规则**：任何层级的 `deny` 都无法被低层级的 `allow` 覆盖。这保证了安全策略的不可绕过性。

---

## 二、扩展体系全景图

### 2.1 六大元素及其关系

```
+-----------------------------------------------------------+
|                    Plugin（可分发的能力包）                   |
|  +--------+  +--------+  +-------+  +-----+  +-----+     |
|  | Skills |  | Agents |  | Hooks |  | MCP |  | LSP |     |
|  +---+----+  +---+----+  +---+---+  +--+--+  +--+--+     |
+------|-----------|-----------|---------|---------|---------+
       |           |           |         |         |
       v           v           v         v         v
+-----------------------------------------------------------+
|                Claude Code 运行时引擎                       |
|                                                           |
|  CLAUDE.md    --> 持久上下文（始终加载）                     |
|  Skills       --> 按需注入（用户/AI 触发）                  |
|  Agents       --> 隔离执行（独立上下文窗口）                 |
|  Hooks        --> 事件拦截（生命周期各节点）                 |
|  MCP          --> 外部工具桥接（数据库、API、浏览器）        |
|  Permissions  --> 分层安全控制（贯穿始终）                   |
+-----------------------------------------------------------+
```

### 2.2 一句话总结

> **CLAUDE.md** 定义规矩，**Skill** 定义能力，**Agent** 定义角色，**Hook** 定义自动化，**MCP** 定义外部连接，**Plugin** 把它们打包分发。**Permission** 贯穿始终控制安全。

---

## 三、CLAUDE.md — 项目的"宪法"

### 3.1 是什么

自然语言编写的持久指令文件，每次会话自动加载到 Claude 的上下文中。相当于给 Claude 一份"入职手册"。

### 3.2 三级作用域

| 作用域 | 位置 | 用途 |
|--------|------|------|
| 用户全局 | `~/.claude/CLAUDE.md` | 个人习惯（回复语言、提交风格） |
| 项目共享 | `./CLAUDE.md` 或 `./.claude/CLAUDE.md` | 团队规范（架构说明、编码约定） |
| 子目录 | `./src/api/CLAUDE.md` | 模块特定规则（API 设计约定） |

Claude Code 从当前工作目录向上遍历目录树，依次加载路径上所有 CLAUDE.md 文件。

### 3.3 进阶特性

**文件导入**：用 `@path/to/file` 导入其他 Markdown 文件（最大递归 5 层）。

**路径限定规则**：`.claude/rules/` 目录下的规则文件可用 `paths` frontmatter 限定生效范围：

```markdown
---
paths:
  - "src/api/**/*.ts"
---
# API 开发规则
- 所有端点需输入验证
- 返回标准错误格式
```

### 3.4 最佳实践

- CLAUDE.md 控制在 200 行以内（超出部分会被截断）
- 详细内容拆到 `.claude/rules/` 或单独文件，通过 `@` 引用
- 把架构决策、文件结构、构建命令写进去——这些是 Claude 最需要的上下文

---

## 四、Skills — 可复用的任务模板

### 4.1 核心概念

Skill 是一个包含 `SKILL.md` 的文件夹，通过 YAML frontmatter 声明元数据。它本质上是一段**结构化的提示词**，在特定时机注入到 Claude 的上下文中。

**与 CLAUDE.md 的区别**：CLAUDE.md 始终加载；Skill 按需加载，用完即释放上下文空间。

### 4.2 两种类型

| 类型 | 目的 | 调用方式 | 示例 |
|------|------|---------|------|
| **任务型** | 执行一套标准化流程 | 用户输入 `/skill-name` | `/commit`、`/brainstorm` |
| **参考型** | 给 Claude 注入领域知识 | Claude 自动判断是否需要 | 编码规范、API 文档 |

### 4.3 文件结构

```
.claude/skills/my-skill/
  SKILL.md          # 必需 - 技能主文件（建议 <500 行）
  reference.md      # 可选 - 详细参考文档
  examples.md       # 可选 - 使用示例
  templates/        # 可选 - 模板文件
  scripts/          # 可选 - 辅助脚本
```

### 4.4 Frontmatter 完整规范

```yaml
---
name: my-skill                      # 技能名称（小写+连字符，最长 64 字符）
description: 何时使用这个技能        # Claude 用此判断是否自动加载（关键！）
argument-hint: "默认行为 | [参数] 说明"  # 自动补全时显示的参数提示

# 调用控制
disable-model-invocation: false      # true = 仅用户手动调用，Claude 不自动触发
user-invocable: true                 # false = 仅 Claude 可调用，不出现在 / 菜单

# 执行环境
allowed-tools: Read, Grep, Bash      # 限制可用工具（白名单）
model: claude-opus-4-6               # 指定执行模型
context: fork                        # "fork" = 在独立子代理中运行
agent: Explore                       # 子代理类型（Explore/Plan/general-purpose）
---
```

**字段详解**：

| 字段 | 默认值 | 关键理解 |
|------|--------|---------|
| `description` | 无 | **最重要的字段**。Claude 通过 description 判断当前任务是否需要加载这个 Skill。写不好 = 永远不会被自动触发 |
| `disable-model-invocation` | `false` | 设为 `true` 适用于有副作用的操作（部署、发布），防止 Claude 自作主张 |
| `user-invocable` | `true` | 设为 `false` 适用于纯知识注入（背景上下文），不需要用户知道它的存在 |
| `argument-hint` | 无 | 用户按 Tab 补全时看到的提示，应同时说明默认行为和可选参数 |
| `context: fork` | 主会话内 | fork 后 Skill 在子代理中运行，不污染主会话上下文 |

### 4.5 字符串替换

Skill 正文中可使用以下变量：

| 变量 | 说明 |
|------|------|
| `$ARGUMENTS` | 调用时传递的所有参数（如 `/commit no-push` 中的 `no-push`） |
| `$ARGUMENTS[0]`、`$0` | 第 N 个参数（0-based） |
| `${CLAUDE_SKILL_DIR}` | Skill 文件所在目录的绝对路径 |
| `${CLAUDE_SESSION_ID}` | 当前会话 ID |

### 4.6 调用机制详解

```
用户输入 /commit no-push
       ↓
Claude Code 查找名为 "commit" 的 Skill
       ↓
读取 SKILL.md，将 $ARGUMENTS 替换为 "no-push"
       ↓
将替换后的内容注入当前上下文
       ↓
Claude 按照 Skill 中的指令执行
       ↓
执行完毕，Skill 内容从上下文释放
```

**自动触发流程**（`disable-model-invocation: false` 时）：

```
用户说 "帮我提交代码"
       ↓
Claude 扫描所有 Skill 的 description
       ↓
匹配到 commit Skill 的 description: "规范化 Git 提交流程"
       ↓
通过 Skill tool 加载并执行
```

### 4.7 Skill 存放位置与优先级

| 位置 | 命名空间 | 优先级 |
|------|---------|--------|
| 企业托管 | 直接名称 | 最高 |
| 用户个人 `~/.claude/skills/` | 直接名称 | 高 |
| 项目级 `.claude/skills/` | 直接名称 | 中 |
| Plugin 内 `plugin/skills/` | `plugin-name:skill-name` | 低 |

同名时高优先级覆盖低优先级。Plugin 中的 Skill 有命名空间前缀，不会与其他层级冲突。

### 4.8 实战示例

```yaml
# ~/.claude/skills/commit/SKILL.md
---
name: commit
description: 规范化 Git 提交流程，默认提交并推送
argument-hint: "默认: commit+push | [no-push] 仅提交"
---

## 提交流程

1. 运行 `git status` 和 `git diff --staged` 查看变更
2. 根据变更生成 Conventional Commits 格式的提交信息
3. 执行 `git commit`
4. 若参数不含 "no-push"，执行 `git push`

## 提交信息规范

- feat: 新功能
- fix: 修复
- refactor: 重构
- docs: 文档
- chore: 杂项
```

---

## 五、Plugins — 可分发的能力包

### 5.1 核心概念

Plugin 是一个**目录**，把 Skills、Agents、Hooks、MCP 配置打包在一起，通过 Marketplace 分发。

**与散装文件的区别**：

| 特性 | 散装文件 | Plugin |
|------|---------|--------|
| 命名空间 | 无，可能冲突 | 有，`/plugin:skill` |
| 版本管理 | 无 | `plugin.json` 中声明 |
| 安装卸载 | 手动拷贝 | `claude plugin install/uninstall` |
| 分发 | 手动共享 | Marketplace 一键安装 |
| 依赖管理 | 无 | 未来可能支持 |

### 5.2 目录结构

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # 必需：插件元数据（只放这一个文件！）
├── skills/                  # 可选：技能集合
│   ├── deploy/
│   │   └── SKILL.md
│   └── review/
│       └── SKILL.md
├── agents/                  # 可选：自定义代理
│   ├── reviewer.md
│   └── tester.md
├── hooks/                   # 可选：事件钩子
│   ├── hooks.json           # 自动发现，无需在 plugin.json 声明
│   └── scripts/
│       └── lint-check.sh
├── .mcp.json                # 可选：MCP 服务器配置
├── .lsp.json                # 可选：LSP 服务器配置
├── settings.json            # 可选：默认设置
└── README.md
```

**关键规则**：
- `.claude-plugin/` 目录内只放 `plugin.json`，所有其他内容放在插件根目录
- `hooks/hooks.json` 会被自动发现和加载，不需要在 `plugin.json` 中显式声明（重复声明会报错）
- `agents` 字段必须指向具体文件，不支持目录路径

### 5.3 plugin.json 完整结构

```json
{
  "name": "my-plugin",                    // 必需：唯一标识（kebab-case）
  "version": "1.2.0",                     // 必需：语义化版本
  "description": "插件描述",               // 推荐：Marketplace 中显示

  "author": {                              // 可选：作者信息
    "name": "Your Name",
    "email": "you@example.com"
  },
  "license": "MIT",
  "keywords": ["workflow", "deploy"],

  // 组件声明（都是数组类型）
  "skills": ["./skills/"],                 // 目录路径或文件路径
  "agents": [                              // 必须是具体文件路径
    "./agents/reviewer.md",
    "./agents/tester.md"
  ],
  // hooks: 不需要声明，hooks/hooks.json 自动加载
  "mcpServers": {                          // 内联或引用 .mcp.json
    "my-db": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/db",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"]
    }
  },
  "lspServers": {                          // LSP 语言服务器
    "go": {
      "command": "gopls",
      "args": ["serve"],
      "extensionToLanguage": { ".go": "go" }
    }
  }
}
```

### 5.4 Plugin 可包含的组件一览

| 组件 | 目录/文件 | 说明 |
|------|----------|------|
| **Skills** | `skills/` | 可调用的技能模板，使用 `plugin-name:skill-name` 命名空间 |
| **Agents** | `agents/*.md` | 自定义子代理，Claude 可根据任务自动派发 |
| **Hooks** | `hooks/hooks.json` | 事件钩子，自动发现加载 |
| **MCP Servers** | `.mcp.json` | 外部工具连接，启用插件时自动启动 |
| **LSP Servers** | `.lsp.json` | 代码智能服务（需预装语言服务器） |
| **Settings** | `settings.json` | 默认配置（目前仅支持 `agent` 字段） |

### 5.5 Marketplace 机制

Marketplace 是插件的发现和分发中心。

**官方 Marketplace**：Claude Code 内置，包含 Anthropic 官方和社区精选插件。

**自定义 Marketplace**：在 `settings.json` 中注册第三方市场：

```json
{
  "extraKnownMarketplaces": {
    "my-marketplace": {
      "source": {
        "source": "github",
        "repo": "org/marketplace-repo"
      }
    }
  }
}
```

**marketplace.json 结构**：

```json
{
  "name": "my-marketplace",
  "plugins": [
    {
      "name": "plugin-name",
      "source": "./relative/path",      // 或 "github:owner/repo"
      "description": "插件描述",
      "category": "workflow"
    }
  ]
}
```

**插件来源类型**：

| 来源 | 格式 | 示例 |
|------|------|------|
| 本地相对路径 | `./path` | `"./plugins/my-plugin"` |
| GitHub | `github:owner/repo` | `"github:anthropics/skills"` |
| Git 仓库 | `git+https://...` | `"git+https://gitlab.com/user/repo"` |
| npm | `npm:package@version` | `"npm:@org/plugin@1.0.0"` |

### 5.6 安装与管理

```bash
# 安装
claude plugin install plugin-name            # 用户级（所有项目）
claude plugin install plugin-name --scope project  # 项目级
claude plugin install plugin-name --scope local    # 本地级

# 管理
claude plugin enable plugin-name
claude plugin disable plugin-name
claude plugin uninstall plugin-name

# 开发调试
claude --plugin-dir ./my-plugin              # 加载本地插件
/reload-plugins                              # 会话中热重载
```

**启用状态存储在 settings.json 中**：

```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "context7@claude-plugins-official": true
  }
}
```

### 5.7 环境变量

Plugin 内的文件可使用以下变量引用路径：

| 变量 | 说明 |
|------|------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin 根目录的绝对路径 |
| `${CLAUDE_PROJECT_DIR}` | 当前项目目录 |

---

## 六、Hooks — 事件驱动的守护者

### 6.1 核心概念

Hook 是在 Claude Code 生命周期的特定节点自动执行的逻辑。它不改变 Claude 的思考过程，而是在**动作的前后**插入检查、转换或记录。

类比：CI/CD 流水线中的 pre-commit hook、post-build hook。

### 6.2 完整事件类型（21 种）

#### 会话生命周期

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `SessionStart` | 会话开始或恢复 | 否 | 会话来源（`startup`/`resume`/`clear`） |
| `SessionEnd` | 会话终止 | 否 | 终止原因 |
| `InstructionsLoaded` | CLAUDE.md 或规则文件加载时 | 否 | 无 |

#### 用户操作

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `UserPromptSubmit` | 用户提交提示词之前 | 是 | 无 |
| `PermissionRequest` | 权限弹窗出现时 | 是 | 无 |

#### 工具调用

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `PreToolUse` | 工具执行前 | 是（allow/deny/ask） | 工具名（`Bash`、`Edit`、`mcp__github__*`） |
| `PostToolUse` | 工具执行成功后 | 有限 | 工具名 |
| `PostToolUseFailure` | 工具执行失败后 | 否 | 工具名 |

#### Claude 响应

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `Stop` | Claude 完成一次响应 | 是 | 无 |
| `Notification` | 发送通知时 | 否 | 通知类型（`permission_prompt`/`idle_prompt`/`auth_success`） |

#### 子代理和团队

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `SubagentStart` | 子代理启动 | 否 | 代理类型 |
| `SubagentStop` | 子代理停止 | 否 | 代理类型 |
| `TeammateIdle` | Agent Teams 成员空闲 | 否 | 无 |
| `TaskCompleted` | 任务标记为完成 | 是 | 无 |

#### 上下文管理

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `PreCompact` | 上下文压缩前 | 否 | 触发原因（`manual`/`auto`） |
| `PostCompact` | 上下文压缩后 | 否 | 无 |
| `ConfigChange` | 配置文件修改 | 是 | 配置源 |

#### Git Worktree

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `WorktreeCreate` | 创建 Git Worktree | 否 | 无 |
| `WorktreeRemove` | 移除 Git Worktree | 否 | 无 |

#### MCP 用户输入

| 事件 | 触发时机 | 能否阻断 | matcher 匹配内容 |
|------|---------|---------|-----------------|
| `Elicitation` | MCP 服务器请求用户输入 | 是 | 无 |
| `ElicitationResult` | 用户响应 MCP 请求后 | 否 | 无 |

### 6.3 四种 Hook 类型

| 类型 | 执行方式 | 响应格式 | 适用场景 |
|------|---------|---------|---------|
| `command` | 运行 Shell 脚本 | 退出码 + stdout | 文件检查、格式化、通知 |
| `http` | POST 到 HTTP 端点 | JSON 响应体 | 远程审计、团队通知 |
| `prompt` | 单轮 LLM 评估 | `{"ok": true/false}` | 质量检查、合规验证 |
| `agent` | 多轮子代理验证 | `{"ok": true/false}` | 复杂测试、多步骤验证 |

### 6.4 配置结构

```json
{
  "hooks": {
    "事件名": [
      {
        "matcher": "正则表达式",    // 可选：过滤条件
        "hooks": [
          {
            "type": "command",      // command | http | prompt | agent
            "command": "脚本路径",
            "timeout": 600,         // 可选：超时秒数
            "async": false          // 可选：true = 后台执行，无法阻断
          }
        ]
      }
    ]
  }
}
```

### 6.5 触发机制：从事件到执行的完整链路

理解 Hook 的关键在于：Claude Code 的运行时有一套**固定的生命周期卡槽**，就像流水线上预埋好的检查点。你不能新增卡槽，只能往已有的卡槽里**挂你的 Hook**。

#### 固定卡槽（简化视图）

```
会话开始
  │
  ├── 【SessionStart】         ← 卡槽
  │
  ▼
用户输入
  │
  ├── 【UserPromptSubmit】     ← 卡槽
  │
  ▼
Claude 思考，决定调用工具
  │
  ├── 【PreToolUse】           ← 卡槽（每次调用任何工具前都经过这里）
  │
  ▼
工具执行
  │
  ├── 【PostToolUse】          ← 卡槽
  │
  ▼
Claude 回答完毕
  │
  ├── 【Stop】                 ← 卡槽
  │
  ▼
会话结束
  │
  └── 【SessionEnd】           ← 卡槽
```

这 21 个卡槽是 Claude Code **写死在代码里的**。Claude 每次调用工具前，都会固定走到 PreToolUse 这个节点，然后检查"这个卡槽上有没有人挂了 Hook"。

#### 四步触发管线

```
Step 1: 事件识别
  运行时判断当前动作对应哪个事件类型
  "要执行工具" → PreToolUse
  "工具执行完" → PostToolUse
  "Claude 说完了" → Stop
        │
        ▼
Step 2: Matcher 过滤
  遍历该事件下所有注册的 Hook 组
  每组有一个 matcher（正则表达式）
  用 matcher 去匹配事件的"匹配目标"

  不同事件的匹配目标不同：
    PreToolUse/PostToolUse → 工具名（"Bash"、"Edit"、"mcp__github__create_issue"）
    Notification           → 通知类型（"idle_prompt"）
    SessionStart           → 来源（"startup"/"resume"）
    Stop                   → 无匹配目标（空 matcher 全匹配）

  matcher 为空字符串 "" → 匹配所有
  matcher 不匹配 → 跳过这组 Hook
        │ 匹配成功
        ▼
Step 3: 数据组装 + 执行
  运行时把当前上下文组装成 JSON，通过 stdin 传给 Hook
        │
        ▼
Step 4: 决策
  根据 Hook 的输出决定后续行为（放行/阻断/警告）
```

#### Matcher 匹配示例

Claude Code 内部为每个工具维护一个名称。每次调用工具，这个名称就是 matcher 的匹配目标：

| Claude 的动作 | 工具内部名称 |
|--------------|-------------|
| 执行 Shell 命令 | `Bash` |
| 编辑文件 | `Edit` |
| 创建文件 | `Write` |
| 读取文件 | `Read` |
| 搜索文件 | `Glob` / `Grep` |
| 调用 GitHub MCP | `mcp__github__create_issue` |
| 调用浏览器 MCP | `mcp__claude-in-chrome__navigate` |

假设配置了三组 Hook：

```json
{
  "PreToolUse": [
    { "matcher": "Bash",       "hooks": [{"type":"command","command":"./check-A.sh"}] },
    { "matcher": "Edit|Write", "hooks": [{"type":"command","command":"./check-B.sh"}] },
    { "matcher": "",           "hooks": [{"type":"command","command":"./check-C.sh"}] }
  ]
}
```

Claude 调用 `Edit` 工具时，逐组匹配：

```
第 1 组: /Bash/ 匹配 "Edit" → 不匹配，跳过 check-A.sh
第 2 组: /Edit|Write/ 匹配 "Edit" → 命中！执行 check-B.sh → exit 0（放行）
第 3 组: // 空字符串匹配一切 → 命中！执行 check-C.sh → exit 0（放行）
全部通过 → Edit 工具正常执行
```

如果 check-B.sh 返回 `exit 2`（阻断），**第 3 组不会执行**，Edit 动作直接取消。

MCP 工具的匹配同理。Claude 调用 `mcp__github__create_issue` 时，matcher `mcp__github__.*` 会匹配所有以 `mcp__github__` 开头的工具。

#### 完整案例：从开发 Hook 到被触发

**需求**：编辑 Swift 文件后，自动检查能不能编译。

**第 1 步：选卡槽**

"编辑后"→ 工具执行完之后 → **PostToolUse**。只关心 Edit 和 Write → matcher 设为 `Edit|Write`。

**第 2 步：写脚本**

```bash
#!/bin/bash
# ~/.claude/hooks/swift-compile-check.sh

INPUT=$(cat)                                          # 从 stdin 读 JSON
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path') # 提取文件路径

# 只处理 .swift 文件
if [[ "$FILE" != *.swift ]]; then exit 0; fi

# 语法检查
if ! swiftc -parse "$FILE" 2>/tmp/swift-err.txt; then
  echo "编译检查失败: $(cat /tmp/swift-err.txt)" >&2  # stderr 反馈给 Claude
  exit 0  # 不阻断（文件已编辑完，阻断没意义），但 Claude 会看到错误信息并自行修复
fi
exit 0
```

**第 3 步：挂到卡槽上**

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/swift-compile-check.sh"
      }]
    }]
  }
}
```

**第 4 步：运行时触发链路**

Claude 编辑了 `FloatingBallView.swift`：

```
Claude 调用 Edit 工具修改 FloatingBallView.swift
    ↓
Edit 工具执行完毕
    ↓
运行时走到 PostToolUse 卡槽
    ↓
检查：卡槽上挂了 Hook 吗？→ 有
    ↓
第 1 组 matcher = "Edit|Write"，当前工具 = "Edit" → 匹配
    ↓
组装 JSON 通过 stdin 传给 swift-compile-check.sh：
  { "tool_name": "Edit",
    "tool_input": { "file_path": ".../FloatingBallView.swift" } }
    ↓
脚本：后缀 .swift → swiftc -parse → 编译失败
    ↓
stderr 输出 "编译检查失败: line 42: expected '}'"
exit 0（不阻断）
    ↓
运行时：放行，但 stderr 内容反馈给 Claude
    ↓
Claude 看到错误信息，自动回去修复第 42 行
```

### 6.6 数据格式与决策机制

**输入**：Hook 通过 stdin 接收 JSON 数据：

```json
{
  "session_id": "abc123",
  "cwd": "/project/path",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /tmp/*" }
}
```

**输出**：通过退出码和 stdout 返回决策：

| 退出码 | 行为 | 用途 |
|--------|------|------|
| `0` | 允许继续 | 检查通过 |
| `2` | **阻断操作** | 安全拦截 |
| 其他 | 继续，但记录警告 | 非关键错误 |

**PreToolUse 的特殊输出格式**（可通过 stdout 返回 JSON）：

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",       // allow | deny | ask
    "permissionDecisionReason": "禁止删除系统目录"
  }
}
```

### 6.7 配置位置与作用域

| 位置 | 作用域 | 可共享 |
|------|--------|--------|
| `~/.claude/settings.json` | 所有项目 | 否（仅本机） |
| `.claude/settings.json` | 单个项目 | 是（可提交 Git） |
| `.claude/settings.local.json` | 单个项目 | 否（gitignored） |
| Plugin `hooks/hooks.json` | 启用插件时 | 是（随插件分发） |

### 6.8 实战示例

**示例 1：桌面通知（Notification + Stop）**

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "idle_prompt",
      "hooks": [{
        "type": "command",
        "command": "osascript -e 'display notification \"Claude 需要你\" with title \"Claude Code\"'"
      }]
    }],
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "/path/to/notifier.sh stop claude"
      }]
    }]
  }
}
```

**示例 2：阻止编辑敏感文件（PreToolUse）**

```bash
#!/bin/bash
# .claude/hooks/protect-files.sh
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

PROTECTED=(".env" "credentials" "secrets")
for pattern in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "阻止编辑保护文件: $FILE_PATH" >&2
    exit 2  # 退出码 2 = 阻断
  fi
done
exit 0
```

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": ".claude/hooks/protect-files.sh"
      }]
    }]
  }
}
```

**示例 3：编辑后自动格式化（PostToolUse）**

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write"
      }]
    }]
  }
}
```

**示例 4：LLM 质量门控（Stop + prompt 类型）**

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "检查所有任务是否完成。如果有遗漏，返回 {\"ok\": false, \"reason\": \"...\"}"
      }]
    }]
  }
}
```

### 6.9 调试技巧

- `/hooks`：在会话中查看所有已配置的 Hook
- `claude --debug`：查看完整执行日志
- `Ctrl+O`：切换详细模式，查看 Hook 输出
- 手动测试：`echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | ./protect.sh`

---

## 七、Agent 体系 — 从单兵到团队

### 7.1 Subagent（子代理）

子代理是拥有**独立上下文窗口**和**受限工具权限**的专门助手。主 Claude 可以把任务委派给子代理，子代理完成后将结果返回。

**与 Skill 的本质区别**：

| | Skill | Agent |
|--|-------|-------|
| 上下文 | 注入到主会话 | 独立窗口 |
| 工具 | 使用主会话的工具 | 可独立限制 |
| 生命周期 | 执行完释放 | 独立进程 |
| 适用场景 | "按手册操作" | "换个人来做" |

**内置子代理类型**：

| 类型 | 模型 | 工具 | 用途 |
|------|------|------|------|
| `Explore` | Haiku（快速） | 只读 | 代码搜索、文件发现 |
| `Plan` | 继承主会话 | 只读 | Plan Mode 中的代码研究 |
| `general-purpose` | 继承主会话 | 全部 | 复杂多步任务 |

### 7.2 自定义 Agent

在 `.claude/agents/` 或 Plugin 的 `agents/` 目录中定义：

```yaml
# .claude/agents/reviewer.md
---
name: reviewer
description: 代码质量审查专家。当审查代码、检查 PR 时使用。
tools: Read, Grep, Glob
model: sonnet
maxTurns: 10
permissionMode: plan
---
你是代码审查员。检查以下方面：
1. 安全漏洞（SQL 注入、XSS）
2. DRY 原则违反
3. 测试覆盖不足
给出具体的改进建议。
```

**Agent 定义的完整字段**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 唯一标识符 |
| `description` | string | Claude 何时应该委派给此 Agent |
| `tools` | string | 允许使用的工具（白名单） |
| `disallowedTools` | string | 禁止使用的工具（黑名单） |
| `model` | string | `sonnet`/`opus`/`haiku`/`inherit` |
| `permissionMode` | string | 权限模式 |
| `maxTurns` | number | 最大对话回合数 |
| `skills` | list | 预加载的技能 |
| `mcpServers` | object | MCP 服务器配置 |
| `hooks` | object | 生命周期钩子 |
| `memory` | string | 持久记忆范围（`user`/`project`/`local`） |
| `background` | boolean | `true` = 始终后台运行 |
| `isolation` | string | `worktree` = 在隔离 Git Worktree 中运行 |

### 7.3 权限模型

每个 Agent 可以独立设置权限模式：

| 模式 | 行为 | 典型用途 |
|------|------|---------|
| `default` | 遇到权限问题时弹窗提示用户 | 日常开发 |
| `acceptEdits` | 自动接受文件编辑，其他仍需确认 | 信任度高的实现任务 |
| `plan` | 只读，不执行不修改 | 方案设计、代码研究 |
| `dontAsk` | 自动拒绝未预批准的操作 | CI/CD、后台任务 |
| `bypassPermissions` | 跳过所有权限检查 | 沙盒环境（慎用） |

### 7.4 前台与后台执行

| 模式 | 行为 | 权限处理 | 适用场景 |
|------|------|---------|---------|
| 前台（默认） | 阻塞主会话，等待完成 | 实时弹窗 | 需要用户交互的任务 |
| 后台 | 并发运行，主会话继续 | 启动前预批准 | 独立的长时间任务 |

后台 Agent 如果遇到未预批准的权限请求，该操作会失败但 Agent 继续运行。

```bash
Ctrl+B    # 将当前前台任务后台化
```

### 7.5 Worktree 隔离

当多个 Agent 需要同时修改代码时，可以使用 Git Worktree 隔离：

```
主仓库（main 分支）
    ├── worktree-auth（feature-auth 分支）   ← Agent A 在这里工作
    ├── worktree-api（feature-api 分支）     ← Agent B 在这里工作
    └── worktree-test（feature-test 分支）   ← Agent C 在这里工作
```

在 Agent 定义中设置 `isolation: worktree`，或在调用时指定：

```bash
claude --worktree feature-auth
```

**清理规则**：
- 无修改：自动删除 worktree 和分支
- 有修改：提示保留或删除

### 7.6 Agent Teams（实验性）

Agent Teams 是 Subagent 的升级版。Subagent 是"派发-返回"的单向模式；Teams 是**多个独立会话并行协作**。

**启用方式**：

```json
// settings.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

**核心架构**：

```
┌─────────────────────────────────────────────┐
│              Team Lead（主会话）              │
│  - 创建团队、分配任务、协调进度              │
│  - 与所有 Teammate 双向通信                  │
└──────────┬──────────┬──────────┬─────────────┘
           │          │          │
     ┌─────v─────┐ ┌──v──────┐ ┌v──────────┐
     │ Teammate A│ │Teammate B│ │Teammate C │
     │ 前端开发  │ │ 后端 API │ │ 测试编写  │
     │ 独立上下文│ │ 独立上下文│ │ 独立上下文│
     └───────────┘ └──────────┘ └───────────┘
```

**Subagent vs Agent Teams**：

| 特性 | Subagent | Agent Teams |
|------|----------|-------------|
| 上下文 | 共享父会话 | 完全独立 |
| 通信 | 仅向主 Agent 报告 | Teammate 之间可直接通信 |
| 协调 | 主 Agent 管理 | 共享任务列表 + 自我协调 |
| Token 成本 | 较低 | 较高（多个独立窗口） |
| 适用场景 | 快速委派 | 复杂并行工作 |

**Teams 的通信机制**：

```
# 点对点消息
@teammate-a 请把 API 接口文档发给我

# 广播消息
broadcast: 数据库 schema 已更新，请各自适配

# 快捷键
Shift+Down    切换 Teammate 面板
Ctrl+T        切换任务列表显示
```

**Teams 最佳实践**：

- 团队规模 3-5 人最有效
- 分解任务使每个 Teammate 拥有不同的文件集，避免冲突
- 从边界清晰的任务开始（PR 审查、独立模块开发）
- 不适合：顺序依赖的任务、同文件编辑

---

## 八、MCP — 连接外部世界（概览）

MCP（Model Context Protocol）是让 Claude 调用外部工具的标准协议。通过 MCP，Claude 可以连接数据库、浏览器、GitHub、Slack 等外部服务。

**三种传输方式**：

| 方式 | 适用场景 | 示例 |
|------|---------|------|
| `http` | 远程服务（推荐） | GitHub、Slack |
| `stdio` | 本地进程 | 数据库、文件处理 |
| `sse` | 旧版远程（已弃用） | 早期 MCP 服务 |

**快速接入**：

```bash
claude mcp add --transport http github https://mcp.github.com
```

MCP 服务器可以在 Plugin 中通过 `.mcp.json` 打包分发，启用插件时自动启动。

---

## 九、对比速查表

| 元素 | 类比 | 加载时机 | 文件格式 | 谁来写 |
|------|------|---------|---------|--------|
| **CLAUDE.md** | 公司规章制度 | 始终加载 | Markdown | 人 |
| **Skill** | 技能培训手册 | 按需加载 | Markdown + YAML | 人 |
| **Agent** | 专职岗位人员 | 被派发时启动 | Markdown + YAML | 人 |
| **Hook** | 流水线质检站 | 事件触发 | JSON + Shell/HTTP | 人 |
| **MCP** | 外部系统接口 | 会话启动时 | JSON | 人/社区 |
| **Plugin** | 能力安装包 | 启用时 | 目录结构 | 人/社区 |

### Skill vs Agent 选择指南

| 场景 | 用 Skill | 用 Agent |
|------|---------|---------|
| 标准化流程（提交、部署） | v | |
| 注入知识（规范、文档） | v | |
| 需要独立上下文 | | v |
| 需要限制权限 | | v |
| 需要并行执行 | | v |
| 简单一次性操作 | v | |
| 复杂多步自治操作 | | v |

> **经验法则**：如果任务需要"换个人来做"，用 Agent；如果只是"按手册操作"，用 Skill。

---

## 十、快速上手路径

### 第一步：创建 CLAUDE.md（5 分钟）

在项目根目录创建 `CLAUDE.md`，写下你的编码规范和项目架构。

### 第二步：写一个 Skill（10 分钟）

创建 `.claude/skills/hello/SKILL.md`，体验 `/hello` 调用。

### 第三步：配置一个 Hook（10 分钟）

在 `.claude/settings.json` 中添加 `PostToolUse` Hook，体验自动格式化。

### 第四步：写一个 Agent（10 分钟）

创建 `.claude/agents/reviewer.md`，体验子代理审查。

### 第五步：打包成 Plugin（15 分钟）

把以上内容组织到插件目录结构中，用 `claude --plugin-dir` 测试。

### 第六步：安装社区 Plugin（5 分钟）

运行 `/plugins` 浏览社区插件，一键安装体验。
