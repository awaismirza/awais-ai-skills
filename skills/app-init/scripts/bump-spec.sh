#!/usr/bin/env bash
# app-init: spec snapshot + version bump.
#
# The one purely mechanical step in Phase 1 — cloning docs/product-spec.md to
# an immutable dated snapshot and rewriting the stable file's version header.
# Kept as a script rather than hand-edited so the snapshot and the header can
# never drift out of sync with each other.
#
# Usage:
#   bump-spec.sh snapshot              # snapshot the CURRENT spec before editing it
#   bump-spec.sh save <NEW_VERSION>    # after editing, snapshot the NEW version and
#                                       # rewrite the header (e.g. save 1.2)
#
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SPEC="${REPO_ROOT}/docs/product-spec.md"
SNAP_DIR="${REPO_ROOT}/docs/specs"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") snapshot            Snapshot the spec at its CURRENT version
                                        (run this BEFORE editing product-spec.md)
  $(basename "$0") save <NEW_VERSION>  Rewrite the header to NEW_VERSION and save
                                        a matching snapshot (run this AFTER editing)
EOF
}

current_version() {
    grep -m1 '^\s*>\s*\*\*Spec version:\*\*' "${SPEC}" | sed -E 's/.*v([0-9]+\.[0-9]+).*/\1/'
}

if [ ! -f "${SPEC}" ]; then
    echo "❌ ${SPEC} does not exist yet — scaffold it from templates/product-spec.md.template first." >&2
    exit 1
fi

mkdir -p "${SNAP_DIR}"

case "${1:-}" in
    snapshot)
        v="$(current_version)"
        if [ -z "${v}" ]; then
            echo "❌ Could not find a '> **Spec version:** vX.Y' header in ${SPEC}." >&2
            exit 1
        fi
        dest="${SNAP_DIR}/product-spec-v${v}.md"
        if [ -f "${dest}" ]; then
            echo "ℹ️  ${dest} already exists — leaving it (snapshots are immutable, not re-written)."
        else
            cp "${SPEC}" "${dest}"
            echo "✅ Snapshotted current spec (v${v}) -> ${dest}"
        fi
        ;;
    save)
        new="${2:-}"
        if [ -z "${new}" ]; then
            echo "❌ Usage: $(basename "$0") save <NEW_VERSION>  (e.g. save 1.2)" >&2
            exit 1
        fi
        old="$(current_version)"
        # Rewrite the version header in place.
        sed -i.bak -E "s/(\*\*Spec version:\*\*[[:space:]]*v)[0-9]+\.[0-9]+/\1${new}/" "${SPEC}"
        rm -f "${SPEC}.bak"
        dest="${SNAP_DIR}/product-spec-v${new}.md"
        cp "${SPEC}" "${dest}"
        echo "✅ Bumped spec header v${old} -> v${new}"
        echo "✅ Saved new snapshot -> ${dest}"
        echo "➡️  Now add an entry to docs/spec-changelog.md for this bump."
        ;;
    *)
        usage
        exit 1
        ;;
esac
