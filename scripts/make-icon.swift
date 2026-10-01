// Renders the app icon to a 1024×1024 PNG: swift scripts/make-icon.swift out.png
// Sky-blue tile, white open book, one glowing yellow highlight, sparkle.
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
func withShadow(_ color: NSColor, blur: CGFloat, offsetY: CGFloat = 0, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: offsetY), blur: blur, color: color.cgColor)
    body()
    ctx.restoreGState()
}

// Tile on the macOS icon grid (824pt square, centred) with drop shadow, gradient and a soft top sheen.
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
withShadow(NSColor.black.withAlphaComponent(0.3), blur: 24, offsetY: -10) { rgb(66, 102, 245).setFill(); tile.fill() }
NSGradient(colors: [rgb(96, 196, 255), rgb(66, 102, 245)])!.draw(in: tile, angle: -90)
ctx.saveGState()
tile.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
ctx.restoreGState()

// Open book: two pages with curved top and bottom edges, separated by a small gap at the spine.
func page(left: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    let inner: CGFloat = left ? 498 : 526, outer: CGFloat = left ? 262 : 762, bow: CGFloat = left ? -70 : 70
    p.move(to: NSPoint(x: inner, y: 330))
    p.line(to: NSPoint(x: inner, y: 690))
    p.curve(to: NSPoint(x: outer, y: 700), controlPoint1: NSPoint(x: inner + bow, y: 728), controlPoint2: NSPoint(x: outer - bow, y: 728))
    p.line(to: NSPoint(x: outer, y: 342))
    p.curve(to: NSPoint(x: inner, y: 330), controlPoint1: NSPoint(x: outer - bow, y: 370), controlPoint2: NSPoint(x: inner + bow, y: 366))
    p.close()
    return p
}
withShadow(NSColor.black.withAlphaComponent(0.18), blur: 30) {
    NSColor.white.setFill()
    page(left: true).fill()
    page(left: false).fill()
}

// Text lines; the right page's second line is replaced by the highlight.
rgb(160, 182, 236).setFill()
for i in 0..<4 {
    let y = 600 - CGFloat(i) * 62
    NSBezierPath(roundedRect: NSRect(x: 318, y: y, width: 140, height: 16), xRadius: 8, yRadius: 8).fill()
    if i != 1 {
        NSBezierPath(roundedRect: NSRect(x: 566, y: y, width: i == 3 ? 90 : 140, height: 16), xRadius: 8, yRadius: 8).fill()
    }
}
withShadow(rgb(255, 190, 30, 0.8), blur: 36) {
    rgb(255, 196, 36).setFill()
    NSBezierPath(roundedRect: NSRect(x: 552, y: 522, width: 170, height: 40), xRadius: 12, yRadius: 12).fill()
}

// Four-point sparkles.
func sparkle(at c: NSPoint, radius r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let k = r * 0.22
    p.move(to: NSPoint(x: c.x, y: c.y + r))
    p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + k, y: c.y + k), controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
    p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + k, y: c.y - k), controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
    p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - k, y: c.y - k), controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
    p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - k, y: c.y + k), controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
    return p
}
withShadow(NSColor.white.withAlphaComponent(0.8), blur: 24) {
    NSColor.white.setFill()
    sparkle(at: NSPoint(x: 730, y: 790), radius: 58).fill()
}
NSColor.white.withAlphaComponent(0.85).setFill()
sparkle(at: NSPoint(x: 800, y: 712), radius: 24).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
