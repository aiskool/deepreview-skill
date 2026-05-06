# deepreview-skill

Multi-agent code review and audit for Claude Code, with independent
verification of every finding.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Latest release](https://img.shields.io/github/v/release/aiskool/deepreview-skill)](https://github.com/aiskool/deepreview-skill/releases/latest)

| Skill        | When to use it                                                  |
|--------------|-----------------------------------------------------------------|
| `deepreview` | Pre-merge review of a **diff** (current branch or a GitHub PR). |
| `deepaudit`  | Audit of **existing code** — a directory or a transversal axis. |

> **Honest framing.** `deepreview` mirrors the *publicly documented*
> architecture of Claude Code's `/ultrareview` (multi-agent fan-out +
> reproduction step). `deepaudit` is a sister skill that applies the
> same architectural ideas to existing code rather than to a diff.
> Neither is a port of Anthropic's internal implementation. Both run
> locally in your Claude Code session, not in a remote sandbox.

> 📘 **User tutorial (PDF, French)** —
> [`docs/tutoriel.pdf`](./docs/tutoriel.pdf): a 12-page walkthrough of
> installation, daily usage, report reading, safety guarantees, and
> troubleshooting. Renders inline on GitHub.

---

## Quickstart

```bash
# 1. Install (review-then-run pattern)
curl -fsSL https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.sh -o /tmp/install.sh
less /tmp/install.sh                           # review before running
DEEPREVIEW_REF=v0.2.1 bash /tmp/install.sh

# 2. Restart your Claude Code session

# 3. Run
deepreview                                     # review your current branch
deepaudit src/auth/                            # audit a directory
```

