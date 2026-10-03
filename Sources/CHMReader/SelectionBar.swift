import AppKit
import SwiftUI

/// Floating actions shown just above selected text: copy, highlight, highlight and write a note.
@MainActor
final class SelectionBar {
    private let host: NSHostingView<SelectionActions>

    init(copy: @escaping () -> Void, highlight: @escaping () -> Void, note: @escaping () -> Void) {
        host = NSHostingView(rootView: SelectionActions(copy: copy, highlight: highlight, note: note))
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = true
    }

    var isShown: Bool { host.superview != nil }

    /// Places the bar above `rect` (in `view`'s coordinates), or below it when there's no room above.
    func show(around rect: NSRect, in view: NSView) {
        let visible = view.bounds
        guard rect.intersects(visible) else { return hide() }
        let size = host.intrinsicContentSize
        let gap: CGFloat = 0  // the bar's own padding (room for its shadow) already spaces it from the text
        let x = min(max(rect.midX - size.width / 2, 8), max(visible.width - size.width - 8, 8))
        var y: CGFloat
        if view.isFlipped {
            y = rect.minY - gap - size.height
            if y < 4 { y = min(rect.maxY + gap, visible.height - size.height - 4) }
        } else {
            y = rect.maxY + gap
            if y + size.height > visible.height - 4 { y = max(rect.minY - gap - size.height, 4) }
        }
        if host.superview !== view { view.addSubview(host) }
        host.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func hide() {
        host.removeFromSuperview()
    }
}

/// A solid bar in the reading theme's text color with the page color as its text (dark brown on 米黃,
/// light on 夜間), so it stands out on any page.
struct SelectionActions: View {
    let copy: () -> Void
    let highlight: () -> Void
    let note: () -> Void
    private var prefs = ReadingPrefs()

    init(copy: @escaping () -> Void, highlight: @escaping () -> Void, note: @escaping () -> Void) {
        self.copy = copy
        self.highlight = highlight
        self.note = note
    }

    var body: some View {
        let colors = prefs.style.colors
        let barIsDark = !prefs.style.isDark
        let fill = Color(nsColor: NSColor(hex: colors.foreground) ?? .black)
        let ink = Color(nsColor: NSColor(hex: colors.background) ?? .white)
        let marker = barIsDark ? HighlightColor.yellow.color : Color(red: 0.85, green: 0.55, blue: 0)
        HStack(spacing: 2) {
            item("複製", "doc.on.doc", ink, ink, copy)
            divider(ink)
            item("螢光標記", "highlighter", marker, ink, highlight)
            divider(ink)
            item("加筆記", "square.and.pencil", ink, ink, note)
        }
        .padding(5)
        .background(fill, in: RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(10)
        .fixedSize()
    }

    private func divider(_ ink: Color) -> some View {
        Rectangle().fill(ink.opacity(0.25)).frame(width: 1, height: 18)
    }

    private func item(_ title: String, _ symbol: String, _ iconColor: Color, _ ink: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionButtonStyle(ink: ink))
    }
}

private struct SelectionButtonStyle: ButtonStyle {
    let ink: Color
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(ink.opacity(configuration.isPressed ? 0.28 : hovering ? 0.16 : 0)))
            .onHover { hovering = $0 }
    }
}
