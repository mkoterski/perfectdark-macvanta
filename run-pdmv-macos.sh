#!/bin/zsh
# run-pdmv-macos.sh
# Perfect Dark macvanta — Intel Mac / macOS Tahoe launcher
#
# Usage:
#   ./run-pdmv-macos.sh                    # launch ntsc-final with OpenGL
#   ./run-pdmv-macos.sh --rom pal-final    # launch PAL region
#   ./run-pdmv-macos.sh --opengl           # force OpenGL (default on Intel)
#   ./run-pdmv-macos.sh --restore-cfg      # restore latest pd.ini backup and exit
#
# Backend handling:
#   Default is OpenGL — required on Intel Mac. The port uses OpenGL 3.0+ via
#   SDL2 and does not support Metal. DYLD_FRAMEWORK_PATH ensures SDL2.framework
#   is resolved from /Library/Frameworks at runtime.
#
# Config backup:
#   pd.ini is backed up before each session and restored on clean exit,
#   Ctrl-C (SIGINT), or SIGTERM via trap — same pattern as starship-macalfa.
#
# Log output:
#   logs/run-<romid>-<timestamp>.log   ← top-level logs/, last 5 runs kept per region
#   logs/pd.ini.backup-<romid>-<timestamp>
#
# CHANGELOG
# v0.12 (2026-03-09) - Log moved to top-level logs/ (consistent with build script,
#                      survives perfect_dark/ deletion); INI_BACKUP moved to same
#                      top-level logs/ so --restore-cfg finds them correctly;
#                      log rotation: keep last 5 run logs per ROMID
# v0.11 (2026-03-09) - Multi-ROM --rom flag; per-region BUILD_DIR/BINARY;
#                      DYLD_FRAMEWORK_PATH for SDL2.framework;
#                      pd.ini backup/restore; --restore-cfg
# v0.10 (2026-03-09) - Initial version

set -eo pipefail
VERSION="0.12"
SCRIPT_DIR="${0:A:h}"
LOG_KEEP=5   # number of run logs to retain per ROMID

# ── Parse arguments ───────────────────────────────────────────────────────────

ROMID="ntsc-final"
BACKEND="opengl"   # Intel Mac default — Metal not supported by this port
RESTORE_CFG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom)         ROMID="$2"; shift 2 ;;
    --opengl)      BACKEND="opengl"; shift ;;
    --restore-cfg) RESTORE_CFG=1; shift ;;
    *) echo "Usage: $0 [--rom ntsc-final|ntsc-1.0|pal-final|jpn-final] [--opengl] [--restore-cfg]" >&2; exit 1 ;;
  esac
done

# Region label for log output
case "$ROMID" in
  ntsc-final) REGION_LABEL="🇺🇸 NTSC US v1.1" ;;
  ntsc-1.0)   REGION_LABEL="🇺🇸 NTSC US v1.0" ;;
  pal-final)  REGION_LABEL="🇪🇺 PAL" ;;
  jpn-final)  REGION_LABEL="🇯🇵 Japan" ;;
  *)          REGION_LABEL="$ROMID" ;;
esac

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
BINARY="$BUILD_DIR/pd.$ROMID"
DATA_DIR="$BUILD_DIR/data"
INI="$BUILD_DIR/pd.ini"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"

# Logs live at top-level logs/ — consistent with pdmv-build-macos.sh,
# and survives rm -rf perfect_dark/ if ever needed.
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/run-$ROMID-$TIMESTAMP.log"
INI_BACKUP="$LOG_DIR/pd.ini.backup-$ROMID-$TIMESTAMP"

mkdir -p "$LOG_DIR"

# ── Restore mode ──────────────────────────────────────────────────────────────

if (( RESTORE_CFG )); then
  LATEST_BAK="$(ls -t "$LOG_DIR"/pd.ini.backup-$ROMID-* 2>/dev/null | head -1 || true)"
  if [[ -n "$LATEST_BAK" ]]; then
    cp "$LATEST_BAK" "$INI"
    echo "✅ Restored: $INI"
    echo "   From: $LATEST_BAK"
  else
    echo "⚠️  No pd.ini backup found for $ROMID in $LOG_DIR/" >&2; exit 1
  fi
  exit 0
