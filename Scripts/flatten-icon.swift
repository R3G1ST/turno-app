// Уплощает PNG иконки: убирает альфа-канал, заливая прозрачные углы цветом
// ближайшего непрозрачного пикселя по диагонали внутрь (iOS требует непрозрачную иконку).
import AppKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: flatten-icon <in.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let inURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let src = NSBitmapImageRep(data: try! Data(contentsOf: inURL)),
      let cg = src.cgImage else {
    FileHandle.standardError.write("cannot read image\n".data(using: .utf8)!)
    exit(1)
}
let w = cg.width, h = cg.height
guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
guard let buf = ctx.data else { exit(1) }
let bp = buf.assumingMemoryBound(to: UInt8.self)
let strideBytes = ctx.bytesPerRow

func px(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
    let o = y * strideBytes + x * 4
    return (Int(bp[o]), Int(bp[o+1]), Int(bp[o+2]), Int(bp[o+3]))
}
func setPx(_ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int) {
    let o = y * strideBytes + x * 4
    bp[o] = UInt8(r); bp[o+1] = UInt8(g); bp[o+2] = UInt8(b); bp[o+3] = 255
}

// Для каждого прозрачного пикселя идём по диагонали к центру, пока не найдём непрозрачный.
let center = CGPoint(x: w / 2, y: h / 2)
for y in 0..<h {
    for x in 0..<w where px(x, y).3 == 0 {
        var fx = Double(x), fy = Double(y)
        let dx = center.x > Double(x) ? 1.0 : -1.0
        let dy = center.y > Double(y) ? 1.0 : -1.0
        var found: (Int, Int, Int)?
        for _ in 0..<(w + h) {
            fx += dx; fy += dy
            let ix = Int(fx.rounded()), iy = Int(fy.rounded())
            guard ix >= 0, ix < w, iy >= 0, iy < h else { break }
            let p = px(ix, iy)
            if p.3 > 200 { found = (p.0, p.1, p.2); break }
        }
        if let f = found { setPx(x, y, f.0, f.1, f.2) } else { setPx(x, y, 90, 90, 230) }
    }
}
// Финальная страховка: нигде нет альфы.
for y in 0..<h {
    for x in 0..<w where px(x, y).3 != 255 {
        setPx(x, y, px(x, y).0, px(x, y).1, px(x, y).2)
    }
}

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: outURL)
print("ok: \(w)x\(h) -> \(outURL.path)")
