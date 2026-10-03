import SwiftData
import SwiftUI

/// Right panel: note cards for this page (or the whole book). Click a card to edit it in place.
struct NotesPanel<R: ReaderModel>: View {
    @ObservedObject var reader: R
    private var prefs = ReadingPrefs()
    @AppStorage("notes.wholeBook") private var wholeBook = false
    @Query private var all: [Annotation]

    init(reader: R) {
        self.reader = reader
        let key = reader.bookKey
        _all = Query(
            filter: #Predicate<Annotation> { $0.bookKey == key },
            sort: [SortDescriptor(\.pagePath), SortDescriptor(\.start)])
    }

    private var shown: [Annotation] {
        wholeBook ? all : all.filter { $0.pagePath.caseInsensitiveCompare(reader.currentPage) == .orderedSame }
    }

    var body: some View {
        let palette = ChromePalette(prefs.style)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.separator).frame(height: 1)

            if shown.isEmpty {
                emptyState(palette)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(groups, id: \.path) { group in
                                if wholeBook {
                                    Text(group.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.secondary)
                                        .padding(.top, 6)
                                        .padding(.horizontal, 4)
                                }
                                ForEach(group.items) { a in
                                    NoteCard(
                                        annotation: a, reader: reader, palette: palette,
                                        isSelected: reader.selectedAnnotation?.id == a.id)
                                    .id(a.id)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: reader.selectedAnnotation?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }

            if !all.isEmpty {
                Rectangle().fill(palette.separator).frame(height: 1)
                Text("全書共 \(all.count) 則")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .background(palette.background)
        .environment(\.colorScheme, palette.colorScheme)
    }

    private func header(_ palette: ChromePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("筆記")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("\(shown.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(palette.accent.opacity(0.14), in: Capsule())
                Spacer()
                Button { reader.showNotePanel = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.secondary)
                .help("關閉筆記 (⌃⌘N)")
            }
            Picker("", selection: $wholeBook) {
                Text("本頁").tag(false)
                Text("全書").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func emptyState(_ palette: ChromePalette) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "highlighter")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.secondary)
            Text(wholeBook ? "這本書還沒有筆記" : "這一頁還沒有筆記")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.text)
            Text("選取文字後，從浮出的工具列螢光標記或加筆記；\n或按便利貼（⌥⌘N）在頁面任一處加筆記。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(palette.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groups: [(path: String, title: String, items: [Annotation])] {
        var order: [String] = []
        var byPage: [String: [Annotation]] = [:]
        for a in shown {
            if byPage[a.pagePath] == nil { order.append(a.pagePath) }
            byPage[a.pagePath, default: []].append(a)
        }
        return order.map { path in
            let items = byPage[path]!
            let title = items.first?.pageTitle ?? ""
            return (path, title.isEmpty ? path : title, items)
        }
    }
}

private struct NoteCard<R: ReaderModel>: View {
    @Bindable var annotation: Annotation
    let reader: R
    let palette: ChromePalette
    let isSelected: Bool
    @State private var hovering = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(annotation.color.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                if annotation.isSticky {
                    Label("便利貼", systemImage: "note.text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                } else {
                    Text(annotation.exact)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(isSelected ? palette.text : palette.secondary)
                        .lineLimit(isSelected ? 10 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isSelected {
                    editor
                } else if !annotation.note.isEmpty {
                    Text(annotation.note)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(palette.text)
                        .lineLimit(4)
                }

                Text(annotation.updatedAt, format: .dateTime.month().day().hour().minute())
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary.opacity(0.8))
            }
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? palette.accent.opacity(0.7) : (hovering ? palette.separator.opacity(2) : palette.separator),
                        lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 6 : 2, y: 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !isSelected else { return }
            withAnimation(.easeOut(duration: 0.18)) { reader.selectedAnnotation = annotation }
            reader.reveal(annotation)
        }
        .contextMenu {
            Button("在另一側開啟") { reader.openBeside?(annotation.pagePath) }
            Button("在新分頁開啟") { reader.openInNewTab?(annotation.pagePath) }
            Button("刪除", role: .destructive) { reader.deleteWithUndo(annotation) }
        }
        // Only a note just created gets the cursor; clicking an existing one keeps focus on the page, so ⌫ deletes it.
        .onChange(of: isSelected, initial: true) { _, selected in
            guard selected, reader.noteToFocus == annotation.id else { return }
            var reader = reader
            reader.noteToFocus = nil
            DispatchQueue.main.async { editorFocused = true }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $annotation.note)
                .font(.system(size: 13))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(minHeight: 80, maxHeight: 220)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if annotation.note.isEmpty {
                        Text("寫下你的筆記…")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: annotation.note) { _, _ in reader.refreshMark(annotation) }

            HStack(spacing: 8) {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        annotation.color = color
                        reader.refreshMark(annotation)
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(palette.text.opacity(0.8), lineWidth: annotation.color == color ? 1.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(color.label)
                }
                Spacer()
                Button { reader.deleteWithUndo(annotation) } label: {
                    Label("刪除", systemImage: "trash").font(.system(size: 12)).lineLimit(1).fixedSize()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.85))
                .help("刪除 (⌫)；可用 ⌘Z 復原")
                Button("完成") {
                    withAnimation(.easeOut(duration: 0.18)) { reader.selectedAnnotation = nil }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
            }
        }
    }
}
