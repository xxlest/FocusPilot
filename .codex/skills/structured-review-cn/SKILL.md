---
name: structured-review-cn
description: Perform structured reviews in Chinese for code, PRs, technical designs, architecture docs, product docs, and implementation plans. Use when the user asks for a review, review comment, design review, architecture review, PRD review, spec review, or wants findings grouped by severity with consistent granularity.
---

# Structured Review CN

Use this skill for any review-oriented task where the output should be:

- in Chinese
- focused on findings rather than summary
- grouped by severity
- consistent across code, documents, specs, and architecture

This is a review skill, not a rewrite skill.

## Scope

Apply the same review structure to:

1. Code changes
2. Pull requests
3. Architecture or technical design documents
4. PRD, specs, implementation plans, and other product or engineering documents

## Core principle

Review for failure modes, regressions, missing transitions, unclear contracts, hidden assumptions, and validation gaps.

Do not optimize for politeness over precision.
Do not lead with praise.
Do not turn the output into a changelog or summary unless the user asks for that explicitly.

## Severity levels

Use exactly these three levels:

- `Critical`
  Not addressing this issue is likely to cause functional failure, broken compatibility, user-visible regression, data loss, security or permission failure, or a major rollout problem.

- `Important`
  Not addressing this issue leaves meaningful risk, ambiguity, migration hazard, maintainability debt, unclear ownership, or insufficient validation, but the system may still appear to work in common paths.

- `Nit`
  Low-risk inconsistency, naming residue, wording issue, stale comments, logging mismatch, or cleanup item that does not materially change behavior.

If a level has no findings, write `无`.

## Review lenses

Choose the relevant lenses based on the artifact being reviewed.

### For code review

Check:

1. Functional correctness
2. Backward compatibility and migration behavior
3. External contracts and integration points
4. Error handling and edge cases
5. State persistence and upgrade paths
6. Observability, logging, and debugging clarity
7. Test coverage or missing validation

### For architecture or technical design review

Check:

1. Whether the design can actually satisfy the stated goal
2. Missing system boundaries, contracts, or ownership
3. Upgrade and rollout risks
4. Runtime failure modes and fallback behavior
5. Data model, persistence, and migration impact
6. Operational complexity and hidden coupling
7. Validation plan and acceptance criteria

### For PRD, specs, or implementation plan review

Check:

1. Requirement ambiguity
2. Missing edge cases or lifecycle states
3. Unclear assumptions or terms
4. Missing technical constraints or compatibility notes
5. Gaps between scope, UX, and implementation
6. Missing rollout, migration, or recovery considerations
7. Missing measurable acceptance criteria

## Output format

Always present findings first.

Use this exact section order:

```markdown
Critical

1. <问题标题>
   - 影响：<不处理会怎样>
   - 依据：<文件、段落、代码位置或设计描述>
   - 建议：<最小可行修正>

Important

1. <问题标题>
   - 影响：<风险或隐患>
   - 依据：<证据>
   - 建议：<修正方向>

Nit

1. <问题标题>
   - 依据：<证据>
   - 建议：<清理建议>
```

## Writing rules

1. 全部用中文输出。
2. 先写 finding，再写概述。
3. 每条 finding 必须说明“为什么这算这个严重级别”。
4. 优先描述用户可见后果、上线后果、升级后果，而不是抽象代码味道。
5. 建议尽量给“最小修复路径”，不要默认建议大重构。
6. 如果信息不足，要明确写出假设条件。
7. 如果没有发现问题，明确写：

```markdown
Critical

无

Important

无

Nit

无
```

## Tone

- 直接
- 克制
- 具体
- 偏审稿意见，不偏方案宣讲

## Good finding pattern

好的 finding 应该像这样：

`将 bundle id 从旧值改到新值，但没有补迁移逻辑，这不是命名一致性问题，而是升级后配置被视为全新安装的问题，因此应归为 Critical。`

或者：

`文档里定义了新契约，但没有说明旧客户端如何兼容，这短期内不一定立刻故障，但会给灰度发布留下隐患，因此应归为 Important。`
