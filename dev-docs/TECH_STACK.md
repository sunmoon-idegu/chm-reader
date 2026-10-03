# CHM Reader for macOS — Tech Stack

## Goals

1. Read Traditional Chinese CHM files correctly (Big5 / CP950 / HKSCS / UTF-8).
2. Highlight text and attach notes while reading.
3. Adjust font, font size, line height, paragraph spacing, and background color.
4. Index page: table of contents (目錄), keyword index (索引), and a notes list (筆記).

## Stack at a glance

| Layer | Choice | Why |
|---|---|---|
| Language | Swift 6 toolchain (Swift 5 language mode) | Native, first-class on macOS |
| UI | SwiftUI + AppKit (`NSViewRepresentable`) | SwiftUI for layout; AppKit where WebKit integration needs it |
| Minimum OS | macOS 14 Sonoma | Required by SwiftData; current dev machine runs macOS 26 |
| Build | XcodeGen (`project.yml` → `CHMReader.xcodeproj`) for the app; SwiftPM (`Package.swift`) for `swift test` | Xcode project needed for signing, sandbox and App Store archives; generated so it never needs hand-editing |
| CHM decoding | [CHMLib 0.40](https://github.com/jedwing/CHMLib) (C), vendored as SwiftPM target `CCHMLib` | The de facto CHM/LZX decoder; tiny API (`chm_open`, `chm_resolve_object`, `chm_retrieve_object`, `chm_enumerate`) |
| CHM model | `CHMKit` Swift target | Swift wrapper, `#SYSTEM` metadata, `.hhc`/`.hhk` parsing, text-encoding detection |
| Rendering | `WKWebView` + custom `WKURLSchemeHandler` (`chm://book/...`) | Pages are HTML; serving straight from the archive keeps relative links, images and CSS working with no temp extraction |
| Typography | CSS injected via `WKUserScript`, updated live via JS | Font size / line height / paragraph spacing / colors are just CSS |
| Highlights | Injected JS: W3C-style text-quote anchors (`exact` + `prefix` + `suffix` + offsets), wrapped in `<mark>` | Survives minor DOM differences better than XPath |
| Persistence | SwiftData (store in `~/Library/Application Support/CHMReader/`) | No third-party dependency; fine for a single-user annotation store |
| Preferences | `@AppStorage` (UserDefaults) | Reading settings, recent books, last-read page |
| Tests | XCTest (`CHMKitTests`) | Parser, path and encoding logic |

## Key decisions and details

### CHM parsing (CHMLib)
- Compiled with `CHM_MT` (thread-safe) and `CHM_USE_PREAD`. Swift wrapper also serializes access with a lock.
- **License: LGPL-2.1.** OK for personal use. If the app is ever distributed, either build CHMLib as a
  separate dynamic library/framework or ship object files so users can relink — or replace it with a
  clean-room Swift LZX decoder.
- Book metadata comes from the `/#SYSTEM` file: TOC file (`.hhc`), index file (`.hhk`), default topic,
  title, and **LCID** (language ID), which tells us the book's legacy code page.
- Fallbacks when `#SYSTEM` is incomplete: scan the archive for the first `*.hhc` / `*.hhk`, then `index.htm(l)`.
- Some books (e.g. `瑜伽師地論.chm`) have **no `.hhc` at all**. The TOC then comes from the binary
  `#TOPICS` + `#URLTBL` + `#URLSTR` + `#STRINGS` tables, which list every page with its title in compile order.
  In such books the default topic (Home button) is usually the hand-made index page.

### Traditional Chinese text encoding
Most Chinese CHMs predate UTF-8. Decoding order for each HTML page / sitemap:
1. Byte-order mark (UTF-8 / UTF-16).
2. `<meta charset>` in the first 4 KB.
3. Strict UTF-8.
4. Book code page from LCID: `0x0404` zh-TW / `0x1404` zh-MO → CP950, Big5-HKSCS, Big5;
   `0x0C04` zh-HK → Big5-HKSCS first; `0x0804` zh-CN → GB18030.
5. Lossy double-byte decode (bad characters → `�`) so a page never fails to open.

HTML is transcoded to UTF-8 before it reaches WebKit and served with `charset=utf-8`, so WebKit never
has to guess. Pages get `lang="zh-Hant"` so the system picks Traditional Chinese glyphs.

### Reader & typography
- Fonts: 蘋方 (PingFang TC), 宋體 (Songti TC), 楷體 (Kaiti TC), or the book's original font.
- Themes: 白 / 米黃 (sepia) / 護眼綠 / 夜間, plus a custom background color.
- Font size, line height, paragraph spacing, page width — all live-updating CSS.
- Caveat: many old CHMs use `<br><br>` instead of `<p>`; paragraph spacing applies to real `<p>`/`<div>` blocks only.

### PDF (feat/pdf)
- `PDFReaderController` (PDFKit `PDFView`) implements the same `ReaderModel` protocol as the CHM reader, so the
  sidebar, notes panel, tabs and toolbar are shared (`BookView<R: ReaderModel>`).
- Contents come from the PDF outline; PDFs without one get a page list. Page ids are `/page/<n>` (`#<y>` for a position).
- Highlights are anchored by page + UTF-16 offsets into `PDFPage.string`, with the quoted text as fallback, and drawn
  as in-memory `PDFAnnotation` highlights tagged `chmreader:<id>`. The PDF file is never written.
- Fixed layout: font-size controls become zoom; the typography panel shows only background themes.
- Not yet: password-protected PDFs, highlights spanning pages (only the first page's part is kept).

### Sticky notes
- `Annotation.kind == "sticky"` (new SwiftData fields `kind`, `x`, `y` with defaults, so old stores migrate).
- Toolbar toggle / ⌥⌘N turns on placement; the next click places the note and opens its card. Esc cancels.
- CHM: the page script reads the click's caret offset (`caretRangeFromPoint`) and anchors the note there with
  prefix/suffix context; it renders as an inline icon, so it follows text reflow.
- PDF: a transparent `NotePlacementOverlay` over the `PDFView` catches the click (crosshair cursor); the note is a
  PDFKit `.text` annotation at that point in page coordinates, drawn in memory only.

### Full-text search (feat/search)
- `CHMKit.FullTextIndex`: in-memory index of every page's visible text, built once per book in the background
  (瑜伽師地論: 529 pages, 7.3 M characters, ~1.8 s), then case/width/diacritic-insensitive substring search (~0.2 s).
- CHM text comes from `HTMLText.plainText` over each archive page; PDF text from `PDFPage.string`.
- A hit is identified by page + occurrence number. CHM jumps via the page script's `chmReader.find(q, n)`, which
  selects the nth match in the rendered DOM; PDF selects `page.selection(for: range)`. The match stays selected,
  so it can be highlighted immediately.
- UI: `FindBar` floats at the top of the page area (⌘F or the toolbar magnifier). `FindSession` (one per tab, in
  `Workspace`) flattens all hits in book order, starts at the current page, and steps with ↩ / ⇧↩, ↑ ↓, ⌘G / ⇧⌘G;
  it re-searches when the active pane changes. PDF jumps leave ~150 pt above the match so the bar doesn't cover it.
  The sidebar field only filters 目錄 / 索引 titles.
- Sidebar tabs: 目錄, 索引 (CHM with `.hhk`), 縮覽圖 (PDF: `page.thumbnail`, cached, rendered lazily); the chosen
  tab is remembered (`sidebar.tab`).
- PDF selections are rebuilt from their text ranges on mouse-up (`textOnly`): dragging over a table gave a block
  selection with NaN geometry, which crashed the selection bar.

### Split view (feat/split)
- Each tab holds a `Workspace`: a primary reader and an optional secondary one (any CHM or PDF), plus which is active.
  `AnyReader` wraps the concrete reader types; the toolbar, menus, sidebar and notes panel follow the active pane.
- Layout: outer `NSSplitViewController` (sidebar | pages | notes); the pages area is a nested
  `NSSplitViewController` with one or two panes. Sidebar and notes containers keep one hosted view per reader,
  so search text and scroll survive switching panes. A local mouse-down monitor makes the clicked pane active.
- ⌘\ toggles the split; the new right pane first shows a chooser (recent files, open, drop) like a new tab's
  welcome screen. Each pane's header can open another file. Dividers keep a 1-pt line but a ~10-pt grab area
  (`WideDividerSplitViewController` widens the effective rect);
  「在另一側開啟」 in the contents and notes context menus opens a page in the other pane.

### Tabs
- Native macOS window tabs (`NSWindow.addTabbedWindow`); each tab is a SwiftUI window keyed by a `BookTarget`
  (book URL + page + unique id). Opened via ⌘T, sidebar right-click → 在新分頁開啟, or ⌘-click a link.
- Window restoration is disabled, so launch always starts at the welcome screen.

### Highlights & notes
- Select text → a floating `SelectionBar` (複製 / 螢光標記 / 加筆記) appears above it; also the right-click menu
  or ⌥⌘H. CHM reports the selection rect from the page script on mouse-up (and on scroll); PDF on `mouseUp`
  and clip-view bounds changes.
- ⌫ deletes the selected note (via the pane container's key monitor, skipped while a text view has focus);
  `deleteWithUndo` registers ⌘Z. Clicking elsewhere on the page deselects. Only newly created notes focus the editor.
- Sticky notes share one look (`StickyArt`: colored square, four lines): PDF draws it via `StickyNoteAnnotation`,
  CHM matches it in CSS, and the placing cursor is the same note (hot spot = its top-left corner).
- CHM swipe back/forward gestures are off (sideways scrolling shouldn't turn pages); there is no 首頁 button.
- Click a highlight to open it in the right-hand note panel: write the note (autosaves), change color, delete.

### Layout
- Three panes on AppKit `NSSplitViewController` (contents | page | note), hosted in SwiftUI via
  `NSViewControllerRepresentable`. Chosen over `NavigationSplitView` because macOS 26 draws that sidebar as a
  floating glass panel, and SwiftUI can't smoothly animate a `WKWebView`'s frame; `NSSplitViewItem.animator().isCollapsed` can.
- Each annotation stores: book key (SHA-256 of file size + first 64 KB, so moving/renaming the file keeps notes),
  page path, quote anchor, color, note, timestamps.
- Notes tab lists all annotations for the book; click to jump.

### Index page
- **目錄** — `.hhc` sitemap as an expandable outline.
- **索引** — `.hhk` keyword index, searchable. If a book has no `.hhk`, falls back to a searchable flat TOC.
- **筆記** — annotations for this book.
- Toolbar "Home" button opens the book's default topic.

## Project layout

```
chm-reader/
├── Package.swift
├── Sources/
│   ├── CCHMLib/          vendored CHMLib C sources (LGPL-2.1)
│   ├── CHMKit/           CHMFile, CHMBook, SitemapParser, TextDecoding
│   └── CHMReader/        SwiftUI app: windows, sidebar, reader, annotations, settings
├── Tests/CHMKitTests/
├── Support/Info.plist    bundle metadata + .chm document type
├── scripts/build-app.sh  builds "CHM Reader.app" into ./build
├── docs/                 website on GitHub Pages: support + privacy policy
└── dev-docs/             tech stack + App Store notes
```

## Build & run

```sh
swift test                  # unit tests
scripts/build-app.sh        # → build/CHM Reader.app (signed, sandboxed)
scripts/archive.sh          # App Store .pkg → build/export/ (see dev-docs/APP_STORE.md)
```

## Not now (possible later)
- Full-text search across a book (would index decoded page text, e.g. SQLite FTS5).
- Vertical text layout (`writing-mode: vertical-rl`) toggle.
- iCloud sync of annotations (SwiftData + CloudKit).
