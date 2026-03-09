#!/bin/zsh
# pdmv-build-macos.sh
# Perfect Dark macvanta — Intel Mac / macOS Tahoe build script
#
# Checks and installs all prerequisites inline (Homebrew, packages,
# SDL2.framework), then clones or updates fgsfdsfgs/perfect_dark,
# configures cmake with ROMID baked in, and compiles the binary.
# Each ROM region gets its own build-<romid>/ directory so all regions
# can coexist without rebuilding from scratch.
# ROMs are copied automatically from the central roms/ directory if present.
#
# Usage:
#   ./pdmv-build-macos.sh                    # build ntsc-final (default)
#   ./pdmv-build-macos.sh --rom pal-final    # 🇪🇺 build PAL region
#   ./pdmv-build-macos.sh --rom ntsc-1.0     # 🇺🇸 build NTSC v1.0
#   ./pdmv-build-macos.sh --rom jpn-final    # 🇯🇵 build Japan
#
# ROM layout (place files here — shared across all builds):
#   roms/pd.ntsc-final.z64   🇺🇸 N64 NTSC US v1.1 (recommended)
#   roms/pd.ntsc-1.0.z64     🇺🇸 N64 NTSC US v1.0
#   roms/pd.pal-final.z64    🇪🇺 N64 PAL
#   roms/pd.jpn-final.z64    🇯🇵 N64 Japan
#   roms/pd.gbc              🎮 GBC (optional — unlocks Transfer Pack content)
#
# Log output:
#   logs/build-<romid>-<timestamp>.log   ← top-level logs/, survives rm -rf perfect_dark/
#
# Supported ROMID values:
#   ntsc-final   🇺🇸 NTSC US v1.1  (recommended, most tested)
#   ntsc-1.0     🇺🇸 NTSC US v1.0  (supported, some known bugs)
#   pal-final    🇪🇺 PAL           (separate binary required)
#   jpn-final    🇯🇵 Japan         (separate binary required)
#
# CHANGELOG
# v0.16 (2026-03-09) - Added region flag emojis 🇺🇸🇪🇺🇯🇵 to ROM layout,
#                      ROMID descriptions, and Step 9 log output
# v0.15 (2026-03-09) - Fix: upstream cmake names binary pd.<arch> (e.g. pd.x86_64),
#                      not pd — use find to locate built binary and rename to pd.<romid>;
#                      Step 8: show build dir listing on failure for easier diagnosis
# v0.14 (2026-03-09) - Fix: log file moved to top-level logs/ — survives rm -rf
#                      perfect_dark/ during stale-clone recovery
# v0.13 (2026-03-09) - Step 9: copy pd.gbc from roms/ → data/ if present
# v0.12 (2026-03-09) - Fix: clone check validates CMakeLists.txt exists;
#                      ROM auto-copy from central roms/; ROM check after mkdir -p;
#                      SDL2 install: drop -v flag
# v0.11 (2026-03-09) - Inline dep check/install; multi-ROM --rom flag;
#                      per-region build dirs; binary renamed pd.<romid>
# v0.10 (2026-03-09) - Initial version

set -eo pipefail
VERSION="0.16"
SCRIPT_DIR="${0:A:h}"
SDL2_VER="2.30.9"

# ── Parse arguments ───────────────────────────────────────────────────────────

ROMID="ntsc-final"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom) ROMID="$2"; shift 2 ;;
    *) echo "Usage: $0 [--rom ntsc-final|ntsc-1.0|pal-final|jpn-final]" >&2; exit 1 ;;
  esac
done

# Friendly region label for log output
case "$ROMID" in
  ntsc-final) REGION_LABEL="🇺🇸 NTSC US v1.1 (recommended)" ;;
  ntsc-1.0)   REGION_LABEL="🇺🇸 NTSC US v1.0" ;;
  pal-final)  REGION_LABEL="🇪🇺 PAL" ;;
  jpn-final)  REGION_LABEL="🇯🇵 Japan" ;;
  *)          REGION_LABEL="$ROMID" ;;
esac

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
BINARY="$BUILD_DIR/pd.$ROMID"
DATA_DIR="$BUILD_DIR/data"
ROM_SOURCE="$SCRIPT_DIR/roms/pd.$ROMID.z64"
ROM_FILE="$DATA_DIR/pd.$ROMID.z64"
GBC_SOURCE="$SCRIPT_DIR/roms/pd.gbc"
GBC_FILE="$DATA_DIR/pd.gbc"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"

# Log lives at top-level logs/ — NOT inside perfect_dark/ — so it survives
# rm -rf perfect_dark/ during stale-clone recovery earlier in this script.
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/build-$ROMID-$TIMESTAMP.log"
mkdir -p "$LOG_DIR"

