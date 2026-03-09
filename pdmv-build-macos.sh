#!/bin/zsh
# pdmv-build-macos.sh
# Perfect Dark macvanta — Intel Mac / macOS Tahoe build script
#
# Checks and installs all prerequisites inline (Homebrew, packages,
# SDL2.framework), then clones or updates fgsfdsfgs/perfect_dark,
# configures cmake with ROMID baked in, and compiles the binary.
# Each ROM region gets its own build-<romid>/ directory so all regions
# can coexist without rebuilding from scratch.
#
# Usage:
#   ./pdmv-build-macos.sh                    # build ntsc-final (default)
#   ./pdmv-build-macos.sh --rom pal-final    # build PAL region
#   ./pdmv-build-macos.sh --rom ntsc-1.0
#   ./pdmv-build-macos.sh --rom jpn-final
#
# Supported ROMID values:
#   ntsc-final   NTSC US v1.1  (recommended, most tested)
#   ntsc-1.0     NTSC US v1.0  (supported, some known bugs)
#   pal-final    PAL           (separate binary required)
#   jpn-final    Japan         (separate binary required)
#
# CHANGELOG
# v0.11 (2026-03-09) - Inline dep check/install; multi-ROM --rom flag;
#                      per-region build dirs; binary renamed pd.<romid>

set -eo pipefail
VERSION="0.11"
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

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
BINARY="$BUILD_DIR/pd.$ROMID"
DATA_DIR="$BUILD_DIR/data"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
LOGFILE="$BUILD_DIR/logs/build-$TIMESTAMP.log"

mkdir -p "$BUILD_DIR/logs"
echo "🔨 pdmv-build-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   ROMID: $ROMID" | tee -a "$LOGFILE"

# ── Step 1: Homebrew ──────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🍺 Step 1: Homebrew" | tee -a "$LOGFILE"
if ! command -v brew &>/dev/null; then
  echo "   Installing Homebrew..." | tee -a "$LOGFILE"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOGFILE"
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

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 3: SDL2.framework" | tee -a "$LOGFILE"
SDL2_FW="/Library/Frameworks/SDL2.framework"
if [[ ! -d "$SDL2_FW" ]]; then
  echo "   Downloading SDL2-${SDL2_VER}.dmg..." | tee -a "$LOGFILE"
  SDL2_DMG="$(mktemp /tmp/SDL2-XXXXXX.dmg)"
  curl -fsSL "https://libsdl.org/release/SDL2-${SDL2_VER}.dmg" -o "$SDL2_DMG" 2>&1 | tee -a "$LOGFILE"
  hdiutil attach "$SDL2_DMG" -mountpoint /Volumes/SDL2tmp -quiet
  sudo cp -vr /Volumes/SDL2tmp/SDL2.framework /Library/Frameworks/ 2>&1 | tee -a "$LOGFILE"
  hdiutil detach /Volumes/SDL2tmp -quiet
  rm -f "$SDL2_DMG"
  echo "   ✅ SDL2.framework installed" | tee -a "$LOGFILE"
else
  echo "   ✅ SDL2.framework present" | tee -a "$LOGFILE"
fi

# ── Step 4: Xcode CLT check ───────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔧 Step 4: Xcode CLT" | tee -a "$LOGFILE"
if ! xcode-select -p &>/dev/null; then
  echo "   ❌ Xcode Command Line Tools not found." | tee -a "$LOGFILE"
  echo "      Run: xcode-select --install  then re-run this script." | tee -a "$LOGFILE"
  exit 1
fi
echo "   ✅ $(xcode-select -p)" | tee -a "$LOGFILE"

# ── Step 5: Clone or update ───────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "📥 Step 5: Clone / update fgsfdsfgs/perfect_dark" | tee -a "$LOGFILE"
if [[ ! -d "$REPO_DIR" ]]; then
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

# Rename output to include ROMID so multiple builds coexist cleanly
[[ -f "$BUILD_DIR/pd" ]] && mv "$BUILD_DIR/pd" "$BINARY"

# ── Step 8: Binary validation ─────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔍 Step 8: Validate" | tee -a "$LOGFILE"
if [[ ! -f "$BINARY" ]]; then
  echo "   ❌ Binary not found — build failed. Check log: $LOGFILE" | tee -a "$LOGFILE"
  exit 1
fi
chmod +x "$BINARY"
echo "   Binary: $(file "$BINARY" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
echo "   Size:   $(du -h "$BINARY" | cut -f1)" | tee -a "$LOGFILE"

# ── Step 9: Data dir + ROM check ──────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 9: ROM check" | tee -a "$LOGFILE"
mkdir -p "$DATA_DIR"
ROM_FILE="$DATA_DIR/pd.$ROMID.z64"
if [[ ! -f "$ROM_FILE" ]]; then
  echo "   ⚠️  ROM not found at:" | tee -a "$LOGFILE"
  echo "      $ROM_FILE" | tee -a "$LOGFILE"
  echo "   Place your ROM there before running." | tee -a "$LOGFILE"
else
  echo "   ✅ ROM present: $(du -h "$ROM_FILE" | cut -f1)" | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo "✅ pdmv-build-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📍 $BINARY" | tee -a "$LOGFILE"
echo "   👉 ./run-pdmv-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
