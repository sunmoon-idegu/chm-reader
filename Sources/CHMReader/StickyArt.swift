import AppKit
import PDFKit

/// The sticky-note look, shared by PDF notes and the placing cursor (CHM notes match it in CSS): a colored
/// square with four lines of "writing", the last one shorter.
enum StickyArt {
    /// Draws the note into `rect`, in y-up coordinates.
    static func draw(in rect: CGRect, color: NSColor, context ctx: CGContext) {
        let r = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
        let body = CGPath(roundedRect: r, cornerWidth: r.width * 0.16, cornerHeight: r.width * 0.16, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -r.height * 0.04), blur: r.height * 0.1,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(body)
        ctx.setFillColor(color.withAlphaComponent(1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(body)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(max(r.width * 0.035, 0.5))
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(r.height * 0.065)
        ctx.setLineCap(.round)
        let left = r.minX + r.width * 0.22
        let full = r.width * 0.56
        for (i, fraction) in [0.27, 0.42, 0.57, 0.72].enumerated() {
            let y = r.maxY - r.height * fraction
            ctx.move(to: CGPoint(x: left, y: y))
            ctx.addLine(to: CGPoint(x: left + (i == 3 ? full * 0.6 : full), y: y))
        }
        ctx.strokePath()
    }

    static let defaultColor = NSColor(HighlightColor.yellow.color)

    /// Cursor while placing a note: the note itself, its top-left corner is where it lands.
    static let cursorSize: CGFloat = 22
    static let cursorHotSpot = NSPoint(x: 2, y: 2)

    static let cursor: NSCursor = {
        let image = NSImage(size: NSSize(width: cursorSize, height: cursorSize), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            StickyArt.draw(in: rect.insetBy(dx: 1.5, dy: 1.5), color: defaultColor, context: ctx)
            return true
        }
        return NSCursor(image: image, hotSpot: cursorHotSpot)
    }()

    /// The same cursor for the CHM page, as a CSS `cursor` value (2× PNG data URL).
    static let cursorCSS: String = {
        let scale: CGFloat = 2
        let pixels = Int(cursorSize * scale)
        guard let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return "crosshair" }
        ctx.scaleBy(x: scale, y: scale)
        StickyArt.draw(in: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize).insetBy(dx: 1.5, dy: 1.5),
             color: defaultColor, context: ctx)
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return "crosshair" }
        let url = "data:image/png;base64,\(png.base64EncodedString())"
        return "-webkit-image-set(url(\"\(url)\") 2x) \(Int(cursorHotSpot.x)) \(Int(cursorHotSpot.y)), crosshair"
    }()
}

/// A PDF sticky note drawn with `StickyArt` instead of PDFKit's own note icon.
final class StickyNoteAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        StickyArt.draw(in: bounds, color: color, context: context)
    }
}
