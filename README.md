# 合盖助手 · Clamshell Assistant

> **让 MacBook 合上盖子也能继续运行。** 原生 macOS 桌面小工具（窗口 + 菜单栏图标），零第三方依赖 —— 不需要 Homebrew，不需要 Xcode，只用系统自带 `swiftc` 就能编译。

<p align="left">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-blue">
  <img alt="arch" src="https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-lightgrey">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## ✨ 功能

| 功能 | 说明 |
| --- | --- |
| 🖥 **合盖运行** | 一键开启「合盖不休眠」：合上盖子后屏幕关闭，但机器持续运行、保持联网，可远程连接（UU远程 / SSH / 屏幕共享） |
| 🔁 **开机自启守护** | 安装 LaunchDaemon 任务，每次开机自动重新应用合盖设置，防止 `disablesleep` 被系统重置 |
| 💡 **屏幕管理** | 熄屏时间（5 / 10 / 30 分钟 / 永不）、屏幕亮度（15% / 40% / 70%）、**锁定亮度**（对抗系统自动亮度覆盖）、**立即熄屏**（屏幕关闭但机器继续跑） |
| 📱 **远程启动** | 「连接电源自动开机」就绪检查 + 智能插座远程开机操作指引（配合智能插座实现异地开机） |

---

## 📦 下载安装

**方式一：下载预编译版本（推荐）**

