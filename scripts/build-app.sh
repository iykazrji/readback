#!/usr/bin/env bash
# Builds build/Readback.app (release, ad-hoc signed) and build/Readback.zip.
#
# Inside the app:
#   Contents/MacOS/Readback                 the menu bar app
#   Contents/Helpers/readback               the CLI the coding tools' hooks run
#   Contents/Helpers/uv                     installs the on-device voice engine
#   Contents/Resources/ClaudeCodePlugin     the Claude Code mod (/readback:speak, /readback:read, the Stop band)
#   Contents/Resources/CodexPluginAssets    the Codex plugin's artwork
#   Contents/Resources/AppIcon.icns, MenuBarIcon(@2x).png, ThirdPartyNotices.txt
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.4.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"

UV="${UV:-$(command -v uv || true)}"
[ -x "$UV" ] || { echo "uv not found: install it or set UV=/path/to/uv" >&2; exit 1; }

swift build -c release --product Readback
swift build -c release --product readback-cli

APP=build/Readback.app
rm -rf "$APP" build/Readback.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp .build/release/Readback "$APP/Contents/MacOS/Readback"
cp .build/release/readback-cli "$APP/Contents/Helpers/readback"
cp "$UV" "$APP/Contents/Helpers/uv"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/"

# The Claude Code mod, without its tests, editor config or the type files Claude Code generates.
# These folder names are AppBundle.swift's; the app and the CLI find everything through it.
rsync -a --exclude tests --exclude tsconfig.json --exclude .claude-plugin/types \
  integrations/claude-code/readback/ "$APP/Contents/Resources/ClaudeCodePlugin/"

# Icon: Cadence, rendered in Blender (source in design/icon), in every size
# macOS wants; and its menu bar template, 18 pt at 1× and 2×.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# The Codex plugin's artwork, copied into the plugin on connect: its list logo and composer icon.
mkdir -p "$APP/Contents/Resources/CodexPluginAssets"
sips -z 512 512 Resources/AppIcon-1024.png --out "$APP/Contents/Resources/CodexPluginAssets/logo.png" >/dev/null
sips -z 32 32 Resources/AppIcon-1024.png --out "$APP/Contents/Resources/CodexPluginAssets/composer-icon.png" >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.readback</string>
  <key>CFBundleName</key><string>Readback</string>
  <key>CFBundleDisplayName</key><string>Readback</string>
  <key>CFBundleExecutable</key><string>Readback</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Readback turns other apps' sound down while it reads a reply aloud, if you switch that on in Reading. The sound only passes through: nothing is recorded or kept.</string>
  <key>NSHumanReadableCopyright</key><string>Readback. Voices run on your Mac.</string>
</dict>
</plist>
PLIST

# Sign the helpers we built, then the app. uv keeps its own signature from Astral.
codesign --force --sign - "$APP/Contents/Helpers/readback"
codesign --force --sign - "$APP/Contents/MacOS/Readback"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

# The zip unpacks to a Readback folder: the app and the README for whoever gets it.
STAGE=build/zip/Readback
rm -rf build/zip; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Readback.app"
cp docs/README-for-friends.md "$STAGE/README.md"
ditto -c -k --keepParent "$STAGE" build/Readback.zip
rm -rf build/zip
echo "built $APP ($VERSION, build $BUILD) and build/Readback.zip"
