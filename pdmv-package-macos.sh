#!/bin/zsh
# pdmv-package-macos.sh
# Perfect Dark macvanta — Intel Mac / macOS Tahoe DMG packager
#
# Creates a distributable DMG installer from pd-macvanta-<romid>.app.
# Run pdmv-bundle-macos.sh first to produce the .app bundle.
#
# Usage:
#   ./pdmv-package-macos.sh                  # package ntsc-final (default)
#   ./pdmv-package-macos.sh --rom pal-final  # package PAL region
#   ./pdmv-package-macos.sh --rom jpn-final
#   ./pdmv-package-macos.sh --rom ntsc-1.0
#
# Output:
#   dist/pd-macvanta-<romid>-Intel-Mac.dmg
#   logs/package-<romid>-<timestamp>.log
#
# DMG layout:
#   pd-macvanta-<romid>.app  ← drag to Applications
#   Applications/            ← symlink
#   .background/background.png  ← dark red/black PD-themed background
#
# CHANGELOG
# v0.11 (2026-03-09) - Renamed app/bundle/DMG from PerfectDark-* to
#                      pd-macvanta-* to avoid copyright name conflicts;
#                      bundle identifier updated to io.macvanta.pd.<romid>
# v0.10 (2026-03-09) - Initial version; adapted from pdmv-starship package-macos.sh
#                      v0.21 — all battle-tested fixes carried over:
#                      (N) nullglob stale-mount eject; plist pipe-delimited
#                      mount-point parse; Finder eject before hdiutil detach;
#                      use framework at top-level of AppleScript (-2741 fix);
#                      NSWorkspace icon applier; top-level logs/ dir;
#                      PD dark red/black JP box art themed DMG background;
#                      icon generated from pd-macvanta-icon.png via iconutil;
#                      per-region --rom flag + dist/ output directory

set -eo pipefail
VERSION="0.11"
SCRIPT_DIR="${0:A:h}"

# ── Parse arguments ───────────────────────────────────────────────────────────

ROMID="ntsc-final"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom) ROMID="$2"; shift 2 ;;
    *) echo "Usage: $0 [--rom ntsc-final|ntsc-1.0|pal-final|jpn-final]" >&2; exit 1 ;;
  esac
done

# Region label
case "$ROMID" in
  ntsc-final) REGION_LABEL="🇺🇸 NTSC US v1.1" ;;
  ntsc-1.0)   REGION_LABEL="🇺🇸 NTSC US v1.0" ;;
  pal-final)  REGION_LABEL="🇪🇺 PAL" ;;
  jpn-final)  REGION_LABEL="🇯🇵 Japan" ;;
  *)          REGION_LABEL="$ROMID" ;;
esac

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
BUNDLE_DIR="$BUILD_DIR/pd-macvanta-$ROMID.app"
DIST_DIR="$SCRIPT_DIR/dist"
DMG_NAME="pd-macvanta-$ROMID-Intel-Mac"
DMG_FINAL="$DIST_DIR/${DMG_NAME}.dmg"
DMG_STAGING="$DIST_DIR/${DMG_NAME}-staging"
DMG_TMP="$DIST_DIR/${DMG_NAME}-tmp.dmg"
DMG_VOLUME="pd-macvanta"
DMG_SIZE="160m"
ICON_SRC="$SCRIPT_DIR/pd-macvanta-icon.png"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"

LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/package-$ROMID-$TIMESTAMP.log"
mkdir -p "$LOG_DIR" "$DIST_DIR"

echo "📀 pdmv-package-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   ROMID:   $ROMID  ($REGION_LABEL)" | tee -a "$LOGFILE"
echo "   Bundle:  $BUNDLE_DIR" | tee -a "$LOGFILE"
echo "   Output:  $DMG_FINAL" | tee -a "$LOGFILE"
echo "   Log:     $LOGFILE" | tee -a "$LOGFILE"

# ── Preflight: eject any stale "pd-macvanta" mounts ──────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔍 Checking for stale mounts..." | tee -a "$LOGFILE"
for vol in /Volumes/pd-macvanta*(N); do
  echo "   ⚠️  Ejecting stale mount: $vol" | tee -a "$LOGFILE"
  hdiutil detach "$vol" -force 2>&1 | tee -a "$LOGFILE" || true
