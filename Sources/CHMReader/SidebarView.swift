import CHMKit
import SwiftUI

/// Left panel: the book's table of contents (plus its keyword index when the book has one).
struct SidebarView<R: ReaderModel>: View {
    @ObservedObject var reader: R
    private var prefs = ReadingPrefs()
    @State private var showIndex = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init(reader: R) { self.reader = reader }

    var body: some View {
        let palette = ChromePalette(prefs.style)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if !reader.keywordIndex.isEmpty {
                    Picker("", selection: $showIndex) {
                        Text("目錄").tag(false)
                        Text("索引").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                SearchField(text: $query, prompt: showIndex ? "搜尋索引" : "搜尋目錄與內文", palette: palette)
                    .focused($searchFocused)
                    .onExitCommand { query = ""; searchFocused = false }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle().fill(palette.separator).frame(height: 1)

            if showIndex {
                FlatEntries(reader: reader, rows: filtered(reader.keywordIndex), palette: palette)
            } else if query.isEmpty {
                TOCTree(reader: reader, palette: palette)
            } else {
                SearchResults(reader: reader, query: query, titleRows: filtered(reader.toc), palette: palette)
            }
        }
        .background(palette.background)
        .environment(\.colorScheme, palette.colorScheme)
        .onChange(of: reader.searchRequest) { _, _ in
            showIndex = false
            // Let the sidebar finish sliding in before taking focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
        }
    }

    private func filtered(_ entries: [SitemapEntry]) -> [(entry: SitemapEntry, depth: Int)] {
        let all = entries.flatMap { $0.flattened() }
        guard !query.isEmpty else { return all }
        return all.filter { $0.entry.name.localizedCaseInsensitiveContains(query) }.map { ($0.entry, 0) }
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

/// Search results: matching contents titles, then full-text matches grouped by page with snippets.
private struct SearchResults<R: ReaderModel>: View {
    @ObservedObject var reader: R
    let query: String
    let titleRows: [(entry: SitemapEntry, depth: Int)]
    let palette: ChromePalette
    @State private var results: [FullTextIndex.PageResult]?
    @State private var showAllTitles = false
    @State private var activeHit: String?
    @State private var expandedPages: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if !titleRows.isEmpty {
                    header("目錄", detail: "\(titleRows.count) 項")
                    ForEach(titleRows.prefix(showAllTitles ? titleRows.count : 5), id: \.entry.id) { row in
                        EntryRow(entry: row.entry, depth: 0, palette: palette, isCurrent: false,
                                 isExpanded: nil, onToggle: {}, reader: reader)
                    }
                    if titleRows.count > 5 && !showAllTitles {
                        Button("顯示全部 \(titleRows.count) 項") { showAllTitles = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.accent)
                            .padding(.leading, 22)
                            .padding(.vertical, 4)
                    }
                }

                header("內文", detail: summary)
                if let results {
                    if results.isEmpty {
                        Text("內文中沒有「\(query)」")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    ForEach(results) { page in
                        pageResult(page)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("搜尋中…（第一次搜尋需要建立索引）")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .padding(8)
        }
        .task(id: query) {
            results = nil
            expandedPages = []
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await reader.searchText(query)
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    private var summary: String {
        guard let results else { return "" }
        let total = results.map(\.totalHits).reduce(0, +)
        return total == 0 ? "" : "\(total) 處 · \(results.count)\(results.count >= 200 ? "+" : "") 頁"
    }

    private func header(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Spacer()
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func pageResult(_ page: FullTextIndex.PageResult) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(page.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(page.totalHits)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)

            let expanded = expandedPages.contains(page.id)
            ForEach(page.hits.prefix(expanded ? page.hits.count : 3)) { hit in
                SnippetRow(hit: hit, palette: palette, isActive: activeHit == hit.id) {
                    activeHit = hit.id
                    reader.openSearchHit(hit, query: query)
                }
            }
            if !expanded && page.totalHits > 3 {
                Button("顯示本頁其餘 \(page.totalHits - 3) 處") { expandedPages.insert(page.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.accent)
                    .padding(.leading, 12)
                    .padding(.vertical, 3)
            } else if expanded && page.totalHits > page.hits.count {
                Text("只列出前 \(page.hits.count) 處")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .padding(.leading, 12)
                    .padding(.vertical, 3)
            }
        }
    }
}

private struct SnippetRow: View {
    let hit: FullTextIndex.Hit
    let palette: ChromePalette
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(snippet)
            .font(.system(size: 12.5))
            .lineSpacing(3)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? palette.accent.opacity(0.14) : (hovering ? palette.hover : .clear)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }

    private var snippet: AttributedString {
        var before = AttributedString("…" + hit.before)
        before.foregroundColor = palette.secondary
        var match = AttributedString(hit.match)
        match.foregroundColor = palette.text
        match.font = .system(size: 12.5, weight: .bold)
        match.backgroundColor = Color(red: 1, green: 0.84, blue: 0.04).opacity(0.45)
        var after = AttributedString(hit.after + "…")
        after.foregroundColor = palette.secondary
        return before + match + after
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