fi

echo "🎮 run-pdmv-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   ROMID:   $ROMID  ($REGION_LABEL)" | tee -a "$LOGFILE"
echo "   Backend: $BACKEND (Intel Mac — OpenGL only)" | tee -a "$LOGFILE"
echo "   Log:     $LOGFILE" | tee -a "$LOGFILE"

# ── Config backup + trap restore ──────────────────────────────────────────────

# pd.ini is backed up before every launch so the pre-session state is
# recoverable if the game crashes. Restored automatically via trap below.

INI_MODIFIED=0

_restore_ini() {
  if (( INI_MODIFIED )) && [[ -f "$INI_BACKUP" ]]; then
    cp "$INI_BACKUP" "$INI"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] pd.ini restored from backup" | tee -a "$LOGFILE"
  fi
}

trap _restore_ini EXIT INT TERM

if [[ -f "$INI" ]]; then
  cp "$INI" "$INI_BACKUP"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Config backup → ${INI_BACKUP##$SCRIPT_DIR/}" | tee -a "$LOGFILE"
  INI_MODIFIED=1
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') [warn] pd.ini not found — will be created on first launch" | tee -a "$LOGFILE"
fi

# ── Preflight checks ──────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Preflight checks..." | tee -a "$LOGFILE"

if [[ ! -f "$BINARY" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [error] Binary not found: $BINARY" | tee -a "$LOGFILE"
  echo "   Run: ./pdmv-build-macos.sh --rom $ROMID" | tee -a "$LOGFILE"
  exit 1
fi

ROM_FILE="$DATA_DIR/pd.$ROMID.z64"
if [[ ! -f "$ROM_FILE" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [error] ROM not found: $ROM_FILE" | tee -a "$LOGFILE"
  exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Binary: $(du -h "$BINARY" | cut -f1)" | tee -a "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [info] ROM:    $(du -h "$ROM_FILE" | cut -f1)  [$REGION_LABEL]" | tee -a "$LOGFILE"

# ── DYLD paths ────────────────────────────────────────────────────────────────

# SDL2.framework is installed system-wide at /Library/Frameworks.
# DYLD_FRAMEWORK_PATH ensures it is resolved even if SIP alters the search order.
export DYLD_FRAMEWORK_PATH="/Library/Frameworks:${DYLD_FRAMEWORK_PATH:-}"
export DYLD_LIBRARY_PATH="/usr/local/lib:${DYLD_LIBRARY_PATH:-}"

# ── Launch ────────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Launching Perfect Dark ($ROMID, OpenGL)..." | tee -a "$LOGFILE"
cd "$BUILD_DIR"
./"${BINARY:t}" 2>&1 | tee -a "$LOGFILE"
EXIT_CODE=${pipestatus[1]}

echo "" | tee -a "$LOGFILE"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Perfect Dark exited cleanly (code 0)" | tee -a "$LOGFILE"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') [warn] Perfect Dark exited with code $EXIT_CODE" | tee -a "$LOGFILE"
fi

# ── Log rotation ──────────────────────────────────────────────────────────────

# Keep only the last LOG_KEEP run logs for this ROMID.
# Avoids unbounded log accumulation across many play sessions.

RUN_LOGS=("${(@f)$(ls -t "$LOG_DIR"/run-$ROMID-*.log 2>/dev/null)}")
if (( ${#RUN_LOGS[@]} > LOG_KEEP )); then
  TO_DELETE=("${RUN_LOGS[@]:$LOG_KEEP}")
  for old in "${TO_DELETE[@]}"; do
    rm -f "$old"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Log rotated: ${old:t}" | tee -a "$LOGFILE"
  done
fi

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ run-pdmv-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📄 $LOGFILE" | tee -a "$LOGFILE"
echo "   💾 Keeping last $LOG_KEEP run logs for $ROMID" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
