---
name: deepaudit
description: Multi-agent local code audit. Runs six specialist auditors
  (security, architecture, bug-hunter, performance, test-coverage,
  documentation) in parallel over a directory or a transversal axis
  such as security across the whole repo. Every finding is independently
  reproduced via a verifier before reporting. Returns only the top N
  most critical issues (default 20) and drops nice-to-have entirely.
  Use this when you want to know what is broken in an existing
  codebase, with no notion of before-and-after diff.
allowed-tools: Bash(git:*), Bash(rg:*), Bash(fd:*), Bash(find:*), Bash(bash:*), Read, Grep, Glob, Write, Task
---

# Deepaudit

A local, multi-agent codebase audit. Sister skill to `deepreview`.
Where `deepreview` looks at a diff before merge, `deepaudit` looks at
the current state of code that already exists. There is no "before"
to compare to — the audit reports what is wrong now.

## When to use

Invoke this skill when the user asks for an "audit", "code audit",
"deep audit", "audit my code", "tell me what is wrong with this code",
or any equivalent. Do NOT invoke it for review of pending changes
(use `deepreview` instead).

## Hard rules

- The skill operates on **a scope the user must specify**. With no
  argument, refuse and ask for a scope. Never fall back to "audit the
  whole repo" implicitly — that produces unreadable reports on
  monorepos and is rarely what the user actually wants.
- Auditor agents are read-only on source files.
- The verifier MAY write files, but only inside `.claude/audit/<run-id>/`.
- A git checkpoint commit MUST be created before Phase 3 (verification),
  because the verifier may install dev dependencies and run tests.
- The final report is **bounded**: it contains at most
  `DEEPAUDIT_MAX_FINDINGS` items (default 20), all critical or important.
  Nice-to-have findings are dropped systematically.
- All sub-agents are dispatched via the `Task` tool. Auditors run in
  parallel; the verifier runs after the fan-in.

## Phase 1 — Scope

Parse the user's invocation. Five forms are supported:

| Invocation                          | Behavior |
|-------------------------------------|----------|
| `deepaudit`                         | Refuse. Ask the user to specify a scope. |
| `deepaudit <path>`                  | All six auditors on `<path>` only. |
| `deepaudit <axis>`                  | Only the named auditor, on the whole repo. |
| `deepaudit <axis> <path>`           | Only the named auditor, on `<path>` only. |
| `deepaudit <path1> <path2> ...`     | All six auditors on the union of paths. |

Where `<axis>` is one of: `security`, `architecture`, `bugs`, `performance`, `tests`, `docs`. Synonyms accepted: `bug-hunter`→`bugs`, `test-coverage`→`tests`, `documentation`→`docs`.

If the user invokes `deepaudit` with no argument, respond with:

> deepaudit needs a scope. Pass a directory (`deepaudit src/auth/`),
> an axis (`deepaudit security`), or both (`deepaudit security src/auth/`).
> See the skill description for all forms.

And stop. Do not start the run.

Once a scope is parsed:

1. Confirm the working directory is a git repository. Required for the
   checkpoint mechanism in Phase 3.
2. Generate `RUN_ID=$(date -u +%Y%m%d-%H%M%S)`.
3. Create `.claude/audit/$RUN_ID/` and subfolders `findings/`,
   `repro-tests/`, `logs/`.
4. Walk the scope to build the file manifest. Skip generated/vendored
   directories: `node_modules/`, `vendor/`, `dist/`, `build/`,
   `.next/`, `.venv/`, `target/`, `__pycache__/`, `.git/`. Use `find`
   or `fd` and respect `.gitignore`.
5. Write `manifest.json` with `{scope, axes, files, root}`.
6. Run the runtime detector:
   `bash .claude/skills/deepaudit/detect-runtime.sh > .claude/audit/$RUN_ID/runtime.json`.
7. Read `DEEPAUDIT_MAX_FINDINGS` from environment (default 20). Store
   in `manifest.json` as `max_findings`.
8. If the file manifest is empty (scope matched zero source files),
   abort with an explanatory message.

