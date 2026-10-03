# Publishing 閱讀器 - PDF & CHM to the Mac App Store

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
   - 平台 macOS · 名稱 `CHM 閱讀器`（1.1.0 起改名為「閱讀器 - PDF & CHM」）· 主要語言 繁體中文 · 套件 ID `com.yuming.chmreader` · SKU `chmreader-001`
2. **Upload**: `scripts/archive.sh --upload` (or open `build/CHMReader.xcarchive` in Xcode Organizer → Distribute).
3. **Fill in the listing** (text below), screenshots, privacy, price → 提交審查.

## Listing text
The current listing (name, subtitle, description, keywords, what's new, review notes) and screenshots live in
`app-store-asset/`; its README maps each file to its App Store Connect field.

## App Privacy (App Store Connect → App 隱私權)
Answer **「不收集資料」 (Data Not Collected)**.

A **privacy policy URL is required**. Suggested text to host (GitHub Pages, Notion public page, etc.):

> 閱讀器 - PDF & CHM 不收集、儲存或傳送任何個人資料。你開啟的檔案、螢光標記與筆記只儲存在你的 Mac 上，
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
