# FocusPilot 性能测试报告

> 日期：2026-03-03 | 方法：运行时采集 + 静态代码分析

---

## 一、运行时性能数据（优化前基线）

| 指标 | 值 | 评价 |
|------|------|------|
| 二进制大小 | 1.1 MB | 极轻量 |
| 启动 RSS | ~99 MB | 正常 |
| 稳态 RSS（数分钟） | ~106 MB | 正常 |
| 长期 RSS（数小时） | ~172 MB | ⚠️ 增长 66%，待复测确认 |
| 空闲 CPU | 0.0% | 优秀，无不必要轮询 |
| 线程数 | 3~5（自动收缩） | 良好 |
| 文件描述符 | 36（新）→ 71（长期） | ⚠️ 翻倍增长，待复测确认 |

## 二、静态分析发现（按优先级排序）

### High

| # | 问题 | 位置 | 状态 |
|---|------|------|:---:|
| H1 | `refreshRunningApps()` 同步调用 AX API，主线程阻塞 50-200ms | AppMonitor:160 | 待优化 |
| H2 | `refreshAllWindows()` 热循环中 N 次冗余 `runningApplications(withBundleIdentifier:)` | AppMonitor:196 | **已修复** |
| H3 | `scanInstalledApps()` 同步遍历文件系统，启动时阻塞 100-500ms | AppMonitor:268 | **已修复** |
| H4 | 两阶段刷新连续发两次 `windowsChanged` 通知 | AppMonitor:213+254 | 待优化 |

### Medium

| # | 问题 | 位置 | 状态 |
|---|------|------|:---:|
| M1 | 收藏 Tab `runningApps.first(where:)` 线性查找 O(N*M) | QuickPanelView:408 | 待优化 |
| M2 | `buildStructuralKey()` 大量字符串拼接 | QuickPanelView:393 | 待优化 |
| M3 | HotkeyRecorderButton NSEvent 监听器泄漏 | PreferencesView:229 | **已修复** |
| M4 | `allCount`/`runningCount` 重复 NSWorkspace 调用 | AppConfigView:103 | 待优化 |
| M5 | `save()` 同步 7 次 JSON 编码 | ConfigStore:61 | 待优化 |

### Low

- symbolCache 只增不减（~10 key，可忽略）
- Logo 图像每次颜色变更重绘（频率极低）
- PermissionManager 可改为指数退避（开销可忽略）

## 三、本次已修复（3 项）

| # | 修复内容 | 改动 |
|---|----------|------|
| H2 | `app.nsApp?.isTerminated == false` 替代 N 次系统调用 | AppMonitor.swift 1 行 |
| H3 | `scanInstalledApps()` 移至 `DispatchQueue.global` 后台 | AppMonitor.swift ~5 行 |
| M3 | `HotkeyRecorderButton` 新增 `activeMonitor` + `onDisappear` 清理 | PreferencesView.swift ~10 行 |

## 四、待执行：长时间复测

### 目的

验证优化后 RSS 和文件描述符是否稳定（之前数据显示 99MB→172MB 增长 + FD 36→71 翻倍）。

### 复测方案

```bash
# 启动监控（多阶段采样：前 30 分钟每 30s，之后每 2 分钟，共 4 小时）
cat > /tmp/focuspilot-monitor.sh << 'SCRIPT'
#!/bin/bash
PID=$(pgrep -x FocusPilot)
LOG=/tmp/focuspilot-perf-monitor.csv
echo "timestamp,cpu,mem_pct,rss_kb,threads,fds" > "$LOG"
sample() {
    if ! kill -0 $PID 2>/dev/null; then echo "进程已退出" >> "$LOG"; exit 0; fi
    TS=$(date '+%H:%M:%S')
    STATS=$(ps -p $PID -o %cpu,%mem,rss | tail -1 | xargs)
    THREADS=$(ps -M -p $PID 2>/dev/null | tail -n +2 | wc -l | xargs)
    FDS=$(lsof -p $PID 2>/dev/null | wc -l | xargs)
    echo "$TS,$STATS,$THREADS,$FDS" >> "$LOG"
}
# 阶段 1：前 30 分钟每 30s 采样（捕捉初期泄漏）
for i in $(seq 1 60); do sample; sleep 30; done
# 阶段 2：之后每 2 分钟采样（3.5 小时）
for i in $(seq 1 105); do sample; sleep 120; done
echo "监控完成" >> "$LOG"
SCRIPT
chmod +x /tmp/focuspilot-monitor.sh
nohup /tmp/focuspilot-monitor.sh &>/dev/null &
echo "监控已启动，PID: $!"
```

### 判定标准

| 指标 | 稳定（PASS） | 泄漏（需深入） |
|------|-------------|---------------|
| RSS | 4h 内波动 < 20MB | 持续单调增长 > 30MB |
| 文件描述符 | 4h 内波动 < 10 | 持续单调增长 > 20 |

### 查看结果

```bash
cat /tmp/focuspilot-perf-monitor.csv
```

## 五、综合评价

| 维度 | 评分 | 说明 |
|------|:---:|------|
| 空闲性能 | A | 0% CPU，优化到位 |
| 内存效率 | B+ | 启动 89MB，待复测长期趋势 |
| 资源管理 | A | Timer/Observer 全覆盖，监听器泄漏已修复 |
| 代码复杂度 | B+ | 5546 行 17 文件，结构清晰 |
| 主线程安全 | B | scanInstalledApps 已后台化，refreshRunningApps 仍待优化 |
| 总体 | **B+** | 3 项低风险修复后质量提升，H1/H4 待复测数据决定是否继续 |

## 六、后续决策点

复测数据出来后：
- **RSS/FD 稳定** → 当前优化足够，H1/H4 可作为技术债务记录
- **RSS/FD 仍增长** → 需深入排查泄漏源（可能是 AX API 对象未释放、NotificationCenter 连锁），优先修复 H1
