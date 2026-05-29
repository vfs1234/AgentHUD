#!/bin/bash
# Build AgentNotifier from Swift source into a double-clickable .app, ad-hoc sign
# it, and install to ~/Applications (stable path so SMAppService login-item works).
# Re-run any time after changing source. Fully reproducible, no Xcode IDE needed.
set -euo pipefail

APP="AgentHUD"
PROJ="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/Applications"

cd "$PROJ"

echo "==> swift build -c release"
# Force a clean compile: SwiftPM incremental builds have gone stale on this
# machine (产物不随源码更新), so always wipe the release artifacts first.
rm -rf .build/release .build/*/release 2>/dev/null || true
swift build -c release
BINDIR="$(swift build -c release --show-bin-path)"
BIN="${BINDIR}/${APP}"
[[ -x "$BIN" ]] || { echo "build failed: $BIN not found"; exit 1; }

echo "==> assembling ${APP}.app"
APPDIR="${PROJ}/build/${APP}.app"
rm -rf "$APPDIR"
mkdir -p "${APPDIR}/Contents/MacOS" "${APPDIR}/Contents/Resources"
cp "$BIN" "${APPDIR}/Contents/MacOS/${APP}"
cp "${PROJ}/Resources/Info.plist" "${APPDIR}/Contents/Info.plist"

# Compile the icon via actool → produces Assets.car + AppIcon.icns. This is what
# makes macOS (esp. Notification Center's source icon) actually pick up the icon:
# a hand-copied .icns alone leaves CFBundleIconName unresolved and the notification
# source glyph blank.
if [[ -d "${PROJ}/Assets.xcassets" ]] && command -v xcrun >/dev/null 2>&1; then
  echo "    actool: compiling Assets.xcassets"
  xcrun actool "${PROJ}/Assets.xcassets" \
    --compile "${APPDIR}/Contents/Resources" \
    --platform macosx --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /tmp/aghud_actool.plist >/dev/null 2>&1 \
    && echo "    actool: ok (Assets.car + AppIcon.icns)" \
    || echo "    actool failed — falling back to plain .icns"
fi
# Fallback / belt-and-suspenders: ensure a .icns exists even if actool didn't run.
[[ -f "${APPDIR}/Contents/Resources/AppIcon.icns" ]] || \
  { [[ -f "${PROJ}/AppIcon.icns" ]] && cp "${PROJ}/AppIcon.icns" "${APPDIR}/Contents/Resources/AppIcon.icns"; }
# PNG copy of the icon for use as a UNNotificationAttachment (banner thumbnail).
if [[ -f "${PROJ}/AppIcon.iconset/icon_256x256.png" ]]; then
  cp "${PROJ}/AppIcon.iconset/icon_256x256.png" "${APPDIR}/Contents/Resources/NotifIcon.png"
fi

echo "==> codesign"
xattr -cr "${APPDIR}" 2>/dev/null || true   # strip resource forks / Finder info so codesign won't reject
# A real signing identity is REQUIRED for UNUserNotificationCenter to deliver:
# notifications from an ad-hoc-signed app are silently dropped by usernoted.
# Prefer Apple Development / Developer ID; fall back to ad-hoc if none exists.
# Match by SHA-1 hash (first column) — robust against name-quoting issues.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Apple Distribution|Developer ID Application' | head -1 | awk '{print $2}')"
if [[ -n "$SIGN_ID" ]]; then
  echo "    using identity: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" "${APPDIR}/Contents/MacOS/${APP}"
  codesign --force --sign "$SIGN_ID" "${APPDIR}"
else
  echo "    no Developer identity — ad-hoc (notifications may be dropped by macOS)"
  codesign --force --sign - "${APPDIR}/Contents/MacOS/${APP}"
  codesign --force --sign - "${APPDIR}"
fi
codesign --verify --verbose=2 "${APPDIR}"

echo "==> install to ${DEST}"
killall "${APP}" 2>/dev/null || true
mkdir -p "${DEST}"
rm -rf "${DEST}/${APP}.app"
cp -R "$APPDIR" "${DEST}/${APP}.app"
xattr -dr com.apple.quarantine "${DEST}/${APP}.app" 2>/dev/null || true

echo "==> done: ${DEST}/${APP}.app"
echo "    launch with: open \"${DEST}/${APP}.app\""
