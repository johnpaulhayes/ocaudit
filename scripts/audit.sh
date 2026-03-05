#!/usr/bin/env bash
# ocaudit - OpenClaw Workspace Audit Tool
# Deterministic workspace file analysis without requiring an LLM

set -euo pipefail

# ============================================================================
# CONFIGURATION & DEFAULTS
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SKILL_DIR/config.json"

# Default workspace
DEFAULT_WORKSPACE="${HOME}/.openclaw/workspace"
WORKSPACE="${DEFAULT_WORKSPACE}"

# Output format
OUTPUT_JSON=false
DRY_RUN=false
SAVE_HISTORY=false
ALL_AGENTS=false

# Core files to audit
CORE_FILES=(
  "AGENTS.md"
  "SOUL.md"
  "USER.md"
  "IDENTITY.md"
  "TOOLS.md"
  "HEARTBEAT.md"
  "MEMORY.md"
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

OpenClaw workspace audit tool - checks configuration files for bloat,
redundancy, security issues, and context efficiency.

OPTIONS:
  --json              Output structured JSON instead of human-readable report
  --dry-run           Show what auto-fix would change without modifying files
  --workspace PATH    Audit a specific workspace (default: ~/.openclaw/workspace)
  --save              Save audit results to history/YYYY-MM-DD.json
  --all-agents        Audit all agents in ~/.openclaw/agents/
  -h, --help          Show this help message

EXAMPLES:
  $(basename "$0")                    # Audit default workspace
  $(basename "$0") --json             # JSON output
  $(basename "$0") --workspace /path  # Audit specific workspace
  $(basename "$0") --save             # Save results to history

EXIT CODES:
  0 - Grade A or B (healthy workspace)
  1 - Grade C or below (needs attention)

EOF
  exit 0
}

log() {
  if [[ "$OUTPUT_JSON" == "false" ]]; then
    echo "$@" >&2
  fi
}

# Load config.json or use defaults
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # Parse JSON using basic tools (avoid jq dependency)
    # For production, consider requiring jq or using python
    if command -v jq &>/dev/null; then
      TRUNCATION_LIMIT=$(jq -r '.truncationLimit // 20000' "$CONFIG_FILE")
    else
      TRUNCATION_LIMIT=20000
    fi
  else
    TRUNCATION_LIMIT=20000
  fi
}

# Get file size in characters
get_file_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    wc -c < "$file" | tr -d ' '
  else
    echo "0"
  fi
}

# Estimate tokens (chars / 4)
estimate_tokens() {
  local chars="$1"
  echo $((chars / 4))
}

# Calculate Shannon entropy (bits/char) for a token
calculate_entropy() {
  local str="$1"
  local len=${#str}

  if [[ $len -eq 0 ]]; then
    echo "0"
    return
  fi

  awk -v s="$str" 'BEGIN {
    n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      f[c]++
    }
    h = 0
    for (c in f) {
      p = f[c] / n
      h += -p * (log(p) / log(2))
    }
    printf "%.4f", h
  }'
}

# Scan for secrets using regex patterns
scan_secrets_regex() {
  local file="$1"
  local findings=0
  
  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi
  
  # Match lines with credential-like ASSIGNMENTS (key=value, key: value patterns)
  # Exclude lines that merely reference/discuss credentials (e.g. "Never disclose credentials")
  local assignment_patterns=(
    "[Pp]assword[[:space:]]*[:=][[:space:]]*[^{}\$]"
    "[Aa]pi[_-]?[Kk]ey[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9]"
    "[Tt]oken[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9]"
    "[Ss]ecret[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9]"
    "[Bb]earer[[:space:]]+[A-Za-z0-9]"
    "[Pp]rivate[_-]?[Kk]ey[[:space:]]*[:=]"
  )
  
  for pattern in "${assignment_patterns[@]}"; do
    # Exclude lines with "stored in", "never", "don't", "do not" — these are references not leaks
    if grep -iE "$pattern" "$file" 2>/dev/null | grep -qivE "stored in|never|don.t|do not|see |check "; then
      ((findings++))
    fi
  done
  
  echo "$findings"
}