## Phase 2 — Parallel fan-out

Dispatch the auditor agents listed in `manifest.axes` in parallel via
`Task`. Each receives:
- `manifest_path`: the manifest from Phase 1.
- `runtime_path`: the runtime descriptor.
- `output_path`: `.claude/audit/$RUN_ID/findings/<axis>.json`.

The seven auditor agents (one per axis, plus the verifier):

| Axis           | Sub-agent name              | Executes? |
|----------------|-----------------------------|-----------|
| Security       | `auditor-security`          | No        |
| Architecture   | `auditor-architecture`      | No        |
| Bugs           | `auditor-bug-hunter`        | Yes       |
| Performance    | `auditor-performance`       | Yes       |
| Tests          | `auditor-test-coverage`     | Yes       |
| Docs           | `auditor-documentation`     | No        |
| (verifier)     | `auditor-verifier`          | Yes       |

Each auditor emits a JSON array of findings:

```json
{
  "id": "<axis>-<8-char-hash>",
  "axis": "security|architecture|bugs|performance|tests|docs",
  "file": "path/relative/to/repo",
  "line_range": [start, end],
  "severity": "critical|important|nice-to-have",
  "category": "free-text",
  "title": "one-line summary",
  "description": "what is wrong and why it matters",
  "trigger_scenario": "concrete state/input that exposes the issue",
  "suggested_fix": "actionable change"
}
```

Wait for all dispatched auditors to complete. If one fails, log to
`logs/<axis>.err` and continue.

## Phase 3 — Verification

1. Create a git checkpoint:
   `git add -A && git commit --no-gpg-sign --allow-empty -m "deepaudit checkpoint $RUN_ID"`.
   Record the SHA in `.claude/audit/$RUN_ID/checkpoint.txt`.
2. Aggregate all findings into `.claude/audit/$RUN_ID/findings/_all.json`.
3. **Pre-prioritization filter**: drop all `nice-to-have` findings
   immediately. They will not be reported, so verifying them wastes
   compute. Keep only `critical` and `important`.
4. For each remaining finding, dispatch `auditor-verifier` sequentially.
   The verifier sets `verified: true|false` and adds `evidence` and
   `evidence_path`.
5. After verification, restore the working tree:
   `git reset --hard <checkpoint-sha>`. Reproduction artifacts inside
   `.claude/audit/<run-id>/` survive.

## Phase 4 — Top-N synthesis

Apply the bounded-report logic:

1. Drop `verified: false`.
2. Deduplicate by `(file, line_range, axis)`.
3. Partition into `critical_verified` and `important_verified`.
4. Build the final list using this rule:
   - If `len(critical_verified) >= max_findings`: take the first
     `max_findings` critical (sort by file/line for determinism), and
     surface a note "N more critical findings exist beyond the top
     <max_findings>".
   - Else: take all `critical_verified`, then fill with
     `important_verified` until `max_findings` is reached.
5. Write the final markdown report to `.claude/audit/$RUN_ID/report.md`:

   ```
   # deepaudit — <run id>

   Scope: <scope description>
   Axes:  <list of axes audited>
   Files: <N>

   <X> critical · <Y> important · 0 nice-to-have (dropped by policy)
   <truncation note if applicable>

   ## Critical
   ### <axis> · <file>:<line_range>
   <title>
   <description>
   Reproduction: <evidence>
   Suggested fix: <suggested_fix>

   ## Important
   ...
   ```

6. Print the report to stdout.

## Phase 5 — Lessons

Append recurring patterns to `.claude/lessons.md` so subsequent audits
can short-circuit. Only `critical` findings are added.

## Failure handling

- If `git commit` fails (GPG, hooks): retry with `--no-verify --no-gpg-sign`.
- If a sub-agent times out (default 5 min per auditor, 60 s per
  verification): record the timeout, mark affected findings unverified,
  continue.
- If the test suite is broken on the current branch (verifier sees
  failing tests before any reproduction): proceed with bugs/perf in
  static-only mode and surface this fact in the report.
