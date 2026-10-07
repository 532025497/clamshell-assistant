import Cocoa
import Foundation
import Darwin

// ============================================================
// 合盖助手 — 桌面应用(带窗口 + 菜单栏图标)
// 功能1: 合盖运行 (服务器模式开关 + 开机自启任务管理)
// 功能2: 屏幕 (熄屏时间 + 亮度调节与锁定)
// 功能3: 远程启动 (就绪状态检查 + 智能插座操作指引)
// ============================================================

// MARK: - 工具函数

/// 执行普通 shell 命令并返回输出(不弹授权框)
func shell(_ exec: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exec)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

/// 以管理员权限执行脚本(弹出系统授权框)
func runAdmin(_ script: String, completion: @escaping (Bool, String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", osa]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch {
            DispatchQueue.main.async { completion(false, "启动失败: \(error.localizedDescription)") }
            return
        }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        DispatchQueue.main.async { completion(p.terminationStatus == 0, out) }
    }
}

// MARK: - 屏幕亮度(私有框架 DisplayServices)

private let displayServicesHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
private typealias BrightnessSetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias BrightnessGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

@discardableResult
func setBrightness(_ percent: Double) -> Bool {
    guard let h = displayServicesHandle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return false }
    let fn = unsafeBitCast(sym, to: BrightnessSetFn.self)
    return fn(CGMainDisplayID(), Float(max(0, min(100, percent)) / 100.0)) == 0
}

func getBrightness() -> Double {
    guard let h = displayServicesHandle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return -1 }
    let fn = unsafeBitCast(sym, to: BrightnessGetFn.self)
    var v: Float = -1
    guard fn(CGMainDisplayID(), &v) == 0, v >= 0 else { return -1 }
    return Double(v) * 100
}

// MARK: - 状态读取

struct Status {
    var sleepDisabled = false
    var daemonInstalled = false
    var autoBoot = false
    var fileVaultOn = false
    var acPower = false
    var displaysleepMinutes = 5
}

func readStatus() -> Status {
    var s = Status()
    let pmset = shell("/usr/bin/pmset", ["-g"])
    let sleepLine = pmset.split(separator: "\n").first { $0.contains("SleepDisabled") }
    s.sleepDisabled = sleepLine?.contains("1") ?? false
    s.daemonInstalled = FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.user.clamshell-server.plist")
    let nvram = shell("/usr/sbin/nvram", ["-p"])
    let bootLine = nvram.split(separator: "\n").first { $0.hasPrefix("auto-boot") }
    s.autoBoot = bootLine?.contains("true") ?? false
    s.fileVaultOn = shell("/usr/bin/fdesetup", ["status"]).contains("On")
    s.acPower = shell("/usr/bin/pmset", ["-g", "batt"]).contains("AC Power")
    let dsLine = pmset.split(separator: "\n").first { $0.contains("displaysleep") }
    let dsTokens = (dsLine ?? "").split(separator: " ").map(String.init)
    if let idx = dsTokens.firstIndex(where: { Int($0) != nil }), let v = Int(dsTokens[idx]) {
        s.displaysleepMinutes = v
    }
    return s
}

