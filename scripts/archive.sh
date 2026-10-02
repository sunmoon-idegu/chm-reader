#!/bin/zsh
# Archives for the Mac App Store and exports a signed .pkg into ./build/export.
# Pass --upload to send it straight to App Store Connect instead.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
DEST=export
[[ "${1:-}" == "--upload" ]] && DEST=upload
mkdir -p build
# Never export or upload a stale archive from an earlier run.
rm -rf build/CHMReader.xcarchive build/export
if ! xcodebuild -project CHMReader.xcodeproj -scheme CHMReader -configuration Release \
    -archivePath build/CHMReader.xcarchive -allowProvisioningUpdates -destination "generic/platform=macOS" \
    archive > build/archive.log 2>&1; then
  grep -E "error:" build/archive.log || tail -30 build/archive.log
  echo "ARCHIVE FAILED (full log: build/archive.log)"
  exit 1
fi
echo "Archived $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>LV99JJMWBN</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$DEST</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath build/CHMReader.xcarchive -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
