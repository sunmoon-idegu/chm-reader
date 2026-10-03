import AppKit
import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case pingfang, songti, kaiti, original
    var id: String { rawValue }

    var label: String {
        switch self {
        case .pingfang: "蘋方"
        case .songti: "宋體"
        case .kaiti: "楷體"
        case .original: "原始字型"
        }
    }

    var cssFamily: String? {
        switch self {
        case .pingfang: #""PingFang TC", "PingFang HK", sans-serif"#
        case .songti: #""Songti TC", "STSong", serif"#
        case .kaiti: #""Kaiti TC", "STKaiti", serif"#
        case .original: nil
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case white, sepia, green, night, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: "白"
        case .sepia: "米黃"
        case .green: "護眼綠"
        case .night: "夜間"
        case .custom: "自訂"
        }
    }

    /// (background, foreground, link) as CSS hex.
    var palette: (String, String, String) {
        switch self {
        case .white: ("#ffffff", "#1d1d1f", "#0a63c9")
        case .sepia: ("#f6efe0", "#4a3a28", "#8a4b12")
        case .green: ("#e2efdc", "#22301f", "#1f6b3a")
        case .night: ("#1c1c1e", "#d8d8d8", "#7ab8ff")
        case .custom: ("#ffffff", "#1d1d1f", "#0a63c9")
        }
    }
}

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow, green, blue, pink
    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: "黃色"
        case .green: "綠色"
        case .blue: "藍色"
        case .pink: "粉紅"
        }
    }

    var color: Color {
        switch self {
        case .yellow: Color(red: 1, green: 0.84, blue: 0.04)
        case .green: Color(red: 0.2, green: 0.78, blue: 0.35)
        case .blue: Color(red: 0.04, green: 0.52, blue: 1)
        case .pink: Color(red: 1, green: 0.18, blue: 0.33)
        }
    }
}

struct ReadingStyle: Equatable {
    var font: ReaderFont
    var fontSize: Double
    var lineHeight: Double
    var paragraphSpacing: Double
    var pageWidth: Double
    var theme: ReaderTheme
    var customBackground: String

    var colors: (background: String, foreground: String, link: String) {
        guard theme == .custom else { return theme.palette }
        let isDark = (NSColor(hex: customBackground)?.luminance ?? 1) < 0.45
        return (customBackground, isDark ? "#e6e6e6" : "#1d1d1f", isDark ? "#7ab8ff" : "#0a63c9")
    }

    var isDark: Bool { (NSColor(hex: colors.background)?.luminance ?? 1) < 0.45 }

