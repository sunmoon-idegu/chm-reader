// Renders the app icon to a 1024×1024 PNG: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt rounded square centred on the 1024 canvas, with a soft drop shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor(srgbRed: 0.82, green: 0.62, blue: 0.40, alpha: 1).setFill()
tilePath.fill()
ctx.restoreGState()
NSGradient(colors: [
    NSColor(srgbRed: 0.93, green: 0.78, blue: 0.56, alpha: 1),
    NSColor(srgbRed: 0.72, green: 0.47, blue: 0.27, alpha: 1),
])!.draw(in: tilePath, angle: -90)

// Open book: two pages meeting at a spine.
let paper = NSColor(srgbRed: 0.99, green: 0.96, blue: 0.90, alpha: 1)
let paperShade = NSColor(srgbRed: 0.93, green: 0.88, blue: 0.79, alpha: 1)
func page(_ left: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    let spineX: CGFloat = 512, top: CGFloat = 720, bottom: CGFloat = 290
    let outer: CGFloat = left ? 230 : 794
    p.move(to: NSPoint(x: spineX, y: bottom + 10))
    p.curve(to: NSPoint(x: outer, y: bottom + 40), controlPoint1: NSPoint(x: spineX + (left ? -90 : 90), y: bottom - 20), controlPoint2: NSPoint(x: outer + (left ? 60 : -60), y: bottom + 20))
    p.line(to: NSPoint(x: outer, y: top + 20))
    p.curve(to: NSPoint(x: spineX, y: top), controlPoint1: NSPoint(x: outer + (left ? 60 : -60), y: top + 40), controlPoint2: NSPoint(x: spineX + (left ? -90 : 90), y: top + 10))
    p.close()
    return p
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)
for left in [true, false] { paper.setFill(); page(left).fill() }
ctx.restoreGState()
NSGradient(colors: [paperShade, paper])!.draw(in: page(true), angle: 0)
NSGradient(colors: [paper, paperShade])!.draw(in: page(false), angle: 0)

// Text lines (vertical-ish feel kept simple: horizontal rules), one highlighted.
let ink = NSColor(srgbRed: 0.45, green: 0.33, blue: 0.22, alpha: 0.55)
func lines(from x0: CGFloat, to x1: CGFloat) {
    for i in 0..<6 {
        let y = 640 - CGFloat(i) * 56
        let r = NSRect(x: x0, y: y, width: x1 - x0 - (i == 5 ? 70 : 0), height: 14)
        ink.setFill()
        NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
    }
}
lines(from: 290, to: 470)
lines(from: 554, to: 734)

// Highlighter stroke over the right page's third line.
let mark = NSRect(x: 540, y: 515, width: 210, height: 44)
NSColor(srgbRed: 1.0, green: 0.82, blue: 0.10, alpha: 0.85).setFill()
NSBezierPath(roundedRect: mark, xRadius: 10, yRadius: 10).fill()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
