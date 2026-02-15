# Biotonomy

Biotonomy is a CLI that runs Codex loops (research→implement→review→fix) inside your repo.
It enforces quality gates (lint/typecheck/test) between stages and records everything as files.
PR automation is next: the repo has an opt-in `gh` helper today, and first-class PR flows are planned.

Biotonomy is intentionally file-based:
- project config lives in `.bt.env`
- ephemeral state lives in `.bt/`
- feature state lives in `specs/<feature>/`

## The Codex Loop

For a feature folder `specs/<feature>/`, the loop is:

1. `bt spec <feature>`: create `SPEC.md` (or `bt spec <issue#>` to pull from GitHub via `gh`)
2. `bt research <feature>`: Codex writes `RESEARCH.md` (Codex required)
3. `bt implement <feature>`: Codex applies code changes + Biotonomy runs quality gates
4. `bt review <feature>`: Codex reviews into `REVIEW.md` (writes a stub if Codex is missing)
5. `bt fix <feature>`: Codex applies targeted fixes + Biotonomy runs quality gates

Supporting commands:
- `bt status`: summarize story status from `SPEC.md` plus latest `gates.json` (if present)
- `bt gates [<feature>]`: run gates and write `gates.json` (feature-local or global)
- `bt reset`: delete `.bt/` and `specs/**/.lock` (does not modify your git working tree)

## Ship Archie (Walkthrough)

This is the intended "ship a feature" path. Some steps are still manual; each TODO points at the tracking issue.

```bash
# 0) Install
npm install -g biotonomy

# 1) Initialize the repo for Biotonomy (creates .bt.env, specs/, .bt/)
bt bootstrap

# 2) Create a spec (local feature name)
bt spec archie

# (Optional) If "Archie" is a GitHub issue:
# bt spec 123   # pulls issue title/body via `gh` into specs/issue-123/SPEC.md

# 3) Research (requires Codex; see Issue #3 for the end-to-end loop/demo harness)
bt research archie

# 4) Implement (runs gates; if Codex is unavailable this records history and still runs gates)
bt implement archie

# 5) Review (writes specs/archie/REVIEW.md; stub output if Codex is unavailable)
bt review archie

# 6) Fix until review is clean (gates are re-run)
bt fix archie

# 7) Check progress at any time
bt status
```

TODOs and tracked work:
- Deterministic end-to-end loop runner + offline stubs: [Issue #3](https://github.com/archive-dot-com/biotonomy/issues/3)
- Make implement/review/fix tighter as an explicit "repeat until APPROVE + gates pass" loop: [Issue #4](https://github.com/archive-dot-com/biotonomy/issues/4), [Issue #5](https://github.com/archive-dot-com/biotonomy/issues/5), [Issue #6](https://github.com/archive-dot-com/biotonomy/issues/6)
- Harden/expand quality gates and configuration: [Issue #7](https://github.com/archive-dot-com/biotonomy/issues/7)
- First-class PR automation (not just a script): [Issue #8](https://github.com/archive-dot-com/biotonomy/issues/8)

## Artifacts And Layout

Biotonomy is minimal bash plus prompt templates:
- `bt.sh`: CLI entrypoint and router
- `commands/*.sh`: command implementations
- `lib/*.sh`: shared helpers (env loading, state paths, notifications, gates, Codex exec)
- `prompts/*.md`: prompt templates for Codex stages
- `hooks/*`: example notification hooks

On disk, expect:
- `.bt.env`: project config (parsed as `KEY=VALUE` without `source` / without executing code)
- `.bt/`: ephemeral state (locks/caches; safe to delete via `bt reset`)
- `specs/<feature>/SPEC.md`: plan and story statuses (parseable; created by `bt spec`)
- `specs/<feature>/RESEARCH.md`: research notes (`bt research`)
- `specs/<feature>/REVIEW.md`: review verdict + findings (`bt review`)
- `specs/<feature>/gates.json`: latest gate results when running `bt gates <feature>`
- `specs/<feature>/progress.txt`: timestamped progress log
- `specs/<feature>/history/*.md`: append-only run history for each stage
- `specs/<feature>/.artifacts/*`: captured stderr from Codex/gh for debugging/repro

## Quality Gates

Stages that run gates:
- `bt implement <feature>`
- `bt fix <feature>`
- `bt gates [<feature>]`

Gate configuration:
- Override per-project in `.bt.env` via `BT_GATE_LINT`, `BT_GATE_TYPECHECK`, `BT_GATE_TEST`
- If unset, Biotonomy tries simple auto-detection (npm/yarn/pnpm/Makefile)

## PR Automation (Opt-In Today)

There is currently a safe helper script (defaults to `--dry-run`) that uses `git` and `gh`:

```bash
npm run pr:open -- archie --dry-run
npm run pr:open -- archie --run
```

It determines the branch from `specs/<feature>/SPEC.md` frontmatter (`branch:`) when present, otherwise uses `feat/<feature>`.
The planned end state is a first-class `bt pr ...` flow. Tracked in [Issue #8](https://github.com/archive-dot-com/biotonomy/issues/8).

## Demos

### Issue #3 Real Loop (End-to-End, Deterministic)

This repo includes an end-to-end "real loop" runner that:
- runs the actual `bt.sh` entrypoint
- uses a deterministic workspace
- stubs `gh` and `codex` so it is reproducible offline
- writes a scrubbed transcript + snapshot under `specs/issue-3-real-loop/`

```bash
npm install
npm run demo

ls -R specs/issue-3-real-loop
sed -n '1,120p' specs/issue-3-real-loop/transcript.txt
sed -n '1,120p' specs/issue-3-real-loop/snapshot.txt
```

## Install

Global install:

```bash
npm install -g biotonomy
bt --help
```

Local (repo) usage:

```bash
npx biotonomy --help
```

## Status (v0.1.0)

Implemented today:
- File-based loop artifacts: `.bt.env`, `.bt/`, `specs/<feature>/...`
- `bt bootstrap`, `bt spec <feature>`, `bt status`, `bt gates`, `bt reset`
- `bt review` produces `REVIEW.md` even without Codex (stub output + required `Verdict:` line)
- `bt implement` and `bt fix` always run quality gates and record history; if Codex is missing they behave as stubs (no code changes)
- `bt research` requires Codex (it dies early if `codex` is not available)
- Opt-in PR helper (`npm run pr:open`) with `--dry-run` by default

In progress (tracked in issues):
- [Issue #3](https://github.com/archive-dot-com/biotonomy/issues/3): core loop demo harness + deterministic runner
- [Issue #4](https://github.com/archive-dot-com/biotonomy/issues/4): implement stage reliability and repeatability
- [Issue #5](https://github.com/archive-dot-com/biotonomy/issues/5): review stage contract and enforcement
- [Issue #6](https://github.com/archive-dot-com/biotonomy/issues/6): fix stage iteration (close the loop from REVIEW.md back to green gates)
- [Issue #7](https://github.com/archive-dot-com/biotonomy/issues/7): quality gates (auto-detect, reporting, policy)
- [Issue #8](https://github.com/archive-dot-com/biotonomy/issues/8): PR automation (first-class workflows)

## Development

```bash
npm test
npm run lint
```

Lint uses `shellcheck` if it is installed; otherwise it skips with a warning (CI installs shellcheck and runs strict).
