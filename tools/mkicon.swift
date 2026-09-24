// mkicon.swift — draws the app icon: the notch, with four session dots.
//
//   swift tools/mkicon.swift build/Lightswitch.iconset
//   iconutil -c icns build/Lightswitch.iconset -o build/Lightswitch.icns
//
// Kept as code rather than a committed binary so the icon is reproducible
// and diffable. macOS app icons carry their own rounded-square shape, inset
// about 10% from the canvas, so that is drawn here too.
import AppKit

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = size
    let inset = s * 0.10
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)

    // Tile: a dark, slightly cool squircle with a faint top light.
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.height * 0.225, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let colors = [CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                  CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // The notch: a black shape hanging from the tile's top edge, with the
    // flared top corners and rounded bottom corners of the real thing.
    let notchW = tile.width * 0.62
    let notchH = tile.height * 0.30
    let t = notchH * 0.10, b = notchH * 0.30
    let nx = tile.midX - notchW / 2, top = tile.maxY, bottom = top - notchH
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: nx - t, y: top))
    notch.addQuadCurve(to: CGPoint(x: nx, y: top - t), control: CGPoint(x: nx, y: top))
    notch.addLine(to: CGPoint(x: nx, y: bottom + b))
    notch.addQuadCurve(to: CGPoint(x: nx + b, y: bottom), control: CGPoint(x: nx, y: bottom))
    notch.addLine(to: CGPoint(x: nx + notchW - b, y: bottom))
    notch.addQuadCurve(to: CGPoint(x: nx + notchW, y: bottom + b), control: CGPoint(x: nx + notchW, y: bottom))
    notch.addLine(to: CGPoint(x: nx + notchW, y: top - t))
    notch.addQuadCurve(to: CGPoint(x: nx + notchW + t, y: top), control: CGPoint(x: nx + notchW, y: top))
    notch.closeSubpath()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(notch)
    ctx.fillPath()

    // Four dots inside the notch: done, working, needs you, idle.
    let dotColors: [CGColor] = [
        CGColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1),
        CGColor(red: 1.00, green: 0.84, blue: 0.04, alpha: 1),
        CGColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1),
        CGColor(gray: 1, alpha: 0.32),
    ]
    let d = notchH * 0.26
    let gap = d * 1.1
    let rowW = 4 * d + 3 * gap
    var x = tile.midX - rowW / 2
    let y = bottom + notchH / 2 - d / 2
    for (i, c) in dotColors.enumerated() {
        if i == 2 {
            // The red one glows.
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: d * 0.9, color: CGColor(red: 1, green: 0.27, blue: 0.23, alpha: 0.9))
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
            ctx.restoreGState()
        }
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
        x += d + gap
    }
    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lightswitch.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(draw(size: CGFloat(px)), pixels: px).write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
    }
}
print("wrote \(out)")
