import CHMKit
import SwiftData
import SwiftUI
import WebKit

struct BookView: View {
    @StateObject private var reader: ReaderController
    private var prefs = ReadingPrefs()
    @State private var showTypography = false
    @AppStorage("reader.showSidebar") private var showSidebar = true
    @State private var showSizeToast = false
    @State private var toastTask: Task<Void, Never>?

    @Environment(\.openWindow) private var openWindow

    init(book: CHMBook, initialPage: String?) {
        _reader = StateObject(wrappedValue: ReaderController(
            book: book, initialPage: initialPage, modelContext: AnnotationStore.container.mainContext))
    }

    var body: some View {
        ReaderSplitView(reader: reader, showLeft: showSidebar, showRight: reader.showNotePanel)
            .overlay(alignment: .top) {
                if showSizeToast {
                    Text("字級 \(Int(prefs.fontSize)) pt")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 14)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        .navigationTitle(reader.pageTitle.isEmpty ? reader.book.title : reader.pageTitle)
        .navigationSubtitle(reader.pageTitle.isEmpty ? "" : reader.book.title)
        .toolbar { toolbar }
        .focusedSceneObject(reader)
        .onAppear {
            reader.openInNewTab = { [book = reader.book, openWindow, weak webView = reader.webView] page in
                TabOpener.openTab(BookTarget(url: book.url, page: page), from: webView?.window, using: openWindow)
            }
            reader.start(style: prefs.style)
        }
        .onChange(of: prefs.style) { _, style in reader.apply(style: style) }
        .onChange(of: prefs.fontSize) { _, _ in
            guard !showTypography else { return }
            withAnimation { showSizeToast = true }
            toastTask?.cancel()
            toastTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                withAnimation { showSizeToast = false }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { showSidebar.toggle() } label: { Label("目錄", systemImage: "sidebar.left") }
                .help(showSidebar ? "隱藏目錄 (⌃⌘S)" : "顯示目錄 (⌃⌘S)")
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button { reader.goHome() } label: { Label("首頁", systemImage: "house") }
                .help("回到本書首頁")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { reader.highlightSelection() } label: {
                Label("螢光標記", systemImage: "highlighter")
            }
            .disabled(!reader.hasSelection)
            .help(reader.hasSelection ? "螢光標記選取的文字 (⌥⌘H)；點標記可寫筆記、改顏色" : "請先選取文字，再螢光標記")

            ControlGroup {
                Button { prefs.fontSize = max(prefs.fontSize - 1, 12) } label: {
                    Label("縮小字級", systemImage: "textformat.size.smaller")
                }
                .disabled(prefs.fontSize <= 12)
                .help("縮小字級 (⌘-)")
                Button { prefs.fontSize = min(prefs.fontSize + 1, 40) } label: {
                    Label("放大字級", systemImage: "textformat.size.larger")
                }
                .disabled(prefs.fontSize >= 40)
                .help("放大字級 (⌘=)")
            }

            Button { showTypography.toggle() } label: { Label("版面", systemImage: "slider.horizontal.3") }
                .help("字型、字級、行距、背景")
                .popover(isPresented: $showTypography, arrowEdge: .bottom) {
                    TypographyPanel().frame(width: 380).padding(20)
                }

            Button { reader.showNotePanel.toggle() } label: { Label("筆記", systemImage: "sidebar.right") }
                .help(reader.showNotePanel ? "隱藏筆記 (⌃⌘N)" : "顯示筆記 (⌃⌘N)")
                .keyboardShortcut("n", modifiers: [.command, .control])
        }
    }
}
