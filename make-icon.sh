#!/bin/bash
# Regenerate all icon assets from AppIcon.svg.
# Run this after editing AppIcon.svg, then run ./build.sh to bake them in.
#
# Produces:
#   AppIcon.iconset/         (legacy, for iconutil → AppIcon.icns fallback)
#   AppIcon.icns             (fallback icon)
#   Assets.xcassets/         (actool source → Assets.car + CFBundleIconName)
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ"
SVG="AppIcon.svg"
MASTER="/tmp/aghud_icon_master.png"

[[ -f "$SVG" ]] || { echo "no $SVG"; exit 1; }

echo "==> render $SVG → 1024 master"
rm -f /tmp/AppIcon.svg.png "$MASTER"
qlmanage -t -s 1024 -o /tmp/ "$SVG" >/dev/null 2>&1
[[ -f /tmp/AppIcon.svg.png ]] || { echo "qlmanage render failed"; exit 1; }
mv -f /tmp/AppIcon.svg.png "$MASTER"

gen() { sips -z "$1" "$1" "$MASTER" --out "$2" >/dev/null 2>&1; }

echo "==> build AppIcon.iconset (+ AppIcon.icns fallback)"
rm -rf AppIcon.iconset && mkdir -p AppIcon.iconset
gen 16  AppIcon.iconset/icon_16x16.png
gen 32  AppIcon.iconset/icon_16x16@2x.png
gen 32  AppIcon.iconset/icon_32x32.png
gen 64  AppIcon.iconset/icon_32x32@2x.png
gen 128 AppIcon.iconset/icon_128x128.png
gen 256 AppIcon.iconset/icon_128x128@2x.png
gen 256 AppIcon.iconset/icon_256x256.png
gen 512 AppIcon.iconset/icon_256x256@2x.png
gen 512 AppIcon.iconset/icon_512x512.png
gen 1024 AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns
xattr -cr AppIcon.icns 2>/dev/null || true

echo "==> build Assets.xcassets/AppIcon.appiconset (for actool)"
ICONSET=Assets.xcassets/AppIcon.appiconset
rm -rf Assets.xcassets && mkdir -p "$ICONSET"
gen 16   "$ICONSET/icon_16.png";    gen 32   "$ICONSET/icon_16@2x.png"
gen 32   "$ICONSET/icon_32.png";    gen 64   "$ICONSET/icon_32@2x.png"
gen 128  "$ICONSET/icon_128.png";   gen 256  "$ICONSET/icon_128@2x.png"
gen 256  "$ICONSET/icon_256.png";   gen 512  "$ICONSET/icon_256@2x.png"
gen 512  "$ICONSET/icon_512.png";   gen 1024 "$ICONSET/icon_512@2x.png"
cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images": [
    {"size":"16x16","idiom":"mac","filename":"icon_16.png","scale":"1x"},
    {"size":"16x16","idiom":"mac","filename":"icon_16@2x.png","scale":"2x"},
    {"size":"32x32","idiom":"mac","filename":"icon_32.png","scale":"1x"},
    {"size":"32x32","idiom":"mac","filename":"icon_32@2x.png","scale":"2x"},
    {"size":"128x128","idiom":"mac","filename":"icon_128.png","scale":"1x"},
    {"size":"128x128","idiom":"mac","filename":"icon_128@2x.png","scale":"2x"},
    {"size":"256x256","idiom":"mac","filename":"icon_256.png","scale":"1x"},
    {"size":"256x256","idiom":"mac","filename":"icon_256@2x.png","scale":"2x"},
    {"size":"512x512","idiom":"mac","filename":"icon_512.png","scale":"1x"},
    {"size":"512x512","idiom":"mac","filename":"icon_512@2x.png","scale":"2x"}
  ],
  "info": {"version":1,"author":"xcode"}
}
JSON

echo "==> done. now run ./build.sh to bake the new icon into the app."
