import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let chm = UTType(filenameExtension: "chm") ?? .data
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Always start at the welcome screen instead of restoring the last window and its book.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CHMReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("CHM Reader", for: BookTarget.self) { $target in
            RootView(target: $target)
                .frame(minWidth: 760, minHeight: 520)
                .background(WindowTabbingConfigurator())
        }
        .modelContainer(AnnotationStore.container)
        .commands { ReaderCommands() }

        Settings {
            TypographyPanel()
                .frame(width: 380)
                .padding(20)
        }
    }
}

struct ReaderCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.openBook) private var openBook
    @FocusedObject private var chmReader: ReaderController?
    @FocusedObject private var pdfReader: PDFReaderController?

    private var focusedReaderHasNoSelection: Bool {
        if let chmReader { return !chmReader.hasSelection }
        if let pdfReader { return !pdfReader.hasSelection }
        return false
    }

    /// The focused reader if SwiftUI knows it (keeps menu states live), else the frontmost window's reader.
    private var reader: (any ReaderModel)? {
        if let chmReader { return chmReader }
        if let pdfReader { return pdfReader }
        return ReaderRegistry.current
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("開啟…") {
                guard let url = RecentBooks.choose() else { return }
                if let openBook { openBook(url) } else { openWindow(value: BookTarget(url: url)) }
            }
            .keyboardShortcut("o")
            Button("新分頁") { TabOpener.openEmptyTab() }
                .keyboardShortcut("t")
        }
        // Replaces Edit ▸ Find, whose own ⌘F would otherwise win and do nothing in a web or PDF view.
        CommandGroup(replacing: .textEditing) {
            Button("搜尋內文…") { reader?.searchRequest += 1 }
                .keyboardShortcut("f")
        }
        CommandMenu("閱讀") {
            Button("首頁") { reader?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button(reader?.isReflowable == false ? "放大" : "放大字級") { reader?.zoom(1) }
                .keyboardShortcut("=")
            Button(reader?.isReflowable == false ? "縮小" : "縮小字級") { reader?.zoom(-1) }
                .keyboardShortcut("-")
            Button(reader?.isReflowable == false ? "符合視窗大小" : "預設字級") { reader?.zoom(0) }
                .keyboardShortcut("0")
            Divider()
            Button("螢光標記") { reader?.highlightSelection() }
                .keyboardShortcut("h", modifiers: [.command, .option])
                .disabled(focusedReaderHasNoSelection)
        }
    }
}

/// Recently opened books, stored as security-scoped bookmarks so the sandboxed app can reopen them.
enum RecentBooks {
    static let key = "recentBookmarks"

    static var urls: [URL] {
        (UserDefaults.standard.array(forKey: key) as? [Data] ?? []).compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() || FileManager.default.isReadableFile(atPath: url.path),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    static func add(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) else { return }
        var list = (UserDefaults.standard.array(forKey: key) as? [Data] ?? []).filter { existing in
            var stale = false
            let resolved = try? URL(resolvingBookmarkData: existing, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            return resolved?.standardizedFileURL != url.standardizedFileURL
        }
        list.insert(data, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: key)
    }

    @MainActor static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.chm, .pdf]
        panel.allowsMultipleSelection = false
        panel.message = "選擇要閱讀的 CHM 或 PDF 檔案"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
