# Publishing CHM 閱讀器 to the Mac App Store

## Already done in the project
- Xcode project generated from `project.yml` (XcodeGen), team `LV99JJMWBN`, automatic signing.
- App Sandbox: user-selected files (read-only), app-scoped bookmarks (最近閱讀), outgoing network
  (WebKit's web content process needs it even for local pages; the app makes no network requests itself).
- Hardened runtime, app icon, privacy manifest (no tracking, no data collected; UserDefaults reason CA92.1),
  `ITSAppUsesNonExemptEncryption = NO` (no export-compliance questions).
- CHMLib (LGPL-2.1) shipped unmodified as the replaceable dynamic library `CCHMLib.framework`;
  license text and source link in the About window (Credits.html) and `CHMLib-LICENSE.txt`.
- Notes from the unsandboxed builds migrate into the sandbox container on first launch.

## Build commands
```sh
scripts/build-app.sh          # signed, sandboxed app for local use → build/CHM Reader.app
scripts/archive.sh            # App Store archive + signed .pkg → build/export/
scripts/archive.sh --upload   # archive and upload to App Store Connect
```
## Releasing an update
1. In `project.yml`, raise `CURRENT_PROJECT_VERSION` by 1 (**every** upload — App Store Connect rejects
   a reused build number). Raise `MARKETING_VERSION` (e.g. 1.0.0 → 1.0.1) when the update ships to users.
2. Add a row to the upload history below.
3. `swift test`, then `scripts/build-app.sh` and try the app.
4. `scripts/archive.sh --upload`.
5. App Store Connect: new version → 此版本的新增內容 (release notes) → pick the build → 提交審查.
6. Commit `project.yml` + this file, tag `v<MARKETING_VERSION>`, push.

### Upload history
| Date | Version | Build | Notes |
|---|---|---|---|
| 2026-10-01 | 1.0.0 | 1 | First upload (sky-blue icon) |

## Steps only you can do (first release)
1. **Create the app record** — appstoreconnect.apple.com → 我的 App → ＋ → 新增 App
   - 平台 macOS · 名稱 `CHM 閱讀器` · 主要語言 繁體中文 · 套件 ID `com.yuming.chmreader` · SKU `chmreader-001`
2. **Upload**: `scripts/archive.sh --upload` (or open `build/CHMReader.xcarchive` in Xcode Organizer → Distribute).
3. **Fill in the listing** (text below), screenshots, privacy, price → 提交審查.

## Listing text (draft)

**副標題** (30 字內)：繁體中文 CHM 電子書閱讀與筆記

**推廣文字**：專為中文經典與講記設計的 CHM 閱讀器——螢光標記、隨手筆記、舒適排版。

**描述**：
CHM 閱讀器讓你在 Mac 上舒適地閱讀 CHM 電子書，特別適合繁體中文的經典、講記與參考書。

• 正確顯示繁體中文：自動辨識 Big5、香港增補字符集等舊編碼，不再出現亂碼
• 目錄側邊欄：依章節瀏覽、搜尋，並自動標示目前閱讀位置
• 螢光標記與筆記：選取文字即可標記，點標記就能在右側寫筆記；可依本頁或全書檢視，並匯出 Markdown
• 舒適排版：蘋方、宋體、楷體字型，自由調整字級、行高、段距、版面寬度
• 多種背景：白、米黃、護眼綠、夜間，或自訂顏色
• 分頁閱讀：同時開啟多個頁面，互相對照
• 記住上次閱讀位置，重新開啟就能接著讀
• 所有資料只存在你的 Mac，不收集任何個人資訊

**關鍵字** (100 字元內)：CHM,電子書,閱讀器,繁體中文,筆記,螢光筆,Big5,講記,佛經,ebook,reader,help

**類別**：書籍 (Books)　次要：參考 (Reference)

**版權**：© 2026 Yuming Lu

## App Privacy (App Store Connect → App 隱私權)
Answer **「不收集資料」 (Data Not Collected)**.

A **privacy policy URL is required**. Suggested text to host (GitHub Pages, Notion public page, etc.):

> CHM 閱讀器不收集、儲存或傳送任何個人資料。你開啟的檔案、螢光標記與筆記只儲存在你的 Mac 上，
> 不會上傳到任何伺服器。本 App 不含廣告、分析或追蹤工具。
> CHM Reader does not collect, store, or transmit any personal data. Files you open, highlights and notes
> are stored only on your Mac. The app contains no ads, analytics, or tracking.

## Screenshots
Required: at least one, 16:10, e.g. 2880×1800 or 1440×900. Show: a page with highlights + the notes panel;
the typography popover; the night theme.

## Review notes (App Review Information → 備註)
> 測試方式：開啟任何 .chm 檔（例如 Windows 說明檔）。選取文字後按工具列螢光筆或 ⌥⌘H 標記，
> 點螢光文字可在右側筆記欄寫筆記。The app needs no account or network access.
> Network client entitlement is required by WKWebView's web-content process; the app makes no requests.

Attach a sample .chm in the review notes if you can share one, so the reviewer doesn't have to find one.
