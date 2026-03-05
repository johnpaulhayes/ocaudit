# ocaudit — OpenClaw Workspace Audit Tool

> **Your OpenClaw workspace files consume tokens every session. Are you wasting them?**

ocaudit is a production-quality workspace audit tool for [OpenClaw](https://github.com/openclaw/openclaw) that analyzes your configuration files (AGENTS.md, SOUL.md, HEARTBEAT.md, etc.) for bloat, redundancy, security issues, and context efficiency — **without needing an LLM**.

Inspired by [claudit](https://github.com/quickstop/claudit), but purpose-built for OpenClaw's architecture and token economy.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## The Problem

OpenClaw injects your workspace files into **every session's system prompt**:
- AGENTS.md, SOUL.md, USER.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md

These files are:
- **Always loaded** → consume tokens on every turn
- **Truncated at 20K chars per file** → bloat = lost instructions
- **Easy to bloat** → copy-paste, duplication, stale content accumulates
- **Costly** → 10K wasted tokens × 10 sessions/day = 100K tokens/day

**Example:**
- A 22K AGENTS.md gets truncated — the last 2K chars (critical rules) are **invisible** to the agent
- A 4K HEARTBEAT.md burns 192K chars/day (48 heartbeats × 4K) for a checklist that should be <1K
- Duplicate rules across files waste tokens AND create contradictions

ocaudit **finds these issues automatically** and scores your workspace health.

---

## Features

- ✅ **Deterministic auditing** — no LLM required, pure bash
- 📊 **6-category scoring** — context efficiency, redundancy, clarity, security, freshness, completeness
- 🔍 **Secret detection** — regex patterns + Shannon entropy detection for API keys
- 📈 **Trend tracking** — save audit history and track improvements over time
- 🎯 **Actionable recommendations** — ranked by point impact
- 🌈 **Telegram-friendly output** — emoji progress bars, <4096 char messages
- 🔧 **Customizable thresholds** — edit `config.json` to match your workflow
- 📦 **Zero dependencies** — bash, grep, awk, wc (standard Unix tools)
- 🚀 **Multi-agent support** — audit all agents with `--all-agents`
- 💾 **History tracking** — `--save` to build trend data

---

## Installation

### Option 1: Clone into skills directory (current)

```bash
cd ~/.openclaw/workspace/skills
git clone https://github.com/johnpaulhayes/ocaudit.git
```

### Option 2: Copy the skill (manual)

```bash
cp -r ocaudit ~/.openclaw/workspace/skills/
```

### Option 3: ClawhHub (future)

```bash
openclaw skills install ocaudit
```

---

## Usage

### Basic audit (human-readable report)

```bash
# From OpenClaw chat
/ocaudit

# Direct script execution
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh
```

### JSON output (for automation)

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh --json
```

### Audit a specific workspace

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh --workspace /path/to/workspace
```

### Save results to history

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh --json --save
```

### View trends over time

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/trend.sh
bash ~/.openclaw/workspace/skills/ocaudit/scripts/trend.sh --all
bash ~/.openclaw/workspace/skills/ocaudit/scripts/trend.sh --json
```

### Audit installed skills

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/self-audit.sh
bash ~/.openclaw/workspace/skills/ocaudit/scripts/self-audit.sh --json
```

### Multi-agent audit

```bash
bash ~/.openclaw/workspace/skills/ocaudit/scripts/audit.sh --all-agents
```

---

## What Gets Audited

### Core Files

| File | Purpose | Ideal Size | Critical Size |
|------|---------|------------|---------------|
| **AGENTS.md** | Operating instructions, rules | <8K | >20K (truncated) |
| **SOUL.md** | Persona, tone, identity | <3K | >10K |
| **HEARTBEAT.md** | Periodic checklist (48×/day!) | <1.5K | >5K |
| **USER.md** | User profile, preferences | <1K | >5K |
| **IDENTITY.md** | Agent name, emoji, type | <500 | >3K |
| **TOOLS.md** | Local tool notes | <5K | >20K |
| **MEMORY.md** | Long-term memory (main session) | <8K | >20K |

### What We Check

**Context Efficiency (25% weight)**
- Total always-loaded tokens
- Files truncated by OpenClaw (>20K)
- Per-file size vs targets
- HEARTBEAT.md bloat (highest cost/char)

**Redundancy (20% weight)**
- Cross-file duplicate lines
- Same rules in multiple files
- Duplicate facts in MEMORY.md + AGENTS.md

**Operational Clarity (20% weight)**
- Number of rules in AGENTS.md (>20 = too many)
- Section structure (clear H2/H3 organization)
- Contradicting instructions across files

**Security (15% weight)**
- Plaintext credentials (regex patterns)
- High-entropy strings (Shannon entropy >4.5 bits/char, >20 chars)
- Personal data in non-MEMORY files

**Freshness (10% weight)**
- Stale date references (>60 days old)
- Days since last memory log
- References to completed projects

**Completeness (10% weight)**
- Required files present
- USER.md has timezone
- Files properly structured

---

## Scoring System

### Overall Grade

| Score | Grade | Label | Meaning |
|-------|-------|-------|---------|
| 95-100 | A+ | Exceptional | Production-ready workspace |
| 90-94 | A | Excellent | Very efficient |
| 75-89 | B | Good | Minor improvements possible |
| 60-74 | C | Needs attention | Review recommendations |
| 40-59 | D | Needs work | Significant issues |
| 0-39 | F | Critical | Files truncated/major problems |

### Exit Codes

- `0` → Grade A or B (healthy)
- `1` → Grade C or below (needs attention)

Use in CI/CD:
```bash
if bash audit.sh; then
  echo "Workspace healthy!"
else
  echo "Workspace needs optimization"
  bash audit.sh --json | jq '.recommendations'
fi
```

---

## Sample Output

See [examples/sample-report.md](examples/sample-report.md) for full before/after examples.

### Quick Preview

```
🔍 OPENCLAW WORKSPACE AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Overall: 92/100 — Grade A (Excellent)

Context Efficiency  🟩🟩🟩🟩🟩🟩🟩🟩🟩🟨  95/100 A+
Redundancy          🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩  100/100 A+
Operational Clarity 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟨  90/100 A
Security            🟩🟩🟩🟩🟩🟩🟩🟩🟩🟨  95/100 A+
Freshness           🟩🟩🟩🟩🟩🟩🟩🟩🟨⬜  85/100 B
Completeness        🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩  100/100 A+
```

---

## Configuration

Edit `config.json` to customize thresholds:

```json
{
  "version": "1.0.0",
  "targets": {
    "AGENTS.md": { "ideal": 8000, "warn": 15000, "critical": 20000 },
    "HEARTBEAT.md": { "ideal": 1500, "warn": 2000, "critical": 5000 }
  },
  "truncationLimit": 20000,
  "secretPatterns": ["password", "api[_-]?key", "token", "secret"],
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

## Best Practices Reference

See [references/best-practices.md](references/best-practices.md) for comprehensive OpenClaw workspace optimization guidance, compiled from official documentation.

**Quick rules:**
1. Keep files under 20K chars (or they're truncated)
2. Target <8K total always-loaded tokens
3. HEARTBEAT.md must be tiny (<2K, 48×/day cost)
4. No duplication across files
5. Credentials in `~/.openclaw/credentials/`, never workspace files
6. Archive stale content (dates >60 days old)
7. Use QMD/OpenBrain before file reads
8. Daily logs for ephemeral notes, MEMORY.md for durable facts

---

## Comparison to claudit

ocaudit is **inspired by** [claudit](https://github.com/quickstop/claudit) (the excellent Claude Project configuration auditor), but adapted for OpenClaw's architecture:

| Feature | claudit | ocaudit |
|---------|---------|---------|
| **Target** | Claude Projects | OpenClaw workspaces |
| **Checks** | Project knowledge | 7 workspace files + cross-file analysis |
| **Truncation** | N/A | 20K/file limit detection |
| **Heartbeat cost** | N/A | HEARTBEAT.md 48×/day analysis |
| **Security** | Basic | Regex + entropy detection |
| **Skills audit** | N/A | `self-audit.sh` for skill health |
| **Trends** | N/A | Historical tracking + `trend.sh` |
| **Multi-agent** | N/A | `--all-agents` support |

Both tools share the same philosophy: **visibility into what your AI is seeing** to optimize token efficiency.

---

## File Structure

```
skills/ocaudit/
├── README.md              # This file
├── SKILL.md               # OpenClaw skill definition (LLM instructions)
├── config.json            # Customizable thresholds
├── references/
│   └── best-practices.md  # OpenClaw workspace best practices guide
├── examples/
│   └── sample-report.md   # Before/after audit examples
├── scripts/
│   ├── audit.sh           # Main audit script (deterministic)
│   ├── self-audit.sh      # Audit installed skills
│   └── trend.sh           # Historical trend analysis
└── history/               # Saved audit results (JSON)
    └── .gitkeep
```

---

## Requirements

- **OS:** Linux, macOS, WSL2
- **Dependencies:** bash, grep, awk, wc, find, date (standard Unix tools)
- **Optional:** jq (for prettier JSON handling in config loading)

No Python, Node, or LLM API calls required.

---

## Contributing

Contributions welcome! This is a community tool.

**Areas for improvement:**
- [ ] Add auto-fix mode (apply recommendations automatically with `--fix`)
- [ ] Per-agent threshold overrides
- [ ] Integration with OpenClaw's `/doctor` command
- [ ] GitHub Actions workflow for automated audits
- [ ] Web UI for visualizing trends
- [ ] Support for custom workspace file patterns
- [ ] Machine-readable output formats (SARIF, JUnit XML)

**How to contribute:**
1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Credits

- **Inspired by:** [claudit](https://github.com/quickstop/claudit) by quickstop
- **Built for:** [OpenClaw](https://github.com/openclaw/openclaw) by cncolder
- **Maintained by:** Community contributors

---

## Support

- **Issues:** [GitHub Issues](https://github.com/johnpaulhayes/ocaudit/issues)
- **Discussions:** [OpenClaw Discord](https://discord.gg/openclaw)
- **OpenClaw Docs:** [https://openclaw.org/docs](https://openclaw.org/docs)
- **ClawhHub:** [https://clawhub.com](https://clawhub.com)

---

## Changelog

### v1.0.0 (2026-03-05)
- Initial production release
- 6-category scoring system
- Secret detection (regex + entropy)
- Cross-file duplication detection
- History tracking and trend analysis
- Skills audit (`self-audit.sh`)
- Multi-agent support
- Comprehensive best practices reference

---

## Support ocaudit

If ocaudit saved you tokens (and sanity), consider buying me a coffee:

Support ocaudit [https://buy.stripe.com/bJe28t2Xf26631T27Qco000]

ocaudit is free and open source. Tips help fund continued development and new features.


**Remember:** Your workspace files are injected into every session. An hour spent optimizing can save thousands of tokens per day. 🚀
