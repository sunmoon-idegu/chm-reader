import AppKit
import CHMKit
import PDFKit
import SwiftData

/// PDFView that reports clicks on our highlights and adds 螢光標記 to the right-click menu.
final class ReaderPDFView: PDFView {
    weak var reader: PDFReaderController?
    /// Navigation requested before the view had a size (PDFView ignores it then); applied on first real layout.
    var pendingPage: String?

    override func layout() {
        super.layout()
        guard bounds.height > 0, let page = pendingPage else { return }
        pendingPage = nil
        DispatchQueue.main.async { [weak self] in self?.reader?.open(page) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let page = page(for: point, nearest: false),
           let id = PDFReaderController.annotationID(page.annotation(at: convert(point, to: page))) {
            reader?.annotationClicked(id)
            return
        }
        // Clicking elsewhere lets go of the selected note (so ⌫ no longer targets it).
        if reader?.selectedAnnotation != nil { reader?.selectedAnnotation = nil }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        reader?.selectionEnded()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if let reader, reader.hasSelection {
            let item = NSMenuItem(title: "螢光標記", action: #selector(PDFReaderController.menuHighlight(_:)), keyEquivalent: "")
            item.target = reader
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }
}

/// Covers the PDF view while the sticky-note tool is on: crosshair cursor, the next click places a note, Esc cancels.
final class NotePlacementOverlay: NSView {
    weak var reader: PDFReaderController?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        guard let reader, let pdfView = superview else { return }
        reader.placeSticky(at: pdfView.convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { reader?.isPlacingNote = false } else { super.keyDown(with: event) }
    }
}

/// Fixed-layout reader for PDF. Page identifiers are `/page/<1-based index>`, optionally `#<y>` for a
/// position on the page. Highlights are drawn as in-memory PDFKit annotations; the file is never modified.
@MainActor
final class PDFReaderController: NSObject, ObservableObject, ReaderModel {
    let bookURL: URL
    let bookKey: String
    let bookTitle: String
    let document: PDFDocument
    let pdfView = ReaderPDFView()
    let modelContext: ModelContext
    let toc: [SitemapEntry]
    let keywordIndex: [SitemapEntry] = []
    let isReflowable = false

    @Published private(set) var currentPage = "/page/1"
    @Published private(set) var pageTitle = ""
    @Published private(set) var hasSelection = false
    @Published private(set) var scalePercent = 100
    @Published var selectedAnnotation: Annotation?
    var noteToFocus: UUID?
    @Published var showNotePanel = false
    var openInNewTab: ((String) -> Void)?
    var openBeside: ((String) -> Void)?
    @Published var searchRequest = 0
    @Published var isPlacingNote = false {
        didSet {
            guard isPlacingNote != oldValue else { return }
            if isPlacingNote {
                selectionBar.hide()
                placementOverlay.reader = self
                placementOverlay.frame = pdfView.bounds
                placementOverlay.autoresizingMask = [.width, .height]
                pdfView.addSubview(placementOverlay)
                pdfView.window?.makeFirstResponder(placementOverlay)
                pdfView.window?.invalidateCursorRects(for: placementOverlay)
            } else {
                placementOverlay.removeFromSuperview()
            }
        }
    }
    private let placementOverlay = NotePlacementOverlay()
    private lazy var selectionBar = SelectionBar(
        copy: { [weak self] in self?.copySelection() },
        highlight: { [weak self] in self?.highlightSelection(thenNote: false) },
        note: { [weak self] in self?.highlightSelection(thenNote: true) })
    private var searchIndex: Task<FullTextIndex, Never>?

    private let initialPage: String
    /// Outline titles by page index, for naming pages ("第 12 頁 · 第二章").
    private let sectionStarts: [(page: Int, title: String)]
    private var lastPageKey: String { "lastPage.\(bookKey)" }

    var contentView: NSView { pdfView }
    var zoomLabel: String { "縮放 \(scalePercent)%" }

    init(url: URL, document: PDFDocument, key: String, initialPage: String?, modelContext: ModelContext) {
        bookURL = url
        bookKey = key
        self.document = document
        self.modelContext = modelContext
        // The file name, not the PDF's metadata title, which is often junk ("Microsoft Word - doc1.docx").
        bookTitle = url.deletingPathExtension().lastPathComponent

        let outline = Self.outlineEntries(document)
        toc = outline.isEmpty
            ? (0..<document.pageCount).map { SitemapEntry(id: $0 + 1, name: "第 \($0 + 1) 頁", local: "/page/\($0 + 1)", children: []) }
            : outline
        sectionStarts = outline.flatMap { $0.flattened() }
            .compactMap { row in Self.pageIndex(of: row.entry.local ?? "").map { ($0, row.entry.name) } }
            .sorted { $0.page < $1.page }
        self.initialPage = initialPage ?? UserDefaults.standard.string(forKey: "lastPage.\(key)") ?? "/page/1"
        super.init()

        pdfView.reader = self
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        center.addObserver(self, selector: #selector(scaleChanged), name: .PDFViewScaleChanged, object: pdfView)
    }

    // MARK: Lifecycle & appearance

    func start(style: ReadingStyle) {
        apply(style: style)
        pdfView.document = document
        for annotation in allAnnotations() { draw(annotation) }
        open(initialPage)
        pageChanged()
        scaleChanged()
        // Keep the selection bar on its text while scrolling.
        if let clip = pdfView.documentView?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(moveSelectionBar), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    func apply(style: ReadingStyle) {
        let bg = NSColor(hex: style.colors.background) ?? .windowBackgroundColor
        let fg = NSColor(hex: style.colors.foreground) ?? .black
        pdfView.backgroundColor = bg.blended(withFraction: 0.08, of: fg) ?? bg
    }

    func zoom(_ step: Int) {
        if step == 0 {
            pdfView.autoScales = true
        } else {
            // Turning off autoScales resets the scale, so read it first.
            let current = pdfView.scaleFactor
            pdfView.autoScales = false
            pdfView.scaleFactor = min(max(current * (step > 0 ? 1.15 : 1 / 1.15), 0.25), 6)
        }
    }

    // MARK: Navigation

    func open(_ page: String) {
        guard pdfView.bounds.height > 0 else {
            pdfView.pendingPage = page
            return
        }
        guard let index = Self.pageIndex(of: page), let pdfPage = document.page(at: index) else { return }
        if let y = CHMPath.fragment(page).flatMap(Double.init) {
            pdfView.go(to: PDFDestination(page: pdfPage, at: NSPoint(x: 0, y: y)))
        } else {
            pdfView.go(to: pdfPage)
        }
    }

    /// Places a sticky note at a point in PDF-view coordinates.
    func placeSticky(at point: NSPoint) {
        isPlacingNote = false
        guard let page = pdfView.page(for: point, nearest: true) else { return }
        let p = pdfView.convert(point, to: page)
        let index = document.index(for: page)
        let charIndex = max(page.characterIndex(at: p), 0)
        let note = Annotation(
            bookKey: bookKey, bookTitle: bookTitle, pagePath: "/page/\(index + 1)",
            pageTitle: title(forPageIndex: index), exact: "", prefix: "", suffix: "",
            start: charIndex, end: charIndex, color: .yellow)
        note.kind = "sticky"
        note.x = Double(p.x)
        note.y = Double(p.y)
        modelContext.insert(note)
        try? modelContext.save()
        draw(note)
        noteToFocus = note.id
        selectedAnnotation = note
        showNotePanel = true
    }

    @objc private func pageChanged() {
        guard let page = pdfView.currentPage else { return }
        let index = document.index(for: page)
        currentPage = "/page/\(index + 1)"
        pageTitle = title(forPageIndex: index)
        UserDefaults.standard.set(currentPage, forKey: lastPageKey)
    }

    @objc private func selectionChanged() {
        let text = pdfView.currentSelection?.string ?? ""
        hasSelection = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasSelection { selectionBar.hide() }
    }

    @objc private func scaleChanged() {
        scalePercent = Int((pdfView.scaleFactor * 100).rounded())
        moveSelectionBar()
    }

    /// After a mouse-up: offer the selection bar if text is selected.
    func selectionEnded() {
        guard hasSelection, !isPlacingNote, let rect = selectionRect() else { return }
        selectionBar.show(around: rect, in: pdfView)
    }

    @objc private func moveSelectionBar() {
        guard selectionBar.isShown else { return }
        if let rect = selectionRect() { selectionBar.show(around: rect, in: pdfView) } else { selectionBar.hide() }
    }

    /// The selection's bounds on its first page, in PDF-view coordinates.
    private func selectionRect() -> NSRect? {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first else { return nil }
        return pdfView.convert(selection.bounds(for: page), from: page)
    }

    private func title(forPageIndex index: Int) -> String {
        let section = sectionStarts.last { $0.page <= index }?.title
        return "第 \(index + 1) 頁" + (section.map { " · \($0)" } ?? "")
    }

    // MARK: Search

    func searchText(_ query: String) async -> [FullTextIndex.PageResult] {
        let task = searchIndex ?? {
            // PDFKit is read on the main actor, yielding so the UI stays responsive on long documents.
            let task = Task { @MainActor [document] in
                var pages: [FullTextIndex.Page] = []
                for i in 0..<document.pageCount {
                    pages.append(.init(id: "/page/\(i + 1)", title: self.title(forPageIndex: i),
                                       text: document.page(at: i)?.string ?? "", joinLines: true))
                    if i % 20 == 19 { await Task.yield() }
                }
                return FullTextIndex(pages: pages)
            }
            searchIndex = task
            return task
        }()
        let index = await task.value
        return await Task.detached(priority: .userInitiated) { index.search(query, hitsPerPage: 100) }.value
    }

    func openSearchHit(_ hit: FullTextIndex.Hit, query: String) {
        guard let index = Self.pageIndex(of: hit.pageID), let page = document.page(at: index),
              let selection = page.selection(for: hit.range) else { return }
        pdfView.go(to: selection)
        pdfView.setCurrentSelection(selection, animate: true)
    }

    // MARK: Highlights

    func copySelection() {
        pdfView.copy(nil)
        selectionBar.hide()
    }

    func highlightSelection(thenNote: Bool) {
        selectionBar.hide()
        guard let selection = pdfView.currentSelection, let page = selection.pages.first else { return }
        // A highlight is anchored to one page; selections spanning pages keep their first-page part.
        let range = selection.range(at: 0, on: page)
        let text = (page.string ?? "") as NSString
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= text.length else { return }
        let exact = text.substring(with: range)
        guard !exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let index = document.index(for: page)
        let prefixStart = max(0, range.location - 32)
        let annotation = Annotation(
            bookKey: bookKey, bookTitle: bookTitle, pagePath: "/page/\(index + 1)",
            pageTitle: title(forPageIndex: index), exact: exact,
            prefix: text.substring(with: NSRange(location: prefixStart, length: range.location - prefixStart)),
            suffix: text.substring(with: NSRange(location: NSMaxRange(range), length: min(32, text.length - NSMaxRange(range)))),
            start: range.location, end: NSMaxRange(range), color: .yellow)
        modelContext.insert(annotation)
        try? modelContext.save()
        draw(annotation)
        pdfView.clearSelection()
        if thenNote {
            noteToFocus = annotation.id
            showNotePanel = true
        }
        selectedAnnotation = annotation
    }

    func refreshMark(_ annotation: Annotation) {
        annotation.updatedAt = .now
        try? modelContext.save()
        draw(annotation)
    }

    func delete(_ annotation: Annotation) {
        erase(annotation)
        if selectedAnnotation?.id == annotation.id { selectedAnnotation = nil }
        modelContext.delete(annotation)
        try? modelContext.save()
    }

    func restore(_ annotation: Annotation) {
        modelContext.insert(annotation)
        try? modelContext.save()
        draw(annotation)
    }

    func reveal(_ annotation: Annotation) {
        if annotation.isSticky {
            guard let index = Self.pageIndex(of: annotation.pagePath), let page = document.page(at: index) else { return }
            pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: annotation.x, y: annotation.y + 80)))
            return
        }
        guard let selection = locate(annotation) else {
            open(annotation.pagePath)
            return
        }
        pdfView.go(to: selection)
        pdfView.setCurrentSelection(selection, animate: true)
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            if pdfView.currentSelection?.string == selection.string { pdfView.clearSelection() }
        }
    }

    func annotationClicked(_ id: UUID) {
        let descriptor = FetchDescriptor<Annotation>(predicate: #Predicate { $0.id == id })
        selectedAnnotation = try? modelContext.fetch(descriptor).first
        showNotePanel = true
    }

    @objc func menuHighlight(_ sender: NSMenuItem) { highlightSelection() }

    private func allAnnotations() -> [Annotation] {
        let key = bookKey
        return (try? modelContext.fetch(FetchDescriptor<Annotation>(predicate: #Predicate { $0.bookKey == key }))) ?? []
    }

    /// The stored text offsets first; if the page text no longer matches, the quoted text (closest to the old spot).
    private func locate(_ annotation: Annotation) -> PDFSelection? {
        guard let index = Self.pageIndex(of: annotation.pagePath), let page = document.page(at: index) else { return nil }
        let text = (page.string ?? "") as NSString
        var range = NSRange(location: annotation.start, length: annotation.end - annotation.start)
        if NSMaxRange(range) > text.length || text.substring(with: range) != annotation.exact {
            range = text.range(of: annotation.exact)
            guard range.location != NSNotFound else { return nil }
        }
        return page.selection(for: range)
    }

    private func draw(_ annotation: Annotation) {
        erase(annotation)
        if annotation.isSticky {
            guard let index = Self.pageIndex(of: annotation.pagePath), let page = document.page(at: index) else { return }
            let size: CGFloat = 22
            let mark = PDFAnnotation(
                bounds: NSRect(x: annotation.x - 4, y: annotation.y - size + 4, width: size, height: size),
                forType: .text, withProperties: nil)
            mark.iconType = .note
            mark.color = NSColor(annotation.color.color)
            mark.userName = Self.markPrefix + annotation.id.uuidString
            mark.contents = annotation.note
            page.addAnnotation(mark)
            pdfView.annotationsChanged(on: page)
            return
        }
        guard let selection = locate(annotation), let page = selection.pages.first else { return }
        let color = NSColor(annotation.color.color).withAlphaComponent(0.45)
        for line in selection.selectionsByLine() {
            let mark = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
            mark.color = color
            mark.userName = Self.markPrefix + annotation.id.uuidString
            if !annotation.note.isEmpty { mark.contents = annotation.note }
            page.addAnnotation(mark)
        }
        pdfView.annotationsChanged(on: page)
    }

    private func erase(_ annotation: Annotation) {
        guard let index = Self.pageIndex(of: annotation.pagePath), let page = document.page(at: index) else { return }
        let tag = Self.markPrefix + annotation.id.uuidString
        let marks = page.annotations.filter { $0.userName == tag }
        guard !marks.isEmpty else { return }
        marks.forEach(page.removeAnnotation)
        pdfView.annotationsChanged(on: page)
    }

    // MARK: Helpers

    private static let markPrefix = "chmreader:"

    nonisolated static func annotationID(_ mark: PDFAnnotation?) -> UUID? {
        guard let name = mark?.userName, name.hasPrefix(markPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(markPrefix.count)))
    }

    nonisolated static func pageIndex(of page: String) -> Int? {
        let path = CHMPath.stripFragment(page)
        guard path.hasPrefix("/page/"), let number = Int(path.dropFirst("/page/".count)), number >= 1 else { return nil }
        return number - 1
    }

    /// The PDF outline, keeping only entries that lead somewhere in this document. Excerpts often carry the
    /// whole book's outline, where most entries are web links to other chapters.
    private static func outlineEntries(_ document: PDFDocument) -> [SitemapEntry] {
        var nextID = 0
        func convert(_ item: PDFOutline) -> SitemapEntry? {
            let children = (0..<item.numberOfChildren).compactMap { item.child(at: $0) }.compactMap(convert)
            var local: String?
            let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination
            if let destination, let page = destination.page {
                local = "/page/\(document.index(for: page) + 1)"
                if destination.point.y != kPDFDestinationUnspecifiedValue { local! += "#\(Int(destination.point.y))" }
            }
            guard local != nil || !children.isEmpty else { return nil }
            nextID += 1
            return SitemapEntry(id: nextID, name: item.label ?? "", local: local, children: children)
        }
        guard let root = document.outlineRoot else { return [] }
        return (0..<root.numberOfChildren).compactMap { root.child(at: $0) }.compactMap(convert)
    }
}
