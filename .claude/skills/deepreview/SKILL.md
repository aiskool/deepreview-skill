---
name: deepreview
description: Multi-agent local code review inspired by /ultrareview. Runs six
  specialist reviewers (security, architecture, bug-hunter, performance,
  test-coverage, documentation) in parallel over a git diff (branch or PR),
  then independently reproduces every finding via a verifier agent that
  writes and runs reproduction tests. Findings that cannot be reproduced
  are filtered out. Use before merging substantial changes.
allowed-tools: Bash(git:*), Bash(gh:*), Bash(rg:*), Bash(fd:*), Bash(bash:*), Read, Grep, Glob, Write, Task
---

# Deep Review

A local, multi-agent replica of `/ultrareview`. It produces a verified,
deduplicated report of real bugs in a diff. Style suggestions and
unreproducible findings are dropped on the floor.

## When to use

Invoke this skill when the user asks for a "deepreview", "deep review", "ultrareview-style
review", "pre-merge review", or any equivalent. Do NOT invoke it for a quick
local review (`/review` already covers that). Do NOT invoke it on an empty
diff.

## Hard rules

- The skill operates on a **diff**, never on the full codebase. If there is
  no diff, ask the user for a base branch or a PR number, then stop.
- The verifier MAY write files, but only inside `.claude/review/<run-id>/`.
  Never edit source files. Never modify tests outside this directory.
- A git checkpoint commit MUST be created before Phase 3 (verification),
  because the verifier may install dev dependencies, run tests, and
  generally touch the working tree. On any critical failure, roll back to
  the checkpoint.
- All sub-agents are dispatched via the `Task` tool. Reviewers run in
  parallel; the verifier runs after the fan-in.
- A finding is only reported if `verified: true` OR if its category is in
  the static-only set (security, architecture, documentation), in which
  case the verifier confirms by static re-inspection rather than execution.

## Phase 1 — Scope

1. Confirm the working directory is a git repository. If not, abort with a
   clear message. Capture the absolute repo root:
   `REPO=$(git rev-parse --show-toplevel)`. **Use `$REPO` as the
   prefix for every path written to disk in this run** — relative
   paths break across Bash invocations because each `Bash` tool call
   spawns a fresh shell with no inherited cwd guarantee.
2. Generate the run id and **persist it to `/tmp` so subsequent Bash
   invocations can recover it**:
   ```
   RUN_ID=$(date -u +%Y%m%d-%H%M%S)
   echo "$RUN_ID" > /tmp/deepreview_run_id.txt
   echo "$REPO"   > /tmp/deepreview_repo.txt
   ```
   In every later Bash invocation, recover both with:
   ```
   RUN_ID=$(cat /tmp/deepreview_run_id.txt)
   REPO=$(cat /tmp/deepreview_repo.txt)
   ```
   Without this, environment variables set in one Bash call do not
   survive to the next.
3. Create `$REPO/.claude/review/$RUN_ID/` and subfolders `findings/`,
   `repro-tests/`, `logs/`.
4. Determine scope:
   - No argument → diff between current `HEAD` and the merge base with the
     default branch (`origin/main` or `origin/master`, whichever exists).
     Include staged and unstaged changes.
   - PR number argument → `gh pr diff <n> --patch` (requires `gh` and a
     `github.com` remote).
   - Explicit base ref argument → diff against that ref.
5. Build a manifest at `$REPO/.claude/review/$RUN_ID/manifest.json` listing
   `{files_changed: [...], line_ranges: {file: [[start, end], ...]},
    base_ref, head_ref, mode}`.
6. Run the runtime detector with absolute paths:
   ```
   bash "$REPO/.claude/skills/deepreview/detect-runtime.sh" \
     > "$REPO/.claude/review/$RUN_ID/runtime.json"
   ```
   This produces `{stacks, test_cmd, coverage_cmd}` consumed by the
   bug-hunter, performance and test-coverage agents.
