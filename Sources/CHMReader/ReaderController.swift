import AppKit
import CHMKit
import Combine
import SwiftData
import UniformTypeIdentifiers
import WebKit

/// Serves archive contents at `chm://book/<path>`. HTML is transcoded to UTF-8 so WebKit never guesses.
final class CHMSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "chm"
    let book: CHMBook

    init(book: CHMBook) { self.book = book }

    static func url(for path: String) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "book"
        c.path = CHMPath.stripFragment(path)
        c.fragment = CHMPath.fragment(path)
        return c.url!
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path.isEmpty ? "/" : url.path
        guard let data = book.file.data(at: path) else {
            task.didFailWithError(URLError(.fileDoesNotExist, userInfo: [NSURLErrorFailingURLErrorKey: url]))
            return
        }
        let ext = (path as NSString).pathExtension.lowercased()
        var body = data
        var mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        var charset: String?
        switch ext {
        case "htm", "html", "xhtml", "shtml":
            mime = "text/html"
            body = Data(TextDecoding.forceUTF8MetaCharset(book.decodeText(data)).utf8)
            charset = "utf-8"
        case "css", "js", "txt":
            charset = TextDecoding.ianaName(book.preferredEncoding)
        default:
            break
        }
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: body.count, textEncodingName: charset)
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Adds highlight/note items to the web view's right-click menu when text is selected.
final class ReaderWebView: WKWebView {
    weak var reader: ReaderController?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let reader, menu.items.contains(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierCopy" }) else { return }
        let highlight = NSMenuItem(title: "螢光標記", action: #selector(ReaderController.menuHighlight(_:)), keyEquivalent: "")
        highlight.target = reader
        menu.insertItem(highlight, at: 0)
        menu.insertItem(.separator(), at: 1)
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

@MainActor
final class ReaderController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let book: CHMBook
    let webView: ReaderWebView
    let modelContext: ModelContext
    private let schemeHandler: CHMSchemeHandler

    @Published private(set) var currentPath: String
    @Published private(set) var pageTitle = ""
    @Published var selectedAnnotation: Annotation?
    @Published var showNotePanel = false
    @Published private(set) var hasSelection = false

    var openInNewTab: ((String) -> Void)?
    @Published var searchRequest = 0
    private var searchIndex: Task<FullTextIndex, Never>?
    private var pendingFind: (query: String, occurrence: Int)?
    private var style: ReadingStyle?
    private var pendingReveal: UUID?

    private var lastPageKey: String { "lastPage.\(book.key)" }

    private lazy var tocTitles: [String: String] = {
        let pairs = book.toc.flatMap { $0.flattened() }.compactMap { row in
            row.entry.local.map { (CHMPath.stripFragment($0).lowercased(), row.entry.name) }
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }()

    init(book: CHMBook, initialPage: String?, modelContext: ModelContext) {
        self.book = book
        self.modelContext = modelContext
        schemeHandler = CHMSchemeHandler(book: book)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: CHMSchemeHandler.scheme)
        config.preferences.isTextInteractionEnabled = true
        webView = ReaderWebView(frame: .zero, configuration: config)
        currentPath = initialPage ?? UserDefaults.standard.string(forKey: "lastPage.\(book.key)") ?? book.defaultTopic
        super.init()

        config.userContentController.add(
            WeakMessageHandler(self), contentWorld: ReaderScript.world, name: ReaderScript.messageHandler)
        webView.reader = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
    }

    func start(style: ReadingStyle) {
        apply(style: style)
        open(currentPath)
    }

    // MARK: Navigation

    func open(_ path: String) {
        let resolved = CHMPath.resolve(path, relativeTo: "/")
        if CHMPath.stripFragment(resolved) == currentPage, webView.url != nil,
           let fragment = CHMPath.fragment(resolved) {
            Task { try? await webView.callAsyncJavaScript(
                "document.getElementById(f)?.scrollIntoView() ?? document.getElementsByName(f)[0]?.scrollIntoView()",
                arguments: ["f": fragment], in: nil, contentWorld: .page) }
            return
        }
        webView.load(URLRequest(url: CHMSchemeHandler.url(for: resolved)))
    }

    func goHome() { open(book.defaultTopic) }

    var currentPage: String { CHMPath.stripFragment(currentPath) }

    private static func path(of url: URL) -> String {
        url.path + (url.fragment.map { "#\($0)" } ?? "")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return .cancel }
        switch scheme {
        case CHMSchemeHandler.scheme:
            // ⌘-click or middle-click a link opens it in a new tab.
            if action.navigationType == .linkActivated,
               action.modifierFlags.contains(.command) || action.buttonNumber == 2, let openInNewTab {
                openInNewTab(Self.path(of: url))
                return .cancel
            }
            return .allow
        case "about", "data", "blob":
            return .allow
        case "ms-its", "mk", "its":
            open(CHMPath.resolve(url.absoluteString.removingPercentEncoding ?? url.absoluteString, relativeTo: currentPath))
            return .cancel
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
            return .cancel
        default:
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasSelection = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState()
        UserDefaults.standard.set(currentPage, forKey: lastPageKey)
        Task { await restoreHighlights() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as? URLError)?.code == .fileDoesNotExist, webView.url == nil, currentPath != book.defaultTopic {
            currentPath = book.defaultTopic
            goHome()
        }
    }

    private func syncState() {
        if let url = webView.url, url.scheme == CHMSchemeHandler.scheme {
            currentPath = Self.path(of: url)
        }
        let title = webView.title ?? ""
        pageTitle = title.isEmpty ? tocTitles[currentPage.lowercased()] ?? "" : title
    }

    // MARK: Style

    func apply(style: ReadingStyle) {
        guard style != self.style else { return }
        self.style = style
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: ReaderScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: ReaderScript.world))
        let cssLiteral = Self.jsString(style.css)
        controller.addUserScript(WKUserScript(
            source: "window.chmReader && chmReader.setStyle(\(cssLiteral));",
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: ReaderScript.world))
        webView.underPageBackgroundColor = NSColor(hex: style.colors.background) ?? .textBackgroundColor
        webView.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
        Task {
            try? await webView.callAsyncJavaScript(
                "window.chmReader && chmReader.setStyle(css)", arguments: ["css": style.css], in: nil,
                contentWorld: ReaderScript.world)
        }
    }

