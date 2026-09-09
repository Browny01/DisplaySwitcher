#!/usr/bin/env bash
# Builds DisplaySwitcher from source and installs it into /Applications.
#
# Usage:
#   ./install.sh            build + install
#   ./install.sh --no-launch   build + install but do not launch the app
set -euo pipefail

APP_NAME="DisplaySwitcher"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$REPO_ROOT/DisplaySwitcher.xcodeproj"
SCHEME="$APP_NAME"
CONFIGURATION="Release"
# Build outside the source tree: ~/Documents&Desktop are iCloud-synced, and
# iCloud stamps files with extended attributes that codesign rejects.
BUILD_DIR="${BUILD_DIR:-${HOME}/.cache/DisplaySwitcher/build}"
DEST="/Applications/$APP_NAME.app"
LAUNCH=1

for arg in "$@"; do
  case "$arg" in
    --no-launch) LAUNCH=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-launch]"
      exit 0
      ;;
  esac
done

echo "==> Checking requirements"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: Xcode (or the Command Line Tools) is required to build $APP_NAME."
  echo "Install it from the App Store, or run:  xcode-select --install"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required (bundled with Xcode Command Line Tools)."
  exit 1
fi

echo "==> Regenerating the Xcode project"
python3 "$REPO_ROOT/tools/generate_project.py"

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  build

APP_BUNDLE="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "Error: build output not found at $APP_BUNDLE"
  exit 1
fi

echo "==> Installing to $DEST"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP_BUNDLE" "$DEST"

echo ""
echo "Done. $APP_NAME is installed at $DEST"
echo "It lives in your menu bar (click the two-displays icon)."

if [ "$LAUNCH" = "1" ]; then
  echo "==> Launching $APP_NAME"
  open "$DEST"
fi

echo "Tip: add a login item in Settings > General > Launch at login,"
echo "or re-run  ./install.sh  any time you want the latest build."