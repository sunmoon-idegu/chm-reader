import AppKit
import CHMKit
import Combine
import PDFKit
import SwiftUI

/// A reader of either kind. The window chrome is generic over `ReaderModel`; this picks the concrete type.
@MainActor
enum AnyReader {
    case chm(ReaderController)
    case pdf(PDFReaderController)

    var model: any ReaderModel {
        switch self {
        case .chm(let r): r
        case .pdf(let r): r
        }
    }

    var id: ObjectIdentifier { ObjectIdentifier(model) }

    var objectWillChange: ObservableObjectPublisher {
        switch self {
        case .chm(let r): r.objectWillChange
        case .pdf(let r): r.objectWillChange
        }
    }

    func sidebar() -> AnyView {
        switch self {
        case .chm(let r): AnyView(SidebarView(reader: r))
        case .pdf(let r): AnyView(SidebarView(reader: r))
        }
    }

    func notes() -> AnyView {
        switch self {
        case .chm(let r): AnyView(NotesPanel(reader: r))
        case .pdf(let r): AnyView(NotesPanel(reader: r))
        }
    }

    static func make(_ document: OpenedDocument, url: URL, page: String?) -> AnyReader {
        let context = AnnotationStore.container.mainContext
        switch document {
        case .chm(let book):
            return .chm(ReaderController(book: book, initialPage: page, modelContext: context))
        case .pdf(let pdf, let key):
            return .pdf(PDFReaderController(url: url, document: pdf, key: key, initialPage: page, modelContext: context))
        }
    }
}

enum DocumentLoader {
    static func load(_ url: URL) async throws -> OpenedDocument {
        // Held for the app's lifetime: tabs and panes reopen the same file while it's being read.
        _ = url.startAccessingSecurityScopedResource()
        if url.pathExtension.lowercased() == "pdf" {
            let key = try await Task.detached { try FileFingerprint.key(for: url) }.value
            guard let pdf = PDFDocument(url: url) else { throw OpenError.unreadablePDF(url) }
            guard !pdf.isLocked else { throw OpenError.lockedPDF(url) }
            return .pdf(pdf, key: key)
        }
        return .chm(try await Task.detached { try CHMBook(url: url) }.value)
    }
}

/// One tab: a book, optionally split with a second book (or another page of the same one) beside it.
/// The active pane drives the sidebar, notes panel, toolbar and menus.
@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var primary: AnyReader
    @Published private(set) var secondary: AnyReader?
    @Published private(set) var activeIsSecondary = false
    @Published private(set) var loadingPane: Bool?
    @Published var error: String?
    /// Bumped by ⌘F; the window shows the sidebar.
    @Published private(set) var searchRequest = 0
    /// Bumped by user zooms; the window shows the zoom toast.
    @Published private(set) var zoomTick = 0

    var openInNewTab: ((URL, String) -> Void)?
    private var style: ReadingStyle?
    private var forwarding: [ObjectIdentifier: AnyCancellable] = [:]

    init(primary: AnyReader) {
        self.primary = primary
    }

    var isSplit: Bool { secondary != nil }
    var active: AnyReader { activeIsSecondary ? (secondary ?? primary) : primary }
    var model: any ReaderModel { active.model }
    var readers: [AnyReader] { [primary] + (secondary.map { [$0] } ?? []) }
    var window: NSWindow? { primary.model.contentView.window }

    func start(style: ReadingStyle) {
        self.style = style
        attach(primary)
    }

    func apply(style: ReadingStyle) {
        self.style = style
        for reader in readers { reader.model.apply(style: style) }
    }

    func activate(secondary: Bool) {
        guard secondary != activeIsSecondary, !secondary || isSplit else { return }
        activeIsSecondary = secondary
    }

    func zoom(_ step: Int) {
        model.zoom(step)
        zoomTick += 1
    }

    func requestSearch() {
        var model = self.model
        model.searchRequest += 1
        searchRequest += 1
    }

    /// Splits with the active book at its current page, or closes the split.
    func toggleSplit() {
        if isSplit {
            closeSplit()
        } else {
            let model = self.model
            Task { await load(model.bookURL, page: model.currentPage, intoSecondary: true) }
        }
    }

    func closeSplit() {
        guard let secondary else { return }
        detach(secondary)
        self.secondary = nil
        activeIsSecondary = false
    }

    /// Loads a file into one pane, replacing what it showed (or creating the right pane).
    func load(_ url: URL, page: String? = nil, intoSecondary: Bool) async {
        loadingPane = intoSecondary
        defer { loadingPane = nil }
        do {
            let reader = AnyReader.make(try await DocumentLoader.load(url), url: url, page: page)
            RecentBooks.add(url)
            if intoSecondary {
                if let old = secondary { detach(old) }
                secondary = reader
            } else {
                detach(primary)
                primary = reader
            }
            attach(reader)
            activeIsSecondary = intoSecondary
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func attach(_ reader: AnyReader) {
        forwarding[reader.id] = reader.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        var model = reader.model
        let url = model.bookURL
        model.openInNewTab = { [weak self] page in self?.openInNewTab?(url, page) }
        model.openBeside = { [weak self, weak object = model as AnyObject] page in
            guard let self, let object else { return }
            let fromSecondary = self.secondary.map { ObjectIdentifier($0.model) == ObjectIdentifier(object) } ?? false
            Task { await self.load(url, page: page, intoSecondary: !fromSecondary) }
        }
        if let style { model.start(style: style) }
    }

    private func detach(_ reader: AnyReader) {
        forwarding[reader.id] = nil
        var model = reader.model
        model.openInNewTab = nil
        model.openBeside = nil
        model.contentView.removeFromSuperview()
    }
}
