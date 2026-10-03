import CHMKit
import SwiftData
import SwiftUI

/// One tab's content: the workspace (one or two panes) with the toolbar acting on the active pane.
struct BookView: View {
    @StateObject private var workspace: Workspace
    private var prefs = ReadingPrefs()
    @State private var showTypography = false
    @AppStorage("reader.showSidebar") private var showSidebar = true
    @State private var showSizeToast = false
    @State private var toastTask: Task<Void, Never>?

    @Environment(\.openWindow) private var openWindow

    init(reader: @autoclosure @escaping () -> AnyReader) {
        _workspace = StateObject(wrappedValue: Workspace(primary: reader()))
    }

    private var model: any ReaderModel { workspace.model }
    private var layoutRevision: String {
        let panes = workspace.readers.map { "\($0.id.hashValue)" }.joined(separator: ",")
        return "\(panes)|\(workspace.activeIsSecondary)|\(String(describing: workspace.loadingPane))|\(model.bookTitle)"
    }

    var body: some View {
        ReaderSplitView(workspace: workspace, showLeft: showSidebar, showRight: model.showNotePanel, revision: layoutRevision)
            .overlay(alignment: .top) {
                if showSizeToast {
                    Text(model.zoomLabel)
                        .font(.callout.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 14)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle(model.bookTitle)
            .navigationSubtitle(model.pageTitle)
            .toolbar { toolbar }
            .focusedSceneObject(workspace)
            .alert("無法開啟", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
                Button("好") {}
            } message: {
                Text(workspace.error ?? "")
            }
            .onAppear {
                workspace.openInNewTab = { [openWindow, weak workspace] url, page in
                    TabOpener.openTab(BookTarget(url: url, page: page), from: workspace?.window, using: openWindow)
                }
                ReaderRegistry.register(workspace)
                workspace.start(style: prefs.style)
            }
            .onChange(of: prefs.style) { _, style in workspace.apply(style: style) }
            .onChange(of: workspace.searchRequest) { _, _ in showSidebar = true }
            // Only zooms the user asked for; a PDF settling its auto-fit scale shouldn't flash the toast.
            .onChange(of: workspace.zoomTick) { _, _ in
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
            Button { model.goHome() } label: { Label("首頁", systemImage: "house") }
                .help("回到本書首頁")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.highlightSelection() } label: {
                Label("螢光標記", systemImage: "highlighter")
            }
            .disabled(!model.hasSelection)
            .help(model.hasSelection ? "螢光標記選取的文字 (⌥⌘H)；點標記可寫筆記、改顏色" : "請先選取文字，再螢光標記")

            ControlGroup {
                Button { workspace.zoom(-1) } label: {
                    Label(model.isReflowable ? "縮小字級" : "縮小", systemImage: model.isReflowable ? "textformat.size.smaller" : "minus.magnifyingglass")
                }
                .help(model.isReflowable ? "縮小字級 (⌘-)" : "縮小 (⌘-)")
                Button { workspace.zoom(1) } label: {
                    Label(model.isReflowable ? "放大字級" : "放大", systemImage: model.isReflowable ? "textformat.size.larger" : "plus.magnifyingglass")
                }
                .help(model.isReflowable ? "放大字級 (⌘=)" : "放大 (⌘=)")
            }

            Button { showTypography.toggle() } label: { Label("版面", systemImage: "slider.horizontal.3") }
                .help(model.isReflowable ? "字型、字級、行距、背景" : "背景")
                .popover(isPresented: $showTypography, arrowEdge: .bottom) {
                    TypographyPanel(themeOnly: !model.isReflowable).frame(width: 380).padding(20)
                }

            Button { workspace.toggleSplit() } label: {
                Label("分割畫面", systemImage: workspace.isSplit ? "rectangle" : "rectangle.split.2x1")
            }
            .help(workspace.isSplit ? "關閉分割畫面 (⌘\\)" : "分割畫面：並排閱讀 (⌘\\)")

            Button { var m = model; m.showNotePanel.toggle() } label: { Label("筆記", systemImage: "sidebar.right") }
                .help(model.showNotePanel ? "隱藏筆記 (⌃⌘N)" : "顯示筆記 (⌃⌘N)")
                .keyboardShortcut("n", modifiers: [.command, .control])
        }
    }
}