# Scan for high-entropy strings (potential API keys)
scan_secrets_entropy() {
  local file="$1"
  local findings=0
  
  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi
  
  # Extract potential key-like strings (alphanumeric, >20 chars)
  while IFS= read -r line; do
    # Skip comments and markdown headers
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Extract long alphanumeric strings
    while [[ "$line" =~ ([A-Za-z0-9_-]{20,}) ]]; do
      local candidate="${BASH_REMATCH[1]}"
      local entropy=$(calculate_entropy "$candidate")
      
      # Flag if entropy >4.5 bits/char (requirement) and token length >20 already enforced
      local threshold_check=$(awk "BEGIN {if ($entropy > 4.5) print 1; else print 0}")
      if [[ "$threshold_check" == "1" ]]; then
        ((findings++))
      fi
      
      # Remove matched part and continue
      line="${line/${BASH_REMATCH[0]}/}"
    done
  done < "$file"
  
  echo "$findings"
}

# Detect cross-file duplication (exact + near-identical normalized lines)
detect_duplication() {
  local workspace="$1"
  local exact_duplicates=0
  local near_duplicates=0

  local temp_exact=$(mktemp)
  local temp_norm=$(mktemp)

  for file in "${CORE_FILES[@]}"; do
    local path="$workspace/$file"
    if [[ -f "$path" ]]; then
      grep -v '^[[:space:]]*$' "$path" 2>/dev/null | \
      grep -v '^[[:space:]]*#' | \
      sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
      while IFS= read -r line; do
        echo "$line" >> "$temp_exact"
        # near-identical: lowercase + strip punctuation + collapse spaces
        echo "$line" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]/ /g;s/[[:space:]]\+/ /g;s/^ //;s/ $//' >> "$temp_norm"
      done
    fi
  done

  if [[ -f "$temp_exact" ]]; then
    exact_duplicates=$(sort "$temp_exact" | uniq -d | wc -l | tr -d ' ')
  fi
  if [[ -f "$temp_norm" ]]; then
    near_duplicates=$(sort "$temp_norm" | uniq -d | wc -l | tr -d ' ')
  fi

  rm -f "$temp_exact" "$temp_norm"
  # return combined signal (weighted to avoid overcounting)
  echo $(( exact_duplicates + (near_duplicates / 2) ))
}

