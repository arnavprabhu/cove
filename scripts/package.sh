#!/usr/bin/env bash
# Builds a release zip of Cove for GitHub Releases and the Homebrew cask.
#
#   scripts/package.sh            # clean Release build → checks → dist/Cove-<version>.zip + SHA-256
#   scripts/package.sh --cask     # also renders the cask to dist/cove.rb (from packaging/cove.rb.in)
#
# The app is ad hoc signed (no Developer ID, not notarized). The checks fail the run if the signature does not
# verify, if the debugger entitlement (get-task-allow) is present, or if the virtualization or sandbox
# entitlement is missing — on the built app and again on a copy extracted from the zip.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
DERIVED="$ROOT/build/package"
APP="$DERIVED/Build/Products/Release/Cove.app"
DIST="$ROOT/dist"
TEMPLATE="$ROOT/packaging/cove.rb.in"
CASK=0

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cask) CASK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option $1 (scripts/package.sh --help)" ;;
  esac
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cove-package.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Fails unless the app's signature verifies and its entitlements are the shipping set.
check_app() {
  local app="$1" ents="$TMP/entitlements.plist"
  codesign --verify --deep --strict "$app" || die "signature does not verify: $app"
  codesign -d --entitlements - --xml "$app" >"$ents" 2>/dev/null || die "could not read entitlements: $app"
  # PlistBuddy, not plutil: entitlement keys contain dots, which plutil reads as a key path.
  ent() { /usr/libexec/PlistBuddy -c "Print :$1" "$ents" 2>/dev/null; }
  [[ "$(ent com.apple.security.virtualization)" == true ]] || die "missing com.apple.security.virtualization: $app"
  [[ "$(ent com.apple.security.app-sandbox)" == true ]] || die "missing com.apple.security.app-sandbox: $app"
  if ent com.apple.security.get-task-allow >/dev/null; then die "get-task-allow present (debug entitlement): $app"; fi
  echo "ok: signature verifies; virtualization + sandbox entitlements, no get-task-allow ($app)"
}

step "Clean Release build"
xcodegen generate -q
rm -rf "$DERIVED"
xcodebuild -project Cove.xcodeproj -scheme Cove -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' clean build -quiet
[[ -d "$APP" ]] || die "build produced no app at $APP"

plist() { plutil -extract "$1" raw -o - "$APP/Contents/Info.plist"; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
BUNDLE_ID="$(plist CFBundleIdentifier)"
[[ "$BUNDLE_ID" == app.cove.Cove ]] || die "unexpected bundle id $BUNDLE_ID"
[[ "$(plist LSMinimumSystemVersion)" == 14.0 ]] || die "LSMinimumSystemVersion is not 14.0"
[[ "$(lipo -archs "$APP/Contents/MacOS/Cove")" == arm64 ]] || die "binary is not arm64-only"
echo "Cove $VERSION ($BUILD), $BUNDLE_ID"

step "Verify the built app"
check_app "$APP"

step "Zip"
ZIP="$DIST/Cove-$VERSION.zip"
mkdir -p "$DIST"
rm -f "$ZIP"
# --keepParent puts Cove.app at the top of the zip; the signature lives in the bundle, not in extended attributes.
ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$ZIP"

step "Verify a copy extracted from the zip"
ditto -x -k "$ZIP" "$TMP/extracted"
check_app "$TMP/extracted/Cove.app"

SHA256="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
printf '%s  %s\n' "$SHA256" "$(basename "$ZIP")" >"$ZIP.sha256"

if [[ $CASK -eq 1 ]]; then
  step "Render cask"
  [[ -f "$TEMPLATE" ]] || die "missing $TEMPLATE"
  sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA256/" "$TEMPLATE" >"$DIST/cove.rb"
  echo "$DIST/cove.rb"
fi

step "Done"
echo "zip:     $ZIP"
echo "sha256:  $SHA256"
