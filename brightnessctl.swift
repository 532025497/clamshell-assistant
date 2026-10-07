import Foundation
import CoreGraphics
import Darwin

// ============================================================
// brightnessctl — 零依赖屏幕亮度控制工具(内建显示器)
//   用法: brightnessctl          查看当前亮度(%)
//         brightnessctl 15       设置为 15%
//         brightnessctl 0        最暗(不关屏)
// 原理: 通过私有框架 DisplayServices 设置内建面板亮度。
// ============================================================

let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
    FileHandle.standardError.write("错误: 无法加载显示服务框架\n".data(using: .utf8)!)
    exit(2)
}
typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

guard let setSym = dlsym(handle, "DisplayServicesSetBrightness"),
      let getSym = dlsym(handle, "DisplayServicesGetBrightness") else {
    FileHandle.standardError.write("错误: 框架缺少亮度接口\n".data(using: .utf8)!)
    exit(3)
}
let setBrightness = unsafeBitCast(setSym, to: SetBrightnessFn.self)
let getBrightness = unsafeBitCast(getSym, to: GetBrightnessFn.self)

let display = CGMainDisplayID()

func current() -> Float {
    var value: Float = -1
    _ = getBrightness(display, &value)
    return value
}

let args = CommandLine.arguments
if args.count < 2 {
    let v = current()
    if v < 0 {
        print("无法读取当前亮度")
        exit(4)
    }
    print("当前亮度: \(Int((v * 100).rounded()))%")
    exit(0)
}

guard let percent = Double(args[1]), percent >= 0, percent <= 100 else {
    FileHandle.standardError.write("用法: brightnessctl [0-100]\n".data(using: .utf8)!)
    exit(5)
}

let target = Float(percent / 100.0)
let rc = setBrightness(display, target)
if rc != 0 {
    FileHandle.standardError.write("设置失败(错误码 \(rc))\n".data(using: .utf8)!)
    exit(6)
}
// 读回确认
usleep(150_000)
let now = current()
print("亮度已设置为 \(Int(percent))%\(now >= 0 ? " (读回 \(Int((now * 100).rounded()))%)" : "")")
