import AppKit
import SwiftUI
import WebKit

/// Three-pane layout (contents | page | note) on AppKit's NSSplitViewController so panels
/// collapse with the system's smooth animation; SwiftUI can't animate the WKWebView's frame.
struct ReaderSplitView<R: ReaderModel>: NSViewControllerRepresentable {
    let reader: R
    var showLeft: Bool
    var showRight: Bool

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let split = NSSplitViewController()
        split.splitView.dividerStyle = .thin

        let left = NSSplitViewItem(viewController: hosting(
            SidebarView(reader: reader).modelContainer(AnnotationStore.container), width: 260))
        left.canCollapse = true
        left.minimumThickness = 200
        left.maximumThickness = 480
        left.holdingPriority = .init(260)
        left.isCollapsed = !showLeft

        let pageController = NSViewController()
        pageController.view = reader.contentView
        let center = NSSplitViewItem(viewController: pageController)
        center.minimumThickness = 360

        let right = NSSplitViewItem(viewController: hosting(
            NotesPanel(reader: reader).modelContainer(AnnotationStore.container), width: 300))
        right.canCollapse = true
        right.minimumThickness = 260
        right.maximumThickness = 460
        right.holdingPriority = .init(260)
        right.isCollapsed = !showRight

        split.addSplitViewItem(left)
        split.addSplitViewItem(center)
        split.addSplitViewItem(right)
        return split
    }

    func updateNSViewController(_ split: NSSplitViewController, context: Context) {
        let items = split.splitViewItems
        guard items.count == 3 else { return }
        let changes = [(items[0], !showLeft), (items[2], !showRight)].filter { $0.0.isCollapsed != $0.1 }
        guard !changes.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            for (item, collapsed) in changes { item.animator().isCollapsed = collapsed }
        }
    }

    private func hosting<V: View>(_ view: V, width: CGFloat) -> NSViewController {
        let controller = NSHostingController(rootView: view
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        // Let the split view own the size; otherwise the hosting view fights it while animating.
        controller.sizingOptions = []
        controller.view.frame.size.width = width
        return controller
    }
}
