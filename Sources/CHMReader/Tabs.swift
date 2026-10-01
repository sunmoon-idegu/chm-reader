import AppKit
import SwiftUI

/// What a window shows. `id` keeps each tab distinct: SwiftUI reuses an existing window for an equal value.
struct BookTarget: Codable, Hashable {
    var url: URL
    var page: String?
    var id = UUID()
}

/// Opens book pages as native macOS window tabs.
@MainActor
enum TabOpener {
    private static weak var pendingParent: NSWindow?

    static func openTab(_ target: BookTarget, from parent: NSWindow?, using openWindow: OpenWindowAction) {
        pendingParent = parent ?? NSApp.keyWindow
        openWindow(value: target)
    }

    /// Called when a new window appears; attaches it as a tab of the window that requested it.
    static func adopt(_ window: NSWindow) {
        // Launch always starts at the welcome screen, even after a crash.
        window.isRestorable = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "CHMReader"
        guard let parent = pendingParent, parent !== window else { return }
        pendingParent = nil
        if parent.tabbedWindows?.contains(window) != true {
            parent.addTabbedWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

/// Hands the hosting NSWindow to `TabOpener` as soon as the view is placed in it.
struct WindowTabbingConfigurator: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { TabOpener.adopt(window) }
        }
    }

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
