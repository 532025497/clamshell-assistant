#!/bin/bash
# ============================================================
# 构建「合盖助手」：App + 命令行亮度工具
# 依赖: 系统自带 swiftc / sips (Xcode Command Line Tools)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

APP="合盖助手.app"

echo "[1/5] 清理旧构建..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "[2/5] 编译应用主体..."
# 通用二进制: 分别编译 arm64 / x86_64 再 lipo 合并
if swiftc -O -target arm64-apple-macosx13.0 -o /tmp/ca-arm64 main.swift 2>/tmp/ca-build.log \
   && swiftc -O -target x86_64-apple-macosx13.0 -o /tmp/ca-x86 main.swift 2>>/tmp/ca-build.log \
   && lipo -create -output "$APP/Contents/MacOS/ClamshellAssistant" /tmp/ca-arm64 /tmp/ca-x86 2>/dev/null; then
    echo "  通用二进制: arm64 + x86_64"
else
    echo "  (交叉编译失败, 回退为本机架构)"
    tail -3 /tmp/ca-build.log 2>/dev/null || true
    swiftc -O -target arm64-apple-macosx13.0 -o "$APP/Contents/MacOS/ClamshellAssistant" main.swift
fi

echo "[3/5] 组装应用包..."
cp Info.plist "$APP/Contents/Info.plist"
cp clamshell-ensure.sh "$APP/Contents/Resources/clamshell-ensure.sh"
chmod 755 "$APP/Contents/Resources/clamshell-ensure.sh"

# 图标(可选素材)
if [ -f preview.png ]; then
    if sips -z 512 512 preview.png --out /tmp/ca-icon-512.png >/dev/null 2>&1 && \
       sips -s format icns /tmp/ca-icon-512.png --out "$APP/Contents/Resources/icon.icns" >/dev/null 2>&1; then
        echo "  图标已生成: icon.icns"
    else
        echo "  (图标生成失败, 使用默认图标)"
    fi
fi

echo "[4/5] ad-hoc 签名..."
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (签名跳过)"

echo "[5/5] 编译命令行亮度工具..."
if swiftc -O -target arm64-apple-macosx13.0 -o /tmp/ca-b-arm64 brightnessctl.swift 2>/dev/null \
   && swiftc -O -target x86_64-apple-macosx13.0 -o /tmp/ca-b-x86 brightnessctl.swift 2>/dev/null \
   && lipo -create -output brightnessctl /tmp/ca-b-arm64 /tmp/ca-b-x86 2>/dev/null; then
    echo "  通用二进制: arm64 + x86_64"
else
    swiftc -O -target arm64-apple-macosx13.0 -o brightnessctl brightnessctl.swift
fi
chmod 755 brightnessctl

echo ""
echo "✅ 构建完成"
echo "   应用:     $(pwd)/$APP"
echo "   亮度工具: $(pwd)/brightnessctl"
echo "   启动:     open \"$APP\""
