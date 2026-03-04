#!/bin/bash
###
 # @Author: xxl
 # @Date: 2026-03-03 21:56:00
 # @LastEditors: xxl
 # @LastEditTime: 2026-03-03 22:11:58
 # @Description: 
 # @FilePath: /PinTop/scripts/perf-monitor.sh
### 
# Focus Copilot 长时间性能监控脚本
# 用法: ./scripts/perf-monitor.sh [采样次数] [间隔秒数]
# 默认: 24 次 x 600 秒 = 4 小时


# 前台运行（看实时输出）                                                    
#./scripts/perf-monitor.sh            
                                                                            
# 后台挂起（走之前执行）             
#nohup ./scripts/perf-monitor.sh &>/dev/null &
                                    
# 自定义参数：12次 x 1200秒 = 4小时
#./scripts/perf-monitor.sh 12 1200
SAMPLES=${1:-24}
INTERVAL=${2:-600}
LOG=/tmp/focuscopilot-perf-monitor.csv
PID=$(pgrep -x FocusCopilot)

if [ -z "$PID" ]; then
    echo "错误: FocusCopilot 未运行"
    exit 1
fi

HOURS=$(echo "scale=1; $SAMPLES * $INTERVAL / 3600" | bc)
echo "=== Focus Copilot 性能监控 ==="
echo "PID: $PID"
echo "采样: ${SAMPLES}次 x ${INTERVAL}秒 ≈ ${HOURS}小时"
echo "输出: $LOG"
echo ""

# 基线
echo "timestamp,cpu,mem_pct,rss_kb,threads,fds" > "$LOG"
echo "--- 基线 ---"
ps -p $PID -o pid,%cpu,%mem,rss | head -2
echo "线程: $(ps -M -p $PID 2>/dev/null | tail -n +2 | wc -l | xargs)"
echo "FD:   $(lsof -p $PID 2>/dev/null | wc -l | xargs)"
echo ""
echo "监控开始... (Ctrl+C 停止)"

for i in $(seq 1 $SAMPLES); do
    if ! kill -0 $PID 2>/dev/null; then
        echo "进程已退出" >> "$LOG"
        echo "进程已退出，监控结束"
        break
    fi
    TS=$(date '+%H:%M')
    CPU=$(ps -p $PID -o %cpu | tail -1 | xargs)
    MEM=$(ps -p $PID -o %mem | tail -1 | xargs)
    RSS=$(ps -p $PID -o rss | tail -1 | xargs)
    THREADS=$(ps -M -p $PID 2>/dev/null | tail -n +2 | wc -l | xargs)
    FDS=$(lsof -p $PID 2>/dev/null | wc -l | xargs)
    echo "$TS,$CPU,$MEM,$RSS,$THREADS,$FDS" >> "$LOG"
    echo "[$i/$SAMPLES] $TS  RSS=${RSS}KB  FD=$FDS  线程=$THREADS"
    [ $i -lt $SAMPLES ] && sleep $INTERVAL
done

echo ""
echo "=== 结果 ==="
cat "$LOG"
