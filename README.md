# deepreview-skill

Two complementary multi-agent code-quality skills for Claude Code,
shipped together in the same repository.

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

## deepreview — pre-merge review

Six specialist reviewers run in parallel over a git diff:

| Axis           | Sub-agent                  | Executes? |
|----------------|----------------------------|-----------|
| Security       | `reviewer-security`        | No        |
| Architecture   | `reviewer-architecture`    | No        |
| Bugs           | `reviewer-bug-hunter`      | Yes       |
| Performance    | `reviewer-performance`     | Yes       |
| Test coverage  | `reviewer-test-coverage`   | Yes       |
| Documentation  | `reviewer-documentation`   | No        |

A `verifier` agent then reproduces each finding by writing and running
a reproduction test (for executable axes) or by careful static
walkthrough (security, architecture, docs). Findings that cannot be
reproduced are dropped. The final report is at
`.claude/review/<run-id>/report.md`, sorted by severity.

**Invocation.**

```
deepreview                          # diff vs default branch
deepreview PR 1234                  # specific GitHub PR
deepreview against origin/develop   # diff vs another base
```

## deepaudit — audit of existing code

Six specialist auditors run in parallel over a scope you specify:

| Axis           | Sub-agent                  | Executes? |
|----------------|----------------------------|-----------|
| Security       | `auditor-security`         | No        |
| Architecture   | `auditor-architecture`     | No        |
| Bugs           | `auditor-bug-hunter`       | Yes       |
| Performance    | `auditor-performance`      | Yes       |
| Test coverage  | `auditor-test-coverage`    | Yes       |
| Documentation  | `auditor-documentation`    | No        |

An `auditor-verifier` agent then independently reproduces every
finding the same way the reviewer's verifier does. The final report
contains the **top N most critical issues** (default 20, configurable
via `DEEPAUDIT_MAX_FINDINGS`). Nice-to-have findings are dropped
entirely so the report stays actionable.

**Invocation.** A scope is required; the skill refuses to run without one.

```
deepaudit src/auth/                 # all six auditors on src/auth/
deepaudit security                  # only security, on the whole repo
deepaudit security src/auth/        # only security, on src/auth/
deepaudit src/auth/ src/billing/    # all six, on the union of paths
```

Valid axes: `security`, `architecture`, `bugs`, `performance`,
`tests`, `docs`. Synonyms accepted: `bug-hunter`, `test-coverage`,
`documentation`.

## Install

### Quick install (recommended)

Review the install script first, then run it. The script installs
both skills into `.claude/` of the current git repository.

```bash
curl -fsSL https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.sh -o /tmp/deepreview-install.sh
less /tmp/deepreview-install.sh   # review before running
DEEPREVIEW_REF=v0.2.0 bash /tmp/deepreview-install.sh
```

For a global install (available in every project):

```bash
DEEPREVIEW_SCOPE=global DEEPREVIEW_REF=v0.2.0 bash /tmp/deepreview-install.sh
```

To install only one of the two skills:

```bash
DEEPREVIEW_SKILLS=deepreview DEEPREVIEW_REF=v0.2.0 bash /tmp/deepreview-install.sh
DEEPREVIEW_SKILLS=deepaudit  DEEPREVIEW_REF=v0.2.0 bash /tmp/deepreview-install.sh
```

### Manual install

```bash
git clone --depth 1 --branch v0.2.0 https://github.com/aiskool/deepreview-skill.git /tmp/deepreview-skill
cp -r /tmp/deepreview-skill/.claude/skills/* .claude/skills/
cp /tmp/deepreview-skill/.claude/agents/*.md .claude/agents/
chmod +x .claude/skills/deepreview/detect-runtime.sh
chmod +x .claude/skills/deepaudit/detect-runtime.sh
```

After installation, restart your Claude Code session so the new
agents are loaded.

## Runtime support

The runtime detector recognizes Node (npm/yarn/pnpm/bun), Python
(uv/poetry/pipenv/pip), Rust (cargo), Go, Ruby (bundler), JVM
(Maven/Gradle), PHP (Composer), Elixir (mix), and .NET. Polyglot
repositories are fine — multiple stacks are returned in priority
order. If your stack is not recognized, the static-only axes still
work; executable axes fall back to static-only verification.

## What this is NOT

- **Not a replacement for `/ultrareview`.** If you have access and
  the budget, the cloud version has more compute and a sandboxed
  runtime.
- **Not a replacement for CI.** Linters, type checkers, and test
  suites still run where they always ran. These skills add a
  semantic layer.
- **Not a replacement for human review.** A reviewer who knows the
  product, the users, and the roadmap catches what no agent will.

## Safety

- All reviewer and auditor agents are read-only on source files.
- The verifier agents may write files **only inside the per-run
  output directory** (`.claude/review/<run-id>/` or
  `.claude/audit/<run-id>/`).
- A git checkpoint is created before verification; the working tree
  is reset afterwards.
- The verifier never executes exploit payloads. Security verification
  is intellectual, not active.

## License

MIT.
