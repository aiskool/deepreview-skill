# Contributing to deepreview

Thanks for considering a contribution. This document covers the basics:
what to work on, how to propose changes, and the conventions the project
follows.

## Ways to contribute

- **Bug reports**: open an issue with the `bug_report` template. Include
  the Claude Code version, the runtime stack of the repository under
  review, and the command you ran.
- **Sub-agent improvements**: refine the prompt of an existing reviewer
  to reduce false positives, broaden coverage of a category, or improve
  the JSON schema.
- **New reviewer axes**: propose a new specialist (accessibility, i18n,
  observability, etc.). Open an issue first to discuss scope.
- **Runtime detector**: add support for a stack the detector misses.
- **Documentation**: clarify the README, the SKILL.md, or any agent
  description.

## Workflow

1. Fork the repository, then clone your fork locally.
2. Create a topic branch: `git checkout -b feat/<short-name>` or
   `fix/<short-name>`.
3. Make your changes. Keep diffs small and focused. One concern per PR.
4. Test the change against a real repository (yours, ideally) and
   include a brief description of what you ran in the PR description.
5. Commit. The maintainer's environment occasionally has GPG signing
   issues; if you hit one, `git commit --no-gpg-sign` is acceptable for
   this project.
6. Push to your fork and open a PR against `main`.

## Conventions

- **Files**: plain UTF-8, LF line endings, no trailing whitespace.
- **YAML frontmatter**: required at the top of every `SKILL.md` and
  agent file. Keep `description` to one paragraph; this is what Claude
  Code uses to decide when to invoke the agent.
- **Agent prompts**: written in second person ("You are a ..."),
  imperative voice. State what the agent does and does not report.
  Specify the JSON output schema explicitly.
- **Commit messages**: short imperative summary on the first line
  (e.g., `feat(verifier): retry on flaky test runs`). Body optional.
- **PR description**: state the motivation, the change, and how you
  validated it. Link related issues.

## What we will not merge

- Features that break the read-only contract of the static reviewers.
- Changes that allow the verifier to write outside
  `.claude/review/<run-id>/`.
- Sub-agents that depend on network calls or external API keys.
- Vendored binaries or large pre-trained artifacts.

## Code of Conduct

By participating, you agree to abide by the
[Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
