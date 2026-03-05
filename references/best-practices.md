# OpenClaw Workspace Best Practices

> Compiled from official OpenClaw documentation: agent-workspace.md, context.md, memory.md, heartbeat.md, system-prompt.md, compaction.md

## The Core Problem

Your workspace files (AGENTS.md, SOUL.md, TOOLS.md, etc.) are **injected into every session's system prompt**. They consume tokens on every turn. OpenClaw truncates files at 20,000 chars per file, so bloat = lost instructions + wasted token budget.

**Key metrics:**
- Files are injected as-is (raw Markdown)
- Token estimate: `chars / 4` (rough)
- Truncation limit: `20,000 chars` per file (configurable via `agents.defaults.bootstrapMaxChars`)
- Always-loaded: AGENTS.md + SOUL.md + USER.md + IDENTITY.md + TOOLS.md + HEARTBEAT.md
- On-demand: MEMORY.md (main session only), `memory/YYYY-MM-DD.md` (via memory tools)

## What Each File Is For

### AGENTS.md — Operating Instructions
**Purpose:** HOW the agent should operate. Rules, priorities, workflows, recall protocols.

**Ideal size:** <8K chars (~2K tokens)  
**Warning:** >15K chars  
**Critical:** >20K chars (truncation zone)

**What belongs here:**
- Core operating rules and priorities
- Memory/recall protocols (when to use OpenBrain, QMD, etc.)
- Safety rules (what to ask before doing)
- Permissions (what requires approval)
- Formatting rules (per-channel output preferences)
- Group chat behavior
- Receipt/expense tracking workflows

**What does NOT belong here:**
- Identity/personality (→ SOUL.md)
- Tool-specific notes (→ TOOLS.md)
- Long-term facts/decisions (→ MEMORY.md)
- User profile (→ USER.md)
- Stale dated rules from >60 days ago that are now habits

**Anti-patterns:**
```markdown
❌ "On 2025-11-15 we learned X" (stale date reference)
❌ Long backstories about past mistakes
❌ Repeating identity info already in SOUL.md
❌ Wall-of-text with no section structure

✅ "When X happens, do Y"
✅ Clear numbered/bulleted rules
✅ Current, actionable instructions
```

### SOUL.md — Persona & Identity
**Purpose:** WHO the agent is. Tone, personality, boundaries, values.

**Ideal size:** <3K chars (~750 tokens)  
**Warning:** >5K chars  
**Critical:** >10K chars

**What belongs here:**
- Persona/character definition
- Tone and voice
- Core values and boundaries
- How you present yourself
- What makes you "you"

**What does NOT belong here:**
- Procedural instructions (→ AGENTS.md)
- Operating rules (→ AGENTS.md)
- Long anti-patterns lists
- Tool documentation

**Anti-patterns:**
```markdown
❌ "Always check QMD before reading files" (operational rule)
❌ 20+ bullet point lists
❌ Repeating rules from AGENTS.md

✅ Concise personality sketch
✅ Tone examples
✅ Core principles
```

### HEARTBEAT.md — Scheduled Checklist
**Purpose:** Tiny checklist for periodic heartbeat checks (~48x/day at 30min interval).

**Ideal size:** <1.5K chars (~375 tokens)  
**Warning:** >2K chars  
**Critical:** >5K chars

**Why it must be tiny:** This file is injected **every heartbeat poll** (every 30-60 minutes). Even 1KB of bloat = 48KB/day = 1.4MB/month of wasted tokens.

**What belongs here:**
- Short checklist of things to check
- Active project reminders
- Quick status checks

**What does NOT belong here:**
- Detailed instructions (→ AGENTS.md)
- Long task descriptions
- Completed/abandoned projects
- Anything not actively relevant

**Anti-patterns:**
```markdown
❌ Detailed descriptions of how to do each task
❌ Projects that finished months ago
❌ Long explanations

✅ "- Check inboxes for urgent items"
✅ "- If daytime, do lightweight check-in if nothing pending"
```

### USER.md — User Profile
**Purpose:** WHO the user is. Name, timezone, preferences, communication style.

**Ideal size:** <1K chars (~250 tokens)  
**Warning:** >2K chars  
**Critical:** >5K chars

**What belongs here:**
- Name, pronouns, preferred name
- Timezone
- Contact preferences
- Communication style
- Key relationships (family members, etc.)

