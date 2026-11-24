#!/usr/bin/env bash
# system_health.sh — Production server health checker
# Usage: ./system_health.sh [--cpu N] [--mem N] [--disk N] [--json] [--help]
# Returns: 0=healthy, 1=warning, 2=critical
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
CPU_THRESHOLD=90
MEM_THRESHOLD=85
DISK_THRESHOLD=80
JSON_OUTPUT=false
LOG_FILE="${LOG_FILE:-/var/log/health_log.txt}"
MAX_LOG_LINES=10000
SCRIPT_NAME="$(basename "$0")"

# ── Help ──────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Collect system health metrics and log them.

Options:
  --cpu  N    CPU usage warning threshold % (default: $CPU_THRESHOLD)
  --mem  N    Memory usage warning threshold % (default: $MEM_THRESHOLD)
  --disk N    Disk usage warning threshold % (default: $DISK_THRESHOLD)
  --json      Output JSON instead of plain text
  --help      Show this help message

Exit codes:
  0  All metrics within thresholds
  1  One or more metrics exceeded a threshold (WARNING)
  2  Critical condition detected

Environment:
  LOG_FILE    Path to log file (default: /var/log/health_log.txt)
EOF
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cpu)  CPU_THRESHOLD="$2";  shift 2 ;;
    --mem)  MEM_THRESHOLD="$2";  shift 2 ;;
    --disk) DISK_THRESHOLD="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true;    shift   ;;
    --help) usage ;;
    *)      echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ── Collect metrics ───────────────────────────────────────────────────────────
TIMESTAMP="$(date -Iseconds)"

# CPU usage (average idle from mpstat, fallback to top)
if command -v mpstat &>/dev/null; then
  CPU_IDLE="$(mpstat 1 1 | awk '/Average/ {print $NF}')"
  CPU_USED="$(echo "100 - $CPU_IDLE" | bc)"
else
  CPU_USED="$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,')"
fi
CPU_USED="${CPU_USED:-0}"

# Memory usage
MEM_TOTAL="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
MEM_AVAILABLE="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
MEM_USED="$(( MEM_TOTAL - MEM_AVAILABLE ))"
MEM_PCT="$(( MEM_USED * 100 / MEM_TOTAL ))"

# Load average (1-min)
LOAD_AVG="$(cut -d' ' -f1 /proc/loadavg)"

# Disk usage per filesystem
declare -A DISK_INFO
while IFS= read -r line; do
  MOUNT="$(echo "$line" | awk '{print $6}')"
  PCT="$(echo "$line" | awk '{print $5}' | tr -d '%')"
  DISK_INFO["$MOUNT"]="$PCT"
done < <(df -h --output=source,size,used,avail,pcent,target | tail -n +2 | grep -v tmpfs | grep -v devtmpfs)

# Top 5 processes by memory
TOP5_PROCS="$(ps aux --sort=-%mem | awk 'NR==1 || NR<=6 {print}' | tail -n 5 | \
  awk '{printf "%s(%s%%)", $11, $4; if(NR<5) printf ","}')"

# ── Threshold checks ──────────────────────────────────────────────────────────
EXIT_CODE=0
WARNINGS=()

# CPU
CPU_INT="${CPU_USED%.*}"
if (( CPU_INT >= CPU_THRESHOLD )); then
  WARNINGS+=("[WARNING] CPU usage ${CPU_INT}% >= threshold ${CPU_THRESHOLD}%")
  EXIT_CODE=1
fi

# Memory
if (( MEM_PCT >= MEM_THRESHOLD )); then
  WARNINGS+=("[WARNING] Memory usage ${MEM_PCT}% >= threshold ${MEM_THRESHOLD}%")
  EXIT_CODE=1
fi

# Disk — flag critical if any filesystem >= threshold
for MOUNT in "${!DISK_INFO[@]}"; do
  PCT="${DISK_INFO[$MOUNT]}"
  if (( PCT >= DISK_THRESHOLD )); then
    WARNINGS+=("[WARNING] Disk ${MOUNT} usage ${PCT}% >= threshold ${DISK_THRESHOLD}%")
    EXIT_CODE=1
  fi
  if (( PCT >= 95 )); then
    EXIT_CODE=2
  fi
done

# ── Build output ──────────────────────────────────────────────────────────────
if $JSON_OUTPUT; then
  DISK_JSON="{"
  for MOUNT in "${!DISK_INFO[@]}"; do
    DISK_JSON+="\"${MOUNT}\": ${DISK_INFO[$MOUNT]},"
  done
  DISK_JSON="${DISK_JSON%,}}"

  OUTPUT=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "cpu_pct": $CPU_INT,
  "mem_pct": $MEM_PCT,
  "load_avg_1m": $LOAD_AVG,
  "disk_pct": $DISK_JSON,
  "top5_procs": "$TOP5_PROCS",
  "warnings": $(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
  "exit_code": $EXIT_CODE
}
EOF
)
else
  OUTPUT="[$TIMESTAMP] CPU=${CPU_INT}% MEM=${MEM_PCT}% LOAD=${LOAD_AVG} TOP5=${TOP5_PROCS}"
  for MOUNT in "${!DISK_INFO[@]}"; do
    OUTPUT+=" DISK(${MOUNT})=${DISK_INFO[$MOUNT]}%"
  done
  for W in "${WARNINGS[@]}"; do
    OUTPUT+=$'\n'"  $W"
    echo "$W" >&2
  done
fi

# ── Log rotation ─────────────────────────────────────────────────────────────
rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    LINE_COUNT="$(wc -l < "$LOG_FILE")"
    if (( LINE_COUNT > MAX_LOG_LINES )); then
      TAIL_FILE="$(mktemp)"
      tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$TAIL_FILE"
      mv "$TAIL_FILE" "$LOG_FILE"
    fi
  fi
}

rotate_log

# ── Append to log & emit to stdout ───────────────────────────────────────────
echo "$OUTPUT" | tee -a "$LOG_FILE"

exit $EXIT_CODE
