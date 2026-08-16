#!/usr/bin/env bash
# ==============================================================================
# awais-ai-skills: Universal Skills Installer for AI Agents
# Supports: Claude Code, OpenAI Codex, Google Antigravity, Cursor, Copilot CLI
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILLS_SRC="${REPO_ROOT}/skills"

MODE="symlink" # Default: symlink (live updates), or "copy"
TARGET=""

print_usage() {
    cat <<EOF
Usage: ./install-skills.sh [OPTIONS]

Options:
  --all              Install/link skills to all known agent directories (default)
  --claude           Install/link skills to ~/.claude/skills/
  --agents           Install/link skills to ~/.agents/skills/ (Codex, Antigravity, Copilot)
  --cursor           Export rules for Cursor AI (.cursor/rules/)
  --target <dir>     Install/link skills into a custom directory
  --copy             Copy files instead of creating symlinks
  --help             Show this help message

Examples:
  ./install-skills.sh --all
  ./install-skills.sh --claude --copy
  ./install-skills.sh --target /path/to/my/project/.claude/skills
EOF
}

install_to_dir() {
    local dest="$1"
    local agent_name="$2"

    echo "📦 Installing skills to ${agent_name} (${dest})..."
    mkdir -p "${dest}"

    for skill_dir in "${SKILLS_SRC}"/*; do
        if [ -d "${skill_dir}" ]; then
            local skill_name="$(basename "${skill_dir}")"
            local target_path="${dest}/${skill_name}"

            if [ "${MODE}" = "symlink" ]; then
                rm -rf "${target_path}"
                ln -sf "${skill_dir}" "${target_path}"
                echo "  ✓ [symlink] ${skill_name} -> ${target_path}"
            else
                rm -rf "${target_path}"
                cp -R "${skill_dir}" "${target_path}"
                echo "  ✓ [copy] ${skill_name} -> ${target_path}"
            fi
        fi
    done
    echo "✅ Finished installing for ${agent_name}."
    echo ""
}

# Parse Arguments
INSTALL_CLAUDE=false
INSTALL_AGENTS=false
INSTALL_CURSOR=false
CUSTOM_TARGET=""

if [ $# -eq 0 ]; then
    INSTALL_CLAUDE=true
    INSTALL_AGENTS=true
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            INSTALL_CLAUDE=true
            INSTALL_AGENTS=true
            shift
            ;;
        --claude)
            INSTALL_CLAUDE=true
            shift
            ;;
        --agents)
            INSTALL_AGENTS=true
            shift
            ;;
        --cursor)
            INSTALL_CURSOR=true
            shift
            ;;
        --target)
            CUSTOM_TARGET="$2"
            shift 2
            ;;
        --copy)
            MODE="copy"
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit 1
            ;;
    esac
done

echo "🚀 Starting AI Skills installation (Mode: ${MODE})..."
echo "Source: ${SKILLS_SRC}"
echo ""

if [ -n "${CUSTOM_TARGET}" ]; then
    install_to_dir "${CUSTOM_TARGET}" "Custom Target"
fi

if [ "${INSTALL_CLAUDE}" = true ]; then
    install_to_dir "${HOME}/.claude/skills" "Claude Code"
fi

if [ "${INSTALL_AGENTS}" = true ]; then
    install_to_dir "${HOME}/.agents/skills" "OpenAI Codex / Antigravity / Gemini"
fi

if [ "${INSTALL_CURSOR}" = true ]; then
    mkdir -p "${REPO_ROOT}/.cursor/rules"
    echo "💡 Cursor rules exported to ${REPO_ROOT}/.cursor/rules/"
fi

echo "🎉 All AI skills successfully configured!"
