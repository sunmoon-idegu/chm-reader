import CHMKit
import PDFKit
import SwiftUI

/// A loaded document, ready for its reader.
enum OpenedDocument {
    case chm(CHMBook)
    case pdf(PDFDocument, key: String)

    var key: String {
        switch self {
        case .chm(let book): book.key
        case .pdf(_, let key): key
        }
    }

    static func isSupported(_ url: URL) -> Bool { ["chm", "pdf"].contains(url.pathExtension.lowercased()) }
}

enum OpenError: LocalizedError {
    case unreadablePDF(URL), lockedPDF(URL)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let url): "無法讀取 PDF：\(url.lastPathComponent)"
        case .lockedPDF(let url): "這個 PDF 有密碼保護，目前無法開啟：\(url.lastPathComponent)"
        }
    }
}

/// One window: the welcome screen until a book is chosen, then the reader.
struct RootView: View {
    @Binding var target: BookTarget?
    @Environment(\.openWindow) private var openWindow
    @State private var document: OpenedDocument?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if let document {
                reader(for: document)
                    .id(document.key)
            } else {
                Group {
                    if loading {
                        ProgressView("開啟中…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        WelcomeView(open: { target = BookTarget(url: $0) })
                    }
                }
                // Same toolbar style as a book tab, so the title bar keeps its height (e.g. after the tab bar's +).
                .navigationTitle("閱讀器")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let url = RecentBooks.choose() { target = BookTarget(url: url) }
                        } label: {
                            Label("開啟", systemImage: "folder")
                        }
                        .help("開啟 CHM 或 PDF 檔案 (⌘O)")
                        .disabled(loading)
                    }
                }
            }
        }
        .task(id: target?.url) { await load() }
        // Route files opened from Finder to an existing window (which adds a tab) instead of a new window.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL(perform: openBook)
        .focusedSceneValue(\.openBook, openBook)
        .alert("無法開啟", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { target = nil }
        } message: {
            Text(error ?? "")
        }
    }

    /// An empty (welcome) window loads the book itself; otherwise the book opens as a new tab of this window.
    private func openBook(_ url: URL) {
        if target == nil {
            target = BookTarget(url: url)
        } else {
            TabOpener.openTab(BookTarget(url: url), from: nil, using: openWindow)
        }
    }

    private func reader(for document: OpenedDocument) -> some View {
        BookView(reader: AnyReader.make(document, url: target!.url, page: target?.page))
    }

    private func load() async {
        guard let url = target?.url else { document = nil; return }
        loading = true
        defer { loading = false }
        do {
            document = try await DocumentLoader.load(url)
            RecentBooks.add(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WelcomeView: View {
    var open: (URL) -> Void
    @State private var recent = RecentBooks.urls

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("閱讀器").font(.largeTitle.weight(.semibold))
            Button("開啟 PDF 或 CHM 檔案…") {
                if let url = RecentBooks.choose() { open(url) }
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近閱讀").font(.headline).foregroundStyle(.secondary)
                    ForEach(recent, id: \.self) { url in
                        Button {
                            open(url)
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "book")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.link)
                        .help(url.path)
                    }
                }
                .frame(maxWidth: 360)
            }
            Text("也可以把 .pdf 或 .chm 檔拖曳到這裡").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: OpenedDocument.isSupported) else { return false }
            open(url)
            return true
        }
    }
}
