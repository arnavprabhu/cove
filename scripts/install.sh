#!/bin/sh
# Builds Cove (Release) and installs it to /Applications, replacing any previous copy.
# Running VMs are suspended when the old copy quits; your library is untouched.
set -e
cd "$(dirname "$0")/.."
xcodegen generate -q
xcodebuild -project Cove.xcodeproj -scheme Cove -configuration Release -derivedDataPath build/release build -quiet
osascript -e 'tell application id "app.cove.Cove" to quit' >/dev/null 2>&1 || true
while pgrep -x Cove >/dev/null; do sleep 1; done
rm -rf /Applications/Cove.app
ditto build/release/Build/Products/Release/Cove.app /Applications/Cove.app
codesign --verify --deep --strict /Applications/Cove.app
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -f /Applications/Cove.app
"$LSR" -u build/release/Build/Products/Release/Cove.app 2>/dev/null || true
open -a /Applications/Cove.app
echo "Installed /Applications/Cove.app"