echo "🔨 pdmv-build-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   ROMID:   $ROMID  ($REGION_LABEL)" | tee -a "$LOGFILE"
echo "   Log:     $LOGFILE" | tee -a "$LOGFILE"

# ── Step 1: Homebrew ──────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🍺 Step 1: Homebrew" | tee -a "$LOGFILE"
if ! command -v brew &>/dev/null; then
  echo "   Installing Homebrew..." | tee -a "$LOGFILE"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOGFILE"
  # Intel Mac: Homebrew prefix is /usr/local on all macOS versions including Tahoe
  eval "$(/usr/local/bin/brew shellenv)"
fi
echo "   ✅ $(brew --version | head -1)" | tee -a "$LOGFILE"

# ── Step 2: Homebrew packages ─────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "📦 Step 2: Homebrew packages" | tee -a "$LOGFILE"
for pkg in cmake gcc python3 git ninja; do
  if ! brew list --versions "$pkg" &>/dev/null; then
    echo "   Installing $pkg..." | tee -a "$LOGFILE"
    brew install "$pkg" 2>&1 | tee -a "$LOGFILE"
  else
    echo "   ✅ $(brew list --versions "$pkg")" | tee -a "$LOGFILE"
  fi
done

# ── Step 3: SDL2.framework ────────────────────────────────────────────────────

# The port requires SDL2.framework installed system-wide at /Library/Frameworks.
# This is NOT the Homebrew sdl2 formula — the upstream build system links
# against the official .framework, not the dylib in /usr/local/opt/sdl2/lib.

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 3: SDL2.framework" | tee -a "$LOGFILE"
SDL2_FW="/Library/Frameworks/SDL2.framework"
if [[ ! -d "$SDL2_FW" ]]; then
  echo "   Downloading SDL2-${SDL2_VER}.dmg..." | tee -a "$LOGFILE"
  SDL2_DMG="$(mktemp /tmp/SDL2-XXXXXX.dmg)"
  curl -fsSL "https://libsdl.org/release/SDL2-${SDL2_VER}.dmg" -o "$SDL2_DMG" 2>&1 | tee -a "$LOGFILE"
  hdiutil attach "$SDL2_DMG" -mountpoint /Volumes/SDL2tmp -quiet
  # -r only: suppress per-file output, still copies correctly
  sudo cp -r /Volumes/SDL2tmp/SDL2.framework /Library/Frameworks/ 2>&1 | tee -a "$LOGFILE"
  hdiutil detach /Volumes/SDL2tmp -quiet
  rm -f "$SDL2_DMG"
  echo "   ✅ SDL2.framework installed" | tee -a "$LOGFILE"
else
  echo "   ✅ SDL2.framework present" | tee -a "$LOGFILE"
fi

# ── Step 4: Xcode CLT ─────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔧 Step 4: Xcode CLT" | tee -a "$LOGFILE"
if ! xcode-select -p &>/dev/null; then
  echo "   ❌ Xcode Command Line Tools not found." | tee -a "$LOGFILE"
  echo "      Run: xcode-select --install  then re-run this script." | tee -a "$LOGFILE"
  exit 1
fi
echo "   ✅ $(xcode-select -p)" | tee -a "$LOGFILE"

# ── Step 5: Clone or update ───────────────────────────────────────────────────

# Check for CMakeLists.txt — not just the directory — to detect stale/empty clones.
# A bare directory left by a failed clone would otherwise silently skip re-cloning.

echo "" | tee -a "$LOGFILE"
echo "📥 Step 5: Clone / update fgsfdsfgs/perfect_dark" | tee -a "$LOGFILE"
if [[ ! -f "$REPO_DIR/CMakeLists.txt" ]]; then
  [[ -d "$REPO_DIR" ]] && echo "   ⚠️  Repo dir exists but CMakeLists.txt missing — removing and re-cloning..." | tee -a "$LOGFILE"
  rm -rf "$REPO_DIR"
  echo "   Cloning..." | tee -a "$LOGFILE"
  git clone --recursive https://github.com/fgsfdsfgs/perfect_dark.git "$REPO_DIR" 2>&1 | tee -a "$LOGFILE"
else
  echo "   Repo exists — pulling latest..." | tee -a "$LOGFILE"
  git -C "$REPO_DIR" pull --recurse-submodules 2>&1 | tee -a "$LOGFILE"
fi

# ── Step 6: CMake configure ───────────────────────────────────────────────────

# ROMID is baked at compile time — each region requires its own binary.
# CMAKE_OSX_ARCHITECTURES=x86_64 ensures an Intel binary even on Rosetta.

