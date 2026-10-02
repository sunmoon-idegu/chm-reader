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
            } else if loading {
                ProgressView("開啟中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeView(open: { target = BookTarget(url: $0) })
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

    @ViewBuilder
    private func reader(for document: OpenedDocument) -> some View {
        let context = AnnotationStore.container.mainContext
        switch document {
        case .chm(let book):
            BookView(reader: ReaderController(book: book, initialPage: target?.page, modelContext: context))
        case .pdf(let pdf, let key):
            BookView(reader: PDFReaderController(
                url: pdf.documentURL ?? target!.url, document: pdf, key: key, initialPage: target?.page, modelContext: context))
        }
    }

    private func load() async {
        guard let url = target?.url else { document = nil; return }
        loading = true
        defer { loading = false }
        // Held for the app's lifetime: tabs reopen the same file while it's being read.
        _ = url.startAccessingSecurityScopedResource()
        do {
            if url.pathExtension.lowercased() == "pdf" {
                let key = try await Task.detached { try FileFingerprint.key(for: url) }.value
                guard let pdf = PDFDocument(url: url) else { throw OpenError.unreadablePDF(url) }
                guard !pdf.isLocked else { throw OpenError.lockedPDF(url) }
                document = .pdf(pdf, key: key)
            } else {
                document = .chm(try await Task.detached { try CHMBook(url: url) }.value)
            }
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
            Text("CHM 閱讀器").font(.largeTitle.weight(.semibold))
            Button("開啟 CHM 或 PDF 檔案…") {
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
            Text("也可以把 .chm 或 .pdf 檔拖曳到這裡").font(.footnote).foregroundStyle(.tertiary)
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
