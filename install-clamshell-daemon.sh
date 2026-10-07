#!/bin/bash
# ============================================================================
# install-clamshell-daemon.sh — 安装 launchd 开机自启任务
#
# 用法:
#   sudo ./install-clamshell-daemon.sh            # 安装并立即应用
#   sudo ./install-clamshell-daemon.sh uninstall  # 卸载
#
# 安装内容:
#   /usr/local/bin/clamshell-ensure.sh            (守护脚本, root 拥有)
#   /Library/LaunchDaemons/com.user.clamshell-server.plist  (开机自启)
#   日志: /var/log/clamshell-ensure.log
# ============================================================================
set -euo pipefail

LABEL="com.user.clamshell-server"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
BIN="/usr/local/bin/clamshell-ensure.sh"
SRC="$(cd "$(dirname "$0")" && pwd)/clamshell-ensure.sh"

if [[ "${1:-}" == "uninstall" ]]; then
    launchctl bootout system/"${LABEL}" 2>/dev/null || true
    rm -f "$PLIST" "$BIN"
    echo "已卸载: 下次开机不再自动应用合盖模式。"
    echo "当前设置仍生效; 如需恢复日常使用, 请运行 clamshell-server.sh --disable"
    exit 0
fi

[[ $EUID -eq 0 ]] || { echo "错误: 请用 sudo 运行本脚本"; exit 1; }
[[ -f "$SRC" ]] || { echo "错误: 找不到 $SRC (请与 install 脚本放在同一目录)"; exit 1; }

# 1. 安装守护脚本
mkdir -p /usr/local/bin
cp "$SRC" "$BIN"
chmod 755 "$BIN"
echo "[1/4] 守护脚本已安装: $BIN"

# 2. 写入 LaunchDaemon plist
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/clamshell-ensure.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/clamshell-ensure.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST"
echo "[2/4] 开机任务已写入: $PLIST"

# 3. 注册并启动
launchctl bootout system/"${LABEL}" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
launchctl enable system/"${LABEL}"
echo "[3/4] 开机任务已注册 (com.user.clamshell-server)"

# 4. 立即应用一次
echo "[4/4] 立即应用设置..."
"$BIN"
echo
echo "完成! 每次开机都会自动应用合盖服务器模式。"
echo "  日志: /var/log/clamshell-ensure.log"
echo "  卸载: sudo $0 uninstall"
echo "  验证: pmset -g | grep SleepDisabled"
