import AppKit
import CHMKit
import SwiftUI

/// What the window chrome (sidebar, notes panel, toolbar, menus) needs from a reader.
/// Implemented by `ReaderController` (CHM, reflowable HTML) and `PDFReaderController` (fixed layout).
/// Page identifiers are archive paths for CHM and `/page/<n>` for PDF.
@MainActor
protocol ReaderModel: ObservableObject {
    var bookTitle: String { get }
    var bookKey: String { get }
    var bookURL: URL { get }
    var toc: [SitemapEntry] { get }
    var keywordIndex: [SitemapEntry] { get }
    var homePage: String { get }
    var currentPage: String { get }
    var pageTitle: String { get }
    var hasSelection: Bool { get }
    var selectedAnnotation: Annotation? { get set }
    var showNotePanel: Bool { get set }
    var openInNewTab: ((String) -> Void)? { get set }
    /// Opens a page of this book in the other pane of the split view.
    var openBeside: ((String) -> Void)? { get set }
    var contentView: NSView { get }

    /// Reflowable books get the typography panel; fixed-layout ones only zoom.
    var isReflowable: Bool { get }
    /// Shown in the toast after zooming, e.g. "字級 21 pt" or "縮放 125%".
    var zoomLabel: String { get }
    /// +1 / −1 to step, 0 to reset.
    func zoom(_ step: Int)

    /// Bumped by ⌘F; the window shows the sidebar and focuses its search field.
    var searchRequest: Int { get set }
    /// Full-text search. The first call builds the book's index in the background.
    func searchText(_ query: String) async -> [FullTextIndex.PageResult]
    /// Opens the hit's page, scrolls to the match and selects it (so it can be highlighted right away).
    func openSearchHit(_ hit: FullTextIndex.Hit, query: String)

    func start(style: ReadingStyle)
    func apply(style: ReadingStyle)
    func open(_ page: String)
    func goHome()
    func highlightSelection()
    func reveal(_ annotation: Annotation)
    func refreshMark(_ annotation: Annotation)
    func delete(_ annotation: Annotation)
}

extension ReaderController: ReaderModel {
    var bookTitle: String { book.title }
    var bookKey: String { book.key }
    var bookURL: URL { book.url }
    var toc: [SitemapEntry] { book.toc }
    var keywordIndex: [SitemapEntry] { book.index }
    var homePage: String { book.defaultTopic }
    var contentView: NSView { webView }
    var isReflowable: Bool { true }

    var zoomLabel: String {
        "字級 \(Int(UserDefaults.standard.object(forKey: Pref.fontSize) as? Double ?? 20)) pt"
    }

    func zoom(_ step: Int) {
        let defaults = UserDefaults.standard
        let size = defaults.object(forKey: Pref.fontSize) as? Double ?? 20
        defaults.set(step == 0 ? 20 : min(max(size + Double(step), 12), 40), forKey: Pref.fontSize)
        objectWillChange.send()
    }
}

/// Finds the workspace in the frontmost window for menu commands. SwiftUI's focused values go missing when an
/// AppKit view (the web view or PDF view) is first responder, which left ⌘F and friends disabled.
@MainActor
enum ReaderRegistry {
    private final class Entry {
        weak var workspace: Workspace?
        init(_ workspace: Workspace) { self.workspace = workspace }
    }
    private static var entries: [Entry] = []

    static func register(_ workspace: Workspace) {
        entries.removeAll { $0.workspace == nil || $0.workspace === workspace }
        entries.append(Entry(workspace))
    }

    static var current: Workspace? {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return entries.lazy.compactMap(\.workspace).first { $0.window === window }
    }
}
