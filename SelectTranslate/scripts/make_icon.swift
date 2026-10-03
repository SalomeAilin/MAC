// 生成 App 图标：swift scripts/make_icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let canvas: CGFloat = 1024

func drawIcon() {
    // macOS 图标网格：1024 画布内 824×824 的圆角矩形
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    let top = NSColor(srgbRed: 0.25, green: 0.58, blue: 1.00, alpha: 1)
    let bottom = NSColor(srgbRed: 0.38, green: 0.29, blue: 0.94, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: tile, angle: -90)

    // 后面的半透明气泡：A
    let back = bubble(NSRect(x: 430, y: 210, width: 380, height: 380), tailAtLeft: false)
    NSColor.white.withAlphaComponent(0.3).setFill()
    back.fill()
    drawGlyph("A", in: NSRect(x: 430, y: 210, width: 380, height: 380), font: roundedFont(size: 250), color: .white)

    // 前面的白色气泡：文
    let front = bubble(NSRect(x: 214, y: 420, width: 390, height: 390), tailAtLeft: true)
    NSGraphicsContext.saveGraphicsState()
    let frontShadow = NSShadow()
    frontShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    frontShadow.shadowBlurRadius = 18
    frontShadow.shadowOffset = NSSize(width: 0, height: -8)
    frontShadow.set()
    NSColor.white.setFill()
    front.fill()
    NSGraphicsContext.restoreGraphicsState()
    let ink = NSColor(srgbRed: 0.27, green: 0.45, blue: 0.98, alpha: 1)
    drawGlyph("文", in: NSRect(x: 214, y: 420, width: 390, height: 390),
              font: NSFont(name: "PingFangSC-Semibold", size: 240) ?? .systemFont(ofSize: 240, weight: .semibold), color: ink)
}

/// 圆角矩形加一个小尾巴的对话气泡
func bubble(_ rect: NSRect, tailAtLeft: Bool) -> NSBezierPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: 92, yRadius: 92)
    let tail = NSBezierPath()
    if tailAtLeft {
        tail.move(to: NSPoint(x: rect.minX + 70, y: rect.minY + 40))
        tail.line(to: NSPoint(x: rect.minX + 40, y: rect.minY - 70))
        tail.line(to: NSPoint(x: rect.minX + 170, y: rect.minY + 10))
    } else {
        // 与圆角矩形同为逆时针，重叠部分才不会被 nonZero 规则挖空
        tail.move(to: NSPoint(x: rect.maxX - 170, y: rect.minY + 10))
        tail.line(to: NSPoint(x: rect.maxX - 40, y: rect.minY - 70))
        tail.line(to: NSPoint(x: rect.maxX - 70, y: rect.minY + 40))
    }
    tail.close()
    path.append(tail)
    path.windingRule = .nonZero
    return path
}

func roundedFont(size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawGlyph(_ glyph: String, in rect: NSRect, font: NSFont, color: NSColor) {
    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color])
    let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
    let size = text.size()
    // 按字形的实际高度居中
    let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - bounds.height / 2 - font.descender * 0.5)
    text.draw(at: origin)
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "AppIcon-\(UUID().uuidString).iconset")
defer { try? FileManager.default.removeItem(at: iconset) }
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationReason == .exit, iconutil.terminationStatus == 0 else {
    throw NSError(domain: "SelectTranslate.Icon", code: Int(iconutil.terminationStatus),
                  userInfo: [NSLocalizedDescriptionKey: "iconutil 生成图标失败"])
}
if CommandLine.arguments.contains("--preview") {
    try renderPNG(pixels: 512).write(to: URL(fileURLWithPath: output + ".png"))
}
print("已生成 \(output)")