done

# ── Preflight checks ──────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔍 Preflight checks..." | tee -a "$LOGFILE"

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "   ❌ Bundle not found: $BUNDLE_DIR" | tee -a "$LOGFILE"
  echo "      Run: ./pdmv-bundle-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
  exit 1
fi

if [[ ! -f "$BUNDLE_DIR/Contents/MacOS/pd-macvanta-bin" ]]; then
  echo "   ❌ Bundle appears incomplete (missing pd-macvanta-bin)" | tee -a "$LOGFILE"
  echo "      Run: ./pdmv-bundle-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
  exit 1
fi

if [[ ! -f "$ICON_SRC" ]]; then
  echo "   ❌ Icon source not found: $ICON_SRC" | tee -a "$LOGFILE"
  exit 1
fi

echo "   ✅ Bundle: $(du -sh "$BUNDLE_DIR" | cut -f1)" | tee -a "$LOGFILE"
echo "   ✅ Icon source: $(du -h "$ICON_SRC" | cut -f1)" | tee -a "$LOGFILE"

rm -rf "$DMG_STAGING" "$DMG_TMP" "$DMG_FINAL"
mkdir -p "$DMG_STAGING/.background"

# ── Step 1: Generate .icns from pd-macvanta-icon.png ─────────────────────────

# iconutil requires a properly named .iconset directory with specific filenames.
# We resize pd-macvanta-icon.png to all required sizes using sips (built-in).
# sips is available on all macOS versions without extra dependencies.

echo "" | tee -a "$LOGFILE"
echo "🖼  Step 1: Generate .icns from pd-macvanta-icon.png" | tee -a "$LOGFILE"

ICONSET_DIR="$DIST_DIR/pd-macvanta.iconset"
ICNS_PATH="$DIST_DIR/pd-macvanta.icns"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for SIZE in 16 32 64 128 256 512 1024; do
  sips -z $SIZE $SIZE "$ICON_SRC" \
    --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" \
    &>/dev/null
  # Retina (@2x) variants — half logical size, double pixel size
  if (( SIZE >= 32 )); then
    HALF=$(( SIZE / 2 ))
    cp "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" \
       "$ICONSET_DIR/icon_${HALF}x${HALF}@2x.png"
  fi
done

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH" 2>&1 | tee -a "$LOGFILE"
rm -rf "$ICONSET_DIR"
echo "   ✅ .icns generated: $(du -h "$ICNS_PATH" | cut -f1)" | tee -a "$LOGFILE"

# ── Step 2: Generate DMG background ──────────────────────────────────────────

# Dark red/black background inspired by the Perfect Dark Japanese N64 box art.
# Pure Python + stdlib only — no Pillow required.

echo "" | tee -a "$LOGFILE"
echo "🌑 Step 2: Generate DMG background (dark red/black JP box art theme)" | tee -a "$LOGFILE"

BG_PATH="$DMG_STAGING/.background/background.png"

python3 - "$BG_PATH" << 'PYEOF' 2>&1 | tee -a "$LOGFILE"
import struct, zlib, sys, math

W, H = 660, 400
out = sys.argv[1]

def png_chunk(name, data):
    c = zlib.crc32(name + data) & 0xffffffff
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', c)

rows = []
for y in range(H):
    row = []
    for x in range(W):
        nx = x / W
        ny = y / H

        # Near-black base
        r_base, g_base, b_base = 6, 2, 2

        # Deep red glow bottom-left — JP box art signature
        dx1 = nx - 0.12; dy1 = ny - 0.92
        red1 = max(0.0, 1.0 - (dx1*dx1 + dy1*dy1) / 0.38) * 95

        # Secondary red accent top-right
        dx2 = nx - 0.90; dy2 = ny - 0.06
        red2 = max(0.0, 1.0 - (dx2*dx2 + dy2*dy2) / 0.20) * 50

        # Subtle horizontal scanlines
        scanline = (math.sin(ny * H * 1.8) * 0.5 + 0.5) * 3.5

        # Gaussian band to lift label readability at icon label zone (~68% down)
        dy_label = (ny - 0.68) / 0.07
        label_lift = math.exp(-dy_label * dy_label * 0.5) * 18

        # Edge vignette
        edge_x = min(nx, 1.0 - nx) * 2.0
        edge_y = min(ny, 1.0 - ny) * 2.0
        vignette = (1.0 - edge_x * edge_y) * 22

        r = max(0, min(255, int(r_base + red1*0.96 + red2*0.80 + scanline + label_lift*0.55 - vignette)))
        g = max(0, min(255, int(g_base + red1*0.04 + scanline*0.25 + label_lift*0.40 - vignette*0.85)))
        b = max(0, min(255, int(b_base + red1*0.05 + red2*0.04 + scanline*0.35 + label_lift*0.35 - vignette*0.70)))

        row += [r, g, b]
    rows.append(bytes(row))

