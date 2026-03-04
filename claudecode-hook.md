<!--
 * @Author: xxl
 * @Date: 2026-03-03 21:49:20
 * @LastEditors: xxl
 * @LastEditTime: 2026-03-03 21:49:25
 * @Description:
 * @FilePath: /PinTop/claudecode-hook.md
-->

Claude Code的Hook机制主要可以从两个维度进行分类：按事件类型分类和按功能类型分类。

一、按事件类型分类（8种核心Hook事件）

根据官方文档和多个技术资料，Claude Code支持以下8种核心Hook事件类型：

事件名称 触发时机 能否阻断 典型用途

SessionStart 会话开始或恢复时 ❌ 不可阻断 初始化环境、检查依赖、加载项目上下文

UserPromptSubmit 用户提交提示词后，Claude处理前 ✅ 可阻断 输入验证、关键词拦截、注入额外上下文

PreToolUse 工具调用前（如Write/Edit/Bash/Read） ✅ 可阻断 危险命令拦截、参数校验、安全审计

PostToolUse 工具成功执行后 ❌ 不可阻断 自动代码格式化、运行Lint、生成变更摘要

Notification Claude发送通知时 ❌ 不可阻断 自定义通知处理（桌面/Slack/飞书等）

Stop Claude完成响应时 ✅ 可阻断 质量门禁（lint/test/git status检查）

SubagentStop 子代理任务完成时 ✅ 可阻断 子任务验收、结果聚合

PreCompact 对话压缩操作前 ❌ 不可阻断 保存重要上下文、备份状态

二、按功能类型分类

1. 命令型Hooks (Command Hooks)

• 定义：执行Shell命令或脚本，适合自动化与校验任务

• 包含事件：SessionStart、UserPromptSubmit、PreToolUse、PostToolUse、Notification、PreCompact

• 特点：通过执行外部脚本实现自动化工作流

2. 提示型Hooks (Prompt Hooks)

• 定义：在Stop/SubagentStop事件中，让Claude进行"停下前的质量检查"

• 包含事件：Stop、SubagentStop

• 特点：基于LLM评估结果决定是否继续工作，形成质量闭环

三、扩展事件类型（12种完整列表）

部分资料提到Claude Code支持12种Hook事件类型，在8种核心事件基础上增加了：

1. SessionEnd - 会话完全结束时触发
2. PermissionRequest - 权限请求对话框显示时触发
3. PostToolUseFailure - 工具调用失败后触发
4. SubagentStart - 子代理启动时触发

四、配置层级分类

1. 用户级配置

• 文件位置：~/.claude/settings.json

• 特点：全局生效，个人专用，跨项目应用

2. 项目级配置

• 文件位置：.claude/settings.json

• 特点：团队共享，版本控制，项目专用

3. 本地项目级配置

• 文件位置：.claude/settings.local.json

• 特点：个人专用，不提交Git，优先级最高

配置优先级：本地项目级 > 项目级 > 用户级 > 默认策略

五、Hook的核心价值

Claude Code的Hook机制主要解决以下痛点：

1. 自动化重复动作：将格式化、Lint、测试等从"你记得做"变成"系统自动做"
2. 安全防护：在危险操作（如rm -rf、git push --force）前自动拦截
3. 质量保证：在任务完成前自动检查测试覆盖率、代码质量等
4. 工作流集成：与外部系统（GitHub、Slack等）无缝集成

通过Hook机制，Claude Code实现了从被动响应到主动干预的转变，让AI辅助开发更加可靠和自动化。
