#!/usr/bin/env swift
// Рисует иконку Turno: градиентный квадрат со «стеклянными» колонками-графиком.
import AppKit

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: CGFloat(pixels), height: CGFloat(pixels))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    let scale = size / 1024.0

    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.35, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.85, alpha: 1),
    ])!
    let inset = CGRect(x: 64 * scale, y: 64 * scale,
                       width: size - 128 * scale, height: size - 128 * scale)
    bg.draw(in: NSBezierPath(roundedRect: inset, xRadius: 220 * scale, yRadius: 220 * scale), angle: -60)

    NSColor.white.withAlphaComponent(0.25).set()
    let colW: CGFloat = 90 * scale
    let gap: CGFloat = 44 * scale
    let totalW = 5 * colW + 4 * gap
    var x = (size - totalW) / 2
    for h: CGFloat in [220, 330, 150, 420, 280] {
        let r = CGRect(x: x, y: 150 * scale, width: colW, height: h * scale)
        NSBezierPath(roundedRect: r, xRadius: 30 * scale, yRadius: 30 * scale).fill()
        x += colW + gap
    }

    let t = NSAttributedString(string: "T", attributes: [
        .font: NSFont.systemFont(ofSize: 300 * scale, weight: .heavy),
        .foregroundColor: NSColor.white,
    ])
    let ts = t.size()
    t.draw(at: CGPoint(x: (size - ts.width) / 2, y: size - ts.height - 80 * scale))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("turno-iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

let specs: [(folder: String, px: Int)] = [
    ("16x16", 16), ("32x32", 32), ("128x128", 128),
    ("256x256", 256), ("512x512", 512),
]
for spec in specs {
    try! renderIcon(pixels: spec.px).write(to: tmp.appendingPathComponent("icon_\(spec.px)x\(spec.px).png"))
    try! renderIcon(pixels: spec.px * 2).write(to: tmp.appendingPathComponent("icon_\(spec.px)x\(spec.px)@2x.png"))
}
print(tmp.path)
