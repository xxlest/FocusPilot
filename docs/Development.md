# FocusPilot 开发指南

> 本文件承接 CLAUDE.md 下沉的"怎么开发"细节：开发规范、构建、参考项目、修改前必读、高频 Bug 防范。CLAUDE.md 只做入口分流，开发明细以本文件为准。

## 修改前必读

修改 UI 前必读 `docs/DesignGuide.md`，修改业务逻辑前必读 `docs/Architecture.md`，修改功能边界时必读 `docs/Editions.md`。PilotOne 新功能开发前必读 `docs/PRD.md`。V1 新界面开发前必读 `docs/FP-UI.md` 和对应页面设计文档（`docs/fp-ui/`）。

## 开发规范

- **开发流程统一走 git worktree**：每个改动在独立工作树（`EnterWorktree` / `.claude/worktrees/`）里开发 + 验证，合并进 `main` 后清理工作树；保持主目录 `main` 始终干净可看，**不在 main 上直接改**。一次一个改动 → PR → 合并 → 清理
- **原型功能改动在 PR/合并前必须做真实运行时验证**：本环境 `preview_*` 工具端口检测失灵，改用 **playwright-core + 系统 Chrome（headless，`channel`/`executablePath` 直连，不下载浏览器）真点交互**验证功能可用。「`node --check` JS 能解析」≠「功能能用」，只交静态校验不算验证
- 使用 **Teams**（多 Agent 协作）进行开发和修复
- **每次修改功能，都要更新 PRD（docs/PRD.md）和架构设计（docs/Architecture.md）；修改 UI 时同步更新设计规范（docs/DesignGuide.md）**
- **每完成一个功能或大修改，自动使用 `/commit` skill 提交并推送到远程仓库**
- **每次修复或新开发完成后，必须执行 `make install` 安装到本地**
- **每次更新 `docs/fp-ui/` 目录下的文件后，必须输出当前 UI 设计进度表（各页面完整度和状态）**
- **页面真实设计完成度以 `docs/fp-ui/00-layout-prototype.html` 母版同步完成为准；仅页面规格文档完成不得标记为 5/5 或"可开发"**
- **每次输出 UI 设计进度表时，必须同时用浏览器打开 `docs/fp-ui/00-layout-prototype.html`，停留在页面等待用户自行查看，不用截图替代用户验收**
- **每次修改功能后，必须检查 Settings 页面（`docs/fp-ui/07-settings.md` 及对应原型）是否需要同步调整配置项**

## 构建

```bash
make build      # 编译到 /tmp/focuspilot-build/
make install    # 编译+签名+安装+启动
make clean      # 清理
```

- 仅 Command Line Tools（无 Xcode IDE），swiftc 直接编译
- VFS overlay 绕过 SwiftBridging module 重复定义 bug
- 自签名证书 `FocusPilot Dev`（`make setup-cert`），权限持久化

## 参考项目

| 项目 | GitHub | 本地路径 | 参考用途 |
|------|--------|---------|---------|
| **Multica** | [multica-ai/multica](https://github.com/multica-ai/multica.git) | `/Users/bruce/Workspace/2-Code/02-oss/ai/agent/coding/multica` | 看板状态模型、Agent Runtime 执行模式、Workspace 数据模型 |
| **Plane** | [makeplane/plane](https://github.com/makeplane/plane.git)（[商业版官网](https://plane.so)） | `/Users/bruce/Workspace/2-Code/02-oss/ai/agent/coding/plane` | Home 页设计、Stickies 便签、项目管理结构（Cycles/Modules/Views） |
| **Z Code** | 闭源（[官网](https://zcode-ai.com/cn/docs)） | 本机已安装 App（`~/Library/Application Support/ai.z.zcode/`） | Workspace Session 模式、多 Agent 框架热切换、对话式开发 ADE、Checkpoint 版本管理。竞品分析见 `docs/竞品分析/Z Code UI 功能层次梳理.md` |
| **Codex** | [openai/codex](https://github.com/openai/codex) | 本机已安装 App | 任务流、代码审查、Agent 执行模式。竞品分析见 `docs/竞品分析/Codex UI 功能层次梳理.md` |

## ⚠️ 高频 Bug 防范：窗口标题"无标题"

**根因**：codesign --force 改变 CDHash → TCC 失效 → AXIsProcessTrusted() 返回 false → 所有窗口标题变成"(无标题)"

**必检项**：每次修改 WindowService / PermissionManager / 安装流程后：

1. 测试首次安装（无 TCC 记录）→ 弹授权 → 授权后标题正常
2. 测试重新安装（有旧 TCC 记录）→ 权限失效 → 重新授权后恢复
3. 测试正常运行 → 所有窗口标题正确

**绝对禁止**：在 buildAXTitleMap 中用 `PermissionManager.shared.accessibilityGranted` 缓存值代替 `AXIsProcessTrusted()` 实时调用
