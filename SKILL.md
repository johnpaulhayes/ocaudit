---
name: ocaudit
description: Audit and optimize OpenClaw workspace files (AGENTS.md, SOUL.md, HEARTBEAT.md, MEMORY.md, TOOLS.md, USER.md, IDENTITY.md). Deterministic scoring + LLM-assisted analysis. Works from Telegram.
---

# OpenClaw Workspace Audit

Audit your OpenClaw workspace configuration for bloat, redundancy, contradictions, security leaks, and context efficiency. Inspired by claudit but purpose-built for OpenClaw.

**Two modes:**
1. **Script-only** — Deterministic analysis without LLM (fast, always accurate)
2. **LLM-assisted** — Script findings + subjective analysis (deeper insights)

---

## When to use

- User says "audit", "ocaudit", "/ocaudit", "audit my config", "check my workspace"
- Periodic self-audit (weekly recommended)
- After major workspace changes
- When context feels bloated or sessions are slow

---

## Quick Start

### Mode 1: Script-Only Audit (Recommended)

Run the audit script directly — no LLM needed, deterministic results:

```bash
bash scripts/audit.sh
```

**Flags:**
- `--json` → Structured JSON output (for automation)
- `--workspace /path` → Audit specific workspace
- `--save` → Save results to `history/YYYY-MM-DD.json`
- `--all-agents` → Audit all agents in `~/.openclaw/agents/`

**Example workflow:**
```bash
# Run audit
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh

# Save history for trend tracking
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh --json --save

# View trends
bash ~/.openclaw/workspace/skills/ocaudit/scripts/trend.sh
```

The script produces:
- ✅ 6-category scores (context efficiency, redundancy, clarity, security, freshness, completeness)
- ✅ Overall grade (A+ to F)
- ✅ File-by-file breakdown
- ✅ Ranked recommendations
- ✅ Exit code (0 = healthy, 1 = needs attention)

**When to use script-only:**
- Quick health check
- CI/CD integration
- Automated monitoring
- When LLM analysis isn't needed

---

### Mode 2: LLM-Assisted Analysis

Run the script + provide deeper subjective analysis:

1. Execute the audit script
2. Read `references/best-practices.md`
3. Provide subjective commentary on:
   - Quality of rule organization
   - Clarity of instructions
   - Persona coherence
   - Specific improvement suggestions beyond what the script can detect

**Example invocation:**

```
User: "audit my config"

Agent:
1. bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh
2. Read references/best-practices.md
3. Analyze script findings + apply subjective judgment
4. Present integrated report with specific, actionable recommendations
```

**When to use LLM-assisted:**
- First-time audit (need education on best practices)
- Major refactoring planning
- Want specific rewrite suggestions
- Investigating why scores are low

---

## Configuration

Edit `config.json` to customize thresholds:

```json
{
  "targets": {
    "AGENTS.md": { "ideal": 8000, "warn": 15000, "critical": 20000 },
    "HEARTBEAT.md": { "ideal": 1500, "warn": 2000, "critical": 5000 }
  },
  "truncationLimit": 20000,
  "secretPatterns": ["password", "api[_-]?key", "token"],
  "scoring": {
    "weights": {
      "contextEfficiency": 25,
      "redundancy": 20,
      "operationalClarity": 20,
      "security": 15,
      "freshness": 10,
      "completeness": 10
    }
  }
}
```

---

## What the Script Audits

### Core Files (Always-Loaded)

These files are injected **every session start** → consume tokens on every turn:

- **AGENTS.md** — Operating instructions, rules
- **SOUL.md** — Persona, tone, identity
- **USER.md** — User profile, preferences
- **IDENTITY.md** — Agent name, emoji, type
- **TOOLS.md** — Local tool notes
- **HEARTBEAT.md** — Periodic checklist (48×/day at 30min interval!)
- **MEMORY.md** — Long-term memory (main session only, on-demand)

### Checks Performed

**Context Efficiency (25% weight)**
- Total always-loaded tokens (target: <8K)
- Files truncated by OpenClaw (>20K chars per file)
- Per-file sizes vs ideal/warn/critical thresholds
- HEARTBEAT.md bloat (highest cost per char due to 48×/day injection)

**Redundancy (20% weight)**
- Cross-file duplicate lines (identical content in 2+ files)
- Same rules appearing in multiple files
- Facts duplicated in MEMORY.md + AGENTS.md

