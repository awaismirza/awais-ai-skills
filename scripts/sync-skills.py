#!/usr/bin/env python3
"""
sync-skills.py: Validates and synchronizes all skills in the repository according
to the open Agent Skills specification (https://agentskills.io/specification).
"""

import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO_ROOT / "skills"

FRONTMATTER_REGEX = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(content: str):
    match = FRONTMATTER_REGEX.match(content)
    if not match:
        return None
    raw_yaml = match.group(1)
    meta = {}
    for line in raw_yaml.splitlines():
        if ":" in line:
            key, val = line.split(":", 1)
            meta[key.strip()] = val.strip().strip("\"'")
    return meta


def validate_all_skills():
    print(f"🔍 Validating skills in: {SKILLS_DIR}")
    skills = []
    errors = []

    for item in sorted(SKILLS_DIR.iterdir()):
        if not item.is_dir():
            continue
        skill_file = item / "SKILL.md"
        if not skill_file.exists():
            errors.append(f"❌ Missing SKILL.md in directory: {item.name}")
            continue

        content = skill_file.read_text(encoding="utf-8")
        meta = parse_frontmatter(content)
        if not meta:
            errors.append(f"❌ Missing or invalid YAML frontmatter in: {item.name}/SKILL.md")
            continue

        name = meta.get("name", item.name)
        desc = meta.get("description", "No description provided.")

        if not re.match(r"^[a-zA-Z0-9_-]+$", name):
            errors.append(f"⚠️  Invalid skill name format '{name}' in {item.name}/SKILL.md (only letters, numbers, hyphens/underscores allowed)")

        skills.append({
            "dir": item.name,
            "name": name,
            "description": desc,
            "path": skill_file
        })

    print(f"✅ Found {len(skills)} valid skills.")
    if errors:
        print("\n⚠️ Validation Warnings/Errors:")
        for err in errors:
            print(f"  {err}")

    return skills, errors


def ensure_repo_symlinks():
    """Sets up repo-internal symlinks for .claude and .agents standard compatibility."""
    claude_dir = REPO_ROOT / ".claude"
    agents_dir = REPO_ROOT / ".agents"

    claude_dir.mkdir(exist_ok=True)
    agents_dir.mkdir(exist_ok=True)

    claude_skills = claude_dir / "skills"
    agents_skills = agents_dir / "skills"

    for target in [claude_skills, agents_skills]:
        if target.is_symlink():
            target.unlink()
        elif target.is_dir():
            # if it was an old dir, remove it
            import shutil
            shutil.rmtree(target)

        target.symlink_to("../skills", target_is_directory=True)
        print(f"🔗 Created symlink: {target} -> ../skills")


def generate_catalog_markdown(skills):
    lines = [
        "| Skill Name | Description | Location |",
        "| :--- | :--- | :--- |"
    ]
    for s in sorted(skills, key=lambda x: x["name"]):
        lines.append(f"| [`{s['name']}`](skills/{s['dir']}/SKILL.md) | {s['description']} | `skills/{s['dir']}` |")
    return "\n".join(lines)


if __name__ == "__main__":
    skills, errors = validate_all_skills()
    ensure_repo_symlinks()
    print(f"\n🎉 Sync completed with {len(skills)} skills ready across all AI agents!")