raw = b''.join(b'\x00' + r for r in rows)
compressed = zlib.compress(raw, 9)

with open(out, 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n')
    f.write(png_chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)))
    f.write(png_chunk(b'IDAT', compressed))
    f.write(png_chunk(b'IEND', b''))

import os
print(f"background.png written ({os.path.getsize(out)} bytes)")
PYEOF

echo "   ✅ Background: $(du -h "$BG_PATH" | cut -f1)" | tee -a "$LOGFILE"

# ── Step 3: Populate staging folder ──────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "📁 Step 3: Staging DMG contents" | tee -a "$LOGFILE"
cp -R "$BUNDLE_DIR" "$DMG_STAGING/pd-macvanta-$ROMID.app"
ln -s /Applications "$DMG_STAGING/Applications"
echo "   ✅ pd-macvanta-$ROMID.app + /Applications alias staged" | tee -a "$LOGFILE"

# ── Step 4: Create writable DMG ──────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "💿 Step 4: Create writable DMG" | tee -a "$LOGFILE"
hdiutil create \
  -srcfolder "$DMG_STAGING" \
  -volname   "$DMG_VOLUME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,b=16" \
  -format UDRW \
  -size "$DMG_SIZE" \
  "$DMG_TMP" 2>&1 | tee -a "$LOGFILE"
echo "   ✅ Writable DMG created" | tee -a "$LOGFILE"

# ── Step 5: Mount DMG — extract mount point + dev entry via plist ─────────────

# plist parse via Python avoids all the grep/awk fragility that caused
# MOUNT_DIR="1" and MOUNT_DIR="2" bugs in earlier Starship iterations.

echo "" | tee -a "$LOGFILE"
echo "💿 Step 5: Mount DMG" | tee -a "$LOGFILE"

ATTACH_PLIST="$LOG_DIR/attach-$$.plist"
hdiutil attach -readwrite -noverify -noautoopen -plist "$DMG_TMP" \
  > "$ATTACH_PLIST" 2>&1

cat "$ATTACH_PLIST" | tee -a "$LOGFILE"

ATTACH_RESULT="$(python3 - "$ATTACH_PLIST" << 'PYEOF'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    data = plistlib.load(f)
for entity in data.get('system-entities', []):
    mp = entity.get('mount-point', '')
    de = entity.get('dev-entry', '')
    if mp:
        print(f"{mp}|{de}")
        break
PYEOF
)"

rm -f "$ATTACH_PLIST"

MOUNT_DIR="$(echo "$ATTACH_RESULT" | cut -d'|' -f1)"
DEV_ENTRY="$(echo "$ATTACH_RESULT" | cut -d'|' -f2)"

if [[ -z "$MOUNT_DIR" ]]; then
  echo "   ❌ Failed to get mount point from hdiutil attach plist" | tee -a "$LOGFILE"
  exit 1
fi

echo "   ✅ Mounted at: '$MOUNT_DIR'  (dev: $DEV_ENTRY)" | tee -a "$LOGFILE"
sleep 2

# ── Step 6: Style with osascript ─────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🎨 Step 6: Style DMG window (dark red/black theme)" | tee -a "$LOGFILE"

ACTUAL_VOLUME="${MOUNT_DIR##*/Volumes/}"
echo "   Volume name: '$ACTUAL_VOLUME'" | tee -a "$LOGFILE"

# Hide .background folder — try SetFile first, fall back to chflags
SetFile -a V "$MOUNT_DIR/.background" 2>&1 | tee -a "$LOGFILE" || \
chflags hidden "$MOUNT_DIR/.background" 2>&1 | tee -a "$LOGFILE" || \
echo "   ⚠️  Could not hide .background (non-fatal)" | tee -a "$LOGFILE"

