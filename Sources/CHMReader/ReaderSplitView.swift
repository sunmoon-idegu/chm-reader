import AppKit
import SwiftUI

/// Window layout (contents | page(s) | notes) on AppKit split views, so panels collapse with the system's smooth
/// animation; SwiftUI can't animate a WKWebView's frame. The page area holds one or two reader panes.
struct ReaderSplitView: NSViewControllerRepresentable {
    let workspace: Workspace
    var showLeft: Bool
    var showRight: Bool
    /// Changes whenever panes or the active pane change. SwiftUI skips updates when inputs look unchanged,
    /// and `workspace` is the same object throughout.
    var revision: String

    final class Coordinator {
        let sidebars = PerReaderContainer()
        let notes = PerReaderContainer()
        let pages = PaneContainer()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let split = NSSplitViewController()
        split.splitView.dividerStyle = .thin
        let c = context.coordinator
        c.pages.workspace = workspace

        let left = NSSplitViewItem(viewController: c.sidebars)
        c.sidebars.view.frame.size.width = 260
        left.canCollapse = true
        left.minimumThickness = 200
        left.maximumThickness = 480
        left.holdingPriority = .init(260)
        left.isCollapsed = !showLeft

        let center = NSSplitViewItem(viewController: c.pages)
        center.minimumThickness = 360

        let right = NSSplitViewItem(viewController: c.notes)
        c.notes.view.frame.size.width = 300
        right.canCollapse = true
        right.minimumThickness = 260
        right.maximumThickness = 460
        right.holdingPriority = .init(260)
        right.isCollapsed = !showRight

        split.addSplitViewItem(left)
        split.addSplitViewItem(center)
        split.addSplitViewItem(right)
        sync(c)
        return split
    }

    func updateNSViewController(_ split: NSSplitViewController, context: Context) {
        sync(context.coordinator)
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

    static func dismantleNSViewController(_ split: NSSplitViewController, coordinator: Coordinator) {
        coordinator.pages.stopTrackingClicks()
    }

    private func sync(_ c: Coordinator) {
        let readers = workspace.readers
        c.sidebars.show(readers: readers, active: workspace.active) { $0.sidebar() }
        c.notes.show(readers: readers, active: workspace.active) { $0.notes() }
        c.pages.sync()
    }
}

/// Keeps one hosted SwiftUI view per reader (so search text, scroll and expansion survive switching panes)
/// and shows only the active reader's.
final class PerReaderContainer: NSViewController {
    private var hosts: [ObjectIdentifier: NSView] = [:]

    override func loadView() { view = NSView() }

    @MainActor
    func show(readers: [AnyReader], active: AnyReader, make: (AnyReader) -> AnyView) {
        let live = Set(readers.map(\.id))
        for (id, host) in hosts where !live.contains(id) {
            host.removeFromSuperview()
            hosts[id] = nil
        }
        for reader in readers where hosts[reader.id] == nil {
            let host = NSHostingView(rootView: make(reader)
                .modelContainer(AnnotationStore.container)
                .frame(maxWidth: .infinity, maxHeight: .infinity))
            host.sizingOptions = []
            host.frame = view.bounds
            host.autoresizingMask = [.width, .height]
            view.addSubview(host)
            hosts[reader.id] = host
        }
        for (id, host) in hosts { host.isHidden = id != active.id }
    }
}

/// The page area: one pane, or two side by side (a nested NSSplitViewController, which sizes added panes
/// properly). Each pane gets a header bar while split; the clicked pane becomes active.
final class PaneContainer: NSSplitViewController {
    weak var workspace: Workspace?
    private var panes: [Pane] = []
    private var clickMonitor: Any?

    final class Pane: NSView {
        let header: NSHostingView<AnyView>
        var content: NSView? {
            didSet {
                oldValue?.removeFromSuperview()
                if let content { addSubview(content) }
                needsLayout = true
            }
        }
        var showsHeader = false { didSet { header.isHidden = !showsHeader; needsLayout = true } }

        init() {
            header = NSHostingView(rootView: AnyView(EmptyView()))
            header.sizingOptions = []
            super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            addSubview(header)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            let headerHeight: CGFloat = showsHeader ? 30 : 0
            header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
            content?.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: bounds.height - headerHeight)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.activatePane(at: event)
            return event
        }
    }

    func stopTrackingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    @MainActor
    private func activatePane(at event: NSEvent) {
        guard let workspace, workspace.isSplit, event.window === view.window else { return }
        for (index, pane) in panes.enumerated() where pane.bounds.contains(pane.convert(event.locationInWindow, from: nil)) {
            workspace.activate(secondary: index == 1)
        }
    }

    @MainActor
    func sync() {
        guard let workspace else { return }
        let readers = workspace.readers
        while panes.count < readers.count {
            let pane = Pane()
            let controller = NSViewController()
            controller.view = pane
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = 320
            panes.append(pane)
            addSplitViewItem(item)
            if panes.count == 2 { equalize() }
        }
        while panes.count > readers.count, let last = splitViewItems.last {
            panes.removeLast()
            removeSplitViewItem(last)
        }
        for (index, reader) in readers.enumerated() {
            let pane = panes[index]
            let view = reader.model.contentView
            if pane.content !== view { pane.content = view }
            pane.showsHeader = workspace.isSplit
            pane.header.rootView = AnyView(PaneHeader(
                title: reader.model.bookTitle,
                isActive: workspace.active.id == reader.id,
                isSecondary: index == 1,
                isLoading: workspace.loadingPane == (index == 1),
                onOpen: { [weak workspace] in
                    guard let url = RecentBooks.choose() else { return }
                    Task { await workspace?.load(url, intoSecondary: index == 1) }
                },
                onClose: { [weak workspace] in workspace?.closeSplit() }))
        }
    }

    private func equalize() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.splitViewItems.count == 2 else { return }
            self.splitView.setPosition(self.splitView.bounds.width / 2, ofDividerAt: 0)
        }
    }
}

/// Slim bar above each pane while split: which book, whether it's the active pane, open another file, close.
private struct PaneHeader: View {
    let title: String
    let isActive: Bool
    let isSecondary: Bool
    let isLoading: Bool
    let onOpen: () -> Void
    let onClose: () -> Void
    private var prefs = ReadingPrefs()

    init(title: String, isActive: Bool, isSecondary: Bool, isLoading: Bool, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self.isActive = isActive
        self.isSecondary = isSecondary
        self.isLoading = isLoading
        self.onOpen = onOpen
        self.onClose = onClose
    }

    var body: some View {
        let palette = ChromePalette(prefs.style)
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? palette.accent : palette.separator)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.text : palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isLoading { ProgressView().controlSize(.mini) }
            Button(action: onOpen) { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .help("在這一側開啟其他檔案")
            if isSecondary {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("關閉分割畫面 (⌘\\)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isActive ? palette.accent : palette.separator).frame(height: isActive ? 2 : 1)
        }
        .environment(\.colorScheme, palette.colorScheme)
    }
}
