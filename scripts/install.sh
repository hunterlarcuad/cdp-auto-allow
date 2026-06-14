#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/CDP Auto Allow.app"
SCPT_SRC="$ROOT_DIR/scripts/cdp-auto-allow.scpt"
PLIST_SRC="$ROOT_DIR/launchd/com.local.cdp-auto-allow.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"
BUNDLE_ID="com.local.CDPAutoAllow"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
CONFIG_SRC="$ROOT_DIR/config.json"
CONFIG_DST="$HOME/.config/cdp-auto-allow/config.json"

SCPT_HASH=$(md5 -q "$SCPT_SRC" 2>/dev/null || md5sum "$SCPT_SRC" | cut -d' ' -f1)
HASH_FILE="$ROOT_DIR/.script-hash"
NEED_BUILD=true

if [[ -d "$APP_DIR" ]] && codesign --verify "$APP_DIR" 2>/dev/null; then
  if [[ -f "$HASH_FILE" && "$(cat "$HASH_FILE")" == "$SCPT_HASH" ]]; then
    NEED_BUILD=false
  fi
fi

# 替换 __CONFIG_PATH__ 为实际安装路径
CONFIG_INSTALL_PATH="$HOME/.config/cdp-auto-allow/config.json"
if $NEED_BUILD; then
  echo "==> Building app bundle from $SCPT_SRC"
  rm -rf "$APP_DIR"
  sed "s|__CONFIG_PATH__|$CONFIG_INSTALL_PATH|g" "$SCPT_SRC" > "$ROOT_DIR/scripts/_build.scpt"
  osacompile -o "$APP_DIR" "$ROOT_DIR/scripts/_build.scpt" >/dev/null
  rm -f "$ROOT_DIR/scripts/_build.scpt"

  "$PLIST_BUDDY" -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
    || "$PLIST_BUDDY" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
  "$PLIST_BUDDY" -c "Add :NSUIElement bool true" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
    || "$PLIST_BUDDY" -c "Set :NSUIElement true" "$APP_DIR/Contents/Info.plist"
  "$PLIST_BUDDY" -c "Delete :LSBackgroundOnly" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true

  codesign --force --deep --sign - "$APP_DIR" >/dev/null
  codesign --verify --verbose "$APP_DIR" >/dev/null

  echo "$SCPT_HASH" > "$HASH_FILE"
  REBUILT=true
else
  echo "==> App bundle up-to-date, skipping rebuild"
  REBUILT=false
fi

# 部署 config
echo "==> Installing config to $CONFIG_DST"
mkdir -p "$(dirname "$CONFIG_DST")"
if [[ ! -f "$CONFIG_DST" ]]; then
  cp "$CONFIG_SRC" "$CONFIG_DST"
  echo "    Config created at $CONFIG_DST"
else
  echo "    Config already exists at $CONFIG_DST, keeping it"
fi

pkill -f "$APP_DIR/Contents/MacOS/applet" 2>/dev/null || true
sleep 0.5

echo "==> Installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s#__APP_DIR__#$APP_DIR#g" "$PLIST_SRC" > "$PLIST_DST"
launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DST"

echo ""
echo "Installed: $PLIST_DST"
echo "Config: $CONFIG_DST"
echo ""

if $REBUILT; then
  echo "*** App bundle was rebuilt ***"
  echo "Need to re-authorize Accessibility:"
  echo "  System Settings > Privacy & Security > Accessibility"
  echo "  1) Remove old CDP Auto Allow entry if exists"
  echo "  2) Click +, Cmd+Shift+G, paste:"
  echo "     $APP_DIR"
  echo "  3) Toggle on"
else
  echo "App bundle unchanged, TCC authorization intact."
fi

echo ""
echo "Logs: /tmp/cdp-auto-allow/YYYY-MM-DD.log"
echo "Uninstall: $ROOT_DIR/scripts/uninstall.sh"
