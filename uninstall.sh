#!/usr/bin/env bash
# Removes DisplaySwitcher from /Applications.
# Your saved presets and settings are left intact so re-installing restores them.
set -euo pipefail

APP_NAME="DisplaySwitcher"
DEST="/Applications/$APP_NAME.app"

echo "==> Removing CLI link"
rm -f /usr/local/bin/display-switcher

if [ ! -d "$DEST" ]; then
  echo "$APP_NAME is not installed at $DEST."
  exit 0
fi

echo "==> Quitting $APP_NAME"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Removing $DEST"
rm -rf "$DEST"

echo "Done. $APP_NAME has been removed."
echo "Run './install.sh' to reinstall it (your presets are still saved)."