**What does NOT belong here:**
- Long backstories
- Detailed life history
- Instructions for the agent (→ AGENTS.md)

### IDENTITY.md — Agent Identity
**Purpose:** Agent's name, emoji, creature type (created during bootstrap ritual).

**Ideal size:** <500 chars (~125 tokens)  
**Warning:** >1K chars  
**Critical:** >3K chars

**What belongs here:**
- Agent name
- Emoji/avatar
- Creature type
- Brief one-liner

**What does NOT belong here:**
- Personality details (→ SOUL.md)
- Operating instructions (→ AGENTS.md)
- Duplication of SOUL.md content

### TOOLS.md — Local Tool Notes
**Purpose:** Environment-specific notes about YOUR tools/setup. Camera names, SSH hosts, API details, device nicknames.

**Ideal size:** <5K chars (~1.25K tokens)  
**Warning:** >10K chars  
**Critical:** >20K chars

**What belongs here:**
- Camera names/locations
- SSH aliases
- Preferred TTS voices
- Device nicknames
- Environment-specific shortcuts
- Custom script locations

**What does NOT belong here:**
- Plaintext credentials (use `~/.openclaw/credentials/`)
- Operating instructions (→ AGENTS.md)
- Stale tool references for tools that no longer exist

**Security rule:** NEVER store API keys, passwords, or secrets in TOOLS.md. Use `~/.openclaw/credentials/` for secrets.

### MEMORY.md — Long-term Memory
**Purpose:** Curated long-term facts, decisions, preferences. **Main session only** (never loaded in groups).

**Ideal size:** <8K chars (~2K tokens)  
**Warning:** >15K chars  
**Critical:** >20K chars

**What belongs here:**
- Durable facts and decisions
- User preferences that don't fit in USER.md
- Important context that spans months
- Key learnings and principles

**What does NOT belong here:**
- Day-to-day notes (→ `memory/YYYY-MM-DD.md`)
- Operating instructions (→ AGENTS.md)
- Stale information >60 days old that's never referenced
- Secrets/credentials
- Exact duplicates of rules in AGENTS.md

**Memory hierarchy:**
- **Daily logs:** `memory/YYYY-MM-DD.md` — append-only, read today + yesterday on session start
- **Long-term:** `MEMORY.md` — curated, loaded in main session only
- **Semantic memory:** OpenBrain (PostgreSQL + pgvector) or QMD (local search)

## Context Budget Management

### The Always-Loaded Bundle
These files are injected **every session start**:
- AGENTS.md
- SOUL.md
- USER.md
- IDENTITY.md
- TOOLS.md
- HEARTBEAT.md

**Token budget calculation:**
```
always_loaded_tokens = sum(min(file_chars, 20000) for each file) / 4
```

### Budget Health Grades

| Total Tokens | Grade | Assessment |
|-------------|-------|------------|
| <3,000 | A+ | Exceptionally lean |
| 3,000-5,000 | A | Efficient |
| 5,000-8,000 | B | Acceptable |
| 8,000-12,000 | C | Heavy — review for cuts |
| 12,000-15,000 | D | Bloated — actively hurting performance |
| >15,000 | F | Critical — files being truncated, instructions lost |

### Truncation = Lost Instructions
When a file exceeds 20,000 chars, OpenClaw truncates it with a marker. **Everything past 20K is invisible to the agent.**

**If your AGENTS.md is 25K:**
- First 20K chars are injected
- Last 5K chars are **lost**
- Critical rules at the end may never be seen

**Solution:** Condense, archive, or split content.

## Memory Architecture

OpenClaw supports multiple memory layers:

### 1. Daily Logs (`memory/YYYY-MM-DD.md`)
- **Not injected automatically** (accessed via tools)
- Read today + yesterday on session start (common pattern in AGENTS.md)
- Append-only, one file per day
- Token cost: only when explicitly read

### 2. Long-term Memory (`MEMORY.md`)
- Injected in main session only (never in groups)
- Curated, durable facts
- Review regularly and archive stale content

### 3. Semantic Memory
- **OpenBrain:** PostgreSQL + pgvector (check FIRST for recalls)
- **QMD:** Local search engine (check SECOND before reading files)
- Token savings: 2-3K per search vs reading full files

### Automatic Memory Flush
Before auto-compaction, OpenClaw triggers a **silent agentic turn** that reminds the model to write durable memory to disk. This is controlled by `agents.defaults.compaction.memoryFlush`.

