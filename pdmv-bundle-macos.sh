#!/bin/zsh
# pdmv-bundle-macos.sh
# Perfect Dark macvanta — Intel Mac / macOS Tahoe app bundle creator
#
# Wraps the compiled pd.<romid> binary into a proper pd-macvanta-<romid>.app
# bundle. The binary is placed in Contents/MacOS/ behind a zsh wrapper that
# sets cwd to Contents/Resources/ so pd.ini and the data/ dir are found at
# runtime — the same pattern used by starship-macalfa for .o2r asset resolution.
#
# Usage:
#   ./pdmv-bundle-macos.sh                    # bundle ntsc-final (default)
#   ./pdmv-bundle-macos.sh --rom pal-final
#
# Output:
#   perfect_dark/build-<romid>/pd-macvanta-<romid>.app
#   logs/bundle-<romid>-<timestamp>.log   ← top-level logs/, survives rm -rf perfect_dark/
#
# CHANGELOG
# v0.11 (2026-05-05) - Renamed bundle to pd-macvanta-<romid>.app, inner binary
#                      to pd-macvanta-bin, wrapper to pd-macvanta — aligns with
#                      package script and avoids "Perfect Dark" name conflict;
#                      bundle ID changed to io.macvanta.pd.<romid>; icon now
#                      generated from pd-macvanta-icon.png via sips/iconutil
#                      (drops Python placeholder); log moved to top-level logs/
#                      for consistency with build/run/package scripts
# v0.10 (2026-03-09) - Initial version; per-region ROM select; placeholder
#                      .icns generation; cwd wrapper; Info.plist

set -e
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

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
BINARY="$BUILD_DIR/pd.$ROMID"
DATA_DIR="$BUILD_DIR/data"
BUNDLE="$BUILD_DIR/pd-macvanta-$ROMID.app"
ICNS="$BUILD_DIR/pd-macvanta.icns"
ICON_SRC="$SCRIPT_DIR/pd-macvanta-icon.png"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"

# Log lives at top-level logs/ — consistent with build/run/package scripts,
# survives rm -rf perfect_dark/.
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/bundle-$ROMID-$TIMESTAMP.log"
mkdir -p "$LOG_DIR"

echo "🎁 pdmv-bundle-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   ROMID:  $ROMID" | tee -a "$LOGFILE"
echo "   Bundle: $BUNDLE" | tee -a "$LOGFILE"
echo "   Log:    $LOGFILE" | tee -a "$LOGFILE"

# ── Preflight checks ──────────────────────────────────────────────────────────

if [[ ! -f "$BINARY" ]]; then
  echo "❌ Binary not found — run ./pdmv-build-macos.sh --rom $ROMID first" | tee -a "$LOGFILE"
  exit 1
fi
if [[ ! -f "$DATA_DIR/pd.$ROMID.z64" ]]; then
  echo "❌ ROM not found at $DATA_DIR/pd.$ROMID.z64" | tee -a "$LOGFILE"
  exit 1
fi
if [[ ! -f "$ICON_SRC" ]]; then
  echo "❌ Icon source not found: $ICON_SRC" | tee -a "$LOGFILE"
  exit 1
fi
echo "✅ Preflight passed" | tee -a "$LOGFILE"

# ── Step 1: Generate .icns from pd-macvanta-icon.png ─────────────────────────

# iconutil requires a properly named .iconset directory with specific filenames.
# We resize pd-macvanta-icon.png to all required sizes using sips (built-in,
# no extra dependencies). Always regenerate so icon updates flow through.

echo "🖼  Step 1: Generate .icns from pd-macvanta-icon.png..." | tee -a "$LOGFILE"
ICONSET_TMP="$(mktemp -d)/pd-macvanta.iconset"
mkdir -p "$ICONSET_TMP"
for SIZE in 16 32 64 128 256 512 1024; do
  sips -z $SIZE $SIZE "$ICON_SRC" \
    --out "$ICONSET_TMP/icon_${SIZE}x${SIZE}.png" \
    &>/dev/null
  # Retina (@2x) variants — half logical size, double pixel size
  if (( SIZE >= 32 )); then
    HALF=$(( SIZE / 2 ))
    cp "$ICONSET_TMP/icon_${SIZE}x${SIZE}.png" \
       "$ICONSET_TMP/icon_${HALF}x${HALF}@2x.png"
  fi
