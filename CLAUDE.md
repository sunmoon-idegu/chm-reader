# 閱讀器 - PDF & CHM (Reader for macOS; formerly 「CHM 閱讀器」)

SwiftUI + AppKit app on the Mac App Store. Stack and design decisions: `dev-docs/TECH_STACK.md`.
App Store details, listing text and upload history: `dev-docs/APP_STORE.md`.

## Layout
- `Sources/CCHMLib` — vendored CHMLib (LGPL-2.1). Must stay an unmodified, separate dynamic framework.
- `Sources/CHMKit` — CHM parsing, sitemap/#TOPICS TOC, Big5/CP950 decoding (unit-tested).
- `Sources/CHMReader` — the app. `ReaderModel` is the protocol shared by `ReaderController` (CHM/WebKit) and `PDFReaderController` (PDFKit); window chrome is generic over it.
- `project.yml` — XcodeGen spec (the `.xcodeproj` is generated and git-ignored). `Package.swift` is only for `swift test`.
- `docs/` — public website on GitHub Pages (support + privacy policy URLs used in the listing). Must stay named `docs/`: built-in Pages hosting only serves `/` or `/docs`, and the user does not want GitHub Actions.
- `app-store-asset/` — listing text, screenshots (2560×1600), icon, `demo/論語選讀.pdf` (public-domain demo, from `scripts/make-demo-pdf.swift`; also served at `docs/demo/`). `scripts/make-icon.swift` draws the icon.

## Commands
```sh
swift test                    # unit tests (CHM_TEST_FILE=~/Downloads/瑜伽師地論.chm also tests a real book)
scripts/build-app.sh          # signed, sandboxed Release build → build/CHM Reader.app
scripts/archive.sh --upload   # archive + upload to App Store Connect (team LV99JJMWBN)
```

## Uploading a new build — always
1. Raise `CURRENT_PROJECT_VERSION` in `project.yml` by 1 before **every** upload (reused build numbers are rejected). Raise `MARKETING_VERSION` for user-visible releases.
2. Append the upload to the history table in `dev-docs/APP_STORE.md`.
3. Confirm with the user before running `scripts/archive.sh --upload`.

## Gotchas
- Sandboxed WKWebView shows blank pages without the `com.apple.security.network.client` entitlement.
- Recent books are security-scoped bookmarks; keep `startAccessingSecurityScopedResource()` in `RootView.load`.
- Screen capture isn't permitted; verify UI by snapshotting the window's theme frame with `cacheDisplay` from a temporary, env-gated hook, then remove the hook. Delete any demo notes it creates.
- The user prefers a lean UI with one control per purpose; reply in the language they write in (Traditional Chinese or English).