1. 前往本仓库的 [Releases](https://github.com/532025497/clamshell-assistant/releases) 页面
2. 下载 `合盖助手.zip`，解压得到 `合盖助手.app`
3. 拖入「应用程序」文件夹即可使用

> ⚠️ 本应用使用 ad-hoc 签名（未购买 Apple 开发者证书）。首次打开若提示「无法验证开发者」：
> - **右键点 App → 打开 → 再点「打开」**，或
> - 终端执行：`xattr -dr com.apple.quarantine /Applications/合盖助手.app`

**方式二：自行编译（源码构建）**

```bash
git clone https://github.com/532025497/clamshell-assistant.git
cd clamshell-assistant
./build.sh          # 需要 Xcode Command Line Tools（提供 swiftc）
open 合盖助手.app
```

---

## 💻 适配机型

### 支持情况一览

| 机型 | 合盖不休眠 | 熄屏设置 | 亮度调节 | 说明 |
| --- | :---: | :---: | :---: | --- |
| **MacBook Air / Pro（Apple Silicon，M1–M5）** | ✅ | ✅ | ✅ | **主力支持机型**，本机实测（macOS 26.5 + MacBook Air M5，Mac17,3） |
| **MacBook Air / Pro（Intel）** | ✅ | ✅ | ✅ | 原理相同，未实机验证；亮度调节视机型 |
| **Mac mini / Mac Studio / iMac（Apple Silicon）** | ➖ | ✅ | ✅ | 无上盖，合盖逻辑不适用；常开、熄屏、亮度均可用 |
| **外接显示器** | — | ✅ | ❌ | 亮度接口仅作用于**内建屏**，外接屏不可调 |
| **macOS 13 Ventura 及以上** | ✅ | ✅ | ✅ | 开发与验证环境：macOS 26.5 (Tahoe) |

### 各功能的兼容性说明

- **合盖不休眠**：基于系统 `pmset -a disablesleep 1`。Apple Silicon 机型若个例无效，可进入「合盖模式」：**外接显示器 + 电源适配器**（键盘/鼠标有线或蓝牙均可）。
- **屏幕亮度调节**：通过系统私有框架 `DisplayServices`（`dlopen` 动态加载，无编译期依赖），只支持**内建显示器**；`brightnessctl` 命令同样。
- **立即熄屏**：`pmset displaysleepnow`，全机型通用。
- **远程启动**：依赖 Mac 默认的「连接电源自动开机」行为（Apple Silicon 笔记本默认开启，可用 `nvram auto-boot` 查询）。macOS 26.5 为 Mac mini / Mac Studio / iMac 新增的「接通电源自动启动」不适用于笔记本。
- **FileVault 用户须知**：开启 FileVault 时无法自动登录，远程开机只能唤醒到登录界面，需本机输密码；如需完整远程开机链路，需关闭 FileVault 并开启自动登录（安全权衡请自行评估）。

---

## 🚀 使用说明

打开 App 后是一个控制窗口（同时常驻菜单栏 🐳 图标，两种入口等效）：

```
合盖运行(服务器模式)
  状态: ✅ 合盖不休眠 / ❌ 未开启
  开机自启: ✅ 已安装 / ❌ 未安装
  [开启合盖模式] [关闭合盖模式]
  [安装开机自启] [卸载开机自启]

屏幕
  熄屏时间: 10 分钟
  [5 分钟] [10 分钟] [30 分钟] [永不熄屏]
  屏幕亮度: 42%
  [调暗 15%] [中等 40%] [调亮 70%] [立即熄屏]
  ☐ 锁定亮度(防止系统自动亮度覆盖)

远程启动(智能插座)
  自动开机 ✅ | FileVault ⚠️ 已开启 | 电源 ✅ 已连接
  [查看操作指引] [复制指引]
```

### 典型用法：合盖当服务器

1. 点「**开启合盖模式**」（输一次管理员密码）
2. 点「**安装开机自启**」（此后每次开机自动恢复，不怕被重置）
3. 合上盖子 → 屏幕关闭、机器继续运行、网络保持
4. 手机用远程工具（如 UU远程）随时连接

> 建议插着电源适配器使用；`womp` / `tcpkeepalive` 已在开启合盖模式时一并设置，用于网络唤醒与长连接保活。

---

## 📂 源码结构

| 文件 | 说明 |
| --- | --- |
| `main.swift` | 应用主体（AppKit）：窗口 UI + 菜单栏 + 状态读取 + 亮度控制（约 500 行，单文件） |
| `Info.plist` | 应用信息（`LSUIElement=false` → 有 Dock 图标与窗口） |
| `build.sh` | 一键构建：`swiftc` 编译 → 组装 .app → 生成图标 → ad-hoc 签名 |
| `brightnessctl.swift` | 独立的命令行亮度工具（零依赖，`brightnessctl 15` 设为 15%） |
| `clamshell-ensure.sh` | 开机守护脚本：应用全部电源设置，熄屏时间从 `/usr/local/etc/clamshell-displaysleep` 读取 |
| `install-clamshell-daemon.sh` | 命令行版开机自启安装/卸载（`sudo ./install-clamshell-daemon.sh [uninstall]`） |
| `clamshell-server.sh` | 纯命令行版控制台（菜单式，适合不装 App 的场景） |
| `preview.png` | 图标素材（构建时自动转为 `icon.icns`） |

### 自行构建

```bash
# 编译 App + 命令行亮度工具
./build.sh

# 可选：把亮度工具装到 PATH
sudo cp brightnessctl /usr/local/bin/
```

仅依赖系统自带工具链（Xcode Command Line Tools 的 `swiftc` + `sips`）。

---

## 🧰 命令行速查（不装 App 也能用）

```bash
# 合盖不休眠
sudo pmset -a disablesleep 1 sleep 0 standby 0 autopoweroff 0 womp 1 tcpkeepalive 1

# 熄屏时间（分钟，0 = 永不）
sudo pmset -a displaysleep 10
echo 10 | sudo tee /usr/local/etc/clamshell-displaysleep    # 持久化（开机守护读取）

# 立即熄屏（屏幕关闭，机器继续跑）
pmset displaysleepnow

# 屏幕亮度
./brightnessctl          # 查看当前亮度
./brightnessctl 15       # 设为 15%

# 开机自启守护
sudo ./install-clamshell-daemon.sh            # 安装
sudo ./install-clamshell-daemon.sh uninstall  # 卸载
tail -5 /var/log/clamshell-ensure.log         # 查看守护日志

# 状态检查
pmset -g | grep -E 'SleepDisabled|displaysleep'
```

---

## ⚙️ 工作原理

| 能力 | 实现方式 |
| --- | --- |
| 合盖不休眠 | `pmset -a disablesleep 1`（macOS 电源管理，需管理员权限） |
| 立即熄屏 | `pmset displaysleepnow` |
| 屏幕亮度 | 私有框架 `DisplayServices` 的 `DisplayServicesSetBrightness/GetBrightness`，通过 `dlopen` 调用 |
| 开机自启 | LaunchDaemon（`/Library/LaunchDaemons/com.user.clamshell-server.plist`）+ 守护脚本，以 root 在开机时执行 |
| 权限模型 | 应用本身以普通用户运行；需要管理员的操作通过 `osascript ... with administrator privileges` 弹出系统授权框 |
| 远程启动 | Mac 的「连接电源自动开机」（`nvram auto-boot`）+ 智能插座远程断电再通电 |

---

## ❓ 常见问题

**Q：合上盖后屏幕是黑的，是不是没在运行？**
A：合盖后屏幕本来就会关闭。判断是否仍在运行：用手机远程连接，或回来执行 `pmset -g log | grep -iE 'Entering Sleep' | tail -3` 查看合盖期间是否出现过睡眠记录。

**Q：开了合盖模式还是睡？**
A：① 确认 `pmset -g | grep SleepDisabled` 显示 `1`；② Apple Silicon 个别机型需接**外接显示器 + 电源**进入合盖模式；③ 检查是否被「优化电池充电/低电量模式」等策略影响。

**Q：亮度调好了，过一会自己变了？**
A：系统「自动调整亮度」（环境光传感器）会覆盖手动设置。两种解决办法：在 系统设置 → 显示器 中关闭「自动调整亮度」，或勾选 App 里的「**锁定亮度**」（每 10 秒检测并纠偏）。

**Q：为什么调节不了外接显示器的亮度？**
A：`DisplayServices` 只作用于内建面板，这是系统限制。

**Q：远程开机需要什么？**
A：需要自备**智能插座**（如米家插座）。Mac 默认「连接电源自动开机」，插座远程断电再通电即可触发开机。注意 FileVault 开启时只能到登录界面。

**Q：`disablesleep` 会被重置吗？**
A：会（重启、系统更新等情况下）。这正是「开机自启守护」存在的原因：安装后每次开机自动重新应用。

---

## ⚠️ 免责声明

本项目会修改 macOS 电源管理设置（`pmset`）并安装 root 权限的 LaunchDaemon。请在理解其作用的前提下使用，风险自负。代码全部开源，可自行审阅。

特别提醒：**长期合盖运行请保持电源适配器连接并注意散热**（尤其无风扇机型），避免放在被褥、包袋等不透气环境中。

## 📄 License

[MIT](LICENSE)
