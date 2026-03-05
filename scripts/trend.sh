#!/usr/bin/env bash
# trend.sh - Show audit score trends over time
# Reads history/*.json files and displays progression

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
HISTORY_DIR="$SKILL_DIR/history"

OUTPUT_JSON=false
LIMIT=10

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Show audit score trends over time by reading history files.

OPTIONS:
  --json          Output structured JSON
  --limit N       Show last N results (default: 10)
  --all           Show all historical results
  -h, --help      Show this help

EXAMPLES:
  $(basename "$0")              # Show last 10 audits
  $(basename "$0") --all        # Show all audits
  $(basename "$0") --json       # JSON output

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --all)
      LIMIT=9999
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
  if [[ "$OUTPUT_JSON" == "false" ]]; then
    echo "$@" >&2
  fi
}

# Extract JSON field using grep/sed (avoid jq dependency)
extract_json_field() {
  local file="$1"
  local field="$2"
  
  grep "\"$field\"" "$file" | head -1 | sed -E 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/'
}

# ============================================================================
# TREND ANALYSIS
# ============================================================================

analyze_trends() {
  if [[ ! -d "$HISTORY_DIR" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      echo '{"error": "History directory not found: '"$HISTORY_DIR"'", "entries": []}'
    else
      echo "Error: History directory not found: $HISTORY_DIR" >&2
      echo "Run audit with --save to start tracking trends."
    fi
    return 1
  fi
  
  # Find all history files
  local history_files=()
  while IFS= read -r -d '' file; do
    history_files+=("$file")
  done < <(find "$HISTORY_DIR" -name "*.json" -type f -print0 2>/dev/null | sort -z)
  
  local total_files=${#history_files[@]}
  
  if [[ $total_files -eq 0 ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      echo '{"message": "No history files found", "entries": []}'
    else
      echo "No history files found in $HISTORY_DIR"
      echo "Run audit.sh with --save to start tracking."
    fi
    return 0
  fi
  
  # Collect data
  declare -a dates
  declare -a overall_scores
  declare -a grades
  declare -a ce_scores
  declare -a rd_scores
  declare -a oc_scores
  declare -a sc_scores
  declare -a fr_scores
  declare -a co_scores
  
  for file in "${history_files[@]}"; do
    local date=$(basename "$file" .json)
    dates+=("$date")
    
    # Extract scores (simple grep-based parsing)
    local overall=$(grep -o '"score"[[:space:]]*:[[:space:]]*[0-9]*' "$file" | head -1 | grep -o '[0-9]*$')
    local grade=$(grep -o '"grade"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | cut -d'"' -f4)
    
    overall_scores+=("${overall:-0}")
    grades+=("${grade:-?}")
    
    # Extract category scores
    local ce=$(grep '"contextEfficiency"' "$file" | sed -E 's/.*"score": ([0-9]+).*/\1/' | head -1)
    local rd=$(grep '"redundancy"' "$file" | sed -E 's/.*"score": ([0-9]+).*/\1/' | head -1)
    local oc=$(grep '"operationalClarity"' "$file" | sed -E 's/.*"score": ([0-9]+).*/\1/' | head -1)
    local sc=$(grep '"security"' "$file" | sed -E 's/.*"score": ([0-9]+).*/\1/' | head -1)
    local fr=$(grep '"freshness"' "$file" | sed -E 's/.*"score": ([0-9]+).*/\1/' | head -1)
    local co=$(grep '"completeness"' "$file" | sed -E 's/.*"score": ([0-9]+).*/\1/' | head -1)
    
    ce_scores+=("${ce:-0}")
    rd_scores+=("${rd:-0}")
    oc_scores+=("${oc:-0}")
    sc_scores+=("${sc:-0}")
    fr_scores+=("${fr:-0}")
    co_scores+=("${co:-0}")
  done
  
  # Limit results
  local start_idx=$((total_files - LIMIT))
  [[ $start_idx -lt 0 ]] && start_idx=0
  
  # Output
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    output_json_trend "$start_idx" "$total_files"
  else
    output_human_trend "$start_idx" "$total_files"
  fi
}

output_human_trend() {
  local start="$1"
  local total="$2"
  
  cat <<EOF
📈 AUDIT TREND ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
History dir: $HISTORY_DIR
Total audits: $total
Showing: Last $((total - start))

Date         Overall  Grade  CE   RD   OC   SC   FR   CO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

  for ((i=start; i<total; i++)); do
    printf "%-10s   %3s     %-3s   %3s  %3s  %3s  %3s  %3s  %3s\n" \
      "${dates[$i]}" \
      "${overall_scores[$i]}" \
      "${grades[$i]}" \
      "${ce_scores[$i]}" \
      "${rd_scores[$i]}" \
      "${oc_scores[$i]}" \
      "${sc_scores[$i]}" \
      "${fr_scores[$i]}" \
      "${co_scores[$i]}"
  done
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Calculate trend
  if [[ $((total - start)) -ge 2 ]]; then
    local first_score="${overall_scores[$start]}"
    local last_score="${overall_scores[$((total-1))]}"
    local delta=$((last_score - first_score))
    
    echo "📊 TREND SUMMARY"
    echo ""
    echo "First audit: ${dates[$start]} → $first_score (${grades[$start]})"
    echo "Last audit:  ${dates[$((total-1))]} → $last_score (${grades[$((total-1))]})"
    echo ""
    
    if [[ $delta -gt 0 ]]; then
      echo "✅ Improvement: +$delta points"
    elif [[ $delta -lt 0 ]]; then
      echo "⚠️  Decline: $delta points"
    else
      echo "➡️  No change"
    fi
  fi
  
  echo ""
  echo "Legend: CE=Context Efficiency, RD=Redundancy, OC=Operational Clarity,"
  echo "        SC=Security, FR=Freshness, CO=Completeness"
}

output_json_trend() {
  local start="$1"
  local total="$2"
  
  cat <<EOF
{
  "historyDir": "$HISTORY_DIR",
  "totalAudits": $total,
  "showing": $((total - start)),
  "entries": [
EOF

  local first=true
  for ((i=start; i<total; i++)); do
    [[ "$first" == "false" ]] && echo ","
    first=false
    
    cat <<ENTRY
    {
      "date": "${dates[$i]}",
      "overall": ${overall_scores[$i]},
      "grade": "${grades[$i]}",
      "scores": {
        "contextEfficiency": ${ce_scores[$i]},
        "redundancy": ${rd_scores[$i]},
        "operationalClarity": ${oc_scores[$i]},
        "security": ${sc_scores[$i]},
        "freshness": ${fr_scores[$i]},
        "completeness": ${co_scores[$i]}
      }
    }
ENTRY
  done
  
  echo ""
  echo "  ]"
  
  # Add trend summary
  if [[ $((total - start)) -ge 2 ]]; then
    local first_score="${overall_scores[$start]}"
    local last_score="${overall_scores[$((total-1))]}"
    local delta=$((last_score - first_score))
    
    cat <<TREND
  ,
  "trend": {
    "firstDate": "${dates[$start]}",
    "firstScore": $first_score,
    "firstGrade": "${grades[$start]}",
    "lastDate": "${dates[$((total-1))]}",
    "lastScore": $last_score,
    "lastGrade": "${grades[$((total-1))]}",
    "delta": $delta
  }
TREND
  fi
  
  echo "}"
}

# ============================================================================
# MAIN
# ============================================================================

analyze_trends
