<p align="center">
  <img src="docs/icon.png" width="128" alt="CHM 閱讀器圖示">
</p>

<h1 align="center">CHM 閱讀器</h1>

<p align="center">
  專為繁體中文設計的 macOS CHM 電子書閱讀器：正確顯示 Big5 舊檔、螢光標記、隨手筆記、舒適排版。<br>
  A macOS CHM e-book reader built for Traditional Chinese, with highlights, notes and comfortable typography.
</p>

<p align="center">
  <a href="https://sunmoon-idegu.github.io/chm-reader/">網站 Website</a> ·
  <a href="https://sunmoon-idegu.github.io/chm-reader/privacy.html">隱私權政策 Privacy</a> ·
  <a href="https://github.com/sunmoon-idegu/chm-reader/issues">回報問題 Issues</a>
</p>

![閱讀與筆記](app-store-asset/screenshots/1-閱讀與筆記-2560x1600.png)

## 功能

- **正確顯示繁體中文**：依書中語系自動辨識 Big5 / CP950、HKSCS、GB18030 等舊編碼，不再出現亂碼。
- **目錄側邊欄**：依章節瀏覽、搜尋，自動標示目前位置；沒有目錄檔的書會依頁面標題自動整理。
- **螢光標記與筆記**：選字按 ⌥⌘H 標記，點螢光文字即可在右側筆記欄寫筆記，自動儲存；可看本頁或全書筆記，並匯出 Markdown。
- **舒適排版**：蘋方、宋體、楷體；字級（⌘= / ⌘-）、行高、段距、版面寬度；白、米黃、護眼綠、夜間或自訂背景。
- **分頁閱讀**：⌘T 或右鍵「在新分頁開啟」，同時對照多個段落。
- **PDF**：同樣的目錄、螢光標記、筆記與分頁，目錄取自 PDF 書籤；可縮放，原始檔案不會被修改。
- **隱私**：檔案與筆記只存在你的 Mac，不收集任何資料。

## Features

- Reads legacy Chinese CHMs correctly: Big5/CP950, HKSCS and GB18030 are detected from the book's language ID and page charset.
- Table-of-contents sidebar with search; books without a `.hhc` get a TOC built from their internal topic tables.
- Highlights (⌥⌘H) with a notes panel: per-page or whole-book view, autosave, Markdown export.
- Typography controls: font, size, line height, paragraph spacing, page width, and themes including night mode.
- PDF support: outline sidebar, highlights and notes, zoom; the PDF file itself is never modified.
- Native macOS tabs, sandboxed, no data collection.

## 系統需求 Requirements

macOS 14 Sonoma 或以上 · macOS 14 Sonoma or later

## 從原始碼建置 Building from source

需要 Xcode 26 與 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
swift test                   # 單元測試 unit tests
scripts/build-app.sh         # → build/CHM Reader.app
open "build/CHM Reader.app"
```

`CHMReader.xcodeproj` 由 `project.yml` 產生（`xcodegen generate`），不納入版本控制。
簽章使用的開發團隊設定在 `project.yml`，自行建置時請改成你自己的 Team ID。

The Xcode project is generated from `project.yml`; set `DEVELOPMENT_TEAM` to your own team to build.

## 專案結構 Project layout

| 路徑 Path | 內容 Contents |
|---|---|
| `Sources/CCHMLib` | CHMLib 0.40（C，未修改），解壓縮 CHM / LZX |
| `Sources/CHMKit` | CHM 讀取、目錄解析、文字編碼偵測 |
| `Sources/CHMReader` | SwiftUI + AppKit App 本體（WKWebView 閱讀、筆記、排版） |
| `Tests/CHMKitTests` | 單元測試 |
| `docs/` | GitHub Pages 網站（支援頁、隱私權政策） |
| `dev-docs/` | 技術選型與上架說明 |
| `app-store-asset/` | App Store 文案、截圖、圖示 |

## 授權 License

本專案原始碼採 [MIT 授權](LICENSE)，第三方程式與品牌說明見 [NOTICE](NOTICE)。App 名稱「CHM 閱讀器」、圖示與 App Store 素材不在授權範圍內，請勿用於其他發佈的 App。
This project's source code is under the [MIT License](LICENSE). The app name, icon and App Store assets are not licensed for reuse in other distributed apps.

本 App 使用 [CHMLib](https://github.com/jedwing/CHMLib)（© Jed Wing），採 GNU LGPL 2.1 授權，
以未經修改、可替換的動態函式庫 `CCHMLib.framework` 隨附；授權全文見 `Sources/CCHMLib/COPYING`。

This app uses [CHMLib](https://github.com/jedwing/CHMLib) © Jed Wing under the GNU LGPL 2.1, shipped unmodified
as the replaceable dynamic library `CCHMLib.framework`. See `Sources/CCHMLib/COPYING`.

© 2026 Yuming Lu
