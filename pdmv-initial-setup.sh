#!/bin/zsh
# pdmv-initial-setup.sh
# Perfect Dark macvanta — first-run setup for macOS Tahoe / Intel Mac
#
# Installs Xcode CLT, Homebrew, build dependencies, and SDL2.framework.
# Validates any ROMs already placed in their expected data/ directories.
# Safe to re-run: all steps are idempotent.
#
# Usage:
#   ./pdmv-initial-setup.sh
#
# Output:
#   perfectdark-macvanta/logs/initial-setup-<timestamp>.log
#
# CHANGELOG
# v0.10 (2026-03-09) - Initial version

set -eo pipefail
VERSION="0.10"
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
  echo "   Not found — launching installer. Complete the GUI prompt, then re-run." | tee -a "$LOGFILE"
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
    sudo cp -vr /Volumes/SDL2tmp/SDL2.framework /Library/Frameworks/ 2>&1 | tee -a "$LOGFILE"
    hdiutil detach /Volumes/SDL2tmp -quiet
    rm -f "$SDL2_DMG"
    echo "   ✅ SDL2.framework installed at $SDL2_FW" | tee -a "$LOGFILE"
  else
    echo "   ❌ Download failed — check network connection and retry." | tee -a "$LOGFILE"
    exit 1
  fi
else
  SDL2_INSTALLED="$(defaults read "$SDL2_FW/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 'unknown')"
  echo "   ✅ SDL2.framework already present (v$SDL2_INSTALLED)" | tee -a "$LOGFILE"
fi

# ── Step 5: ROM status ────────────────────────────────────────────────────────

# Each ROM ID requires a separate cmake build and its own binary.
# Place ROMs at the paths shown below before running pdmv-build-macos.sh.
# MD5 checksums from the upstream fgsfdsfgs/perfect_dark README.

echo "" | tee -a "$LOGFILE"
echo "🎮 Step 5: ROM status" | tee -a "$LOGFILE"
echo "   Place ROM files at these paths before building:" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

declare -A ROM_MD5=(
  [ntsc-final]="e03b088b6ac9e0080440efed07c1e40f"
  [ntsc-1.0]="7f4171b0c8d17815be37913f535e4e93"
  [pal-final]="d9b5cd305d228424891ce38e71bc9213"
  [jpn-final]="538d2b75945eae069b29c46193e74790"
)
for rid in ntsc-final ntsc-1.0 pal-final jpn-final; do
  ROM_PATH="$SCRIPT_DIR/perfect_dark/build-$rid/data/pd.$rid.z64"
  if [[ -f "$ROM_PATH" ]]; then
    ACTUAL="$(md5 -q "$ROM_PATH")"
    EXPECTED="${ROM_MD5[$rid]}"
    if [[ "$ACTUAL" == "$EXPECTED" ]]; then
      echo "   ✅ $rid — $(du -h "$ROM_PATH" | cut -f1)  MD5 OK" | tee -a "$LOGFILE"
    else
      echo "   ⚠️  $rid — MD5 MISMATCH" | tee -a "$LOGFILE"
      echo "       got:      $ACTUAL" | tee -a "$LOGFILE"
      echo "       expected: $EXPECTED" | tee -a "$LOGFILE"
    fi
  else
    echo "   · $rid — not present" | tee -a "$LOGFILE"
    echo "       → $ROM_PATH" | tee -a "$LOGFILE"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ pdmv-initial-setup.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "   Next steps:" | tee -a "$LOGFILE"
echo "   1. Place at least one ROM in the path shown above" | tee -a "$LOGFILE"
echo "   2. ./pdmv-build-macos.sh                     # builds ntsc-final (default)" | tee -a "$LOGFILE"
echo "   3. ./pdmv-build-macos.sh --rom pal-final      # build a second region" | tee -a "$LOGFILE"
echo "   4. ./run-pdmv-macos.sh                        # launch ntsc-final" | tee -a "$LOGFILE"
echo "   5. ./run-pdmv-macos.sh --rom pal-final        # launch PAL" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