echo "" | tee -a "$LOGFILE"
echo "⚙️  Step 6: CMake configure (ROMID=$ROMID, x86_64)" | tee -a "$LOGFILE"
cmake -G "Unix Makefiles" \
  -B"$BUILD_DIR" \
  -S"$REPO_DIR" \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DROMID="$ROMID" \
  2>&1 | tee -a "$LOGFILE"

# ── Step 7: Build ─────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔨 Step 7: Build ($(sysctl -n hw.logicalcpu) cores)" | tee -a "$LOGFILE"
cmake --build "$BUILD_DIR" --target pd --clean-first -j"$(sysctl -n hw.logicalcpu)" 2>&1 | tee -a "$LOGFILE"

# Upstream cmake names the output pd.<arch> (e.g. pd.x86_64) not pd.
# Find whatever was built at depth 1, exclude known non-binaries, rename to pd.<romid>.
BUILT_BIN="$(find "$BUILD_DIR" -maxdepth 1 -name "pd.*" \
  ! -name "*.log" ! -name "*.cmake" ! -name "*.z64" ! -name "*.gbc" \
  -type f | head -1)"
if [[ -n "$BUILT_BIN" && "$BUILT_BIN" != "$BINARY" ]]; then
  echo "   Renaming: ${BUILT_BIN:t} → pd.$ROMID" | tee -a "$LOGFILE"
  mv "$BUILT_BIN" "$BINARY"
fi

# ── Step 8: Binary validation ─────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔍 Step 8: Validate binary" | tee -a "$LOGFILE"
if [[ ! -f "$BINARY" ]]; then
  echo "   ❌ Binary not found at: $BINARY" | tee -a "$LOGFILE"
  echo "   Build dir contents:" | tee -a "$LOGFILE"
  ls -lh "$BUILD_DIR" 2>/dev/null | tee -a "$LOGFILE"
  echo "   Check log: $LOGFILE" | tee -a "$LOGFILE"
  exit 1
fi
chmod +x "$BINARY"
echo "   ✅ Binary: $(file "$BINARY" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
echo "   ✅ Size:   $(du -h "$BINARY" | cut -f1)" | tee -a "$LOGFILE"
echo "   ✅ Built:  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY")" | tee -a "$LOGFILE"

# ── Step 9: ROMs ──────────────────────────────────────────────────────────────

# data/ is created here — after cmake — so the path always exists before the check.
# N64 ROM: required. Auto-copied from roms/ if present there.
# GBC ROM: optional. Unlocks Transfer Pack content. Also auto-copied from roms/.

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 9: ROMs" | tee -a "$LOGFILE"
mkdir -p "$DATA_DIR"

# N64 ROM
if [[ -f "$ROM_FILE" ]]; then
  echo "   ✅ N64 ROM already in place [$REGION_LABEL]: $(du -h "$ROM_FILE" | cut -f1)" | tee -a "$LOGFILE"
elif [[ -f "$ROM_SOURCE" ]]; then
  echo "   📋 Copying N64 ROM [$REGION_LABEL] from roms/ → data/..." | tee -a "$LOGFILE"
  cp "$ROM_SOURCE" "$ROM_FILE"
  echo "   ✅ N64 ROM copied [$REGION_LABEL]: $(du -h "$ROM_FILE" | cut -f1)" | tee -a "$LOGFILE"
else
  echo "   ⚠️  N64 ROM [$REGION_LABEL] not found. Place it at either:" | tee -a "$LOGFILE"
  echo "      $ROM_SOURCE  ← recommended (shared across all builds)" | tee -a "$LOGFILE"
  echo "      $ROM_FILE" | tee -a "$LOGFILE"
fi

# GBC ROM (optional)
if [[ -f "$GBC_FILE" ]]; then
  echo "   ✅ GBC ROM already in place 🎮: $(du -h "$GBC_FILE" | cut -f1)" | tee -a "$LOGFILE"
elif [[ -f "$GBC_SOURCE" ]]; then
  echo "   📋 Copying GBC ROM 🎮 from roms/ → data/..." | tee -a "$LOGFILE"
  cp "$GBC_SOURCE" "$GBC_FILE"
  echo "   ✅ GBC ROM copied 🎮: $(du -h "$GBC_FILE" | cut -f1)" | tee -a "$LOGFILE"
else
  echo "   · GBC ROM not present 🎮 (optional — unlocks Transfer Pack content)" | tee -a "$LOGFILE"
  echo "      → place at roms/pd.gbc to enable" | tee -a "$LOGFILE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ pdmv-build-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📍 $BINARY" | tee -a "$LOGFILE"
echo "   📄 $LOGFILE" | tee -a "$LOGFILE"
echo "   👉 ./run-pdmv-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