7. If the manifest is empty, abort with an explanatory message.

## Phase 2 — Parallel fan-out (six reviewers)

Dispatch six sub-agents in parallel via `Task`. Each receives:
- The path to the manifest.
- The path to the runtime descriptor.
- The path where it must write its findings:
  `.claude/review/$RUN_ID/findings/<axis>.json`.

The six axes (one agent each):

| Axis            | Sub-agent name              | May execute? |
|-----------------|-----------------------------|--------------|
| Security        | `reviewer-security`         | No           |
| Architecture    | `reviewer-architecture`     | No           |
| Bugs            | `reviewer-bug-hunter`       | Yes          |
| Performance     | `reviewer-performance`      | Yes          |
| Test coverage   | `reviewer-test-coverage`    | Yes          |
| Documentation   | `reviewer-documentation`    | No           |

Each sub-agent emits a JSON array of findings with this shape:

```json
{
  "id": "<axis>-<short-hash>",
  "axis": "security|architecture|bugs|performance|tests|docs",
  "file": "path/relative/to/repo",
  "line_range": [start, end],
  "severity": "critical|important|nice-to-have",
  "category": "free-text",
  "title": "one-line summary",
  "description": "what is wrong and why it matters",
  "trigger_scenario": "what input/state triggers it (bugs/perf only)",
  "suggested_fix": "actionable suggestion"
}
```

Wait for all six to complete before moving on. If one fails, log the error
under `logs/<axis>.err` and continue with the rest.

## Phase 3 — Verification

1. Create a git checkpoint:
   `git add -A && git commit --no-gpg-sign --allow-empty -m "deepreview checkpoint $RUN_ID"`.
   Record the SHA in `.claude/review/$RUN_ID/checkpoint.txt`.
2. Aggregate all findings into one list:
   `.claude/review/$RUN_ID/findings/_all.json`.
3. For each finding, dispatch the `verifier` sub-agent (sequentially, not in
   parallel — running multiple test invocations concurrently corrupts state).
   Pass it the finding plus the runtime descriptor.
4. The verifier sets `verified: true|false` and adds an `evidence` field
   pointing to the reproduction artifact (test file, benchmark output, or
   static-inspection note).
5. After verification, restore the working tree:
   `git reset --hard <checkpoint-sha>` to discard any reproduction tests
   the verifier wrote outside `.claude/review/`. The reproduction tests
   inside `.claude/review/` survive because they were committed in step 1.

## Phase 4 — Synthesis

1. Drop all findings with `verified: false`.
2. Deduplicate by `(file, line_range, axis)` — keep the highest severity.
3. Sort by severity (critical → important → nice-to-have), then by file.
4. Write the final markdown report to
   `$REPO/.claude/review/$RUN_ID/report.md` (absolute path, recovered
   via `REPO=$(cat /tmp/deepreview_repo.txt)` and
   `RUN_ID=$(cat /tmp/deepreview_run_id.txt)`) with this structure:

   ```
   # Deep Review — <run id>

   <base_ref>...<head_ref> · <N> files · <M> findings verified
   <M_critical> critical · <M_important> important · <M_nice> nice-to-have

   ## Critical
   ### <axis> · <file>:<line_range>
   <title>
   <description>
   Reproduction: <evidence>
   Suggested fix: <suggested_fix>

   ...
   ```

5. Print the report to stdout for the user.

## Phase 5 — Lessons

Append recurring patterns to `$REPO/.claude/lessons.md` so future
reviews can short-circuit. Format:

```
- [<axis>] <pattern>: seen in <file>:<line> on <date>. Cause: <root cause>.
  Mitigation: <fix>.
```

Only add entries for `critical` findings to keep the lessons file
dense.

> ⚠️ **`$REPO/.claude/lessons.md` is shared with other Claude Code
> skills** (Autopilot, deepaudit, and any others installed). It is
> NOT a deepreview-owned file. Phase 6 cleanup MUST NOT delete or
> modify it.

