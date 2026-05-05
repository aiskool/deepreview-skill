#!/usr/bin/env bash
# install.sh — install deepreview and deepaudit skills.
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
#                      Pin to a tag for reproducibility: DEEPREVIEW_REF=v0.2.0
#   DEEPREVIEW_REPO    full repo slug, default "aiskool/deepreview-skill"
#   DEEPREVIEW_SKILLS  comma-separated subset to install. Default: "deepreview,deepaudit".
#                      Examples: DEEPREVIEW_SKILLS=deepreview, DEEPREVIEW_SKILLS=deepaudit

set -euo pipefail

SCOPE="${DEEPREVIEW_SCOPE:-project}"
REF="${DEEPREVIEW_REF:-main}"
REPO="${DEEPREVIEW_REPO:-aiskool/deepreview-skill}"
SKILLS_CSV="${DEEPREVIEW_SKILLS:-deepreview,deepaudit}"

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

# Parse skills list.
IFS=',' read -ra SKILLS <<< "$SKILLS_CSV"

# Validate.
for s in "${SKILLS[@]}"; do
  case "$s" in
    deepreview|deepaudit) ;;
    *) echo "error: unknown skill '$s'. Valid: deepreview, deepaudit." >&2; exit 1 ;;
  esac
done

echo "Installing"
echo "  skills: ${SKILLS[*]}"
echo "  scope:  $SCOPE"
echo "  ref:    $REF"
echo "  repo:   $REPO"
echo "  target: $ROOT/"
echo

mkdir -p "$ROOT/agents"

fetch() {
  local src="$1" dst="$2"
  echo "  fetch  $src"
  curl -fsSL "$RAW/$src" -o "$dst"
}

# Per-skill files.
for skill in "${SKILLS[@]}"; do
  mkdir -p "$ROOT/skills/$skill"
  fetch ".claude/skills/$skill/SKILL.md"          "$ROOT/skills/$skill/SKILL.md"
  fetch ".claude/skills/$skill/detect-runtime.sh" "$ROOT/skills/$skill/detect-runtime.sh"
  chmod +x "$ROOT/skills/$skill/detect-runtime.sh"
done

# Reviewer agents (only if deepreview is being installed).
if [[ " ${SKILLS[*]} " == *" deepreview "* ]]; then
  for agent in reviewer-security reviewer-architecture reviewer-bug-hunter \
               reviewer-performance reviewer-test-coverage reviewer-documentation \
               verifier; do
    fetch ".claude/agents/${agent}.md" "$ROOT/agents/${agent}.md"
  done
fi

# Auditor agents (only if deepaudit is being installed).
if [[ " ${SKILLS[*]} " == *" deepaudit "* ]]; then
  for agent in auditor-security auditor-architecture auditor-bug-hunter \
               auditor-performance auditor-test-coverage auditor-documentation \
               auditor-verifier; do
    fetch ".claude/agents/${agent}.md" "$ROOT/agents/${agent}.md"
  done
fi

echo
echo "Installed: ${SKILLS[*]}"
echo "Restart your Claude Code session so the new agents are loaded."
echo
if [[ " ${SKILLS[*]} " == *" deepreview "* ]]; then
  echo "  deepreview                    — pre-merge review of a diff"
fi
if [[ " ${SKILLS[*]} " == *" deepaudit "* ]]; then
  echo "  deepaudit <scope>             — audit existing code (needs a scope)"
fi
