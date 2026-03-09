#!/bin/zsh
# pdmv-collect-crash.sh
# Perfect Dark macvanta — macOS crash report collector
#
# Collects the most recent Perfect Dark crash reports from macOS
# DiagnosticReports and copies them into build-<romid>/logs/ alongside
# run logs. Attach the output folder when filing OpenGL bug reports.
#
# Usage:
#   ./pdmv-collect-crash.sh                    # collect last 5 (ntsc-final)
#   ./pdmv-collect-crash.sh --rom pal-final    # target PAL build
#   ./pdmv-collect-crash.sh -n 10              # collect last N reports
#   ./pdmv-collect-crash.sh --list             # list only, no copy
#
# CHANGELOG
# v0.10 (2026-03-09) - Initial version; adapted from collect-crash-5.sh v0.10;
#                      multi-ROM --rom flag; searches pd.* and PerfectDark.*

set -eo pipefail
VERSION="0.10"
SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
ROMID="ntsc-final"
MAX_REPORTS=5
LIST_ONLY=0

# ── Parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rom) ROMID="$2";       shift 2 ;;
    -n)    MAX_REPORTS="$2"; shift 2 ;;
    --list) LIST_ONLY=1;     shift ;;
    *) echo "Usage: $0 [--rom <id>] [-n <count>] [--list]" >&2; exit 1 ;;
  esac
done

REPO_DIR="$SCRIPT_DIR/perfect_dark"
BUILD_DIR="$REPO_DIR/build-$ROMID"
OUT_DIR="$BUILD_DIR/logs/crash-$TIMESTAMP"
LOGFILE="$OUT_DIR/collect-crash-$TIMESTAMP.log"

mkdir -p "$OUT_DIR"
echo "💥 pdmv-collect-crash.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   Output: $OUT_DIR" | tee -a "$LOGFILE"
echo "   ROMID:  $ROMID" | tee -a "$LOGFILE"

# ── Search paths ──────────────────────────────────────────────────────────────

# macOS writes crash reports in two locations:
#   User:   ~/Library/Logs/DiagnosticReports/
#   System: /Library/Logs/DiagnosticReports/
# Both .ips (modern JSON-based) and .crash (legacy) formats are collected.
# (N) suppresses errors on no match (zsh nullglob).

USER_DIAG="$HOME/Library/Logs/DiagnosticReports"
SYS_DIAG="/Library/Logs/DiagnosticReports"

echo "" | tee -a "$LOGFILE"
echo "🔍 Searching for Perfect Dark crash reports..." | tee -a "$LOGFILE"

ALL_CRASHES=()
for dir in "$USER_DIAG" "$SYS_DIAG"; do
  if [[ -d "$dir" ]]; then
    for f in "$dir"/pd*.ips(N) "$dir"/pd*.crash(N) \
              "$dir"/PerfectDark*.ips(N) "$dir"/PerfectDark*.crash(N); do
      ALL_CRASHES+=("$f")
    done
  fi
done

# Sort by mtime descending
if (( ${#ALL_CRASHES[@]} > 0 )); then
  ALL_CRASHES=(${(f)"$(for f in "${ALL_CRASHES[@]}"; do
    echo "$(stat -f '%m' "$f") $f"
  done | sort -rn | awk '{print $2}')"})
fi

TOTAL=${#ALL_CRASHES[@]}

if (( TOTAL == 0 )); then
  echo "   ℹ️  No Perfect Dark crash reports found." | tee -a "$LOGFILE"
  echo "      Crashes appear in Console.app → Crash Reports" | tee -a "$LOGFILE"
  exit 0
fi

echo "   Found $TOTAL crash report(s) — collecting up to $MAX_REPORTS" | tee -a "$LOGFILE"

# ── List or copy ──────────────────────────────────────────────────────────────

COPIED=0
for f in "${ALL_CRASHES[@]}"; do
  (( COPIED >= MAX_REPORTS )) && break
  MTIME="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$f")"
  SIZE="$(du -h "$f" | cut -f1)"
  FNAME="${f:t}"
  echo "   📄 $MTIME  $SIZE  $FNAME" | tee -a "$LOGFILE"
  if (( LIST_ONLY == 0 )); then
    cp "$f" "$OUT_DIR/"
    (( COPIED++ ))
  fi
done

if (( LIST_ONLY )); then
  echo "" | tee -a "$LOGFILE"
  echo "   (--list mode: no files copied)" | tee -a "$LOGFILE"
  exit 0
fi

# ── Attach sysinfo ────────────────────────────────────────────────────────────

if [[ -f "$SCRIPT_DIR/pdmv-systeminfo.sh" ]]; then
  echo "" | tee -a "$LOGFILE"
  echo "📋 Running pdmv-systeminfo.sh..." | tee -a "$LOGFILE"
  "$SCRIPT_DIR/pdmv-systeminfo.sh" --rom "$ROMID" --out "$OUT_DIR" 2>&1 | tee -a "$LOGFILE" || \
    echo "   ⚠️  sysinfo failed (non-fatal)" | tee -a "$LOGFILE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "✅ pdmv-collect-crash.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📁 $OUT_DIR" | tee -a "$LOGFILE"
echo "   Copied $COPIED of $TOTAL crash report(s)" | tee -a "$LOGFILE"
echo "   👉 Attach this folder when filing an OpenGL bug report." | tee -a "$LOGFILE"
