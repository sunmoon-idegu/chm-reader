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

struct SelectionActions: View {
    let copy: () -> Void
    let highlight: () -> Void
    let note: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            item("複製", "doc.on.doc", copy)
            divider
            item("螢光標記", "highlighter", highlight)
            divider
            item("加筆記", "square.and.pencil", note)
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .padding(8)
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 16)
    }

    private func item(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(SelectionButtonStyle())
    }
}

private struct SelectionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0)))
            .onHover { hovering = $0 }
    }
}
