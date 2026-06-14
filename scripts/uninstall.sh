#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_DST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"

echo "==> Uninstalling CDP Auto Allow"
launchctl unload "$PLIST_DST" 2>/dev/null || true
rm -f "$PLIST_DST"
rm -rf "$ROOT_DIR/CDP Auto Allow.app"
rm -f "$ROOT_DIR/.script-hash"
rm -f /tmp/cdp-auto-allow.debug.log

echo "Done. 可在 System Settings > Privacy & Security > Accessibility 中移除 CDP Auto Allow。"