Windows users: see [PowerShell install](#windows-powershell) below.
For global install, single-skill install, or pinning details:
[full install options](#install).

---

## How it works

Both skills follow the same pattern: **six specialist agents fan out
in parallel, then an independent verifier reproduces every finding
before it reaches the report.** Findings that cannot be reproduced
are dropped. This is what makes the report's signal-to-noise ratio
much higher than a static linter.

### The six axes

| Axis           | `deepreview` agent          | `deepaudit` agent          | Reproduction strategy                   |
|----------------|-----------------------------|----------------------------|------------------------------------------|
| Security       | `reviewer-security`         | `auditor-security`         | Static walkthrough of the exploit chain |
| Architecture   | `reviewer-architecture`     | `auditor-architecture`     | Static review of the structural claim   |
| Bugs           | `reviewer-bug-hunter`       | `auditor-bug-hunter`       | A test that fails on current code       |
| Performance    | `reviewer-performance`      | `auditor-performance`      | A timed micro-benchmark                 |
| Test coverage  | `reviewer-test-coverage`    | `auditor-test-coverage`    | Coverage report intersection            |
| Documentation  | `reviewer-documentation`    | `auditor-documentation`    | Static comparison of code vs docs       |

Plus a `verifier` (deepreview) or `auditor-verifier` (deepaudit)
that runs the reproduction strategy for every finding. Verifiers
also deduplicate across axes — a hardcoded fallback secret reported
both as a security issue and a bug is merged into a single finding,
under the most precise axis.

### What you get

Reports are preserved at a stable, durable location:

| Skill        | Report location                                              |
|--------------|--------------------------------------------------------------|
| `deepreview` | `.claude/review-reports/<run-id>-<scope-hint>.md`            |
| `deepaudit`  | `.claude/audit-reports/<run-id>-<scope-hint>.md`             |

The per-run working directory (`.claude/review/<run-id>/` or
`.claude/audit/<run-id>/`) is cleaned up automatically. The
`.claude/lessons.md` file — shared with other skills like Autopilot —
is never deleted.

For `deepaudit`, the report is capped at the **top N most critical
issues** (default 20, configurable via `DEEPAUDIT_MAX_FINDINGS`).
Nice-to-have findings are dropped entirely. The report explicitly
notes how many additional findings exist beyond the cap.

---

## Usage

### deepreview — review a diff

```
deepreview                          # diff vs default branch (main/master)
deepreview PR 1234                  # specific GitHub PR
deepreview against origin/develop   # diff vs another base
```

Typical run: 5 to 15 minutes depending on diff size.

### deepaudit — audit existing code

A scope is **required**; the skill refuses to run without one.

```
deepaudit src/auth/                 # all six auditors on src/auth/
deepaudit security                  # only security, on the whole repo
deepaudit security src/auth/        # only security, on src/auth/
deepaudit src/auth/ src/billing/    # all six, on the union of paths
```

Valid axes: `security`, `architecture`, `bugs`, `performance`,
`tests`, `docs`. Synonyms accepted: `bug-hunter`, `test-coverage`,
`documentation`.

---

## Install

The repository ships two installer scripts that honour the same
environment-variable protocol (`DEEPREVIEW_SCOPE`, `DEEPREVIEW_REF`,
`DEEPREVIEW_REPO`, `DEEPREVIEW_SKILLS`) and produce identical layouts
under `.claude/`.

### macOS, Linux, or Windows with WSL/Git Bash

```bash
curl -fsSL https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.sh -o /tmp/deepreview-install.sh
less /tmp/deepreview-install.sh                # review before running
DEEPREVIEW_REF=v0.2.1 bash /tmp/deepreview-install.sh
```

Variants:

```bash
# Global install (available in every project)
DEEPREVIEW_SCOPE=global DEEPREVIEW_REF=v0.2.1 bash /tmp/deepreview-install.sh

# Single skill
DEEPREVIEW_SKILLS=deepreview DEEPREVIEW_REF=v0.2.1 bash /tmp/deepreview-install.sh
DEEPREVIEW_SKILLS=deepaudit  DEEPREVIEW_REF=v0.2.1 bash /tmp/deepreview-install.sh
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.ps1 -OutFile install.ps1
notepad install.ps1                            # review before running
$env:DEEPREVIEW_REF = "v0.2.1"
.\install.ps1
```

If your execution policy blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

> **Bash is still required at runtime, even on Windows.** The skills'
> runtime detector and several SKILL.md examples shell out to `bash`.
> Ensure `bash` is on `PATH` via WSL (recommended), Git for Windows
> (tick "Use Git and optional Unix tools" during install), Cygwin, or
> MSYS2. Without `bash`, executable axes fall back to static-only
> verification.

### Manual install

```bash
git clone --depth 1 --branch v0.2.1 https://github.com/aiskool/deepreview-skill.git /tmp/deepreview-skill
cp -r /tmp/deepreview-skill/.claude/skills/* .claude/skills/
cp /tmp/deepreview-skill/.claude/agents/*.md .claude/agents/
# On Unix-like systems only:
chmod +x .claude/skills/deepreview/detect-runtime.sh
chmod +x .claude/skills/deepaudit/detect-runtime.sh
```

After installation, restart your Claude Code session so the new
agents are loaded.

---

## Runtime support

The runtime detector recognizes Node (npm/yarn/pnpm/bun), Python
(uv/poetry/pipenv/pip), Rust (cargo), Go, Ruby (bundler), JVM
(Maven/Gradle), PHP (Composer), Elixir (mix), and .NET. Polyglot
repositories are fine — multiple stacks are returned in priority
order. If your stack is not recognized, the static-only axes still
work; executable axes fall back to static-only verification.

---

## What this is NOT

- **Not a replacement for `/ultrareview`.** If you have access and
  the budget, the cloud version has more compute and a sandboxed
  runtime.
- **Not a replacement for CI.** Linters, type checkers, and test
  suites still run where they always ran. These skills add a
  semantic layer.
- **Not a replacement for human review.** A reviewer who knows the
  product, the users, and the roadmap catches what no agent will.

Expect 5 to 15 % of findings to be debatable on a typical run
(misread flow, severity slightly off, etc.). Read the report
critically — every finding is a starting point for a conversation
with the code, not a verdict.

---

## Safety

- All reviewer and auditor agents are **read-only** on source files.
- The verifier agents may write files **only** inside the per-run
  output directory (`.claude/review/<run-id>/` or
  `.claude/audit/<run-id>/`).
- A git checkpoint is created before verification; the working tree
  is reset afterwards.
- The verifier **never executes exploit payloads**. Security
  verification is intellectual, not active.
- After each run, the working directory is cleaned up; the final
  report is preserved. **`.claude/lessons.md` is shared across
  skills (e.g. Autopilot) and is never deleted by these skills.**

To report a vulnerability, open a private security advisory at
[github.com/aiskool/deepreview-skill/security/advisories](https://github.com/aiskool/deepreview-skill/security/advisories).

---

## License

MIT — see [LICENSE](./LICENSE).
