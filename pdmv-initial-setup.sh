#!/bin/zsh
# pdmv-initial-setup.sh
# Perfect Dark macvanta — first-run setup for macOS Tahoe / Intel Mac
#
# Installs Xcode CLT, Homebrew, build dependencies, and SDL2.framework.
# Validates any ROMs already present in the central roms/ directory.
# Safe to re-run: all steps are idempotent.
#
# Usage:
#   ./pdmv-initial-setup.sh
#
# Output:
#   perfectdark-macvanta/logs/initial-setup-<timestamp>.log
#
# ROM layout (place files here before building):
#   roms/pd.ntsc-final.z64   🇺🇸 N64 NTSC US v1.1 (recommended)
#   roms/pd.ntsc-1.0.z64     🇺🇸 N64 NTSC US v1.0
#   roms/pd.pal-final.z64    🇪🇺 N64 PAL
#   roms/pd.jpn-final.z64    🇯🇵 N64 Japan
#   roms/pd.gbc              🎮 GBC (optional — unlocks Transfer Pack content)
#
# CHANGELOG
# v0.13 (2026-03-09) - Added region flag emojis 🇺🇸🇪🇺🇯🇵 to ROM status output
# v0.12 (2026-03-09) - ROM check: added pd.gbc (GBC ROM, optional);
#                      ROM check now reads from central roms/ directory
# v0.11 (2026-03-09) - SDL2 install: drop -v flag (less verbose output);
#                      ROM check moved to roms/ (not build-*/data/)
# v0.10 (2026-03-09) - Initial version

set -eo pipefail
VERSION="0.13"
SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/initial-setup-$TIMESTAMP.log"
SDL2_VER="2.30.9"

mkdir -p "$LOG_DIR"
echo "🛠 pdmv-initial-setup.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   macOS: $(sw_vers -productName) $(sw_vers -productVersion)" | tee -a "$LOGFILE"
echo "   Arch:  $(uname -m)" | tee -a "$LOGFILE"

# ── Architecture guard ────────────────────────────────────────────────────────

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "⚠️  Non-Intel architecture detected ($(uname -m))." | tee -a "$LOGFILE"
  echo "   This project targets Intel x86_64 Macs." | tee -a "$LOGFILE"
  echo "   On Apple Silicon, use Rosetta 2 or build a native arm64 variant." | tee -a "$LOGFILE"
fi

# ── Step 1: Xcode Command Line Tools ─────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🔧 Step 1: Xcode Command Line Tools" | tee -a "$LOGFILE"
if ! xcode-select -p &>/dev/null; then
  echo "   Not found — launching installer." | tee -a "$LOGFILE"
  echo "   Complete the GUI prompt, then re-run this script." | tee -a "$LOGFILE"
  xcode-select --install
  exit 0
fi
echo "   ✅ $(xcode-select -p)" | tee -a "$LOGFILE"

# ── Step 2: Homebrew ──────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "🍺 Step 2: Homebrew" | tee -a "$LOGFILE"
if ! command -v brew &>/dev/null; then
  echo "   Installing Homebrew..." | tee -a "$LOGFILE"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOGFILE"
  # Intel Mac: Homebrew prefix is /usr/local on all macOS versions including Tahoe
  eval "$(/usr/local/bin/brew shellenv)"
fi
echo "   ✅ $(brew --version | head -1)" | tee -a "$LOGFILE"

# ── Step 3: Homebrew packages ─────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "📦 Step 3: Homebrew packages" | tee -a "$LOGFILE"
for pkg in cmake gcc python3 git ninja; do
  if ! brew list --versions "$pkg" &>/dev/null; then
    echo "   Installing $pkg..." | tee -a "$LOGFILE"
    brew install "$pkg" 2>&1 | tee -a "$LOGFILE"
  else
    echo "   ✅ $(brew list --versions "$pkg")" | tee -a "$LOGFILE"
  fi
done

# ── Step 4: SDL2.framework ────────────────────────────────────────────────────

# The port requires SDL2.framework installed system-wide at /Library/Frameworks.
# This is NOT the Homebrew sdl2 formula — the upstream build system links
# against the official .framework, not the dylib in /usr/local/opt/sdl2/lib.

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 4: SDL2.framework (system-wide)" | tee -a "$LOGFILE"
SDL2_FW="/Library/Frameworks/SDL2.framework"
if [[ ! -d "$SDL2_FW" ]]; then
  echo "   Downloading SDL2-${SDL2_VER}.dmg..." | tee -a "$LOGFILE"
  SDL2_DMG="$(mktemp /tmp/SDL2-XXXXXX.dmg)"
  if curl -fsSL "https://libsdl.org/release/SDL2-${SDL2_VER}.dmg" -o "$SDL2_DMG" 2>&1 | tee -a "$LOGFILE"; then
    hdiutil attach "$SDL2_DMG" -mountpoint /Volumes/SDL2tmp -quiet
    # -r only: suppress per-file output, still copies correctly
    sudo cp -r /Volumes/SDL2tmp/SDL2.framework /Library/Frameworks/ 2>&1 | tee -a "$LOGFILE"
    hdiutil detach /Volumes/SDL2tmp -quiet
    rm -f "$SDL2_DMG"
    echo "   ✅ SDL2.framework installed at $SDL2_FW" | tee -a "$LOGFILE"
  else
    echo "   ❌ SDL2 download failed. Check network and retry." | tee -a "$LOGFILE"
    exit 1
  fi
