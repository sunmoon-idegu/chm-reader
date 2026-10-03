import CHMKit
import SwiftUI

/// Find-in-book for one tab: the query, every match in book order, and which one is shown.
/// Searches the active pane's book; ⌘F opens the bar, ⌘G / ⇧⌘G (or ↩ / ⇧↩) step through matches.
@MainActor
final class FindSession: ObservableObject {
    @Published private(set) var isShown = false
    @Published var query = "" {
        didSet { if query != oldValue { search() } }
    }
    @Published private(set) var hits: [FullTextIndex.Hit] = []
    @Published private(set) var current: Int?
    @Published private(set) var searching = false
    /// Bumped to put the cursor in the field (⌘F while the bar is already open).
    @Published private(set) var focusRequest = 0

    weak var workspace: Workspace?
    private var task: Task<Void, Never>?

    func show() {
        isShown = true
        focusRequest += 1
    }

    func close() {
        isShown = false
        task?.cancel()
        searching = false
    }

    func next() { step(1) }
    func previous() { step(-1) }

    /// Searches again, e.g. after switching panes.
    func refresh() {
        guard isShown else { return }
        search()
    }

    private func step(_ delta: Int) {
        if !isShown { show() }
        guard !hits.isEmpty else { return }
        let index = current.map { ($0 + delta + hits.count) % hits.count } ?? (delta > 0 ? 0 : hits.count - 1)
        go(to: index)
    }

    private func go(to index: Int) {
        guard let model = workspace?.model, hits.indices.contains(index) else { return }
        current = index
        model.openSearchHit(hits[index], query: query)
    }

    private func search() {
        task?.cancel()
        hits = []
        current = nil
        let query = self.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let model = workspace?.model else {
            searching = false
            return
        }
        searching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = await model.searchText(query)
            guard !Task.isCancelled, let self else { return }
            self.searching = false
            self.hits = results.flatMap(\.hits)
            if let start = Self.firstHit(in: self.hits, from: model.currentPage) { self.go(to: start) }
        }
    }

    /// The first match on the current page, else the first after it (PDF page numbers), else the first.
    private static func firstHit(in hits: [FullTextIndex.Hit], from page: String) -> Int? {
        guard !hits.isEmpty else { return nil }
        if let here = hits.firstIndex(where: { $0.pageID.caseInsensitiveCompare(page) == .orderedSame }) { return here }
        if let now = PDFReaderController.pageIndex(of: page),
           let after = hits.firstIndex(where: { (PDFReaderController.pageIndex(of: $0.pageID) ?? -1) > now }) {
            return after
        }
        return 0
    }
}

/// Floating bar at the top of the page area.
struct FindBar: View {
    @ObservedObject var find: FindSession
    private var prefs = ReadingPrefs()
    @FocusState private var focused: Bool

    init(find: FindSession) { self.find = find }

    var body: some View {
        let palette = ChromePalette(prefs.style)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondary)
            TextField("搜尋內文", text: $find.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .frame(width: 220)
                .focused($focused)
                .onSubmit { find.next() }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    find.previous()
                    return .handled
                }
                .onExitCommand { find.close() }

            status(palette)
                .frame(minWidth: 64, alignment: .trailing)

            Rectangle().fill(palette.separator).frame(width: 1, height: 18)

            HStack(spacing: 2) {
                stepButton("chevron.up", help: "上一個 (⇧⌘G)", palette: palette) { find.previous() }
                stepButton("chevron.down", help: "下一個 (⌘G)", palette: palette) { find.next() }
            }
            .disabled(find.hits.isEmpty)

            Button { find.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondary)
            .help("關閉 (Esc)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.separator))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .environment(\.colorScheme, palette.colorScheme)
        .onChange(of: find.focusRequest, initial: true) { _, _ in
            DispatchQueue.main.async { focused = true }
        }
    }

    @ViewBuilder
    private func status(_ palette: ChromePalette) -> some View {
        Group {
            if find.searching {
                ProgressView().controlSize(.small)
            } else if find.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("")
            } else if find.hits.isEmpty {
                Text("沒有結果").foregroundStyle(.red.opacity(0.8))
            } else {
                Text("\((find.current ?? 0) + 1) / \(find.hits.count)").foregroundStyle(palette.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
    }

    private func stepButton(_ symbol: String, help: String, palette: ChromePalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(find.hits.isEmpty ? palette.secondary.opacity(0.5) : palette.text)
        .help(help)
    }
}