**Operational Clarity (20% weight)**
- Rule count in AGENTS.md (>20 = too many to follow)
- Section structure (clear H2/H3 organization)
- Contradicting instructions across files

**Security (15% weight)**
- Plaintext credentials (regex patterns: password, api_key, token, secret, etc.)
- High-entropy strings (Shannon entropy >4.5 bits/char, length >20 chars)
- Personal data in files that might leak in group chats

**Freshness (10% weight)**
- Stale date references (>60 days old, e.g., "On 2025-11-15 we learned X")
- Days since last memory log (`memory/YYYY-MM-DD.md`)
- References to completed/abandoned projects

**Completeness (10% weight)**
- Required files present (AGENTS.md, SOUL.md, USER.md, IDENTITY.md)
- USER.md has timezone
- Files properly structured with sections

---

## Scoring Algorithm

Each category starts at 100 points with deductions/bonuses:

**Example deductions:**
- File truncated (>20K): -30 pts (Context Efficiency)
- Always-loaded >12K tokens: -20 pts (Context Efficiency)
- HEARTBEAT.md >2K chars: -10 pts (Context Efficiency)
- Duplicate rule in 2+ files: -10 pts each (Redundancy, max -30)
- Plaintext credential: -30 pts each (Security)
- Stale date reference: -5 pts each (Freshness, max -15)

**Bonuses:**
- Always-loaded <5K tokens: +10 pts (Context Efficiency)
- Always-loaded <3K tokens: +15 pts (Context Efficiency)
- Zero cross-file duplication: +10 pts (Redundancy)
- Clean security posture: +10 pts (Security)

**Overall score:**
```
Overall = (CE × 0.25) + (RD × 0.20) + (OC × 0.20) + (SC × 0.15) + (FR × 0.10) + (CO × 0.10)
```

**Grades:**
- 95-100: A+ (Exceptional)
- 90-94: A (Excellent)
- 75-89: B (Good)
- 60-74: C (Needs attention)
- 40-59: D (Needs work)
- 0-39: F (Critical)

**Exit code:**
- 0 → A or B (healthy)
- 1 → C or below (needs attention)

---

## LLM-Assisted Mode: How to Run

When the user requests an audit, follow this workflow:

### Step 1: Execute the script

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh
```

Capture the output (or use `--json` for structured data).

### Step 2: Read best practices

```bash
read references/best-practices.md
```

This file contains:
- What each workspace file is for
- Ideal size targets
- Context budget management
- Common anti-patterns
- Security best practices
- Memory architecture
- Heartbeat efficiency
- What belongs where

### Step 3: Analyze findings

Combine script output + best practices to provide:

1. **What the script found** (objective metrics)
2. **Why it matters** (context from best-practices.md)
3. **Specific fixes** (subjective analysis of actual content)

**Example subjective insights:**
- "Your AGENTS.md has 47 rules — consider grouping related rules under H2 sections"
- "SOUL.md includes operational instructions like 'always check QMD first' — move to AGENTS.md"
- "HEARTBEAT.md contains detailed task descriptions — replace with short bullet points and reference AGENTS.md for details"
- "12 rules in AGENTS.md reference dates from November 2025 — these are now habits, condense to principles"

### Step 4: Present integrated report

**Telegram-friendly format** (keep messages <4096 chars):

```
🔍 OPENCLAW WORKSPACE AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Overall: XX/100 — Grade X (Label)

[Emoji bars for each category]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 KEY FINDINGS

🔴 Critical:
• AGENTS.md truncated at 20K (2K chars lost)
• 3 potential credentials found in TOOLS.md

⚠️ High priority:
• Always-loaded: 13K tokens (target: <8K)
• HEARTBEAT.md: 3.9K chars (target: <2K)

💡 Quick wins:
• Remove 23 duplicate lines across files (+10 pts)
• Archive 7 stale MEMORY.md entries (+5 pts)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 SPECIFIC RECOMMENDATIONS

1. **Condense AGENTS.md (22K → 12K)**
   • Remove 12 dated rules (e.g., "On 2025-11-15...")
   • Consolidate lessons into principles
   • Move tool docs to TOOLS.md

2. **Trim HEARTBEAT.md (3.9K → 1.2K)**
   • Remove completed projects
   • Replace detailed instructions with short checklist
   • Reference AGENTS.md for details

3. **Deduplicate rules**
   • [Specific example of duplicate found]
   • Choose single source of truth per rule