# Count sections (headers) in a file
count_sections() {
  local file="$1"
  if [[ -f "$file" ]]; then
    grep -c '^#' "$file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Count rules (numbered or bulleted items)
count_rules() {
  local file="$1"
  if [[ -f "$file" ]]; then
    grep -cE '^[[:space:]]*([0-9]+\.|[-*+])' "$file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Check for stale date references (>60 days old)
check_stale_dates() {
  local file="$1"
  local stale_count=0
  
  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi
  
  local now=$(date +%s)
  local sixty_days_ago=$((now - 60 * 86400))
  
  # Match dates in format YYYY-MM-DD
  while IFS= read -r line; do
    if [[ "$line" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
      local date_str="${BASH_REMATCH[0]}"
      local date_epoch=$(date -d "$date_str" +%s 2>/dev/null || echo "0")
      
      if [[ $date_epoch -gt 0 && $date_epoch -lt $sixty_days_ago ]]; then
        ((stale_count++))
      fi
    fi
  done < "$file"
  
  echo "$stale_count"
}

# Get file last modified timestamp
get_last_modified() {
  local file="$1"
  if [[ -f "$file" ]]; then
    date -r "$file" +%s 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# ============================================================================
# SCORING FUNCTIONS
# ============================================================================

# Calculate context efficiency score
score_context_efficiency() {
  local total_tokens="$1"
  local truncated_count="$2"
  local heartbeat_size="$3"
  local agents_size="$4"
  local soul_size="$5"
  
  local score=100
  
  # Deductions
  [[ $truncated_count -gt 0 ]] && score=$((score - 30))
  [[ $total_tokens -gt 12000 ]] && score=$((score - 20))
  [[ $total_tokens -gt 8000 ]] && score=$((score - 10))
  [[ $heartbeat_size -gt 2000 ]] && score=$((score - 10))
  [[ $agents_size -gt 15000 ]] && score=$((score - 15))
  [[ $soul_size -gt 5000 ]] && score=$((score - 10))
  
  # Bonuses
  [[ $total_tokens -lt 5000 ]] && score=$((score + 10))
  [[ $total_tokens -lt 3000 ]] && score=$((score + 15))
  
  # Clamp to 0-100
  [[ $score -lt 0 ]] && score=0
  [[ $score -gt 100 ]] && score=100
  
  echo "$score"
}

# Calculate redundancy score
score_redundancy() {
  local duplicates="$1"
  
  local score=100
  
  # Deduction for duplicates (-10 each, max -30)
  local deduction=$((duplicates * 10))
  [[ $deduction -gt 30 ]] && deduction=30
  score=$((score - deduction))
  
  # Bonus for zero duplication
  [[ $duplicates -eq 0 ]] && score=$((score + 10))
  
  [[ $score -lt 0 ]] && score=0
  [[ $score -gt 100 ]] && score=100
  
  echo "$score"
}

# Calculate operational clarity score
score_operational_clarity() {
  local agents_rules="$1"
  local agents_sections="$2"
  local has_structure="$3"
  
  local score=100
  
  # Too many rules
  [[ $agents_rules -gt 20 ]] && score=$((score - 10))
  
  # Poor structure
  [[ "$has_structure" == "false" ]] && score=$((score - 10))
  
  # Bonus for well-structured
  [[ "$has_structure" == "true" && $agents_sections -gt 3 && $agents_sections -lt 15 ]] && score=$((score + 10))
  
  [[ $score -lt 0 ]] && score=0
  [[ $score -gt 100 ]] && score=100
  
  echo "$score"
}

# Calculate security score
score_security() {
  local secret_findings="$1"
  
  local score=100
  
  # Deduction for secrets (-30 each)
  local deduction=$((secret_findings * 30))
  score=$((score - deduction))
  
  # Bonus for clean posture
  [[ $secret_findings -eq 0 ]] && score=$((score + 10))
  
  [[ $score -lt 0 ]] && score=0
  [[ $score -gt 100 ]] && score=100
  
  echo "$score"
}

# Calculate freshness score
score_freshness() {
  local stale_dates="$1"
  local days_since_memory="$2"
  
  local score=100
  
  # Deduction for stale dates (-5 each, max -15)
  local deduction=$((stale_dates * 5))
  [[ $deduction -gt 15 ]] && deduction=15
  score=$((score - deduction))
  
  # Deduction for no recent memory
  [[ $days_since_memory -gt 7 ]] && score=$((score - 15))
  
  # Bonus for current content
  [[ $stale_dates -eq 0 && $days_since_memory -le 1 ]] && score=$((score + 10))
  
  [[ $score -lt 0 ]] && score=0
  [[ $score -gt 100 ]] && score=100
  
  echo "$score"
}

# Calculate completeness score
score_completeness() {
  local missing_agents="$1"
  local missing_soul="$2"
  local missing_user="$3"
  local missing_identity="$4"
  local user_has_timezone="$5"
  
  local score=100
  
  # Deductions for missing files
  [[ "$missing_agents" == "true" ]] && score=$((score - 40))
  [[ "$missing_soul" == "true" ]] && score=$((score - 20))
  [[ "$missing_user" == "true" ]] && score=$((score - 15))
  [[ "$missing_identity" == "true" ]] && score=$((score - 10))
  [[ "$user_has_timezone" == "false" ]] && score=$((score - 5))
  
  # Bonus for complete setup
  if [[ "$missing_agents" == "false" && "$missing_soul" == "false" && \
        "$missing_user" == "false" && "$missing_identity" == "false" && \
        "$user_has_timezone" == "true" ]]; then
    score=$((score + 10))
  fi
  
  [[ $score -lt 0 ]] && score=0
  [[ $score -gt 100 ]] && score=100
  
  echo "$score"
}

# Calculate weighted overall score
calculate_overall_score() {
  local ce="$1"  # context efficiency
  local rd="$2"  # redundancy
  local oc="$3"  # operational clarity
  local sc="$4"  # security
  local fr="$5"  # freshness
  local co="$6"  # completeness
  
  # Weights (total = 100%)
  local overall=$(awk "BEGIN {print ($ce * 0.25) + ($rd * 0.20) + ($oc * 0.20) + ($sc * 0.15) + ($fr * 0.10) + ($co * 0.10)}")
  printf "%.0f" "$overall"
}

# Convert score to letter grade
score_to_grade() {
  local score="$1"
  
  if [[ $score -ge 95 ]]; then
    echo "A+"
  elif [[ $score -ge 90 ]]; then
    echo "A"
  elif [[ $score -ge 75 ]]; then
    echo "B"
  elif [[ $score -ge 60 ]]; then
    echo "C"
  elif [[ $score -ge 40 ]]; then
    echo "D"
  else
    echo "F"
  fi
}

# Get grade label
grade_label() {
  local grade="$1"
  
  case "$grade" in
    "A+") echo "Exceptional" ;;
    "A")  echo "Excellent" ;;
    "B")  echo "Good" ;;
    "C")  echo "Needs attention" ;;
    "D")  echo "Needs work" ;;
    "F")  echo "Critical" ;;
    *)    echo "Unknown" ;;
  esac
}

