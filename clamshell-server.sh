#!/usr/bin/env bash
# ============================================================================
# clamshell-server.sh — 让 MacBook 合盖(熄屏)后保持唤醒、联网，当服务器用
#
# 用法:
#   ./clamshell-server.sh                    # 交互式菜单
#   ./clamshell-server.sh --enable           # 直接开启服务器模式
#   ./clamshell-server.sh --disable          # 关闭并恢复日常设置
#   ./clamshell-server.sh --status           # 查看当前电源/唤醒设置
#   ./clamshell-server.sh --schedule 08:00   # 每天 08:00 定时唤醒(从睡眠唤醒)
#   DISPLAY_SLEEP_MIN=10 ./clamshell-server.sh --enable   # 10 分钟后熄屏
#
# 原理: 通过 pmset 写入电源管理参数，macOS 会持久保存(重启不丢失)。
# ============================================================================

set -euo pipefail

# ---- 颜色输出 ----
C_RESET='\033[0m'; C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YEL='\033[1;33m'; C_CYN='\033[1;36m'
info() { printf "${C_CYN}[i]${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN}[ok]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YEL}[!]${C_RESET} %s\n" "$*"; }
die()  { printf "${C_RED}[x]${C_RESET} %s\n" "$*" >&2; exit 1; }

DISPLAY_SLEEP_MIN="${DISPLAY_SLEEP_MIN:-5}"   # 屏幕熄灭时间(分钟)，机器本身不休眠

# ============================================================================
# 开启服务器模式: 合盖不休眠 + 保持联网 + 网络唤醒
# ============================================================================
enable_mode() {
  command -v sudo >/dev/null || die "未找到 sudo"
  info "开启服务器模式(需要管理员密码)..."
  sudo pmset -a disablesleep 1        # 关键项: 合盖也不睡眠
  sudo pmset -a sleep 0               # 系统睡眠: 永不
  sudo pmset -a standby 0             # 关闭深度待机(防止远程唤醒失败)
  sudo pmset -a autopoweroff 0        # 关闭自动关机
  sudo pmset -a womp 1                # 网络唤醒 Wake on LAN
  sudo pmset -a tcpkeepalive 1        # 睡眠期间保持 TCP 连接(SSH 不掉线)
  sudo pmset -a lidwake 1             # 打开盖子仍可唤醒(日常使用不受影响)
  sudo pmset -a acwake 1              # 插上电源适配器时自动唤醒
  DS_CFG="$(cat /usr/local/etc/clamshell-displaysleep 2>/dev/null || true)"
  [[ "$DS_CFG" =~ ^[0-9]+$ ]] || DS_CFG="${DISPLAY_SLEEP_MIN:-5}"
  sudo pmset -a displaysleep "$DS_CFG"   # 按时熄屏(读取已存配置), 机器不休眠
  ok "已开启。当前关键设置:"
  show_key_settings
  notes
}

# ============================================================================
# 关闭服务器模式，恢复日常设置
# ============================================================================
disable_mode() {
  command -v sudo >/dev/null || die "未找到 sudo"
  info "关闭服务器模式，恢复日常设置(需要管理员密码)..."
  sudo pmset -a disablesleep 0
  sudo pmset -a sleep 10
  sudo pmset -a standby 1
  sudo pmset -a autopoweroff 1
  sudo pmset -a displaysleep 10
  if launchctl print system/com.user.clamshell-server >/dev/null 2>&1; then
    warn "提示: 检测到开机自启任务(com.user.clamshell-server), 下次开机将重新应用服务器模式。"
    warn "如需彻底关闭, 请先运行: sudo ./install-clamshell-daemon.sh uninstall"
  fi
  ok "已恢复。当前关键设置:"
  show_key_settings
}

show_key_settings() {
  echo "------------------------------------------------------------"
  pmset -g | grep -iE 'SleepDisabled| sleep |displaysleep|standby|autopoweroff|womp|tcpkeepalive|lidwake|acwake' || true
  echo "------------------------------------------------------------"
}

# ============================================================================
# 查看状态
# ============================================================================
status() {
  info "当前电源设置:"
  pmset -g
  echo
  info "定时唤醒计划:"
  pmset -g sched || true
  echo
  if [[ "$(pmset -g | awk '/SleepDisabled/{print $2}')" == "1" ]]; then
    ok "服务器模式: 开启中(合盖不休眠)"
  else
    warn "服务器模式: 未开启"
  fi
}

# ============================================================================
# 设置每天定时唤醒(只能从睡眠唤醒，Apple Silicon 不支持关机状态定时开机)
# ============================================================================
set_wake_schedule() {
  local t="${1:-}"
  if [[ -z "$t" ]]; then
    read -rp "输入每天唤醒时间(格式 HH:MM，如 08:00): " t
  fi
  [[ "$t" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "时间格式错误: $t (应为 HH:MM)"
  command -v sudo >/dev/null || die "未找到 sudo"
  sudo pmset repeat wakeorpoweron MTWRFSU "${t}:00"
  ok "已设置每天 ${t} 唤醒。取消: sudo pmset repeat cancel"
}

notes() {
  echo
  warn "注意事项:"
  echo "  1) 本机为 Apple Silicon(arm64): 若合盖后仍然睡眠，需要进入『合盖模式』:"
  echo "     外接显示器 + 插电源适配器 + 连接键盘/鼠标(有线或蓝牙均可)。"
  echo "  2) 请保持电源适配器常插，合盖使用期间建议接上外接显示器。"
  echo "  3) 远程唤醒(WOL)主要走有线网; 纯 Wi-Fi 下不稳定，建议用 SSH 保持连接。"
  echo "  4) 定时唤醒只能从『睡眠』状态唤醒; Apple Silicon 不支持关机后定时开机。"
  echo "  5) 临时手动保持唤醒(不写设置): caffeinate -d -i"
}

usage() {
  cat <<'EOF'
用法: ./clamshell-server.sh [选项]

  无参数          交互式菜单
  --enable        开启服务器模式(合盖不休眠、保持联网)
  --disable       关闭服务器模式，恢复日常设置
  --status        查看当前电源与唤醒设置
  --schedule HH:MM  设置每天定时唤醒(从睡眠唤醒)
  -h|--help       显示帮助

环境变量: DISPLAY_SLEEP_MIN=分钟数(默认 5，即屏幕熄灭时间)
EOF
}

# ---- 命令行参数模式 ----
if [[ $# -gt 0 ]]; then
  case "$1" in
    --enable)    enable_mode ;;
    --disable)   disable_mode ;;
    --status)    status ;;
    --schedule)  set_wake_schedule "${2:-}" ;;
    -h|--help)   usage ;;
    *)           die "未知参数: $1 (用 --help 查看用法)" ;;
  esac
  exit 0
fi

# ---- 交互菜单模式 ----
while true; do
  echo
  echo "${C_CYN}===== MacBook 合盖服务器模式 =====${C_RESET}"
  echo "  1) 开启服务器模式 (合盖不休眠、保持联网)"
  echo "  2) 关闭服务器模式 (恢复日常设置)"
  echo "  3) 查看当前设置"
  echo "  4) 设置每天定时唤醒"
  echo "  0) 退出"
  read -rp "请选择: " choice
  case "$choice" in
    1) enable_mode ;;
    2) disable_mode ;;
    3) status ;;
    4) set_wake_schedule ;;
    0) echo "再见"; exit 0 ;;
    *) warn "无效选择" ;;
  esac
done
