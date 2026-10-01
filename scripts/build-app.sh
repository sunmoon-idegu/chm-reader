#!/bin/zsh
# Builds a signed, sandboxed "CHM Reader.app" into ./build for local use.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project CHMReader.xcodeproj -scheme CHMReader -configuration Release \
  -derivedDataPath build/dd -allowProvisioningUpdates build | grep -E "error:|BUILD" || true
rm -rf "build/CHM Reader.app"
cp -R "build/dd/Build/Products/Release/CHM Reader.app" build/
echo "Built build/CHM Reader.app"