else
  SDL2_INSTALLED="$(defaults read "$SDL2_FW/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 'unknown')"
  echo "   ✅ SDL2.framework already present (v$SDL2_INSTALLED)" | tee -a "$LOGFILE"
fi

# ── Step 5: ROM status ────────────────────────────────────────────────────────

# ROMs live in the central roms/ directory (gitignored).
# The build script copies N64 ROMs into build-<romid>/data/ automatically.
# The GBC ROM is also copied into data/ — it unlocks Transfer Pack content.
# MD5 checksums for N64 ROMs from fgsfdsfgs/perfect_dark README.
# Note: ntsc-1.0 is supported but has known gameplay bugs upstream.

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 5: ROM status" | tee -a "$LOGFILE"
echo "   Checking roms/ directory: $SCRIPT_DIR/roms/" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

declare -A ROM_MD5=(
  [ntsc-final]="e03b088b6ac9e0080440efed07c1e40f"
  [ntsc-1.0]="7f4171b0c8d17815be37913f535e4e93"
  [pal-final]="d9b5cd305d228424891ce38e71bc9213"
  [jpn-final]="538d2b75945eae069b29c46193e74790"
)
declare -A ROM_LABEL=(
  [ntsc-final]="🇺🇸 NTSC US v1.1 (recommended)"
  [ntsc-1.0]="🇺🇸 NTSC US v1.0"
  [pal-final]="🇪🇺 PAL"
  [jpn-final]="🇯🇵 Japan"
)

echo "   N64 ROMs (required — at least ntsc-final):" | tee -a "$LOGFILE"
for rid in ntsc-final ntsc-1.0 pal-final jpn-final; do
  ROM_PATH="$SCRIPT_DIR/roms/pd.$rid.z64"
  LABEL="${ROM_LABEL[$rid]}"
  if [[ -f "$ROM_PATH" ]]; then
    ACTUAL="$(md5 -q "$ROM_PATH")"
    EXPECTED="${ROM_MD5[$rid]}"
    if [[ "$ACTUAL" == "$EXPECTED" ]]; then
      echo "   ✅ $LABEL — $(du -h "$ROM_PATH" | cut -f1)  MD5 OK" | tee -a "$LOGFILE"
    else
      echo "   ⚠️  $LABEL — MD5 MISMATCH" | tee -a "$LOGFILE"
      echo "       got:      $ACTUAL" | tee -a "$LOGFILE"
      echo "       expected: $EXPECTED" | tee -a "$LOGFILE"
    fi
  else
    echo "   · $LABEL — not present → roms/pd.$rid.z64" | tee -a "$LOGFILE"
  fi
done

echo "" | tee -a "$LOGFILE"
echo "   GBC ROM (optional — unlocks Transfer Pack content):" | tee -a "$LOGFILE"
GBC_PATH="$SCRIPT_DIR/roms/pd.gbc"
if [[ -f "$GBC_PATH" ]]; then
  echo "   ✅ 🎮 pd.gbc — $(du -h "$GBC_PATH" | cut -f1)  present" | tee -a "$LOGFILE"
else
  echo "   · 🎮 pd.gbc — not present (optional) → roms/pd.gbc" | tee -a "$LOGFILE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ pdmv-initial-setup.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "   Next steps:" | tee -a "$LOGFILE"
echo "   1. Place ROM(s) in roms/  (see paths above)" | tee -a "$LOGFILE"
echo "   2. ./pdmv-build-macos.sh                     # 🇺🇸 builds ntsc-final (default)" | tee -a "$LOGFILE"
echo "   3. ./pdmv-build-macos.sh --rom pal-final      # 🇪🇺 build PAL" | tee -a "$LOGFILE"
echo "   4. ./pdmv-build-macos.sh --rom jpn-final      # 🇯🇵 build Japan" | tee -a "$LOGFILE"
echo "   5. ./run-pdmv-macos.sh                        # launch ntsc-final" | tee -a "$LOGFILE"
echo "   6. ./run-pdmv-macos.sh --rom pal-final        # launch PAL" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
