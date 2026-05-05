# Security Policy

## Threat model

`deepreview` is a Claude Code skill that runs inside your local development
environment. It reads source code, git metadata, and project manifests in
the repository where it is invoked, and it may execute the project's test
and coverage commands in order to reproduce review findings.

The threat surface a user should consider before installing this skill:

- **Local code execution**: the `verifier` agent writes reproduction tests
  inside `.claude/review/<run-id>/` and runs them via the project's test
  runner. If your project's test runner has access to credentials,
  network, or external services, that access is implicitly available
  during verification.
- **Read access to source**: all reviewer agents read repository files
  in plain text. Do not invoke this skill on a checkout that contains
  unencrypted secrets you would not want surfaced in agent output.
- **Network access**: agents themselves do not require network access.
  However, the project's test runner, when invoked, runs with whatever
  network access your shell environment grants.

## Supply-chain integrity

When installing from the public repository, you are running code authored
by the maintainer. Before running the install script, you should:

1. Read it: `curl -fsSL <install-url> | less`.
2. Pin to a tag rather than `main` once releases are tagged.
3. Verify the SHA-256 checksum if a checksum file is published with the
   release.

## Reporting a vulnerability

If you discover a vulnerability in this skill — an injection vector in
the orchestration logic, an unintended write outside `.claude/review/`,
a way to make the verifier execute arbitrary user-controlled code, or
similar — please **do not** open a public issue.

Open a private security advisory via GitHub:
`https://github.com/<your-org>/deepreview-skill/security/advisories/new`

Or email the maintainer directly with `[deepreview-security]` in the
subject line.

You can expect an acknowledgement within 5 business days. Confirmed
vulnerabilities will be patched on the `main` branch and announced via
a tagged release with release notes.

## Scope

In scope:
- The orchestration logic in `SKILL.md`.
- Sub-agent definitions in `.claude/agents/`.
- The `detect-runtime.sh` helper.
- The install script.

Out of scope:
- Bugs in Claude Code itself (report to Anthropic).
- Bugs in third-party test runners invoked by the verifier.
- User error (running on a repository they do not trust).
