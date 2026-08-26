# Awais AI Skills Hub

A universal, open-standard repository of production AI Agent Skills and engineering workflows designed to work seamlessly across **Claude Code, OpenAI Codex, Google Antigravity, Cursor, Windsurf, and Copilot CLI**.

---

## ⚡ Quick Start: Install Skills

Use the unified installer script to link or copy all skills into your local agent environment:

```bash
# Symlink skills for all detected agents (Claude Code, Codex, Antigravity, Cursor)
./scripts/install-skills.sh --all

# Or install specifically for Claude Code:
./scripts/install-skills.sh --claude

# Or install specifically for OpenAI Codex / Google Antigravity:
./scripts/install-skills.sh --agents

# Or install into a custom project path:
./scripts/install-skills.sh --target /path/to/your/project/.claude/skills
```

To validate all skills and maintain repository compatibility:
```bash
python3 scripts/sync-skills.py
```

---

## 🚀 Featured Skill: `app-init`

Location: [`skills/app-init/`](skills/app-init/SKILL.md)

Two-phase repo scaffolder for a new or existing app: **Phase 1** sets up the agent-coding process infrastructure (`AGENTS.md`-canonical / `CLAUDE.md`-pointer, a versioned spec with immutable snapshots, split shipped/spec changelogs, a roadmap, release docs, and a `STATUS.md` cross-session handoff log so any agent can pick up in-progress work cold); **Phase 2** runs a platform feature-checklist playbook (iOS today, via `ios-common-features`) with a configurable manual/simulator/browser/E2E verification mode, persisted per repo and switchable later with a flag.

---

## 📱 Featured Skill: `ios-common-features`

Location: [`skills/ios-common-features/`](skills/ios-common-features/SKILL.md)

Production architecture, SwiftUI components, and business rules for mandatory iOS application features:

### Core Capabilities:
1. **Support & Links Card**: Unified Settings card with clean labels for Website, Terms of Use, Privacy Policy, Support, Rate The App, and iPad-safe system share sheet (`UIActivityViewController`).
2. **Version & Update Card**: Dynamic version / build number extraction (`CFBundleShortVersionString` + `CFBundleVersion`), interactive "Check for Updates" action with spinner and status feedback, and copyright notice.
3. **Automated Update Checking & Alerts**: Launch/foreground update checks (iTunes Lookup API / custom backend), native update alert prompts, red circle notification badge (`1`), and a top-of-Settings upgrade banner.
4. **Smart Usage-Based Paywall**: Tracks user session frequency and free core actions, enforcing a strict **fortnightly (14-day)** cooldown between automatic paywall presentations.
5. **Persistent Upgrade Entry Point**: Always-visible top-right "Upgrade" pill (hidden once premium) opening a paywall sheet that supports both auto-renewable-subscription and one-time-lifetime-unlock monetization models.
6. **App Store Rating Flow**: Native StoreKit review requests triggered only after positive user milestones, protected by an internal **3-month (90-day)** cooldown.
7. **Optional, Non-Blocking Permissions**: Camera/mic/location/notifications never gate a feature's existence, plus a full-width permission-nudge banner explaining denied/undetermined permissions in plain language.
8. **Adaptive Appearance**: Semantic light/dark colors and Liquid Glass / system-material surfaces.
9. **First-Launch Onboarding**: Resumable, spec-derived multi-step onboarding flow.

---

## 📁 Repository Structure

```
awais-ai-skills/
├── README.md                      # Hub documentation and skill catalog
├── AGENTS.md                      # Multi-agent standard operational instructions
├── scripts/
│   ├── install-skills.sh          # One-command installer for local agent runtimes
│   └── sync-skills.py             # YAML frontmatter validator and symlink synchronizer
├── skills/                        # Canonical Open-Standard Skills (agentskills.io spec)
│   ├── app-init/                  # Agent-Coding Process Scaffolding + Feature Playbooks
│   ├── ios-common-features/       # iOS Standard Architecture & SwiftUI Components
│   ├── design-system/             # Design Tokens, Components, & Slide Creation
│   ├── ui-ux-pro-max/             # UI/UX Engineering & Styling Standards
│   ├── superpowers/               # TDD, Systematic Debugging, & Plan Execution
│   ├── expo-*                     # 15+ Expo & React Native production skills
│   └── ...                        # 90+ consolidated engineering skills
├── .claude/
│   └── skills -> ../skills        # Symlink for Claude Code compatibility
└── .agents/
    └── skills -> ../skills        # Symlink for Codex / Antigravity compatibility
```

---

## 🛠️ Skill Specification Standards

Every skill in this repository complies with the [Agent Skills Specification](https://agentskills.io/specification):
- **YAML Frontmatter**: Requires `name` and `description`.
- **Trigger-Focused Descriptions**: Descriptions strictly begin with `"Use when..."` and state triggering conditions and symptoms.
- **Modular Design**: Complex skills include `references/` for deep documentation and `templates/` for copy-pasteable production code.

---

## 📄 License
MIT License. Created and maintained by Awais Jamil.
