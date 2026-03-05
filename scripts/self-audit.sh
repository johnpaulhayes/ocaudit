#!/usr/bin/env bash
# self-audit.sh - Audit all installed skills in the workspace
# Checks skill structure, frontmatter, sizes, and health

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

WORKSPACE="${HOME}/.openclaw/workspace"
OUTPUT_JSON=false

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    *)
      # Optional positional workspace path
      if [[ -d "$1" ]]; then
        WORKSPACE="$1"
      fi
      shift
      ;;
  esac
done

WORKSPACE="${WORKSPACE/#\~/$HOME}"
SKILLS_DIR="$WORKSPACE/skills"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
  if [[ "$OUTPUT_JSON" == "false" ]]; then
    echo "$@" >&2
  fi
}

# Extract frontmatter field from SKILL.md
get_frontmatter_field() {
  local file="$1"
  local field="$2"
  
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  
  # Simple frontmatter parser (looks for --- blocks)
  awk -v field="$field" '
    /^---$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^" field ":" {
      sub("^" field ":[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

# Check if skill has valid frontmatter
has_valid_frontmatter() {
  local skill_file="$1"
  
  if [[ ! -f "$skill_file" ]]; then
    echo "false"
    return
  fi
  
  local name=$(get_frontmatter_field "$skill_file" "name")
  local desc=$(get_frontmatter_field "$skill_file" "description")
  
  if [[ -n "$name" && -n "$desc" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Get skill size
get_skill_size() {
  local skill_file="$1"
  if [[ -f "$skill_file" ]]; then
    wc -c < "$skill_file" | tr -d ' '
  else
    echo "0"
  fi
}

# Check for references directory
has_references() {
  local skill_dir="$1"
  if [[ -d "$skill_dir/references" ]]; then
    local ref_count=$(find "$skill_dir/references" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "$ref_count"
  else
    echo "0"
  fi
}

# Check last modified date
get_last_modified_days() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local modified=$(date -r "$file" +%s 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
    local now=$(date +%s)
    echo $(( (now - modified) / 86400 ))
  else
    echo "999"
  fi
}

# ============================================================================
# AUDIT IMPLEMENTATION
# ============================================================================

audit_skills() {
  if [[ ! -d "$SKILLS_DIR" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
      echo '{"error": "Skills directory not found: '"$SKILLS_DIR"'"}'
    else
      echo "Error: Skills directory not found: $SKILLS_DIR" >&2
    fi
    return 1
  fi
  
  declare -a skills
  declare -A skill_names
  declare -A skill_sizes
  declare -A skill_has_fm
  declare -A skill_refs
  declare -A skill_stale
  
  local total_skills=0
  local valid_skills=0
  local missing_fm=0
  local no_refs=0
  local stale_skills=0
  
  # Scan all skills
  while IFS= read -r -d '' skill_dir; do
    local skill_name=$(basename "$skill_dir")
    local skill_file="$skill_dir/SKILL.md"
    
    ((++total_skills))
    skills+=("$skill_name")
    
    # Check frontmatter
    local has_fm=$(has_valid_frontmatter "$skill_file")
    skill_has_fm[$skill_name]=$has_fm
    if [[ "$has_fm" == "true" ]]; then
      ((++valid_skills))
    else
      ((++missing_fm))
    fi
    
    # Get metadata
    skill_names[$skill_name]=$(get_frontmatter_field "$skill_file" "name")
    skill_sizes[$skill_name]=$(get_skill_size "$skill_file")
    
    # Check references
    local refs=$(has_references "$skill_dir")
    skill_refs[$skill_name]=$refs
    [[ $refs -eq 0 ]] && ((++no_refs))
    
    # Check staleness (>180 days)
    local days=$(get_last_modified_days "$skill_file")
    skill_stale[$skill_name]=$days
    [[ $days -gt 180 ]] && ((++stale_skills))
    
  done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
  
  # Output results
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    output_json_skills
  else
    output_human_skills
  fi
  
  # Exit code: 0 if all skills have valid frontmatter, 1 otherwise
  [[ $missing_fm -eq 0 ]]
}

output_human_skills() {
  cat <<EOF
🔍 SKILLS AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workspace: $WORKSPACE
Skills dir: $SKILLS_DIR
Date: $(date +"%Y-%m-%d %H:%M:%S")

📊 SUMMARY
Total skills:        $total_skills
Valid frontmatter:   $valid_skills
Missing frontmatter: $missing_fm
No references:       $no_refs
Stale (>180 days):   $stale_skills

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 SKILLS INVENTORY

Skill                   Size     FM    Refs  Days  Status
EOF

  for skill in "${skills[@]}"; do
    local size="${skill_sizes[$skill]}"
    local has_fm="${skill_has_fm[$skill]}"
    local refs="${skill_refs[$skill]}"
    local days="${skill_stale[$skill]}"
    
    local status="OK"
    local fm_mark="✓"
    
    [[ "$has_fm" == "false" ]] && { status="NO-FM"; fm_mark="✗"; }
    [[ $refs -eq 0 ]] && status="NO-REFS"
    [[ $days -gt 180 ]] && status="STALE"
    [[ $size -eq 0 ]] && status="EMPTY"
    
    printf "%-22s  %7s   %s    %3s   %4s  %s\n" \
      "$skill" "${size}B" "$fm_mark" "$refs" "$days" "$status"
  done
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Recommendations
  if [[ $missing_fm -gt 0 || $no_refs -gt 0 || $stale_skills -gt 0 ]]; then
    echo "📋 RECOMMENDATIONS"
    echo ""
    [[ $missing_fm -gt 0 ]] && echo "⚠️  Add frontmatter (name, description) to $missing_fm skill(s)"
    [[ $no_refs -gt 0 ]] && echo "💡 Add references/ directories to $no_refs skill(s) for best practices"
    [[ $stale_skills -gt 0 ]] && echo "💡 Review $stale_skills stale skill(s) (>180 days old)"
  else
    echo "✅ All skills are healthy!"
  fi
  
  echo ""
}

output_json_skills() {
  cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "workspace": "$WORKSPACE",
  "skillsDir": "$SKILLS_DIR",
  "summary": {
    "total": $total_skills,
    "valid": $valid_skills,
    "missingFrontmatter": $missing_fm,
    "noReferences": $no_refs,
    "stale": $stale_skills
  },
  "skills": [
EOF

  local first=true
  for skill in "${skills[@]}"; do
    [[ "$first" == "false" ]] && echo ","
    first=false
    
    local name="${skill_names[$skill]}"
    local size="${skill_sizes[$skill]}"
    local has_fm="${skill_has_fm[$skill]}"
    local refs="${skill_refs[$skill]}"
    local days="${skill_stale[$skill]}"
    
    cat <<SKILLEOF
    {
      "skill": "$skill",
      "name": "$name",
      "size": $size,
      "hasValidFrontmatter": $has_fm,
      "referenceCount": $refs,
      "daysSinceModified": $days
    }
SKILLEOF
  done
  
  echo ""
  echo "  ]"
  echo "}"
}

# ============================================================================
# MAIN
# ============================================================================

audit_skills