**The contract:**
- If nothing to store, reply `NO_REPLY`
- Write lasting notes to `memory/YYYY-MM-DD.md`
- Keep it concise

## Heartbeat Efficiency

Heartbeats run every 30-60 minutes (~48x/day). Every byte in HEARTBEAT.md is injected 48 times.

**Cost example:**
- 5KB HEARTBEAT.md = 240KB/day = 7.2MB/month of wasted tokens
- 1KB HEARTBEAT.md = 48KB/day = 1.4MB/month (acceptable)

**Optimization strategies:**
1. Keep HEARTBEAT.md <2K chars
2. Use `target: "none"` if you only want internal checks
3. Use a cheaper model for heartbeats
4. Set `activeHours` to restrict heartbeats to working hours
5. Empty HEARTBEAT.md is fine — the agent will still run basic checks

**Visibility controls:**
```json5
channels: {
  defaults: {
    heartbeat: {
      showOk: false,      // Hide HEARTBEAT_OK acks (default)
      showAlerts: true,   // Show alert messages (default)
      useIndicator: true  // Emit indicator events (default)
    }
  }
}
```

## Common Anti-Patterns

### 1. Duplication Across Files
**Problem:** Same rule appears in AGENTS.md, SOUL.md, and MEMORY.md.

**Solution:** Each file should own distinct content:
- AGENTS.md = HOW to operate
- SOUL.md = WHO you are
- MEMORY.md = WHAT you know
- TOOLS.md = Environment specifics

### 2. Stale Date References
**Problem:** "On 2025-11-15 we fixed X" still in AGENTS.md 6 months later.

**Solution:**
- Archive dated lessons after 60 days
- Condense into principles
- Move to `memory/archive/` if historically important

### 3. Graduated Lessons
**Problem:** Long explanations of mistakes with dates.

**Solution:** Condense into actionable rules:
```markdown
❌ "On 2025-11-15 I posted broken links. Never do that again."
✅ "Verify URLs return 200 before posting publicly."
```

### 4. Identity in Multiple Files
**Problem:** Persona info in SOUL.md, IDENTITY.md, and AGENTS.md.

**Solution:**
- IDENTITY.md = name, emoji, creature type (tiny)
- SOUL.md = personality, tone, values (concise)
- AGENTS.md = operating rules only (no identity)

### 5. Operational Rules in SOUL.md
**Problem:** "Always check QMD before reading files" in SOUL.md.

**Solution:** Move to AGENTS.md. SOUL.md is WHO, not HOW.

### 6. Tool Documentation in AGENTS.md
**Problem:** Long explanations of how to use scrapling, QMD, X posting scripts.

**Solution:** Move to TOOLS.md. Keep AGENTS.md focused on operating principles.

### 7. Credentials in Workspace Files
**Problem:** API keys, passwords in TOOLS.md or MEMORY.md.

**Solution:**
- Store in `~/.openclaw/credentials/`
- Reference them by path in TOOLS.md
- Never commit secrets to git

### 8. Massive HEARTBEAT.md
**Problem:** 10KB checklist with detailed instructions.

**Solution:**
- Keep <2K chars
- Reference AGENTS.md for details
- Remove completed projects

## What Belongs Where

Quick reference:

| Content Type | File |
|-------------|------|
| Operating rules | AGENTS.md |
| Memory protocols | AGENTS.md |
| Safety rules | AGENTS.md |
| Permissions | AGENTS.md |
| Channel formatting | AGENTS.md |
| Personality/tone | SOUL.md |
| Core values | SOUL.md |
| Boundaries | SOUL.md |
| User name/timezone | USER.md |
| Communication prefs | USER.md |
| Agent name/emoji | IDENTITY.md |
| Camera names | TOOLS.md |
| SSH aliases | TOOLS.md |
| Custom scripts | TOOLS.md |
| Long-term facts | MEMORY.md |
| Decisions/preferences | MEMORY.md |
| Daily notes | memory/YYYY-MM-DD.md |
| Heartbeat checklist | HEARTBEAT.md |
| Active project reminders | HEARTBEAT.md |

## Security Best Practices

1. **Never store credentials in workspace files**
   - Use `~/.openclaw/credentials/` for secrets
   - Even private repos can leak

2. **Treat MEMORY.md as potentially shared**
   - Don't put highly sensitive info even though it's "main session only"
   - Context can leak via screenshots, logs, debugging

