import CHMKit
import PDFKit
import SwiftUI

/// Left panel: tabs for the table of contents, the keyword index (CHM books that have one) and page
/// thumbnails (PDF). Contents and index can be filtered by title; full-text search is the find bar (⌘F).
struct SidebarView<R: ReaderModel>: View {
    @ObservedObject var reader: R
    /// Set for PDFs, which get the 縮覽圖 tab.
    let document: PDFDocument?
    private var prefs = ReadingPrefs()
    /// Remembered across books; a book without that tab shows 目錄.
    @AppStorage("sidebar.tab") private var savedTab = Tab.contents
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    enum Tab: String, Hashable { case contents, index, thumbnails }

    private var tab: Tab { tabs.contains { $0.0 == savedTab } ? savedTab : .contents }

    init(reader: R, document: PDFDocument? = nil) {
        self.reader = reader
        self.document = document
    }

    private var tabs: [(Tab, String)] {
        [(.contents, "目錄")]
            + (reader.keywordIndex.isEmpty ? [] : [(.index, "索引")])
            + (document == nil ? [] : [(.thumbnails, "縮覽圖")])
    }

    var body: some View {
        let palette = ChromePalette(prefs.style)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if tabs.count > 1 {
                    Picker("", selection: Binding(get: { tab }, set: { savedTab = $0 })) {
                        ForEach(tabs, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if tab != .thumbnails {
                    SearchField(text: $query, prompt: tab == .index ? "篩選索引" : "篩選目錄", palette: palette)
                        .focused($filterFocused)
                        .onExitCommand { query = ""; filterFocused = false }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle().fill(palette.separator).frame(height: 1)

            switch tab {
            case .thumbnails:
                if let document { ThumbnailList(reader: reader, document: document, palette: palette) }
            case .index:
                FlatEntries(reader: reader, rows: filtered(reader.keywordIndex), palette: palette)
            case .contents:
                if query.isEmpty {
                    TOCTree(reader: reader, palette: palette)
                } else {
                    FlatEntries(reader: reader, rows: filtered(reader.toc), palette: palette)
                }
            }
        }
        .background(palette.background)
        .environment(\.colorScheme, palette.colorScheme)
    }

    private func filtered(_ entries: [SitemapEntry]) -> [(entry: SitemapEntry, depth: Int)] {
        let all = entries.flatMap { $0.flattened() }
        guard !query.isEmpty else { return all }
        return all.filter { $0.entry.name.localizedCaseInsensitiveContains(query) }.map { ($0.entry, 0) }
    }
}

/// PDF page thumbnails; the current page is outlined, a click goes to the page.
private struct ThumbnailList<R: ReaderModel>: View {
    @ObservedObject var reader: R
    let document: PDFDocument
    let palette: ChromePalette

    private var currentIndex: Int? { PDFReaderController.pageIndex(of: reader.currentPage) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        if let page = document.page(at: index) {
                            PageThumbnail(page: page, number: index + 1, isCurrent: index == currentIndex, palette: palette) {
                                reader.open("/page/\(index + 1)")
                            }
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .onAppear { if let currentIndex { proxy.scrollTo(currentIndex, anchor: .center) } }
            .onChange(of: currentIndex) { _, index in
                guard let index else { return }
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }
}

private struct PageThumbnail: View {
    let page: PDFPage
    let number: Int
    let isCurrent: Bool
    let palette: ChromePalette
    let action: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    private static let cache = NSCache<PDFPage, NSImage>()
    private static let width: CGFloat = 140

    private var aspect: CGFloat {
        let size = page.bounds(for: .cropBox).size
        let turned = page.rotation % 180 != 0
        let (w, h) = turned ? (size.height, size.width) : (size.width, size.height)
        return h > 0 ? w / h : 0.75
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.white
                if let image { Image(nsImage: image).resizable().interpolation(.high) }
            }
            .frame(width: Self.width, height: Self.width / aspect)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCurrent ? palette.accent : (hovering ? palette.separator.opacity(3) : .clear),
                            lineWidth: isCurrent ? 3 : 1.5))
            Text("\(number)")
                .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isCurrent ? palette.accent : palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .task {
            if let cached = Self.cache.object(forKey: page) { image = cached; return }
            await Task.yield()  // let scrolling draw first; thumbnails render as rows come into view
            guard !Task.isCancelled else { return }
            let scale: CGFloat = 2
            let rendered = page.thumbnail(of: CGSize(width: Self.width * scale, height: Self.width * scale / aspect), for: .cropBox)
            Self.cache.setObject(rendered, forKey: page)
            image = rendered
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String
    let palette: ChromePalette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.separator))
    }
}

private struct TOCTree<R: ReaderModel>: View {
    @ObservedObject var reader: R
    let palette: ChromePalette
    @State private var expanded: Set<Int> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(visibleRows, id: \.entry.id) { row in
                        EntryRow(
                            entry: row.entry, depth: row.depth, palette: palette,
                            isCurrent: isCurrent(row.entry),
                            isExpanded: row.entry.children.isEmpty ? nil : expanded.contains(row.entry.id),
                            onToggle: { toggle(row.entry.id) },
                            reader: reader)
                        .id(row.entry.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onAppear { revealCurrent(proxy, animated: false) }
            .onChange(of: reader.currentPage) { _, _ in revealCurrent(proxy, animated: true) }
        }
    }