    var css: String {
        let (bg, fg, link) = colors
        let family = font.cssFamily.map { "font-family: \($0) !important;" } ?? ""
        let darkOverrides = isDark ? """
            body *:not(a):not(mark) { color: inherit !important; }
            body table, body tr, body td, body th, body div, body p, body span, body font {
              background-color: transparent !important; border-color: #555 !important; }
            """ : ""
        return """
            html, body { background: \(bg) !important; background-image: none !important; }
            body {
              color: \(fg) !important; \(family)
              font-size: \(Int(fontSize))px !important;
              line-height: \(lineHeight) !important;
              max-width: \(Int(pageWidth))em; margin: 0 auto !important;
              padding: 2.5em 3em 5em !important; box-sizing: border-box;
              -webkit-font-smoothing: antialiased; text-align: justify;
            }
            body :is(p, div, span, font, td, th, li, dd, dt, blockquote, a, b, i, u, em, strong, center, pre) {
              font-size: inherit !important; line-height: inherit !important; \(family)
            }
            body :is(h1, h2, h3, h4, h5, h6) { line-height: 1.4 !important; \(family) }
            body :is(p, blockquote, li) { margin-top: 0 !important; margin-bottom: \(paragraphSpacing)em !important; }
            body div:not(:has(> div, > p, > table)) { margin-bottom: \(paragraphSpacing)em; }
            body a { color: \(link) !important; }
            body img { max-width: 100%; height: auto; }
            \(darkOverrides)
            mark.chmr-hl { color: inherit !important; border-radius: 2px; padding: 0 1px; cursor: pointer; }
            mark.chmr-hl[data-color="yellow"] { background: rgba(255, 214, 10, \(isDark ? 0.35 : 0.5)) !important; }
            mark.chmr-hl[data-color="green"] { background: rgba(52, 199, 89, \(isDark ? 0.35 : 0.38)) !important; }
            mark.chmr-hl[data-color="blue"] { background: rgba(10, 132, 255, \(isDark ? 0.4 : 0.28)) !important; }
            mark.chmr-hl[data-color="pink"] { background: rgba(255, 45, 85, \(isDark ? 0.4 : 0.28)) !important; }
            mark.chmr-hl[data-note="1"] { text-decoration: underline dotted 2px; text-underline-offset: 0.25em; }
            mark.chmr-hl.chmr-flash, .chmr-sticky.chmr-flash { outline: 2px solid \(link); }
            .chmr-sticky { display: inline-block; position: relative; width: 1.2em; height: 1.2em; margin: 0 0.15em;
              vertical-align: -0.2em; border-radius: 0.2em; cursor: pointer; text-indent: 0; box-sizing: border-box;
              background: rgb(255, 214, 10) !important; border: 0.04em solid rgba(0, 0, 0, 0.3);
              box-shadow: 0 0.05em 0.15em rgba(0, 0, 0, 0.35); }
            .chmr-sticky::after { content: ""; position: absolute; left: 20%; right: 20%; top: 23%; bottom: 25%;
              --ink: linear-gradient(rgba(0, 0, 0, 0.55), rgba(0, 0, 0, 0.55));
              background: var(--ink) 0 0 / 100% 0.075em no-repeat, var(--ink) 0 33.3% / 100% 0.075em no-repeat,
                var(--ink) 0 66.6% / 100% 0.075em no-repeat, var(--ink) 0 100% / 60% 0.075em no-repeat; }
            .chmr-sticky[data-color="green"] { background: rgb(52, 199, 89) !important; }
            .chmr-sticky[data-color="blue"] { background: rgb(10, 132, 255) !important; }
            .chmr-sticky[data-color="pink"] { background: rgb(255, 45, 85) !important; }
            html.chmr-placing, html.chmr-placing * { cursor: \(StickyArt.cursorCSS) !important; }
            """
    }
}

/// Sidebar colors derived from the reading theme, so the panels match the page.
struct ChromePalette {
    let background: Color
    let card: Color
    let hover: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let separator: Color
    let colorScheme: ColorScheme

    init(_ style: ReadingStyle) {
        let (bgHex, fgHex, linkHex) = style.colors
        let bg = NSColor(hex: bgHex) ?? .white
        let fg = NSColor(hex: fgHex) ?? .black
        let mix = { (fraction: CGFloat, other: NSColor) in Color(nsColor: bg.blended(withFraction: fraction, of: other) ?? bg) }
        background = mix(style.isDark ? 0.05 : 0.05, fg)
        card = style.isDark ? mix(0.11, fg) : mix(0.55, .white)
        hover = mix(style.isDark ? 0.14 : 0.09, fg)
        text = Color(nsColor: fg)
        secondary = Color(nsColor: fg).opacity(0.62)
        accent = Color(nsColor: NSColor(hex: linkHex) ?? .controlAccentColor)
        separator = Color(nsColor: fg).opacity(0.12)
        colorScheme = style.isDark ? .dark : .light
    }
}

enum Pref {
    static let font = "reader.font"
    static let fontSize = "reader.fontSize"
    static let lineHeight = "reader.lineHeight"
    static let paragraphSpacing = "reader.paragraphSpacing"
    static let pageWidth = "reader.pageWidth"
    static let theme = "reader.theme"
    static let customBackground = "reader.customBackground"
}

/// All reading preferences, persisted in UserDefaults.
struct ReadingPrefs: DynamicProperty {
    @AppStorage(Pref.font) var font: ReaderFont = .pingfang
    @AppStorage(Pref.fontSize) var fontSize: Double = 20
    @AppStorage(Pref.lineHeight) var lineHeight: Double = 1.9
    @AppStorage(Pref.paragraphSpacing) var paragraphSpacing: Double = 1.0
    @AppStorage(Pref.pageWidth) var pageWidth: Double = 38
    @AppStorage(Pref.theme) var theme: ReaderTheme = .sepia
    @AppStorage(Pref.customBackground) var customBackground: String = "#fdf6e3"

    var style: ReadingStyle {
        ReadingStyle(
            font: font, fontSize: fontSize, lineHeight: lineHeight, paragraphSpacing: paragraphSpacing,
            pageWidth: pageWidth, theme: theme, customBackground: customBackground)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#ffffff" }
        return String(
            format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
            Int(round(c.blueComponent * 255)))
    }

    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}
