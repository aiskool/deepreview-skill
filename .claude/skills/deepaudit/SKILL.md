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
   checkpoint mechanism in Phase 3. Capture the absolute repo root:
   `REPO=$(git rev-parse --show-toplevel)`. **Use `$REPO` as the
   prefix for every path written to disk in this run** — relative
   paths break across Bash invocations because each `Bash` tool call
   spawns a fresh shell with no inherited cwd guarantee.
2. Generate the run id and **persist it to `/tmp` so subsequent Bash
   invocations can recover it**:
   ```
   RUN_ID=$(date -u +%Y%m%d-%H%M%S)
   echo "$RUN_ID" > /tmp/deepaudit_run_id.txt
   echo "$REPO"   > /tmp/deepaudit_repo.txt
   ```
   In every later Bash invocation, recover both with:
   ```
   RUN_ID=$(cat /tmp/deepaudit_run_id.txt)
   REPO=$(cat /tmp/deepaudit_repo.txt)
   ```
   Without this, environment variables set in one Bash call do not
   survive to the next.
3. Create `$REPO/.claude/audit/$RUN_ID/` and subfolders `findings/`,
   `repro-tests/`, `logs/`.
4. Walk the scope to build the file manifest. Skip generated/vendored
   directories: `node_modules/`, `vendor/`, `dist/`, `build/`,
   `.next/`, `.venv/`, `target/`, `__pycache__/`, `.git/`. Use `find`
   or `fd` and respect `.gitignore`.
5. Write `$REPO/.claude/audit/$RUN_ID/manifest.json` with
   `{scope, axes, files, root}`.
6. Run the runtime detector with absolute paths:
   ```
   bash "$REPO/.claude/skills/deepaudit/detect-runtime.sh" \
     > "$REPO/.claude/audit/$RUN_ID/runtime.json"
   ```
7. Read `DEEPAUDIT_MAX_FINDINGS` from environment (default 20). Store
   in `manifest.json` as `max_findings`.
8. **Derive a `scope_hint` slug** from the user's invocation. This is
   used by Phase 6 to name the preserved report. Rules:
   - Single axis (e.g. `deepaudit security`): slug = the axis name.
   - Single path (e.g. `deepaudit src/auth/`): slug = last 1-2 path
     components, lowercased, slashes and dots replaced by hyphens,
     extension stripped (`src/auth/` → `auth`,
     `backend/src/services/paypal.service.ts` → `paypal-service`).
   - Axis + path: `<axis>-<path-slug>`.
   - Multiple paths: pick the most distinctive shared parent or
     concatenate the first 2 with `--` (e.g. `auth--billing`).
   - Truncate to 40 chars. Fallback: `scope` if nothing meaningful
     can be derived.
   Persist the result: `echo "<slug>" > /tmp/deepaudit_scope_hint.txt`.
9. If the file manifest is empty (scope matched zero source files),
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
5. Write the final markdown report to
   `$REPO/.claude/audit/$RUN_ID/report.md` (absolute path, recovered
   via `REPO=$(cat /tmp/deepaudit_repo.txt)` and
   `RUN_ID=$(cat /tmp/deepaudit_run_id.txt)`):

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

Append recurring patterns to `$REPO/.claude/lessons.md` so subsequent
audits can short-circuit. Only `critical` findings are added.

> ⚠️ **`$REPO/.claude/lessons.md` is shared with other Claude Code
> skills** (Autopilot and any others installed). It is NOT a
> deepaudit-owned file. Phase 6 cleanup MUST NOT delete or modify it.

This phase MUST run **before** Phase 6 cleanup, because lessons are
extracted from the verified findings JSON which is about to be
deleted.

## Phase 6 — Persist report and cleanup intermediate artifacts

The `<run-id>/` working directory contains intermediate artifacts
(findings JSONs, manifest, runtime descriptor, repro tests, logs)
that have no value once the report is synthesized and lessons are
extracted. Without cleanup, repeat audits accumulate dozens of these
folders. This phase preserves the report at a stable location and
removes the per-run scratch directory.

**Order of operations (do not reorder):**

1. **Recover persistent variables** from `/tmp`:
   ```bash
   REPO=$(cat /tmp/deepaudit_repo.txt)
   RUN_ID=$(cat /tmp/deepaudit_run_id.txt)
   SCOPE_HINT=$(cat /tmp/deepaudit_scope_hint.txt)
   ```

2. **Sanity check before any `rm`**: abort cleanup if any of `$REPO`,
   `$RUN_ID`, `$SCOPE_HINT` is empty. Print an error and stop. Never
   run `rm -rf` with an unset variable.

3. **Copy the report to its persistent location**:
   ```bash
   mkdir -p "$REPO/.claude/audit-reports"
   cp "$REPO/.claude/audit/$RUN_ID/report.md" \
      "$REPO/.claude/audit-reports/${RUN_ID}-${SCOPE_HINT}.md"
   ```
   The destination filename is `<run-id>-<scope-hint>.md` (e.g.
   `20260506-092357-auth-surface.md`). This directory is the durable
   record of all past audits.

4. **Verify the copy succeeded** before deleting the source:
   ```bash
   test -s "$REPO/.claude/audit-reports/${RUN_ID}-${SCOPE_HINT}.md" \
     || { echo "report copy failed; aborting cleanup" >&2; exit 1; }
   ```

5. **Delete only the per-run scratch directory**:
   ```bash
   rm -rf "$REPO/.claude/audit/$RUN_ID"
   ```

   **CRITICAL safety rules for this `rm`:**
   - The path MUST be exactly `"$REPO/.claude/audit/$RUN_ID"` —
     never the parent `.claude/audit/`, never `.claude/`, never
     anything broader.
   - **NEVER touch `$REPO/.claude/lessons.md`** — that file is
     shared with other skills and must persist across audit runs.
   - **NEVER touch other entries inside `$REPO/.claude/`** —
     `skills/`, `agents/`, `audit-reports/`, `lessons.md`, or any
     skill-specific files. Only the specific `audit/$RUN_ID/`
     subfolder is in scope for deletion.
   - **NEVER delete `$REPO/.claude/audit/`** itself (the parent
     directory of per-run subdirs). It is the canonical workspace
     for future runs and may already contain other run-id folders
     from concurrent or recent runs.

6. **Clean up `/tmp` markers**:
   ```bash
   rm -f /tmp/deepaudit_run_id.txt /tmp/deepaudit_repo.txt \
         /tmp/deepaudit_scope_hint.txt
   ```

7. **Print the final user-facing line**:
   ```bash
   echo "Report saved: .claude/audit-reports/${RUN_ID}-${SCOPE_HINT}.md"
   ```
   The user knows exactly where to look. No run-id directories left
   behind, lessons preserved, working tree clean.

## Failure handling

- If `git commit` fails (GPG, hooks): retry with `--no-verify --no-gpg-sign`.
- If a sub-agent times out (default 5 min per auditor, 60 s per
  verification): record the timeout, mark affected findings unverified,
  continue.
- If the test suite is broken on the current branch (verifier sees
  failing tests before any reproduction): proceed with bugs/perf in
  static-only mode and surface this fact in the report.
