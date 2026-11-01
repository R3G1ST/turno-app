// Делает иконку полностью непрозрачной (требование iOS): прозрачные углы
// заливаем цветом ближайшего непрозрачного пикселя по горизонтали к центру —
// градиент фона продолжается плавно, без артефактов.
import AppKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: icon-fill <in.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let inURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let src = NSBitmapImageRep(data: try! Data(contentsOf: inURL)),
      let cg = src.cgImage else { exit(1) }
let w = cg.width, h = cg.height

guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// Зум внутрь: рисуем картинку больше холста, чтобы прозрачная кайма и артефакты
// скруглений маковской иконки вышли за края — видимая площадь будет целиком непрозрачной.
let zoom: CGFloat = 1.14
let side = CGFloat(w) * zoom
let off = (side - CGFloat(w)) / 2
ctx.interpolationQuality = .high
ctx.draw(cg, in: CGRect(x: -off, y: -off, width: side, height: side))
guard let buf = ctx.data else { exit(1) }
let bp = buf.assumingMemoryBound(to: UInt8.self)
let strideBytes = ctx.bytesPerRow

func alphaAt(_ x: Int, _ y: Int) -> Int { Int(bp[y * strideBytes + x * 4 + 3]) }
func copyPx(_ from: Int, _ to: Int, y: Int) {
    let o = y * strideBytes
    for c in 0..<3 { bp[o + to * 4 + c] = bp[o + from * 4 + c] }
    bp[o + to * 4 + 3] = 255
}
func copyV(_ from: Int, _ to: Int, x: Int) {
    for c in 0..<3 { bp[to * strideBytes + x * 4 + c] = bp[from * strideBytes + x * 4 + c] }
    bp[to * strideBytes + x * 4 + 3] = 255
}

// Слева направо: тянем цвет последнего непрозрачного пикселя в прозрачные зоны.
for y in 0..<h {
    var lastOpaque: Int?
    for x in 0..<w {
        if alphaAt(x, y) > 200 { lastOpaque = x } else if let lo = lastOpaque {
            copyPx(lo, x, y: y)
        }
    }
    // Справа налево — закрываем хвост, если начало строки было прозрачным.
    var lastRight: Int?
    for x in stride(from: w - 1, through: 0, by: -1) {
        if alphaAt(x, y) > 200 { lastRight = x } else if let lr = lastRight {
            copyPx(lr, x, y: y)
        }
    }
}
// Сверху вниз / снизу вверх: строки, целиком прозрачные (верх и низ у скруглений),
// горизонтальная заливка не трогает — тянем цвет ближайшей непрозрачной строки.
for x in 0..<w {
    var lastDown: Int?
    for y in 0..<h {
        if alphaAt(x, y) > 200 { lastDown = y } else if let ld = lastDown {
            copyV(ld, y, x: x)
        }
    }
    var lastUp: Int?
    for y in stride(from: h - 1, through: 0, by: -1) {
        if alphaAt(x, y) > 200 { lastUp = y } else if let lu = lastUp {
            copyV(lu, y, x: x)
        }
    }
}
// Страховка: убеждаемся, что альфа нигде не осталась.
for y in 0..<h {
    for x in 0..<w where alphaAt(x, y) != 255 {
        bp[y * strideBytes + x * 4 + 3] = 255
    }
}

guard let out = ctx.makeImage() else { print("нет out"); exit(1) }
// Финальная конвертация в PNG без альфа-канала (требование iOS-иконок).
guard let flatCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    print("нет flatCtx"); exit(1)
}
flatCtx.interpolationQuality = .high
flatCtx.draw(out, in: CGRect(x: 0, y: 0, width: w, height: h))
guard let flat = flatCtx.makeImage() else { print("нет flat"); exit(1) }
let outRep = NSBitmapImageRep(cgImage: flat)
guard let png = outRep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: outURL)
print("ok: \(w)x\(h) opaque, no alpha")
