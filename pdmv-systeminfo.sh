#!/bin/zsh
# pdmv-systeminfo.sh
# Perfect Dark macvanta — system snapshot for bug reports
#
# Captures hardware, GPU, macOS version, Homebrew deps, and PD build info
# into a single text file. Called automatically by pdmv-collect-crash.sh.
#
# Usage:
#   ./pdmv-systeminfo.sh                       # write to build-ntsc-final/logs/
#   ./pdmv-systeminfo.sh --rom pal-final       # target PAL build dir
#   ./pdmv-systeminfo.sh --out /some/dir       # write to specified directory
#   ./pdmv-systeminfo.sh --print               # also print to stdout
#
# CHANGELOG
# v0.10 (2026-03-09) - Initial version; adapted from sysinfo-6.sh v0.11;
#                      multi-ROM --rom flag; pd.ini config read; pd binary

set -eo pipefail
VERSION="0.10"
SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
ROMID="ntsc-final"
PRINT_STDOUT=0

# ── Parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom)   ROMID="$2";    shift 2 ;;
    --out)   OUT_DIR="$2";  shift 2 ;;
    --print) PRINT_STDOUT=1; shift ;;
    *) echo "Usage: $0 [--rom <id>] [--out <dir>] [--print]" >&2; exit 1 ;;
  esac
done

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
OUT_DIR="${OUT_DIR:-$BUILD_DIR/logs}"
mkdir -p "$OUT_DIR"
OUTFILE="$OUT_DIR/sysinfo-$TIMESTAMP.txt"

# Helper — write to file, optionally stdout
# || true prevents set -e from firing on arithmetic false (PRINT_STDOUT=0)
w() {
  echo "$@" >> "$OUTFILE"
  (( PRINT_STDOUT )) && echo "$@" || true
}

# ── Header ────────────────────────────────────────────────────────────────────

w "════════════════════════════════════════════════════════════════"
w " Perfect Dark macvanta — System Snapshot"
w " pdmv-systeminfo.sh v$VERSION — $(date)"
w " ROMID: $ROMID"
w "════════════════════════════════════════════════════════════════"
w ""

# ── macOS & Hardware ──────────────────────────────────────────────────────────

w "── macOS ────────────────────────────────────────────────────────"
sw_vers >> "$OUTFILE" 2>&1
w "Kernel: $(uname -r)"
w "Architecture: $(uname -m)"
w ""

w "── Hardware ─────────────────────────────────────────────────────"
system_profiler SPHardwareDataType 2>/dev/null \
  | grep -E 'Model Name|Model Identifier|Processor|Cores|Memory|Serial' \
  | sed 's/^[[:space:]]*/  /' >> "$OUTFILE"
w ""

# ── GPU & OpenGL ──────────────────────────────────────────────────────────────

# macOS Tahoe no longer exposes OpenGL version via system_profiler.
# The GL renderer string requires an active context — not available from a script.
# Run the game with OpenGL and check Console.app for the renderer string.

w "── GPU / OpenGL ─────────────────────────────────────────────────"
system_profiler SPDisplaysDataType 2>/dev/null \
  | grep -E 'Chipset|VRAM|Metal|Vendor|Device|Resolution|Pixel' \
  | sed 's/^[[:space:]]*/  /' >> "$OUTFILE"
system_profiler SPDisplaysDataType 2>/dev/null \
  | grep -iE 'OpenGL|GLSL' \
  | sed 's/^[[:space:]]*/  /' >> "$OUTFILE" || true
w "  Note: GL renderer string requires active context (launch game to capture)"
BINARY="$BUILD_DIR/pd.$ROMID"
w "  Linked SDL2: $(otool -L "$BINARY" 2>/dev/null | grep -i sdl | xargs || echo 'n/a')"
w ""

# ── Homebrew dependencies ─────────────────────────────────────────────────────

w "── Homebrew dependencies ────────────────────────────────────────"
if command -v brew &>/dev/null; then
  for pkg in cmake gcc python3 git ninja; do
    VER="$(brew list --versions "$pkg" 2>/dev/null || echo 'not installed')"
    w "  $pkg: $VER"
  done
  w "  SDL2.framework: $([[ -d /Library/Frameworks/SDL2.framework ]] && \
      echo "present ($(defaults read /Library/Frameworks/SDL2.framework/Resources/Info.plist CFBundleShortVersionString 2>/dev/null || echo 'version unknown'))" || \
      echo 'NOT FOUND — run ./pdmv-initial-setup.sh')"
else
  w "  brew not found"
fi
w ""

# ── Perfect Dark binary ───────────────────────────────────────────────────────

w "── Perfect Dark binary ($ROMID) ─────────────────────────────────"
if [[ -f "$BINARY" ]]; then
  w "  Path:   $BINARY"
  w "  Size:   $(du -h "$BINARY" | cut -f1)"
  w "  Arch:   $(file "$BINARY" | cut -d: -f2 | xargs)"
  w "  Built:  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY")"
  w "  Linked libs (otool -L):"
  otool -L "$BINARY" 2>/dev/null | sed 's/^/    /' >> "$OUTFILE" || true
else
  w "  Binary not found at $BINARY"
  w "  Run: ./pdmv-build-macos.sh --rom $ROMID"
fi
w ""

# ── pd.ini config ─────────────────────────────────────────────────────────────

w "── pd.ini ───────────────────────────────────────────────────────"
INI="$BUILD_DIR/pd.ini"
if [[ -f "$INI" ]]; then
  head -40 "$INI" >> "$OUTFILE" 2>/dev/null || true
else
  w "  pd.ini not found at $INI"
  w "  (created automatically on first launch)"
fi
w ""

# ── Disk & Memory ─────────────────────────────────────────────────────────────

w "── Disk & Memory ────────────────────────────────────────────────"
w "  Disk (project): $(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)"
w "  Disk (build):   $(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)"
df -h "$SCRIPT_DIR" 2>/dev/null | tail -1 \
  | awk '{print "  Free on volume: " $4}' >> "$OUTFILE"
vm_stat 2>/dev/null \
  | grep -E 'Pages (free|active|wired)' \
  | awk '{printf "  vm_stat: %s\n", $0}' >> "$OUTFILE" || true
w ""

# ── Footer ────────────────────────────────────────────────────────────────────

w "════════════════════════════════════════════════════════════════"
w " End of snapshot — $(date)"
w "════════════════════════════════════════════════════════════════"

echo "✅ pdmv-systeminfo.sh v$VERSION → $OUTFILE"