    private var visibleRows: [(entry: SitemapEntry, depth: Int)] {
        var rows: [(SitemapEntry, Int)] = []
        func walk(_ entries: [SitemapEntry], _ depth: Int) {
            for e in entries {
                rows.append((e, depth))
                if expanded.contains(e.id) { walk(e.children, depth + 1) }
            }
        }
        walk(reader.toc, 0)
        return rows
    }

    private func toggle(_ id: Int) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    private func isCurrent(_ entry: SitemapEntry) -> Bool {
        guard let local = entry.local else { return false }
        return CHMPath.stripFragment(local).caseInsensitiveCompare(reader.currentPage) == .orderedSame
    }

    private func revealCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let path = ancestry(in: reader.toc), let target = path.last else { return }
        expanded.formUnion(path.dropLast().map(\.id))
        DispatchQueue.main.async {
            if animated {
                withAnimation { proxy.scrollTo(target.id, anchor: .center) }
            } else {
                proxy.scrollTo(target.id, anchor: .center)
            }
        }
    }

    private func ancestry(in entries: [SitemapEntry]) -> [SitemapEntry]? {
        // Deepest match wins: a chapter and its first section often start on the same page.
        for e in entries {
            if let sub = ancestry(in: e.children) { return [e] + sub }
            if isCurrent(e) { return [e] }
        }
        return nil
    }
}

private struct FlatEntries<R: ReaderModel>: View {
    @ObservedObject var reader: R
    let rows: [(entry: SitemapEntry, depth: Int)]
    let palette: ChromePalette

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(rows, id: \.entry.id) { row in
                    EntryRow(
                        entry: row.entry, depth: row.depth, palette: palette,
                        isCurrent: row.entry.local.map {
                            CHMPath.stripFragment($0).caseInsensitiveCompare(reader.currentPage) == .orderedSame
                        } ?? false,
                        isExpanded: nil, onToggle: {}, reader: reader)
                }
            }
            .padding(8)
        }
        .overlay {
            if rows.isEmpty {
                Text("沒有符合的項目").font(.callout).foregroundStyle(palette.secondary)
            }
        }
    }
}

private struct EntryRow<R: ReaderModel>: View {
    let entry: SitemapEntry
    let depth: Int
    let palette: ChromePalette
    let isCurrent: Bool
    let isExpanded: Bool?
    let onToggle: () -> Void
    let reader: R
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Group {
                if let isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onToggle)
                } else {
                    Color.clear.frame(width: 14, height: 1)
                }
            }
            Text(entry.name)
                .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                .lineSpacing(3)
                .foregroundStyle(isCurrent ? palette.accent : (entry.local == nil ? palette.secondary : palette.text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(depth) * 14 + 4)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? palette.accent.opacity(0.14) : (hovering ? palette.hover : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let local = entry.local { reader.open(local) } else { onToggle() }
        }
        .contextMenu {
            if let local = entry.local {
                Button("在另一側開啟") { reader.openBeside?(local) }
                Button("在新分頁開啟") { reader.openInNewTab?(local) }
            }
        }
    }
}