    private static func jsString(_ s: String) -> String {
        (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
    }

    // MARK: Highlights

    func annotationsOnCurrentPage() -> [Annotation] {
        let key = book.key
        let path = currentPage
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate { $0.bookKey == key && $0.pagePath == path }, sortBy: [SortDescriptor(\.start)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func js(_ body: String, _ args: [String: Any] = [:]) async -> Any? {
        try? await webView.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: ReaderScript.world)
    }

    private func restoreHighlights() async {
        let items = annotationsOnCurrentPage().map(\.jsPayload)
        if !items.isEmpty {
            _ = await js("return chmReader.restore(items)", ["items": items])
        }
        if let id = pendingReveal {
            pendingReveal = nil
            _ = await js("return chmReader.scrollTo(id)", ["id": id.uuidString])
        }
        if let find = pendingFind {
            pendingFind = nil
            _ = await js("return chmReader.find(q, n)", ["q": find.query, "n": find.occurrence])
        }
    }

    // MARK: Search

    func searchText(_ query: String) async -> [FullTextIndex.PageResult] {
        let task = searchIndex ?? {
            let book = self.book
            let task = Task.detached(priority: .userInitiated) { FullTextIndex(pages: book.searchablePages()) }
            searchIndex = task
            return task
        }()
        let index = await task.value
        return await Task.detached(priority: .userInitiated) { index.search(query, hitsPerPage: 100) }.value
    }

    func openSearchHit(_ hit: FullTextIndex.Hit, query: String) {
        if hit.pageID.caseInsensitiveCompare(currentPage) == .orderedSame {
            Task { _ = await js("return chmReader.find(q, n)", ["q": query, "n": hit.occurrence]) }
        } else {
            pendingFind = (query, hit.occurrence)
            open(hit.pageID)
        }
    }

    func highlightSelection() {
        Task {
            guard let anchor = await js("return chmReader.capture()") as? [String: Any],
                  let exact = anchor["exact"] as? String,
                  let start = (anchor["start"] as? NSNumber)?.intValue,
                  let end = (anchor["end"] as? NSNumber)?.intValue else {
                NSSound.beep()
                return
            }
            let annotation = Annotation(
                bookKey: book.key, bookTitle: book.title, pagePath: currentPage,
                pageTitle: pageTitle, exact: exact, prefix: anchor["prefix"] as? String ?? "",
                suffix: anchor["suffix"] as? String ?? "", start: start, end: end, color: .yellow)
            modelContext.insert(annotation)
            try? modelContext.save()
            _ = await js("chmReader.apply(a); chmReader.clearSelection()", ["a": annotation.jsPayload])
            selectedAnnotation = annotation
        }
    }

    func refreshMark(_ annotation: Annotation) {
        annotation.updatedAt = .now
        try? modelContext.save()
        Task {
            _ = await js(
                "chmReader.update(id, color, note)",
                ["id": annotation.id.uuidString, "color": annotation.colorName, "note": !annotation.note.isEmpty])
        }
    }

    func delete(_ annotation: Annotation) {
        let id = annotation.id.uuidString
        if selectedAnnotation?.id == annotation.id { selectedAnnotation = nil }
        modelContext.delete(annotation)
        try? modelContext.save()
        Task { _ = await js("chmReader.remove(id)", ["id": id]) }
    }

    func reveal(_ annotation: Annotation) {
        if annotation.pagePath == currentPage {
            Task { _ = await js("return chmReader.scrollTo(id)", ["id": annotation.id.uuidString]) }
        } else {
            pendingReveal = annotation.id
            open(annotation.pagePath)
        }
    }

    /// Handles WebKit's "Open Link in New Window" and `target=_blank` links by opening a tab instead.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url, url.scheme == CHMSchemeHandler.scheme {
            openInNewTab?(Self.path(of: url))
        }
        return nil
    }

    @objc func menuHighlight(_ sender: NSMenuItem) {
        highlightSelection()
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "selection" {
            hasSelection = (body["has"] as? NSNumber)?.boolValue ?? false
            return
        }
        guard body["type"] as? String == "highlightClicked",
              let idString = body["id"] as? String, let id = UUID(uuidString: idString) else { return }
        let descriptor = FetchDescriptor<Annotation>(predicate: #Predicate { $0.id == id })
        selectedAnnotation = try? modelContext.fetch(descriptor).first
        showNotePanel = true
    }
}
