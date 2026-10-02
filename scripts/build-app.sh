#!/bin/zsh
# Builds a signed, sandboxed "CHM Reader.app" into ./build for local use.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --quiet
if ! xcodebuild -project CHMReader.xcodeproj -scheme CHMReader -configuration Release \
    -derivedDataPath build/dd -allowProvisioningUpdates build > build/build.log 2>&1; then
  grep -E "error:" build/build.log || tail -30 build/build.log
  echo "BUILD FAILED (full log: build/build.log)"
  exit 1
fi
rm -rf "build/CHM Reader.app"
cp -R "build/dd/Build/Products/Release/CHM Reader.app" build/
echo "Built build/CHM Reader.app ($(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD))"
