# Biotonomy

Biotonomy is a command-line tool for shipping code changes with Codex. It wraps the messy, manual steps of AI-assisted development into a structured, verifiable loop: `spec -> research -> implement -> review -> fix -> pr`.

- **Verifiable**: Every stage (spec, implementation, fix) is enforced by quality gates (tests, lint, typecheck).
- **History-aware**: Keeps versioned history of specs, research, and reviews in your repo.
- **Autonomous**: Can run as a fully automated driver (`bt loop`) that iterates until code passes review and gates.

> **Status**: v0.2.0 is stable. It supports full manual stage progression and the new autonomous `bt loop` driver.

## 60-Second Quickstart

Install via npm:

```bash
npm i -g biotonomy
# then use: bt ...
```

Or run directly with npx:

```bash
npx biotonomy ...
```

### Try the Demo
In any git repository (or a fresh one):

```bash
# 1. Initialize biotonomy scaffold
bt bootstrap

# 2. Define a new feature (creates specs/hello-world/SPEC.md)
bt spec hello-world

# 3. Check status
bt status
```

## The "True Loop" Workflow

The primary power of Biotonomy is the autonomous implementation driver. Instead of running stages manually, you can let Biotonomy drive Codex until the feature is complete and verified.

```bash
# Start a loop that iterates research -> implement -> review -> fix
# It continues until the review verdict is APPROVE and gates pass.
bt loop my-feature --max-iterations 3
```

## Manual Stage Progression

If you prefer step-by-step control, use the individual commands:

1. **`bt spec <feature|issue#>`**: Scaffolds a feature spec. If an issue number is provided, it fetches details from GitHub.
2. **`bt research <feature>`**: Uses Codex to gather context and write `RESEARCH.md`.
3. **`bt plan-review <feature>`**: Enforces an explicit planning gate before code is touched.
4. **`bt implement <feature>`**: Primary code generation stage. Runs implementation gates (tests, lint) automatically.
5. **`bt review <feature>`**: Generates a quality review of the implementation.
6. **`bt fix <feature>`**: Addresses review findings and quality gate failures.
7. **`bt pr <feature> --run`**: Formats artifacts into a PR description, pushes the branch, and opens a GitHub PR.

## Expected Artifacts

Biotonomy keeps your work organized under `specs/<feature>/`:

- `SPEC.md`: Feature requirements and plan.
- `RESEARCH.md`: Context and architectural findings.
- `PLAN_REVIEW.md`: Planning gate verdict history.
- `REVIEW.md`: Latest implementation review.
- `progress.json`: State tracking for the loop driver.
- `history/`: Versioned snapshots of every major stage iteration.
- `.artifacts/`: Raw LLM logs and diagnostic traces.

## Configuration & Quality Gates

Biotonomy automatically detects your test/lint stack (npm, vitest, jest, eslint, etc.). You can override them in `.bt.env`:

```bash
BT_GATE_LINT="npm run lint"
BT_GATE_TYPECHECK="tsc --noEmit"
BT_GATE_TEST="npm test"
BT_CODEX_BIN="/usr/local/bin/codex"
```

## Requirements

- **Node.js**: >= 18
- **git**: Required for state and PR management.
- **gh CLI**: Required for `bt spec <issue#>` and `bt pr`.
- **Codex**: Required for autonomous stages (`research`, `implement`, `review`, `fix`, `loop`).

## Commands Reference

```bash
bt bootstrap                      # Initialize biotonomy in current repo
bt spec <feature|issue#>          # Create/fetch spec
bt research <feature>             # Run research phase
bt plan-review <feature>          # Run planning gate
bt implement <feature>            # Run implementation phase
bt review <feature>               # Run review phase
bt fix <feature>                  # Run fix phase
bt loop <feature>                 # Run autonomous impl cycle
bt gates [feature]                 # Run all quality gates
bt status                         # Show workspace status
bt pr <feature> [--run]           # Open GitHub PR
bt reset                          # Clear local biotonomy state
```

---
© 2026 Archive. CLI designed for autonomous workflows.