# ============================================================================
# AUDIT IMPLEMENTATION
# ============================================================================

audit_workspace() {
  local workspace="$1"
  
  # Initialize results
  declare -A file_sizes
  declare -A file_tokens
  declare -A file_status
  declare -A file_sections
  declare -A file_rules
  declare -A file_stale_dates
  declare -A file_modified
  
  local total_chars=0
  local total_tokens=0
  local truncated_count=0
  local total_secret_regex=0
  local total_secret_entropy=0
  
  # Phase 1: Measure files
  for file in "${CORE_FILES[@]}"; do
    local path="$workspace/$file"
    local size=$(get_file_size "$path")
    local tokens=$(estimate_tokens "$size")
    
    file_sizes[$file]=$size
    file_tokens[$file]=$tokens
    
    if [[ $size -eq 0 ]]; then
      file_status[$file]="MISSING"
    elif [[ $size -gt $TRUNCATION_LIMIT ]]; then
      file_status[$file]="TRUNCATED"
      ((truncated_count++))
    elif [[ $size -gt 10000 ]]; then
      file_status[$file]="LARGE"
    else
      file_status[$file]="OK"
    fi
    
    # Count sections and rules
    file_sections[$file]=$(count_sections "$path")
    file_rules[$file]=$(count_rules "$path")
    
    # Check for stale dates
    file_stale_dates[$file]=$(check_stale_dates "$path")
    
    # Get last modified
    file_modified[$file]=$(get_last_modified "$path")
    
    # Sum always-loaded files
    if [[ "$file" != "MEMORY.md" ]]; then
      total_chars=$((total_chars + size))
      total_tokens=$((total_tokens + tokens))
    fi
    
    # Scan for secrets
    if [[ -f "$path" ]]; then
      local regex_findings=$(scan_secrets_regex "$path")
      local entropy_findings=$(scan_secrets_entropy "$path")
      total_secret_regex=$((total_secret_regex + regex_findings))
      total_secret_entropy=$((total_secret_entropy + entropy_findings))
    fi
  done
  
  # Phase 2: Cross-file analysis
  local duplicates=$(detect_duplication "$workspace")
  
  # Phase 3: Additional checks
  local memory_dir="$workspace/memory"
  local latest_memory="0"
  if [[ -d "$memory_dir" ]]; then
    latest_memory=$(find "$memory_dir" -name "*.md" -type f -exec date -r {} +%s \; 2>/dev/null | sort -rn | head -1 || echo "0")
  fi
  local now=$(date +%s)
  local days_since_memory=$(( (now - latest_memory) / 86400 ))
  [[ $latest_memory -eq 0 ]] && days_since_memory=999
  
  # Check for timezone in USER.md
  local user_has_timezone="false"
  if [[ -f "$workspace/USER.md" ]] && grep -qiE '(timezone|time.zone|tz)' "$workspace/USER.md"; then
    user_has_timezone="true"
  fi
  
  # Phase 4: Calculate scores
  local ce_score=$(score_context_efficiency "$total_tokens" "$truncated_count" "${file_sizes[HEARTBEAT.md]}" "${file_sizes[AGENTS.md]}" "${file_sizes[SOUL.md]}")
  local rd_score=$(score_redundancy "$duplicates")
  local oc_score=$(score_operational_clarity "${file_rules[AGENTS.md]}" "${file_sections[AGENTS.md]}" "true")
  local sc_score=$(score_security "$((total_secret_regex + total_secret_entropy))")
  local fr_score=$(score_freshness "$(echo "${file_stale_dates[@]}" | awk '{s=0; for(i=1;i<=NF;i++)s+=$i; print s}')" "$days_since_memory")
  local co_score=$(score_completeness \
    "$([[ ${file_status[AGENTS.md]} == "MISSING" ]] && echo "true" || echo "false")" \
    "$([[ ${file_status[SOUL.md]} == "MISSING" ]] && echo "true" || echo "false")" \
    "$([[ ${file_status[USER.md]} == "MISSING" ]] && echo "true" || echo "false")" \
    "$([[ ${file_status[IDENTITY.md]} == "MISSING" ]] && echo "true" || echo "false")" \
    "$user_has_timezone")
  
  local overall=$(calculate_overall_score "$ce_score" "$rd_score" "$oc_score" "$sc_score" "$fr_score" "$co_score")
  local grade=$(score_to_grade "$overall")
  local label=$(grade_label "$grade")
  
  # Phase 5: Output results
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    output_json "$workspace" "$overall" "$grade" "$label" \
      "$ce_score" "$rd_score" "$oc_score" "$sc_score" "$fr_score" "$co_score" \
      "$total_chars" "$total_tokens" "$truncated_count" "$duplicates" \
      "$total_secret_regex" "$total_secret_entropy" "$days_since_memory"
  else
    output_human "$workspace" "$overall" "$grade" "$label" \
      "$ce_score" "$rd_score" "$oc_score" "$sc_score" "$fr_score" "$co_score" \
      "$total_chars" "$total_tokens" "$truncated_count" "$duplicates" \
      "$total_secret_regex" "$total_secret_entropy" "$days_since_memory"
  fi
  
  # Exit code: 0 for A/B, 1 for C or below
  if [[ "$grade" == "A+" || "$grade" == "A" || "$grade" == "B" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

# Generate emoji progress bar
emoji_bar() {
  local score="$1"
  local filled=$((score / 10))
  local empty=$((10 - filled))
  
  local bar=""
  for ((i=0; i<filled; i++)); do
    bar+="🟩"
  done
  
  # Add transition block if not perfect
  if [[ $filled -lt 10 && $filled -gt 0 ]]; then
    bar+="🟨"
    ((empty--))
  fi
  
  for ((i=0; i<empty; i++)); do
    bar+="⬜"
  done
  
  echo "$bar"
}

output_human() {
  local workspace="$1"
  local overall="$2"
  local grade="$3"
  local label="$4"
  local ce="$5"
  local rd="$6"
  local oc="$7"
  local sc="$8"
  local fr="$9"
  local co="${10}"
  local total_chars="${11}"
  local total_tokens="${12}"
  local truncated="${13}"
  local duplicates="${14}"
  local secrets_regex="${15}"
  local secrets_entropy="${16}"
  local days_memory="${17}"
  
  cat <<EOF
🔍 OPENCLAW WORKSPACE AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workspace: $workspace
Date: $(date +"%Y-%m-%d %H:%M:%S")

📊 Overall: $overall/100 — Grade $grade ($label)

Context Efficiency  $(emoji_bar "$ce")  $ce/100 $(score_to_grade "$ce")
Redundancy          $(emoji_bar "$rd")  $rd/100 $(score_to_grade "$rd")
Operational Clarity $(emoji_bar "$oc")  $oc/100 $(score_to_grade "$oc")
Security            $(emoji_bar "$sc")  $sc/100 $(score_to_grade "$sc")
Freshness           $(emoji_bar "$fr")  $fr/100 $(score_to_grade "$fr")
Completeness        $(emoji_bar "$co")  $co/100 $(score_to_grade "$co")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 WORKSPACE MAP

Always-loaded:    $total_chars chars (~$total_tokens tokens)
Files truncated:  $truncated
Cross-file dupes: $duplicates lines
Secret findings:  $((secrets_regex + secrets_entropy)) (regex: $secrets_regex, entropy: $secrets_entropy)
Memory freshness: $days_memory days since last log

File              Size    ~Tokens  Status
EOF

  for file in "${CORE_FILES[@]}"; do
    local size="${file_sizes[$file]}"
    local tokens="${file_tokens[$file]}"
    local status="${file_status[$file]}"
    
    printf "%-16s  %6s  %7s   %s\n" "$file" "${size}B" "$tokens" "$status"
  done
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Recommendations
  if [[ $overall -lt 75 ]]; then
    echo "📋 TOP RECOMMENDATIONS"
    echo ""
    
    [[ $truncated -gt 0 ]] && echo "🔴 CRITICAL: $truncated file(s) truncated (>20K chars) — instructions are being lost"
    [[ $((secrets_regex + secrets_entropy)) -gt 0 ]] && echo "🔴 SECURITY: $((secrets_regex + secrets_entropy)) potential credential(s) found — move to ~/.openclaw/credentials/"
    [[ $total_tokens -gt 12000 ]] && echo "⚠️  Reduce always-loaded files from $total_tokens to <8K tokens (+20 pts)"
    [[ ${file_sizes[HEARTBEAT.md]} -gt 2000 ]] && echo "⚠️  Trim HEARTBEAT.md from ${file_sizes[HEARTBEAT.md]} to <2K chars (+10 pts)"
    [[ $duplicates -gt 5 ]] && echo "⚠️  Remove $duplicates duplicate lines across files (+10 pts)"
    [[ $days_memory -gt 7 ]] && echo "💡 Create memory/$(date +%Y-%m-%d).md to track daily notes (+5 pts)"
  else
    echo "✅ Workspace is in good health!"
    echo ""
    echo "💡 QUICK WINS:"
    [[ $total_tokens -gt 5000 && $total_tokens -lt 8000 ]] && echo "   • Trim files to <5K tokens for A+ efficiency"
    [[ $duplicates -gt 0 ]] && echo "   • Remove $duplicates duplicate line(s) for bonus points"
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "🧪 DRY-RUN (no files changed)"
    echo "Would apply these auto-fix actions:"
    [[ $truncated -gt 0 ]] && echo "  • Condense oversized files to below truncation limit ($TRUNCATION_LIMIT chars)"
    [[ ${file_sizes[HEARTBEAT.md]} -gt 2000 ]] && echo "  • Trim HEARTBEAT.md to <2K chars"
    [[ $duplicates -gt 0 ]] && echo "  • Remove duplicated rules/facts across files"
    [[ $days_memory -gt 7 ]] && echo "  • Create/update today's memory/YYYY-MM-DD.md"
    [[ $((secrets_regex + secrets_entropy)) -gt 0 ]] && echo "  • Replace credential-like values with credential path references"
  fi

  echo ""
  echo "Run with --json for structured output"
  echo "Run with --save to store results in history/"
}

output_json() {
  local workspace="$1"
  local overall="$2"
  local grade="$3"
  local label="$4"
  local ce="$5"
  local rd="$6"
  local oc="$7"
  local sc="$8"
  local fr="$9"
  local co="${10}"
  local total_chars="${11}"
  local total_tokens="${12}"
  local truncated="${13}"
  local duplicates="${14}"
  local secrets_regex="${15}"
  local secrets_entropy="${16}"
  local days_memory="${17}"
  
  cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "workspace": "$workspace",
  "version": "1.0.0",
  "dryRun": $DRY_RUN,
  "overall": {
    "score": $overall,
    "grade": "$grade",
    "label": "$label"
  },
  "scores": {
    "contextEfficiency": { "score": $ce, "grade": "$(score_to_grade "$ce")", "weight": 25 },
    "redundancy": { "score": $rd, "grade": "$(score_to_grade "$rd")", "weight": 20 },
    "operationalClarity": { "score": $oc, "grade": "$(score_to_grade "$oc")", "weight": 20 },
    "security": { "score": $sc, "grade": "$(score_to_grade "$sc")", "weight": 15 },
    "freshness": { "score": $fr, "grade": "$(score_to_grade "$fr")", "weight": 10 },
    "completeness": { "score": $co, "grade": "$(score_to_grade "$co")", "weight": 10 }
  },
  "metrics": {
    "totalChars": $total_chars,
    "totalTokens": $total_tokens,
    "truncatedFiles": $truncated,
    "crossFileDuplicates": $duplicates,
    "secretFindings": {
      "regex": $secrets_regex,
      "entropy": $secrets_entropy,
      "total": $((secrets_regex + secrets_entropy))
    },
    "daysSinceMemory": $days_memory
  },
  "files": [
EOF

  local first=true
  for file in "${CORE_FILES[@]}"; do
    [[ "$first" == "false" ]] && echo ","
    first=false
    
    cat <<FILEEOF
    {
      "name": "$file",
      "size": ${file_sizes[$file]},
      "tokens": ${file_tokens[$file]},
      "status": "${file_status[$file]}",
      "sections": ${file_sections[$file]},
      "rules": ${file_rules[$file]},
      "staleDates": ${file_stale_dates[$file]},
      "lastModified": ${file_modified[$file]}
    }
FILEEOF
  done
  
  echo ""
  echo "  ],"
  
  # Recommendations
  echo '  "recommendations": ['
  local rec_first=true
  
  if [[ $truncated -gt 0 ]]; then
    [[ "$rec_first" == "false" ]] && echo ","
    rec_first=false
    echo '    { "priority": "critical", "category": "context", "message": "'"$truncated"' file(s) truncated - instructions being lost", "impact": 30 }'
  fi
  
  if [[ $((secrets_regex + secrets_entropy)) -gt 0 ]]; then
    [[ "$rec_first" == "false" ]] && echo ","
    rec_first=false
    echo '    { "priority": "critical", "category": "security", "message": "'"$((secrets_regex + secrets_entropy))"' potential credential(s) found", "impact": 30 }'
  fi
  
  if [[ $total_tokens -gt 12000 ]]; then
    [[ "$rec_first" == "false" ]] && echo ","
    rec_first=false
    echo '    { "priority": "high", "category": "context", "message": "Reduce always-loaded files from '"$total_tokens"' to <8K tokens", "impact": 20 }'
  fi
  
  if [[ ${file_sizes[HEARTBEAT.md]} -gt 2000 ]]; then
    [[ "$rec_first" == "false" ]] && echo ","
    rec_first=false
    echo '    { "priority": "medium", "category": "context", "message": "Trim HEARTBEAT.md from '"${file_sizes[HEARTBEAT.md]}"' to <2K chars", "impact": 10 }'
  fi
  
  if [[ $duplicates -gt 5 ]]; then
    [[ "$rec_first" == "false" ]] && echo ","
    rec_first=false
    echo '    { "priority": "medium", "category": "redundancy", "message": "Remove '"$duplicates"' duplicate lines across files", "impact": 10 }'
  fi
  
  if [[ $days_memory -gt 7 ]]; then
    [[ "$rec_first" == "false" ]] && echo ","
    rec_first=false
    echo '    { "priority": "low", "category": "freshness", "message": "Create memory/'"$(date +%Y-%m-%d)"'.md for daily notes", "impact": 5 }'
  fi
  
  echo ""
  echo "  ]"
  echo "}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --workspace)
        WORKSPACE="$2"
        shift 2
        ;;
      --save)
        SAVE_HISTORY=true
        shift
        ;;
      --all-agents)
        ALL_AGENTS=true
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
  
  # Load configuration
  load_config
  
  # Expand workspace path
  WORKSPACE="${WORKSPACE/#\~/$HOME}"
  
  # Check if workspace exists
  if [[ ! -d "$WORKSPACE" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      echo '{"error": "Workspace not found: '"$WORKSPACE"'"}'
    else
      echo "Error: Workspace not found: $WORKSPACE" >&2
    fi
    exit 1
  fi
  
  local exit_code=0

  if [[ "$ALL_AGENTS" == "true" ]]; then
    local agents_root="${HOME}/.openclaw/agents"
    local audited_any=false
    if [[ -d "$agents_root" ]]; then
      while IFS= read -r -d '' agent_dir; do
        local agent_id
        agent_id="$(basename "$agent_dir")"
        local agent_ws="$agent_dir/workspace"
        [[ ! -d "$agent_ws" ]] && continue

        audited_any=true
        [[ "$OUTPUT_JSON" == "false" ]] && echo "\n🤖 Agent: $agent_id"
        if ! audit_workspace "$agent_ws"; then
          exit_code=1
        fi
      done < <(find "$agents_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    if [[ "$audited_any" == "false" ]]; then
      [[ "$OUTPUT_JSON" == "false" ]] && echo "No agent workspaces found under $agents_root; auditing current workspace instead."
      if ! audit_workspace "$WORKSPACE"; then
        exit_code=1
      fi
    fi
  else
    if ! audit_workspace "$WORKSPACE"; then
      exit_code=1
    fi
  fi

  # Save history if requested (single-workspace mode only)
  if [[ "$SAVE_HISTORY" == "true" && "$ALL_AGENTS" == "false" ]]; then
    local history_file="$SKILL_DIR/history/$(date +%Y-%m-%d).json"
    mkdir -p "$(dirname "$history_file")"
    OUTPUT_JSON=true audit_workspace "$WORKSPACE" > "$history_file" || true
    log "Saved audit results to $history_file"
  fi

  exit $exit_code
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