let DAEMON_PLIST = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.clamshell-server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/usr/local/bin/clamshell-ensure.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/clamshell-ensure.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/clamshell-ensure.log</string>
</dict>
</plist>
"""

// MARK: - 应用

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // 常规应用: 有 Dock 图标和窗口

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var timer: Timer?
    var latest = Status()

    // 菜单动态项
    var clamshellItem: NSMenuItem!
    var daemonItem: NSMenuItem!
    var autoBootItem: NSMenuItem!
    var fileVaultItem: NSMenuItem!
    var acItem: NSMenuItem!
    var displayItem: NSMenuItem!
    var brightnessItem: NSMenuItem!

    // 窗口状态标签
    var wClamshell: NSTextField!
    var wDaemon: NSTextField!
    var wDisplay: NSTextField!
    var wBrightness: NSTextField!
    var wRemote: NSTextField!

    // 亮度锁定
    var brightnessLock: NSButton!
    var lockOn = false
    var targetBrightness: Double = 15

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildWindow()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 点 Dock 图标时把窗口调出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - 菜单栏

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button,
           let iconPath = Bundle.main.path(forResource: "icon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            icon.size = NSSize(width: 17, height: 17)
            btn.image = icon
            btn.imagePosition = .imageLeading
        }
        let m = NSMenu()

        let h1 = NSMenuItem(title: "合盖运行(服务器模式)", action: nil, keyEquivalent: "")
        h1.isEnabled = false
        m.addItem(h1)

        clamshellItem = NSMenuItem(title: "状态: 读取中…", action: nil, keyEquivalent: "")
        clamshellItem.isEnabled = false
        m.addItem(clamshellItem)

        m.addItem(actionItem("开启合盖模式(合盖不休眠)", #selector(enableClamshell)))
        m.addItem(actionItem("关闭合盖模式(恢复日常)", #selector(disableClamshell)))

        displayItem = NSMenuItem(title: "熄屏时间: 读取中…", action: nil, keyEquivalent: "")
        displayItem.isEnabled = false
        m.addItem(displayItem)
        m.addItem(actionItem("5 分钟后熄屏", #selector(setDisplaySleep5)))
        m.addItem(actionItem("10 分钟后熄屏", #selector(setDisplaySleep10)))
        m.addItem(actionItem("30 分钟后熄屏", #selector(setDisplaySleep30)))
        m.addItem(actionItem("永不熄屏(0 分钟)", #selector(setDisplaySleepNever)))

        brightnessItem = NSMenuItem(title: "屏幕亮度: 读取中…", action: nil, keyEquivalent: "")
        brightnessItem.isEnabled = false
        m.addItem(brightnessItem)
        m.addItem(actionItem("调暗亮度 (15%)", #selector(setBrightnessLow)))
        m.addItem(actionItem("调亮 (70%)", #selector(setBrightnessHigh)))
        m.addItem(actionItem("立即熄屏(机器继续运行)", #selector(sleepDisplayNow)))

        m.addItem(.separator())

        daemonItem = NSMenuItem(title: "开机自启: 检查中…", action: nil, keyEquivalent: "")
        daemonItem.isEnabled = false
        m.addItem(daemonItem)
        m.addItem(actionItem("安装开机自启任务", #selector(installDaemon)))
        m.addItem(actionItem("卸载开机自启任务", #selector(uninstallDaemon)))

        m.addItem(.separator())

        let h2 = NSMenuItem(title: "远程启动", action: nil, keyEquivalent: "")
        h2.isEnabled = false
        m.addItem(h2)

        autoBootItem = NSMenuItem(title: "连接电源自动开机: 检查中…", action: nil, keyEquivalent: "")
        autoBootItem.isEnabled = false
        m.addItem(autoBootItem)

        fileVaultItem = NSMenuItem(title: "FileVault: 检查中…", action: nil, keyEquivalent: "")
        fileVaultItem.isEnabled = false
        m.addItem(fileVaultItem)

        acItem = NSMenuItem(title: "电源适配器: 检查中…", action: nil, keyEquivalent: "")
        acItem.isEnabled = false
        m.addItem(acItem)

        m.addItem(actionItem("查看远程开机操作指引", #selector(showRemoteGuide)))
        m.addItem(actionItem("复制操作指引到剪贴板", #selector(copyRemoteGuide)))

        m.addItem(.separator())
        m.addItem(actionItem("打开控制窗口", #selector(showWindow)))
        m.addItem(actionItem("刷新状态", #selector(refreshNow)))
        m.addItem(actionItem("退出合盖助手", #selector(quitApp)))

        statusItem.menu = m
    }

    func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 控制窗口

    func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)
        return l
    }

    func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    func makeRow(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        s.alignment = .centerY
        return s
    }

    func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered,
                         defer: false)
        w.title = "合盖助手"
        w.center()

        let content = NSView()
        w.contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])

        // —— 合盖运行 ——
        stack.addArrangedSubview(makeLabel("合盖运行(服务器模式)", bold: true))
        wClamshell = makeLabel("状态: 读取中…")
        wDaemon = makeLabel("开机自启: 读取中…")
        stack.addArrangedSubview(wClamshell)
        stack.addArrangedSubview(wDaemon)
        stack.addArrangedSubview(makeRow([
            makeButton("开启合盖模式", #selector(enableClamshell)),
            makeButton("关闭合盖模式", #selector(disableClamshell))
        ]))
        stack.addArrangedSubview(makeRow([
            makeButton("安装开机自启", #selector(installDaemon)),
            makeButton("卸载开机自启", #selector(uninstallDaemon))
        ]))

        stack.addArrangedSubview(NSBox.separator())

        // —— 屏幕 ——
        stack.addArrangedSubview(makeLabel("屏幕", bold: true))
        wDisplay = makeLabel("熄屏时间: 读取中…")
        wBrightness = makeLabel("屏幕亮度: 读取中…")
        stack.addArrangedSubview(wDisplay)
        stack.addArrangedSubview(makeRow([
            makeButton("5 分钟", #selector(setDisplaySleep5)),
            makeButton("10 分钟", #selector(setDisplaySleep10)),
            makeButton("30 分钟", #selector(setDisplaySleep30)),
            makeButton("永不熄屏", #selector(setDisplaySleepNever))
        ]))
        stack.addArrangedSubview(wBrightness)
        stack.addArrangedSubview(makeRow([
            makeButton("调暗 15%", #selector(setBrightnessLow)),
            makeButton("中等 40%", #selector(setBrightnessMid)),
            makeButton("调亮 70%", #selector(setBrightnessHigh)),
            makeButton("立即熄屏", #selector(sleepDisplayNow))
        ]))
        brightnessLock = NSButton(checkboxWithTitle: "锁定亮度(防止系统自动亮度覆盖)", target: self, action: #selector(toggleBrightnessLock))
        stack.addArrangedSubview(brightnessLock)

        stack.addArrangedSubview(NSBox.separator())

        // —— 远程启动 ——
        stack.addArrangedSubview(makeLabel("远程启动(智能插座)", bold: true))
        wRemote = makeLabel("就绪检查: 读取中…")
        stack.addArrangedSubview(wRemote)
        stack.addArrangedSubview(makeRow([
            makeButton("查看操作指引", #selector(showRemoteGuide)),
            makeButton("复制指引", #selector(copyRemoteGuide))
        ]))

        stack.addArrangedSubview(NSBox.separator())
        stack.addArrangedSubview(makeRow([
            makeButton("刷新状态", #selector(refreshNow)),
            makeButton("退出", #selector(quitApp))
        ]))

        w.makeKeyAndOrderFront(nil)
        window = w
    }

    // MARK: - 刷新

    func refresh() {
        latest = readStatus()
        // 亮度锁定: 检测到漂移就纠回
        if lockOn {
            let cur = getBrightness()
            if cur >= 0 && abs(cur - targetBrightness) > 3 { setBrightness(targetBrightness) }
        }
        updateIcon()
        updateMenu()
        updateWindow()
    }

    func updateIcon() {
        let title = latest.sleepDisabled ? "合盖:开" : "合盖:关"
        let color: NSColor = latest.sleepDisabled ? .systemGreen : .secondaryLabelColor
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        ])
    }

    func updateMenu() {
        clamshellItem.title = latest.sleepDisabled ? "状态: ✅ 合盖不休眠" : "状态: ❌ 未开启"
        daemonItem.title = latest.daemonInstalled ? "开机自启: ✅ 已安装" : "开机自启: ❌ 未安装"
        autoBootItem.title = latest.autoBoot ? "连接电源自动开机: ✅ 已启用" : "连接电源自动开机: ❌ 已禁用"
        fileVaultItem.title = latest.fileVaultOn ? "FileVault: ⚠️ 已开启(关机后需本机解锁)" : "FileVault: ✅ 未开启"
        acItem.title = latest.acPower ? "电源适配器: ✅ 已连接" : "电源适配器: ❌ 未连接"
        displayItem.title = latest.displaysleepMinutes == 0 ? "熄屏时间: 永不" : "熄屏时间: \(latest.displaysleepMinutes) 分钟"
        let b = getBrightness()
        brightnessItem.title = b >= 0 ? "屏幕亮度: \(Int(b.rounded()))%\(lockOn ? " (已锁定)" : "")" : "屏幕亮度: 不可调(外接屏)"
    }

    func updateWindow() {
        guard wClamshell != nil else { return }
        wClamshell.stringValue = latest.sleepDisabled
            ? "状态: ✅ 合盖不休眠(机器保持唤醒)"
            : "状态: ❌ 未开启(合盖会睡眠)"
        wDaemon.stringValue = latest.daemonInstalled
            ? "开机自启: ✅ 已安装(每次开机自动应用)"
            : "开机自启: ❌ 未安装"
        wDisplay.stringValue = latest.displaysleepMinutes == 0
            ? "熄屏时间: 永不熄屏"
            : "熄屏时间: \(latest.displaysleepMinutes) 分钟"
        let b = getBrightness()
        wBrightness.stringValue = b >= 0
            ? "屏幕亮度: \(Int(b.rounded()))%\(lockOn ? " (已锁定, 自动纠偏)" : "")"
            : "屏幕亮度: 不可调(外接屏)"
        let boot = latest.autoBoot ? "✅" : "❌"
        let fv = latest.fileVaultOn ? "⚠️ 已开启" : "✅ 未开启"
        let ac = latest.acPower ? "✅ 已连接" : "❌ 未连接"
        wRemote.stringValue = "自动开机 \(boot) | FileVault \(fv) | 电源 \(ac)"
    }

    // MARK: - 合盖运行操作

    @objc func enableClamshell() {
        let ds = latest.displaysleepMinutes
        runAdmin("pmset -a disablesleep 1 && pmset -a sleep 0 && pmset -a standby 0 && pmset -a autopoweroff 0 && pmset -a womp 1 && pmset -a tcpkeepalive 1 && pmset -a lidwake 1 && pmset -a acwake 1 && pmset -a displaysleep \(ds)") { ok, out in
            if ok { self.alert("完成", "合盖模式已开启, 机器将持续保持唤醒。") }
            else { self.alert("操作失败", out, style: .critical) }
            self.refresh()
        }
    }

    @objc func disableClamshell() {
        runAdmin("pmset -a disablesleep 0 && pmset -a sleep 10 && pmset -a standby 1 && pmset -a autopoweroff 1 && pmset -a displaysleep 10") { ok, out in
            if ok { self.alert("完成", "已恢复日常设置(合盖会正常睡眠)。") }
            else { self.alert("操作失败", out, style: .critical) }
            self.refresh()
        }
    }

    @objc func installDaemon() {
        let fm = FileManager.default
        let tmpScript = "/tmp/clamshell-ensure.sh"
        let tmpPlist = "/tmp/com.user.clamshell-server.plist"
        do {
            guard let res = Bundle.main.resourceURL?.appendingPathComponent("clamshell-ensure.sh") else {
                alert("缺少资源", "应用包内缺少 clamshell-ensure.sh", style: .critical)
                return
            }
            try? fm.removeItem(atPath: tmpScript)
            try Data(contentsOf: res).write(to: URL(fileURLWithPath: tmpScript))
            try? fm.removeItem(atPath: tmpPlist)
            try DAEMON_PLIST.data(using: .utf8)!.write(to: URL(fileURLWithPath: tmpPlist))
        } catch {
            alert("写入临时文件失败", error.localizedDescription, style: .critical)
            return
        }
        let script = """
        mkdir -p /usr/local/bin && cp /tmp/clamshell-ensure.sh /usr/local/bin/clamshell-ensure.sh && chmod 755 /usr/local/bin/clamshell-ensure.sh && cp /tmp/com.user.clamshell-server.plist /Library/LaunchDaemons/com.user.clamshell-server.plist && (launchctl bootout system/com.user.clamshell-server 2>/dev/null || true) && launchctl bootstrap system /Library/LaunchDaemons/com.user.clamshell-server.plist && launchctl enable system/com.user.clamshell-server && /usr/local/bin/clamshell-ensure.sh
        """
        runAdmin(script) { ok, out in
            if ok { self.alert("完成", "开机自启任务已安装, 合盖模式已立即应用。") }
            else { self.alert("安装失败", out, style: .critical) }
            self.refresh()
        }
    }

    @objc func uninstallDaemon() {
        runAdmin("launchctl bootout system/com.user.clamshell-server 2>/dev/null || true; rm -f /Library/LaunchDaemons/com.user.clamshell-server.plist /usr/local/bin/clamshell-ensure.sh") { ok, out in
            if ok { self.alert("完成", "开机自启任务已卸载。") }
            else { self.alert("卸载失败", out, style: .critical) }
            self.refresh()
        }
    }

    // MARK: - 熄屏时间

    @objc func setDisplaySleep5() { setDisplaySleep(5) }
    @objc func setDisplaySleep10() { setDisplaySleep(10) }
    @objc func setDisplaySleep30() { setDisplaySleep(30) }
    @objc func setDisplaySleepNever() { setDisplaySleep(0) }

    func setDisplaySleep(_ minutes: Int) {
        runAdmin("mkdir -p /usr/local/etc && echo \(minutes) > /usr/local/etc/clamshell-displaysleep && pmset -a displaysleep \(minutes)") { ok, out in
            if ok {
                let msg = minutes == 0 ? "屏幕将永不熄灭。" : "屏幕将在 \(minutes) 分钟后熄灭。"
                self.alert("完成", "\(msg)\n已写入开机自启配置, 重启后依然生效。")
            } else {
                self.alert("操作失败", out, style: .critical)
            }
            self.refresh()
        }
    }

    // MARK: - 立即熄屏(屏幕关闭, 机器继续运行)

    @objc func sleepDisplayNow() {
        _ = shell("/usr/bin/pmset", ["displaysleepnow"])
        refresh()
    }

    // MARK: - 屏幕亮度

    @objc func setBrightnessLow() { applyBrightness(15) }
    @objc func setBrightnessMid() { applyBrightness(40) }
    @objc func setBrightnessHigh() { applyBrightness(70) }

    func applyBrightness(_ percent: Double) {
        targetBrightness = percent
        if setBrightness(percent) {
            refresh()
        } else {
            alert("设置失败", "无法调节屏幕亮度(内建屏幕不可用时会出现此提示)。", style: .critical)
        }
    }

    @objc func toggleBrightnessLock() {
        lockOn = (brightnessLock.state == .on)
        if lockOn {
            let cur = getBrightness()
            targetBrightness = cur > 0 ? cur : targetBrightness
            alert("已开启亮度锁定", "关闭自动亮度覆盖: 每 10 秒检测一次, 亮度被系统调走时会自动纠回 \(Int(targetBrightness))%。\n\n提示: 也可在 系统设置 → 显示器 里关闭\"自动调整亮度\"。")
        }
        refresh()
    }

    // MARK: - 远程启动

    var guideText: String {
        let boot = latest.autoBoot ? "✅ 已启用" : "❌ 已禁用"
        let fv = latest.fileVaultOn ? "⚠️ 已开启" : "✅ 未开启"
        let ac = latest.acPower ? "✅ 已连接" : "❌ 未连接"
        let fvNote = latest.fileVaultOn ? " — 关机后开机需本机输密码, 只能唤醒到登录界面" : ""
        return """
        智能插座远程开机(关机状态):
        1. 手机打开智能插座 App(如米家)
        2. 关闭插座电源, 等待 5 秒
        3. 重新打开插座电源
        4. Mac 检测到电源接入, 自动开机
        5. 等待 1~2 分钟, 用 UU远程 连接

        就绪检查:
        · 连接电源自动开机: \(boot)
        · FileVault: \(fv)\(fvNote)
        · 电源适配器: \(ac)

        提示: 平时保持合盖模式常开即可, 无需关机; 此指引仅用于断电或关机后的应急开机。
        """
    }

    @objc func showRemoteGuide() { alert("远程启动(智能插座)操作指引", guideText) }

    @objc func copyRemoteGuide() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(guideText, forType: .string)
        alert("已复制", "操作指引已复制到剪贴板。")
    }

    // MARK: - 通用

    @objc func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func refreshNow() { refresh() }
    @objc func quitApp() { app.terminate(nil) }

    func alert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        a.addButton(withTitle: "好")
        a.runModal()
    }
}

// NSBox 分隔线辅助
extension NSBox {
    static func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 470).isActive = true
        return b
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
