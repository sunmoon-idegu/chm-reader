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
    private static let tabbingIdentifier = "CHMReader"

    static func openTab(_ target: BookTarget, from parent: NSWindow?, using openWindow: OpenWindowAction) {
        pendingParent = parent ?? NSApp.keyWindow
        openWindow(value: target)
    }

    /// A new tab on the welcome screen, like the tab bar's + button.
    static func openEmptyTab() {
        let window = NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.tabbingIdentifier == tabbingIdentifier }
        _ = window?.tryToPerform(#selector(NSResponder.newWindowForTab(_:)), with: nil)
    }

    /// Called when a new window appears. Every reader window joins an existing one as a tab: the window that
    /// asked for it, or else the frontmost reader window (SwiftUI makes its own window for files opened from Finder).
    static func adopt(_ window: NSWindow) {
        // Launch always starts at the welcome screen, even after a crash.
        window.isRestorable = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = tabbingIdentifier
        // Keep the tab bar (and its + button) visible even with a single tab.
        DispatchQueue.main.async {
            if window.tabGroup?.isTabBarVisible == false { window.toggleTabBar(nil) }
        }
        let fallback = NSApp.orderedWindows.first {
            $0 !== window && $0.isVisible && $0.tabbingIdentifier == tabbingIdentifier
        }
        guard let parent = pendingParent ?? fallback, parent !== window else { return }
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

/// Lets the File ▸ Open command reach the frontmost window, so a new book becomes a tab there.
struct OpenBookKey: FocusedValueKey {
    typealias Value = (URL) -> Void
}

extension FocusedValues {
    var openBook: ((URL) -> Void)? {
        get { self[OpenBookKey.self] }
        set { self[OpenBookKey.self] = newValue }
    }
}
