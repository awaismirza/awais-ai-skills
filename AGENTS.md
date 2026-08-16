# Universal Agent Instructions

This repository contains reusable, production-grade AI Agent Skills compliant with the [Agent Skills Specification](https://agentskills.io/specification).

## Repository Guidelines for AI Agents

1. **Standard Skill Location**:
   - All skills live in `skills/<skill-name>/SKILL.md`.
   - `.claude/skills` and `.agents/skills` are symlinked to `skills/` for compatibility across all agent harnesses (Claude Code, OpenAI Codex, Google Antigravity, Cursor, Windsurf, Copilot CLI).
2. **Frontmatter Standard**:
   - Every skill must have a valid YAML frontmatter block at the top with `name` and `description`.
   - The `description` MUST start with `"Use when..."` and describe the exact triggering conditions, symptoms, and contexts—never summarize the workflow.
3. **Adding / Modifying Skills**:
   - When creating a new skill, create a directory in `skills/<skill-name>/` containing `SKILL.md`.
   - Place long reference documents in `references/` and code samples/templates in `templates/` or `examples/`.
   - Run `python3 scripts/sync-skills.py` to validate frontmatter and ensure all symlinks are preserved.
4. **Testing Skills**:
   - Skills follow the Test-Driven Development (TDD) cycle for documentation: define test scenarios, verify agents without skill fail or rationalise loopholes, verify compliance with skill.
