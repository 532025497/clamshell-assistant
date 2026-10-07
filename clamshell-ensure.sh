#!/bin/bash
# ============================================================================
# clamshell-ensure.sh — 开机时由 launchd 以 root 身份执行，
# 确保「合盖服务器模式」生效(防止 disablesleep 被系统重置)。
# 安装后位于: /usr/local/bin/clamshell-ensure.sh
# 日志: /var/log/clamshell-ensure.log
# ============================================================================

LOG="/var/log/clamshell-ensure.log"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null || true; }

log "===== 应用合盖服务器模式 ====="

pmset -a disablesleep 1     # 合盖不休眠
pmset -a sleep 0            # 系统睡眠: 永不
pmset -a standby 0          # 关闭深度待机
pmset -a autopoweroff 0     # 关闭自动关机
pmset -a womp 1             # 网络唤醒
pmset -a tcpkeepalive 1     # 睡眠期间保持 TCP 连接
pmset -a lidwake 1          # 开盖可唤醒
pmset -a acwake 1           # 插电自动唤醒
# 熄屏时间: 读取配置文件(分钟, 0=永不), 默认 5
DS="$(cat /usr/local/etc/clamshell-displaysleep 2>/dev/null || echo 5)"
[[ "$DS" =~ ^[0-9]+$ ]] || DS=5
pmset -a displaysleep "$DS"     # 熄屏时间(分钟, 0=永不), 机器不休眠

sd="$(pmset -g | awk '/SleepDisabled/{print $2}')"
log "完成: SleepDisabled=${sd}"

exit 0
