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
        let split = WideDividerSplitViewController()
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
        coordinator.pages.stopTrackingEvents()
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

/// Thin dividers that are still easy to grab: the draggable area extends a few points past the 1-pt line.
class WideDividerSplitViewController: NSSplitViewController {
    override func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let rect = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return splitView.isVertical ? rect.insetBy(dx: -4, dy: 0) : rect.insetBy(dx: 0, dy: -4)
    }
}

/// The page area: one pane, or two side by side (a nested NSSplitViewController, which sizes added panes
/// properly). Each pane gets a header bar while split; the clicked pane becomes active. Right after splitting,
/// the right pane asks which file to open.
final class PaneContainer: WideDividerSplitViewController {
    weak var workspace: Workspace?
    private var panes: [Pane] = []
    private var eventMonitor: Any?
    private var chooser: NSView?

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
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown { return self.deleteSelectedNote(event) ? nil : event }
            self.activatePane(at: event)
            return event
        }
    }

    func stopTrackingEvents() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// ⌫ / ⌦ deletes the selected note, unless the user is typing somewhere (the note editor, the search field).
    @MainActor
    private func deleteSelectedNote(_ event: NSEvent) -> Bool {
        guard event.window === view.window, event.keyCode == 51 || event.keyCode == 117,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              !(view.window?.firstResponder is NSText),
              let model = workspace?.model, let note = model.selectedAnnotation else { return false }
        model.deleteWithUndo(note)
        return true
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
        let count = readers.count + (workspace.choosingSecondary ? 1 : 0)
        while panes.count < count {
            let pane = Pane()
            let controller = NSViewController()
            controller.view = pane
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = 320
            panes.append(pane)
            addSplitViewItem(item)
            if panes.count == 2 { equalize() }
        }
        while panes.count > count, let last = splitViewItems.last {
            panes.removeLast()
            removeSplitViewItem(last)
        }
        if workspace.choosingSecondary, let pane = panes.last {
            let chooser = self.chooser ?? makeChooser(workspace)
            self.chooser = chooser
            if pane.content !== chooser { pane.content = chooser }
            pane.showsHeader = true
            pane.header.rootView = AnyView(PaneHeader(
                title: "選擇要並排的檔案", isActive: false, isSecondary: true,
                isLoading: workspace.loadingPane == true, onOpen: nil,
                onClose: { [weak workspace] in workspace?.closeSplit() }))
        } else {
            chooser = nil  // made fresh next time, so its recent files are current
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

    @MainActor
    private func makeChooser(_ workspace: Workspace) -> NSView {
        let open: (URL) -> Void = { [weak workspace] url in
            Task { await workspace?.load(url, intoSecondary: true) }
        }
        let host = NSHostingView(rootView: PaneChooser(open: open))
        host.sizingOptions = []
        return host
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
    let onOpen: (() -> Void)?
    let onClose: () -> Void
    private var prefs = ReadingPrefs()

    init(title: String, isActive: Bool, isSecondary: Bool, isLoading: Bool, onOpen: (() -> Void)?, onClose: @escaping () -> Void) {
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
            if let onOpen {
                Button(action: onOpen) { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
                    .help("在這一側開啟其他檔案")
            }
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

/// The right pane right after splitting: pick a recent file or open one, like a new tab's welcome screen.
private struct PaneChooser: View {
    let open: (URL) -> Void
    @State private var recent = RecentBooks.urls
    private var prefs = ReadingPrefs()

    init(open: @escaping (URL) -> Void) { self.open = open }

    var body: some View {
        let palette = ChromePalette(prefs.style)
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.secondary)
            Text("並排閱讀")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.text)
            Button("開啟 PDF 或 CHM 檔案…") {
                if let url = RecentBooks.choose() { open(url) }
            }
            .controlSize(.large)

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近閱讀")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    ForEach(recent, id: \.self) { url in
                        RecentRow(url: url, palette: palette) { open(url) }
                    }
                }
                .frame(maxWidth: 320)
            }
            Text("也可以把 .pdf 或 .chm 檔拖曳到這裡")
                .font(.footnote)
                .foregroundStyle(palette.secondary.opacity(0.8))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .environment(\.colorScheme, palette.colorScheme)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: OpenedDocument.isSupported) else { return false }
            open(url)
            return true
        }
    }
}

private struct RecentRow: View {
    let url: URL
    let palette: ChromePalette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(url.deletingPathExtension().lastPathComponent,
                  systemImage: url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "book")
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hovering ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}