done
iconutil -c icns "$ICONSET_TMP" -o "$ICNS" 2>&1 | tee -a "$LOGFILE"
rm -rf "$(dirname "$ICONSET_TMP")"
echo "   ✅ pd-macvanta.icns ($(du -h "$ICNS" | cut -f1))" | tee -a "$LOGFILE"

# ── Step 2: Bundle structure ──────────────────────────────────────────────────

echo "📁 Step 2: Creating bundle structure..." | tee -a "$LOGFILE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
echo "   ✅ $BUNDLE created" | tee -a "$LOGFILE"

# ── Step 3: Binary + cwd wrapper ──────────────────────────────────────────────

# The wrapper sets cwd to Contents/Resources/ so pd.ini and data/ are found
# at runtime — mirrors the starship-macalfa StarshipBin/Starship pattern.

echo "📦 Step 3: Binary + wrapper..." | tee -a "$LOGFILE"
cp "$BINARY" "$BUNDLE/Contents/MacOS/pd-macvanta-bin"
chmod +x "$BUNDLE/Contents/MacOS/pd-macvanta-bin"

cat > "$BUNDLE/Contents/MacOS/pd-macvanta" << 'WRAPPER'
#!/bin/zsh
export DYLD_FRAMEWORK_PATH="/Library/Frameworks:${DYLD_FRAMEWORK_PATH:-}"
cd "${0:A:h}/../Resources"
exec "${0:A:h}/pd-macvanta-bin" "$@"
WRAPPER
chmod +x "$BUNDLE/Contents/MacOS/pd-macvanta"
echo "   ✅ Launcher wrapper created (cwd → Resources/)" | tee -a "$LOGFILE"

# ── Step 4: Icon ──────────────────────────────────────────────────────────────

echo "🖼  Step 4: Icon..." | tee -a "$LOGFILE"
cp "$ICNS" "$BUNDLE/Contents/Resources/pd-macvanta.icns"
echo "   ✅ pd-macvanta.icns → Resources/" | tee -a "$LOGFILE"

# ── Step 5: Game assets ───────────────────────────────────────────────────────

echo "📦 Step 5: Game assets..." | tee -a "$LOGFILE"
cp -R "$DATA_DIR" "$BUNDLE/Contents/Resources/data"
echo "   ✅ data/ ($(du -sh "$BUNDLE/Contents/Resources/data" | cut -f1))" | tee -a "$LOGFILE"
[[ -f "$BUILD_DIR/pd.ini" ]] && cp "$BUILD_DIR/pd.ini" "$BUNDLE/Contents/Resources/pd.ini" && \
  echo "   ✅ pd.ini" | tee -a "$LOGFILE" || true

# ── Step 6: Info.plist ────────────────────────────────────────────────────────

echo "📄 Step 6: Info.plist..." | tee -a "$LOGFILE"
cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>pd-macvanta</string>
  <key>CFBundleDisplayName</key>       <string>pd-macvanta</string>
  <key>CFBundleIdentifier</key>        <string>io.macvanta.pd.$ROMID</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key>        <string>pd-macvanta</string>
  <key>CFBundleIconFile</key>          <string>pd-macvanta</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>LSMinimumSystemVersion</key>    <string>10.9</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>NSHumanReadableCopyright</key>  <string>mkoterski / fgsfdsfgs</string>
</dict>
</plist>
PLIST
echo "   ✅ Info.plist written (LSMinimumSystemVersion 10.9)" | tee -a "$LOGFILE"

# ── Step 7: Verify bundle ─────────────────────────────────────────────────────

echo "🔍 Step 7: Verify bundle..." | tee -a "$LOGFILE"
echo "   Binary: $(file "$BUNDLE/Contents/MacOS/pd-macvanta-bin" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
echo "   Icon:   $(du -h "$BUNDLE/Contents/Resources/pd-macvanta.icns" | cut -f1)" | tee -a "$LOGFILE"
echo "   data/:  $(du -sh "$BUNDLE/Contents/Resources/data" | cut -f1)" | tee -a "$LOGFILE"
echo "   Bundle: $(du -sh "$BUNDLE" | cut -f1) total" | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ pdmv-bundle-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📍 $BUNDLE" | tee -a "$LOGFILE"
echo "   📄 $LOGFILE" | tee -a "$LOGFILE"
echo "   👉 Test by double-clicking, then run ./pdmv-package-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