This phase MUST run **before** Phase 6 cleanup, because lessons are
extracted from the verified findings JSON which is about to be
deleted.

## Phase 6 — Persist report and cleanup intermediate artifacts

The `<run-id>/` working directory contains intermediate artifacts
(findings JSONs, manifest, runtime descriptor, repro tests, logs)
that have no value once the report is synthesized and lessons are
extracted. Without cleanup, repeat reviews accumulate dozens of these
folders. This phase preserves the report at a stable location and
removes the per-run scratch directory.

**Order of operations (do not reorder):**

1. **Recover persistent variables** from `/tmp`:
   ```bash
   REPO=$(cat /tmp/deepreview_repo.txt)
   RUN_ID=$(cat /tmp/deepreview_run_id.txt)
   SCOPE_HINT=$(cat /tmp/deepreview_scope_hint.txt)
   ```

2. **Build the `<scope-hint>` slug** if not already persisted in
   Phase 1:
   - PR mode → `pr-<number>` (e.g. `pr-1234`)
   - Branch mode → `<head-branch>` lowercased and hyphenated, capped
     at 40 chars (e.g. `feat-paypal-checkout`)
   - Explicit base ref → `vs-<base-ref-sanitized>` (e.g.
     `vs-origin-develop`)
   Persist if needed:
   `echo "<slug>" > /tmp/deepreview_scope_hint.txt`.

3. **Sanity check before any `rm`**: abort cleanup if any of `$REPO`,
   `$RUN_ID`, `$SCOPE_HINT` is empty. Print an error and stop. Never
   run `rm -rf` with an unset variable.

4. **Copy the report to its persistent location**:
   ```bash
   mkdir -p "$REPO/.claude/review-reports"
   cp "$REPO/.claude/review/$RUN_ID/report.md" \
      "$REPO/.claude/review-reports/${RUN_ID}-${SCOPE_HINT}.md"
   ```

5. **Verify the copy succeeded** before deleting the source:
   ```bash
   test -s "$REPO/.claude/review-reports/${RUN_ID}-${SCOPE_HINT}.md" \
     || { echo "report copy failed; aborting cleanup" >&2; exit 1; }
   ```

6. **Delete only the per-run scratch directory**:
   ```bash
   rm -rf "$REPO/.claude/review/$RUN_ID"
   ```

   **CRITICAL safety rules for this `rm`:**
   - The path MUST be exactly `"$REPO/.claude/review/$RUN_ID"` —
     never the parent `.claude/review/`, never `.claude/`, never
     anything broader.
   - **NEVER touch `$REPO/.claude/lessons.md`** — that file is
     shared with other skills and must persist across runs.
   - **NEVER touch other entries inside `$REPO/.claude/`** —
     `skills/`, `agents/`, `review-reports/`, `lessons.md`, or any
     skill-specific files. Only the specific `review/$RUN_ID/`
     subfolder is in scope for deletion.
   - **NEVER delete `$REPO/.claude/review/`** itself (the parent
     directory of per-run subdirs). It is the canonical workspace
     for future runs.

7. **Clean up `/tmp` markers**:
   ```bash
   rm -f /tmp/deepreview_run_id.txt /tmp/deepreview_repo.txt \
         /tmp/deepreview_scope_hint.txt
   ```

8. **Print the final user-facing line**:
   ```bash
   echo "Report saved: .claude/review-reports/${RUN_ID}-${SCOPE_HINT}.md"
   ```

## Failure handling

- If `git commit` fails (GPG, hooks, etc.), retry with `--no-verify --no-gpg-sign`.
- If a sub-agent times out (default 5 min per reviewer, 60s per verifier
  finding), record the timeout, mark affected findings `verified: false`,
  and continue.
- If the test suite is broken on the base branch (verifier sees failing
  tests before any reproduction is added), abort verification and surface
  this fact in the report — a broken baseline invalidates every reproduction.
