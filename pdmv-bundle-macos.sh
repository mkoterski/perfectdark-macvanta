#!/bin/zsh
# pdmv-bundle-macos.sh
# Perfect Dark macvanta — Intel Mac / macOS Tahoe app bundle creator
#
# Wraps the compiled pd.<romid> binary into a proper PerfectDark.app bundle.
# The binary is placed in Contents/MacOS/ behind a zsh wrapper that sets
# cwd to Contents/Resources/ so pd.ini and the data/ dir are found at runtime —
# the same pattern used by starship-macalfa for .o2r asset resolution.
#
# Usage:
#   ./pdmv-bundle-macos.sh                    # bundle ntsc-final (default)
#   ./pdmv-bundle-macos.sh --rom pal-final
#
# CHANGELOG
# v0.10 (2026-03-09) - Initial version; per-region ROM select; placeholder
#                      .icns generation; cwd wrapper; Info.plist

set -e
VERSION="0.10"
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
BUNDLE="$BUILD_DIR/PerfectDark.app"
ICNS="$BUILD_DIR/perfectdark.icns"
LOGFILE="$BUILD_DIR/logs/bundle-$(date '+%Y%m%d-%H%M').log"

mkdir -p "$BUILD_DIR/logs"
echo "🎁 pdmv-bundle-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   ROMID: $ROMID" | tee -a "$LOGFILE"

# ── Preflight checks ──────────────────────────────────────────────────────────

if [[ ! -f "$BINARY" ]]; then
  echo "❌ Binary not found — run ./pdmv-build-macos.sh --rom $ROMID first" | tee -a "$LOGFILE"
  exit 1
fi
if [[ ! -f "$DATA_DIR/pd.$ROMID.z64" ]]; then
  echo "❌ ROM not found at $DATA_DIR/pd.$ROMID.z64" | tee -a "$LOGFILE"
  exit 1
fi
echo "✅ Preflight passed" | tee -a "$LOGFILE"

# ── Step 1: Generate placeholder .icns ────────────────────────────────────────

# Replace with a real Perfect Dark iconset when artwork is available.
# Until then a dark navy placeholder is generated via Python — no ImageMagick needed.

if [[ ! -f "$ICNS" ]]; then
  echo "🖼  Step 1: Generating placeholder perfectdark.icns..." | tee -a "$LOGFILE"
  ICONSET_TMP="$(mktemp -d)/pd.iconset"
  mkdir -p "$ICONSET_TMP"
  python3 - "$ICONSET_TMP" << 'PYEOF'
import struct, zlib, sys, os
def mkpng(w, h):
    rows = bytearray()
    for y in range(h):
        rows += b'\x00'
        for x in range(w):
            rows += bytes([0, 0, 40, 255])  # dark navy
    compressed = zlib.compress(bytes(rows), 9)
    def chunk(name, data):
        c = zlib.crc32(name + data) & 0xffffffff
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', c)
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', compressed) +
            chunk(b'IEND', b''))
iconset = sys.argv[1]
for s in [16, 32, 64, 128, 256, 512]:
    with open(f'{iconset}/icon_{s}x{s}.png', 'wb') as f:     f.write(mkpng(s, s))
    with open(f'{iconset}/icon_{s}x{s}@2x.png', 'wb') as f:  f.write(mkpng(s*2, s*2))
PYEOF
  iconutil -c icns "$ICONSET_TMP" -o "$ICNS" 2>&1 | tee -a "$LOGFILE"
  rm -rf "$(dirname "$ICONSET_TMP")"
fi
echo "   ✅ perfectdark.icns ($(du -h "$ICNS" | cut -f1))" | tee -a "$LOGFILE"

# ── Step 2: Bundle structure ──────────────────────────────────────────────────

echo "📁 Step 2: Creating bundle structure..." | tee -a "$LOGFILE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources/data"
echo "   ✅ $BUNDLE created" | tee -a "$LOGFILE"

# ── Step 3: Binary + cwd wrapper ──────────────────────────────────────────────

# The wrapper sets cwd to Contents/Resources/ so pd.ini and data/ are found
# at runtime — mirrors the starship-macalfa StarshipBin/Starship pattern.

echo "📦 Step 3: Binary + wrapper..." | tee -a "$LOGFILE"
cp "$BINARY" "$BUNDLE/Contents/MacOS/PerfectDarkBin"
chmod +x "$BUNDLE/Contents/MacOS/PerfectDarkBin"

cat > "$BUNDLE/Contents/MacOS/PerfectDark" << 'WRAPPER'
#!/bin/zsh
export DYLD_FRAMEWORK_PATH="/Library/Frameworks:${DYLD_FRAMEWORK_PATH:-}"
cd "${0:A:h}/../Resources"
exec "${0:A:h}/PerfectDarkBin" "$@"
WRAPPER
chmod +x "$BUNDLE/Contents/MacOS/PerfectDark"
echo "   ✅ Launcher wrapper created (cwd → Resources/)" | tee -a "$LOGFILE"

# ── Step 4: Icon ──────────────────────────────────────────────────────────────

echo "🖼  Step 4: Icon..." | tee -a "$LOGFILE"
cp "$ICNS" "$BUNDLE/Contents/Resources/perfectdark.icns"
echo "   ✅ perfectdark.icns → Resources/" | tee -a "$LOGFILE"

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
  <key>CFBundleName</key>              <string>Perfect Dark</string>
  <key>CFBundleDisplayName</key>       <string>Perfect Dark</string>
  <key>CFBundleIdentifier</key>        <string>com.mkoterski.perfectdark-macvanta</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key>        <string>PerfectDark</string>
  <key>CFBundleIconFile</key>          <string>perfectdark</string>
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
echo "   Binary: $(file "$BUNDLE/Contents/MacOS/PerfectDarkBin" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
echo "   Icon:   $(du -h "$BUNDLE/Contents/Resources/perfectdark.icns" | cut -f1)" | tee -a "$LOGFILE"
echo "   data/:  $(du -sh "$BUNDLE/Contents/Resources/data" | cut -f1)" | tee -a "$LOGFILE"
echo "   Bundle: $(du -sh "$BUNDLE" | cut -f1) total" | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo "✅ pdmv-bundle-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📍 $BUNDLE" | tee -a "$LOGFILE"
echo "   👉 Test by double-clicking, then run ./pdmv-package-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
