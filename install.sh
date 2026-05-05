#!/usr/bin/env bash
# install.sh — install deepreview into the current repo or globally.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/deepreview-skill/main/install.sh | bash
#
# Or, recommended (review before running):
#   curl -fsSL https://raw.githubusercontent.com/<org>/deepreview-skill/main/install.sh -o install.sh
#   less install.sh
#   bash install.sh
#
# Environment variables:
#   DEEPREVIEW_SCOPE   "project" (default) or "global"
#   DEEPREVIEW_REF     git ref to install from. Default: "main".
#                      Pin to a tag for reproducibility: DEEPREVIEW_REF=v0.1.0
#   DEEPREVIEW_REPO    full repo slug, default "aiskool/deepreview-skill"

set -euo pipefail

SCOPE="${DEEPREVIEW_SCOPE:-project}"
REF="${DEEPREVIEW_REF:-main}"
REPO="${DEEPREVIEW_REPO:-aiskool/deepreview-skill}"

RAW="https://raw.githubusercontent.com/${REPO}/${REF}"

# Resolve install root.
case "$SCOPE" in
  project)
    if [[ ! -d .git ]]; then
      echo "error: project scope requires a git repository in the current directory." >&2
      echo "       run 'git init' first, or set DEEPREVIEW_SCOPE=global." >&2
      exit 1
    fi
    ROOT=".claude"
    ;;
  global)
    ROOT="${HOME}/.claude"
    ;;
  *)
    echo "error: DEEPREVIEW_SCOPE must be 'project' or 'global'." >&2
    exit 1
    ;;
esac

echo "Installing deepreview"
echo "  scope:  $SCOPE"
echo "  ref:    $REF"
echo "  repo:   $REPO"
echo "  target: $ROOT/"
echo

mkdir -p "$ROOT/skills/deepreview" "$ROOT/agents"

fetch() {
  local src="$1" dst="$2"
  echo "  fetch  $src"
  curl -fsSL "$RAW/$src" -o "$dst"
}

fetch ".claude/skills/deepreview/SKILL.md"        "$ROOT/skills/deepreview/SKILL.md"
fetch ".claude/skills/deepreview/detect-runtime.sh" "$ROOT/skills/deepreview/detect-runtime.sh"
chmod +x "$ROOT/skills/deepreview/detect-runtime.sh"

for agent in reviewer-security reviewer-architecture reviewer-bug-hunter \
             reviewer-performance reviewer-test-coverage reviewer-documentation \
             verifier; do
  fetch ".claude/agents/${agent}.md" "$ROOT/agents/${agent}.md"
done

echo
echo "deepreview installed."
echo "Restart your Claude Code session so the new agents are loaded."
echo "Then in Claude Code, type:  deepreview"
