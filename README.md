# Biotonomy

Biotonomy (`bt`) is a CLI for running a Codex-driven development workflow in a repo:

`spec -> research -> plan-review -> implement -> review -> fix -> pr`

It supports both:
- manual stage-by-stage execution
- a one-command iterative loop with `bt loop`

## Quickstart

Prereqs: Node.js >= 18, `git`, Codex CLI available as `codex` (or set `BT_CODEX_BIN`).

```bash
# Install
npm i -g biotonomy

# In your project repo
bt bootstrap

# Create a feature scaffold
FEATURE=hello-world
bt spec "$FEATURE"

# Loop requires an approved plan review verdict first
cat > "specs/$FEATURE/PLAN_REVIEW.md" <<'MD'
Verdict: APPROVED_PLAN
MD

# Run autonomous implement/review/fix iterations (with gates)
bt loop "$FEATURE" --max-iterations 3
```

## `bt loop`

`bt loop <feature> [--max-iterations N]` runs:
1. preflight quality gates
2. `implement`
3. `review`
4. `fix` only when review verdict is `NEEDS_CHANGES`
5. repeat until verdict is `APPROVE`/`APPROVED` and gates pass, or max iterations is reached

Loop hard-requires an approved `specs/<feature>/PLAN_REVIEW.md` verdict (`APPROVE_PLAN` or `APPROVED_PLAN`).

## Artifacts And State

Biotonomy writes feature state under `specs/<feature>/`:
- `SPEC.md`
- `RESEARCH.md`
- `PLAN_REVIEW.md`
- `REVIEW.md`
- `history/` stage snapshots (`###-<stage>.md`) and loop iteration snapshots (`*-loop-iter-###.md`)
- `loop-progress.json` loop summary and per-iteration status
- `progress.txt` append-only stage log
- `.artifacts/` Codex logs and command artifacts (for example `codex-implement.log`, `codex-review.log`, `codex-fix.log`)
- `gates.json` feature gate results when running `bt gates <feature>`

Global gate state is written to `.bt/state/gates.json` when running `bt gates` without a feature.

## Manual Commands

```bash
bt bootstrap
bt spec <feature|issue#>
bt research <feature>
bt plan-review <feature>
bt implement <feature>
bt review <feature>
bt fix <feature>
bt loop <feature> [--max-iterations N]
bt gates [feature]
bt status
bt pr <feature> [--run]
```

## Configuration

Project config lives in `.bt.env` (created by `bt bootstrap`). Common overrides:

```bash
BT_SPECS_DIR=specs
BT_STATE_DIR=.bt
BT_GATE_LINT="npm run lint"
BT_GATE_TYPECHECK="tsc --noEmit"
BT_GATE_TEST="npm test"
BT_CODEX_BIN="/path/to/codex"
```

## Release

Run the release readiness checks:

```bash
npm run release:ready
```

That script runs tests, lint, pack verification, and `npm pack --dry-run`.
