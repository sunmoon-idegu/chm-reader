// Builds the public-domain demo PDF used for App Store screenshots:
//   swift scripts/make-demo-pdf.swift app-store-asset/demo/論語選讀.pdf
import AppKit
import CoreText
import PDFKit

let chapters: [(title: String, passages: [String])] = [
    ("學而第一", [
        "子曰：「學而時習之，不亦說乎？有朋自遠方來，不亦樂乎？人不知而不慍，不亦君子乎？」",
        "有子曰：「其為人也孝弟，而好犯上者，鮮矣；不好犯上，而好作亂者，未之有也。君子務本，本立而道生。孝弟也者，其為仁之本與！」",
        "子曰：「巧言令色，鮮矣仁！」",
        "曾子曰：「吾日三省吾身：為人謀而不忠乎？與朋友交而不信乎？傳不習乎？」",
        "子曰：「道千乘之國，敬事而信，節用而愛人，使民以時。」",
        "子曰：「弟子入則孝，出則弟，謹而信，汎愛眾，而親仁。行有餘力，則以學文。」",
        "子夏曰：「賢賢易色；事父母，能竭其力；事君，能致其身；與朋友交，言而有信。雖曰未學，吾必謂之學矣。」",
        "子曰：「君子不重則不威，學則不固。主忠信，無友不如己者，過則勿憚改。」",
        "曾子曰：「慎終追遠，民德歸厚矣。」",
        "子曰：「君子食無求飽，居無求安，敏於事而慎於言，就有道而正焉，可謂好學也已。」",
        "子曰：「不患人之不己知，患不知人也。」",
    ]),
    ("為政第二", [
        "子曰：「為政以德，譬如北辰，居其所而眾星共之。」",
        "子曰：「詩三百，一言以蔽之，曰：『思無邪』。」",
        "子曰：「道之以政，齊之以刑，民免而無恥；道之以德，齊之以禮，有恥且格。」",
        "子曰：「吾十有五而志于學，三十而立，四十而不惑，五十而知天命，六十而耳順，七十而從心所欲，不踰矩。」",
        "子曰：「溫故而知新，可以為師矣。」",
        "子曰：「君子不器。」",
        "子曰：「學而不思則罔，思而不學則殆。」",
        "子曰：「由！誨女知之乎？知之為知之，不知為不知，是知也。」",
    ]),
]

let pageRect = CGRect(x: 0, y: 0, width: 420, height: 595)
let textRect = pageRect.insetBy(dx: 52, dy: 60)
let ink = NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1)
let accent = NSColor(srgbRed: 0.55, green: 0.13, blue: 0.10, alpha: 1)

func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size) }
func style(spacingBefore: CGFloat = 0, after: CGFloat, line: CGFloat, align: NSTextAlignment = .justified, indent: CGFloat = 0) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.paragraphSpacingBefore = spacingBefore
    p.paragraphSpacing = after
    p.lineSpacing = line
    p.alignment = align
    p.firstLineHeadIndent = indent
    return p
}

let out = CommandLine.arguments[1]
let data = NSMutableData()
var box = pageRect
let info = [kCGPDFContextTitle: "論語選讀", kCGPDFContextAuthor: "示範文件"] as CFDictionary
let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, info)!
var chapterPages: [(String, Int)] = []
var pageCount = 0

func drawPages(_ text: NSAttributedString, footer: String) {
    let setter = CTFramesetterCreateWithAttributedString(text)
    var location = 0
    while location < text.length {
        ctx.beginPDFPage(nil)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
        location += CTFrameGetVisibleStringRange(frame).length
        pageCount += 1
        let number = NSAttributedString(string: "\(footer) · \(pageCount)", attributes: [.font: font("PingFangTC-Regular", 9), .foregroundColor: NSColor.gray])
        let line = CTLineCreateWithAttributedString(number)
        ctx.textPosition = CGPoint(x: pageRect.midX - CTLineGetTypographicBounds(line, nil, nil, nil) / 2, y: 30)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
    }
}

// Title page
let cover = NSMutableAttributedString()
cover.append(NSAttributedString(string: "論語選讀\n", attributes: [
    .font: font("PingFangTC-Semibold", 34), .foregroundColor: accent,
    .paragraphStyle: style(spacingBefore: 150, after: 18, line: 0, align: .center)]))
cover.append(NSAttributedString(string: "學而第一　為政第二\n", attributes: [
    .font: font("PingFangTC-Regular", 15), .foregroundColor: ink, .paragraphStyle: style(after: 40, line: 0, align: .center)]))
cover.append(NSAttributedString(string: "示範文件　公有領域文本", attributes: [
    .font: font("PingFangTC-Regular", 11), .foregroundColor: NSColor.gray, .paragraphStyle: style(after: 0, line: 0, align: .center)]))
drawPages(cover, footer: "論語選讀")

for chapter in chapters {
    chapterPages.append((chapter.title, pageCount))
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: chapter.title + "\n", attributes: [
        .font: font("PingFangTC-Semibold", 22), .foregroundColor: accent, .paragraphStyle: style(after: 22, line: 0, align: .left)]))
    for passage in chapter.passages {
        text.append(NSAttributedString(string: passage + "\n", attributes: [
            .font: font("PingFangTC-Regular", 14.5), .foregroundColor: ink, .paragraphStyle: style(after: 13, line: 7, align: .natural, indent: 29)]))
    }
    drawPages(text, footer: "論語選讀")
}
// The outline is written by Quartz itself: re-saving through PDFKit loses the text's Unicode mapping
// (CJK characters come back as look-alike Kangxi radicals, which breaks search).
let children = chapterPages.map { title, page in
    ["Title": title, "Destination": page + 1] as [String: Any]
}
CGPDFContextSetOutline(ctx, ["Children": children] as CFDictionary)
ctx.closePDF()
try! (data as Data).write(to: URL(fileURLWithPath: out))
let document = PDFDocument(data: data as Data)!
print("pages=\(document.pageCount) outline=\(document.outlineRoot?.numberOfChildren ?? 0) chapters=\(chapterPages)")