```

---

## Additional Tools

### Audit Installed Skills

Check health of all skills in the workspace:

```bash
bash scripts/self-audit.sh
bash scripts/self-audit.sh --json
```

Checks for:
- Valid frontmatter (name, description)
- Skill file sizes
- Presence of references/ directories
- Stale skills (>180 days since modification)

### Trend Analysis

Track improvement over time:

```bash
bash scripts/trend.sh
bash scripts/trend.sh --all
bash scripts/trend.sh --json --limit 20
```

Requires: saved audit history (run audit with `--save` flag)

Shows:
- Score progression over time
- Grade changes
- Per-category trends
- Overall delta (first → last)

---

## Telegram Considerations

- **Keep messages <4096 chars** (split if needed)
- **Use emoji bars** instead of ASCII art
- **Bold key findings** for scannability
- **Prioritize recommendations** by impact (critical → quick wins)
- **Split report if needed**: Overview → Scores → Recommendations

**Message splitting example:**

Message 1: Header + Scores
Message 2: File map + Metrics
Message 3: Recommendations

---

## Best Practices Reference

The `references/best-practices.md` file is your knowledge base. It contains:

- **File-by-file guidance** (what belongs where, ideal sizes)
- **Context budget management** (always-loaded vs on-demand)
- **Memory architecture** (daily logs vs MEMORY.md vs semantic memory)
- **Heartbeat efficiency** (why HEARTBEAT.md must be tiny)
- **Common anti-patterns** (with examples)
- **Security best practices** (never store credentials in workspace)
- **Maintenance schedules** (when to audit, archive, condense)

**Always reference this file when providing LLM-assisted analysis.**

---

## Script Output Formats

### Human-Readable (Default)

Telegram-friendly with emoji bars:

```
🔍 OPENCLAW WORKSPACE AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Overall: 92/100 — Grade A (Excellent)

Context Efficiency  🟩🟩🟩🟩🟩🟩🟩🟩🟩🟨  95/100 A+
Redundancy          🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩  100/100 A+
...
```

### JSON (--json flag)

Structured data for automation:

```json
{
  "timestamp": "2026-03-05T14:23:45Z",
  "workspace": "/home/user/.openclaw/workspace",
  "overall": { "score": 92, "grade": "A", "label": "Excellent" },
  "scores": { ... },
  "metrics": { ... },
  "files": [ ... ],
  "recommendations": [ ... ]
}
```

---

## Exit Codes

The audit script returns:
- **0** → Grade A or B (workspace healthy)
- **1** → Grade C or below (needs attention)

Use in automation:

```bash
if bash scripts/audit.sh --json --save; then
  echo "✅ Workspace healthy"
else
  echo "⚠️ Workspace needs optimization"
  bash scripts/audit.sh --json | jq '.recommendations'
fi
```

---

## Example Workflow (LLM-Assisted)

**User:** "audit my config"

**Agent:**

1. **Run script:**
   ```bash
   bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh
   ```

2. **Read best practices:**
   ```bash
   read references/best-practices.md
   ```

3. **Analyze findings:**
   - Script reports: Overall 68/100 (Grade C)
   - Context Efficiency: 52/100 (D)
   - 1 file truncated (AGENTS.md at 22K)
   - 23 duplicate lines across files
   - HEARTBEAT.md is 3.9K (should be <2K)

4. **Read actual files to provide specific advice:**
   ```bash
   head -50 AGENTS.md
   head -50 HEARTBEAT.md
   ```

5. **Present integrated report:**
   - Show script scores
   - Explain what each score means
   - Provide specific, actionable fixes:
     * "Your AGENTS.md has 12 rules with dates from Nov 2025. Example: 'On 2025-11-15 we fixed X' — condense these to 'Always verify X before Y'"
     * "HEARTBEAT.md line 45-78 contains detailed task instructions — move to AGENTS.md and reference here with '- Check project status (see AGENTS.md)'"
   - Rank recommendations by impact

---

## Summary

**Script-only mode:**
- Fast, deterministic, always accurate
- Perfect for monitoring and automation
- Run with `bash scripts/audit.sh`

**LLM-assisted mode:**
- Script findings + subjective analysis
- Specific rewrite suggestions
- Educational (explains best practices)
- Best for first-time audits and major refactoring

**Both modes use the same scoring algorithm and checks.**

**Always reference:**
- `references/best-practices.md` for guidance
- `examples/sample-report.md` for output examples
- `config.json` for threshold customization

**Run weekly, keep your workspace lean, save tokens.** 🚀
