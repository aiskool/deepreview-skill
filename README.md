# deepreview

A multi-agent code review skill for Claude Code. A local replica of the
architectural pattern behind `/ultrareview`: parallel specialist
reviewers plus an independent verification step that drops findings it
cannot reproduce.

> **Honest framing.** This skill mirrors the *publicly documented*
> architecture of `/ultrareview` (multi-agent fan-out + reproduction
> step), and the axes commonly observed in third-party reports. It is
> not a port of Anthropic's internal implementation, which is not
> public. It runs locally in your Claude Code session, not in a remote
> sandbox.

## What it does

When invoked on a git diff (current branch or a GitHub PR), the skill
runs six specialist reviewers in parallel:

| Axis            | Sub-agent                  | Executes? |
|-----------------|----------------------------|-----------|
| Security        | `reviewer-security`        | No        |
| Architecture    | `reviewer-architecture`    | No        |
| Bugs            | `reviewer-bug-hunter`      | Yes       |
| Performance     | `reviewer-performance`     | Yes       |
| Test coverage   | `reviewer-test-coverage`   | Yes       |
| Documentation   | `reviewer-documentation`   | No        |

Then a `verifier` agent independently reproduces each finding — by
writing and running a reproduction test for executable axes, or by
careful static re-inspection for the others. **Findings that cannot be
reproduced are dropped.** This is what gives the report its signal.

The final output is a single markdown report at
`.claude/review/<run-id>/report.md`, sorted by severity (critical /
important / nice-to-have).

## Install

### Quick install (recommended)

Review the install script first, then run it. The script installs into
`.claude/` of the current git repository.

```bash
curl -fsSL https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.sh -o /tmp/deepreview-install.sh
less /tmp/deepreview-install.sh   # review before running
bash /tmp/deepreview-install.sh
```

For a global install (available in every project):

```bash
DEEPREVIEW_SCOPE=global bash /tmp/deepreview-install.sh
```

To pin to a specific release tag instead of `main`:

```bash
DEEPREVIEW_REF=v0.1.0 bash /tmp/deepreview-install.sh
```

### Manual install

```bash
git clone https://github.com/aiskool/deepreview-skill.git /tmp/deepreview-skill
cp -r /tmp/deepreview-skill/.claude/skills/deepreview .claude/skills/
cp /tmp/deepreview-skill/.claude/agents/*.md .claude/agents/
chmod +x .claude/skills/deepreview/detect-runtime.sh
```

Or globally:

```bash
cp -r /tmp/deepreview-skill/.claude/skills/deepreview ~/.claude/skills/
cp /tmp/deepreview-skill/.claude/agents/*.md ~/.claude/agents/
```

Restart your Claude Code session so the new agents are loaded.

## Use

In Claude Code:

```
deepreview
```

Or, for a specific PR:

```
deepreview PR 1234
```

Or, for a specific base branch:

```
deepreview against origin/develop
```

## Runtime support

The runtime detector recognizes Node (npm/yarn/pnpm/bun), Python
(uv/poetry/pipenv/pip), Rust (cargo), Go, Ruby (bundler), JVM (Maven /
Gradle), PHP (Composer), Elixir (mix), and .NET. Polyglot repos are
fine — multiple stacks are returned in priority order. If your stack
is not recognized, the static-only axes still work; executable axes
fall back to static-only verification.

## What it is NOT

- **Not a replacement for `/ultrareview`.** If you have access and the
  budget, the cloud version has more compute and a sandboxed runtime.
- **Not a replacement for CI.** Linters, type checkers, and test suites
  still run where they always ran. This skill adds a semantic layer.
- **Not a replacement for human review.** A reviewer who knows the
  product, the users, and the roadmap catches what no agent will.

## Safety

- Reviewer agents are read-only on source files.
- The verifier may write files **only inside `.claude/review/<run-id>/`**.
- A git checkpoint is created before verification; the working tree is
  reset afterwards.
- The verifier never executes exploit payloads. Security verification
  is intellectual, not active.

## License

MIT.
