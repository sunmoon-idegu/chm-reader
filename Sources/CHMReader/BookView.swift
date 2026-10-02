import CHMKit
import SwiftData
import SwiftUI
import WebKit

struct BookView<R: ReaderModel>: View {
    @StateObject private var reader: R
    private var prefs = ReadingPrefs()
    @State private var showTypography = false
    @AppStorage("reader.showSidebar") private var showSidebar = true
    @State private var showSizeToast = false
    @State private var toastTask: Task<Void, Never>?

    @Environment(\.openWindow) private var openWindow

    init(reader: @autoclosure @escaping () -> R) {
        _reader = StateObject(wrappedValue: reader())
    }

    var body: some View {
        ReaderSplitView(reader: reader, showLeft: showSidebar, showRight: reader.showNotePanel)
            .overlay(alignment: .top) {
                if showSizeToast {
                    Text(reader.zoomLabel)
                        .font(.callout.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 14)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        .navigationTitle(reader.pageTitle.isEmpty ? reader.bookTitle : reader.pageTitle)
        .navigationSubtitle(reader.pageTitle.isEmpty ? "" : reader.bookTitle)
        .toolbar { toolbar }
        .focusedSceneObject(reader)
        .onAppear {
            reader.openInNewTab = { [url = reader.bookURL, openWindow, weak view = reader.contentView] page in
                TabOpener.openTab(BookTarget(url: url, page: page), from: view?.window, using: openWindow)
            }
            reader.start(style: prefs.style)
        }
        .onChange(of: prefs.style) { _, style in reader.apply(style: style) }
        .onChange(of: reader.zoomLabel) { _, _ in
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
                Button { reader.zoom(-1) } label: {
                    Label(reader.isReflowable ? "縮小字級" : "縮小", systemImage: reader.isReflowable ? "textformat.size.smaller" : "minus.magnifyingglass")
                }
                .help(reader.isReflowable ? "縮小字級 (⌘-)" : "縮小 (⌘-)")
                Button { reader.zoom(1) } label: {
                    Label(reader.isReflowable ? "放大字級" : "放大", systemImage: reader.isReflowable ? "textformat.size.larger" : "plus.magnifyingglass")
                }
                .help(reader.isReflowable ? "放大字級 (⌘=)" : "放大 (⌘=)")
            }

            Button { showTypography.toggle() } label: { Label("版面", systemImage: "slider.horizontal.3") }
                .help(reader.isReflowable ? "字型、字級、行距、背景" : "背景")
                .popover(isPresented: $showTypography, arrowEdge: .bottom) {
                    TypographyPanel(themeOnly: !reader.isReflowable).frame(width: 380).padding(20)
                }

            Button { reader.showNotePanel.toggle() } label: { Label("筆記", systemImage: "sidebar.right") }
                .help(reader.showNotePanel ? "隱藏筆記 (⌃⌘N)" : "顯示筆記 (⌃⌘N)")
                .keyboardShortcut("n", modifiers: [.command, .control])
        }
    }
}