osascript - "$ACTUAL_VOLUME" << 'OSASCRIPT' 2>&1 | tee -a "$LOGFILE"
on run argv
    set volName to item 1 of argv
    tell application "Finder"
        tell disk volName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {400, 100, 1060, 500}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 100
            set text size of theViewOptions to 13
            set background picture of theViewOptions to ¬
                file ".background:background.png"
            set position of item 1 of container window to {160, 180}
            set position of item 2 of container window to {500, 180}
            update without registering applications
            delay 3
            close
        end tell
    end tell
end run
OSASCRIPT

echo "   ✅ DMG styled" | tee -a "$LOGFILE"

# ── Step 7: Release Finder's hold, then detach ───────────────────────────────

# Finder holds a lock after window styling — eject first, then hdiutil detach.
# The sleep + Finder eject pattern is inherited from Starship v0.16 fix.

echo "" | tee -a "$LOGFILE"
echo "💿 Step 7: Unmount DMG" | tee -a "$LOGFILE"

sync
sleep 5

osascript - "$ACTUAL_VOLUME" << 'EJECTSCRIPT' 2>&1 | tee -a "$LOGFILE" || true
on run argv
    set volName to item 1 of argv
    tell application "Finder"
        try
            eject disk volName
        end try
    end tell
end run
EJECTSCRIPT

sleep 2

if [[ -d "$MOUNT_DIR" ]]; then
  hdiutil detach "$MOUNT_DIR" -force 2>&1 | tee -a "$LOGFILE" || \
  hdiutil detach "$DEV_ENTRY" -force 2>&1 | tee -a "$LOGFILE"
else
  echo "   (volume already unmounted by Finder eject)" | tee -a "$LOGFILE"
fi

echo "   ✅ DMG unmounted" | tee -a "$LOGFILE"

# ── Step 8: Convert to compressed read-only DMG ───────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🗜  Step 8: Convert to compressed read-only DMG" | tee -a "$LOGFILE"
hdiutil convert "$DMG_TMP" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_FINAL" 2>&1 | tee -a "$LOGFILE"

rm -f "$DMG_TMP"
rm -rf "$DMG_STAGING"
echo "   ✅ Compressed DMG created" | tee -a "$LOGFILE"

# ── Step 9: Verify DMG ────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔍 Step 9: Verify DMG" | tee -a "$LOGFILE"
hdiutil verify "$DMG_FINAL" 2>&1 | tee -a "$LOGFILE"
echo "   ✅ Size: $(du -h "$DMG_FINAL" | cut -f1)" | tee -a "$LOGFILE"

# ── Step 10: Apply app icon to DMG file ──────────────────────────────────────

# "use framework" MUST be at the top level of the AppleScript — not inside
# "on run" — otherwise osascript throws error -2741. Inherited from Starship v0.21.

echo "" | tee -a "$LOGFILE"
echo "🎨 Step 10: Apply app icon to DMG file" | tee -a "$LOGFILE"

osascript - "$BUNDLE_DIR" "$DMG_FINAL" << 'ICONSCRIPT' 2>&1 | tee -a "$LOGFILE"
use framework "AppKit"
use framework "Foundation"
use scripting additions

on run argv
    set appPath to item 1 of argv
    set dmgPath to item 2 of argv
    try
        set ws to current application's NSWorkspace's sharedWorkspace()
        set appIcon to ws's iconForFile:appPath
        set didSet to ws's setIcon:appIcon forFile:dmgPath options:0
        if didSet as boolean then
            log "✅ pd-macvanta icon applied to DMG"
        else
            log "⚠️  setIcon returned false (icon may not persist)"
        end if
    on error errMsg number errNum
        log "⚠️  Icon not applied (non-fatal): " & errMsg & " (" & errNum & ")"
    end try
end run
ICONSCRIPT

# ── Summary ───────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ pdmv-package-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📀 $DMG_FINAL" | tee -a "$LOGFILE"
echo "   📄 $LOGFILE" | tee -a "$LOGFILE"
echo "   👉 Distribute or drag-mount to install pd-macvanta-$ROMID.app" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
