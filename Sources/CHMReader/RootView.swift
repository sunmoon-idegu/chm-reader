import CHMKit
import SwiftUI

/// One window: the welcome screen until a book is chosen, then the reader.
struct RootView: View {
    @Binding var target: BookTarget?
    @Environment(\.openWindow) private var openWindow
    @State private var book: CHMBook?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if let book {
                BookView(book: book, initialPage: target?.page)
                    .id(book.key)
            } else if loading {
                ProgressView("開啟中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeView(open: { target = BookTarget(url: $0) })
            }
        }
        .task(id: target?.url) { await load() }
        .onOpenURL { incoming in
            if target == nil { target = BookTarget(url: incoming) } else { openWindow(value: BookTarget(url: incoming)) }
        }
        .alert("無法開啟", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { target = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func load() async {
        guard let url = target?.url else { book = nil; return }
        loading = true
        defer { loading = false }
        // Held for the app's lifetime: tabs reopen the same file while it's being read.
        _ = url.startAccessingSecurityScopedResource()
        do {
            let opened = try await Task.detached { try CHMBook(url: url) }.value
            RecentBooks.add(url)
            book = opened
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
            Button("開啟 CHM 檔案…") {
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
            Text("也可以把 .chm 檔拖曳到這裡").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "chm" }) else { return false }
            open(url)
            return true
        }
    }
}
