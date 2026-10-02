import CHMKit
import SwiftUI

/// Left panel: the book's table of contents (plus its keyword index when the book has one).
struct SidebarView<R: ReaderModel>: View {
    @ObservedObject var reader: R
    private var prefs = ReadingPrefs()
    @State private var showIndex = false
    @State private var query = ""

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

                SearchField(text: $query, prompt: showIndex ? "搜尋索引" : "搜尋目錄", palette: palette)
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
                FlatEntries(reader: reader, rows: filtered(reader.toc), palette: palette)
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
                Button("在新分頁開啟") { reader.openInNewTab?(local) }
            }
        }
    }
}