3. **Use `.gitignore` for sensitive patterns**
   ```gitignore
   .DS_Store
   .env
   **/*.key
   **/*.pem
   **/secrets*
   ```

4. **Scan for accidental leaks**
   - API keys (patterns: `api[_-]?key`, `token`, `bearer`)
   - High-entropy strings (potential keys)
   - Passwords, credentials

## Freshness & Maintenance

### Regular Audits
- Run `/ocaudit` weekly
- Check for stale date references (>60 days old)
- Archive completed projects
- Condense graduated lessons into principles

### File Freshness Checks
- Last modified dates on all files
- Stale content that hasn't been referenced in 60+ days
- Outdated version references
- Dead tool references

### Memory Maintenance
- Review MEMORY.md quarterly
- Archive old entries to `memory/archive/YYYY-MM.md`
- Check for duplicates with AGENTS.md
- Verify all memory is still relevant

## Compaction & Context Windows

Every model has a **context window** (token limit). Long sessions accumulate messages and tool results. When the window is tight, OpenClaw **compacts** older history:

1. Summarizes older conversation into a compact entry
2. Keeps recent messages intact
3. Summary persists in session JSONL

**Commands:**
- `/status` — shows compaction count and context usage
- `/compact` — manually trigger compaction
- `/context list` — see what's injected and sizes
- `/context detail` — deeper breakdown per file/tool

**Auto-compaction triggers when:**
- Session nears context window limit
- Configured via `agents.defaults.compaction.reserveTokensFloor`

**Pre-compaction memory flush:**
- Silent turn before compaction
- Agent writes durable memory to disk
- Reply `NO_REPLY` if nothing to store

## Tools That Save Tokens

### QMD (Query Markup Documents)
**Always search QMD before reading files.**

Token savings: 2-3K per search vs reading full files.

```bash
qmd search "query" -n 5                    # Keyword search
qmd search "query" -c memory               # Search specific collection
qmd query "query" --json                   # Hybrid: keyword + vector + reranking
```

### OpenBrain (Semantic Memory)
**Check FIRST for any recall.**

Vector search over stored thoughts. Use before QMD, before file reads.

```bash
/root/.openclaw/workspace/openbrain/query.sh "search terms" [limit]
```

### Memory Tools
- `memory_search` — semantic search over memory files (doesn't inject full files)
- `memory_get` — read specific memory file only when needed

## Performance Optimization Checklist

- [ ] Total always-loaded tokens <8K
- [ ] No files truncated (all <20K chars)
- [ ] HEARTBEAT.md <2K chars
- [ ] No cross-file duplication
- [ ] No stale date references >60 days old
- [ ] No credentials in workspace files
- [ ] AGENTS.md <15K chars
- [ ] SOUL.md <5K chars
- [ ] MEMORY.md <15K chars
- [ ] All files have clear section structure
- [ ] Daily memory logs used for ephemeral notes
- [ ] QMD/OpenBrain used before file reads
- [ ] Git backup of workspace to private repo

## Monitoring Commands

```bash
# See context breakdown
/context list
/context detail

# Session status
/status

# Manual compaction
/compact

# Audit workspace
/ocaudit

# Check audit script directly
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh --json
```

## Summary: The Golden Rules

1. **Keep files under 20K chars** (or they're truncated)
2. **Target <8K total always-loaded tokens** (grade B or better)
3. **Each file owns distinct content** (no duplication)
4. **HEARTBEAT.md must be tiny** (<2K chars, 48x/day cost)
5. **Credentials never in workspace** (use `~/.openclaw/credentials/`)
6. **Archive stale content** (dates >60 days old)
7. **Use memory tools** (QMD, OpenBrain before file reads)
8. **Daily logs for ephemeral notes** (`memory/YYYY-MM-DD.md`)
9. **MEMORY.md for durable facts** (curated, main session only)
10. **Audit weekly** (`/ocaudit` or audit script)

---

**Sources:**
- `/usr/lib/node_modules/openclaw/docs/concepts/agent-workspace.md`
- `/usr/lib/node_modules/openclaw/docs/concepts/context.md`
- `/usr/lib/node_modules/openclaw/docs/concepts/memory.md`
- `/usr/lib/node_modules/openclaw/docs/gateway/heartbeat.md`
- `/usr/lib/node_modules/openclaw/docs/concepts/system-prompt.md`
- `/usr/lib/node_modules/openclaw/docs/concepts/compaction.md`
