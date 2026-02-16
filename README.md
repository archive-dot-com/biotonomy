# Biotonomy

Biotonomy is a command-line workflow for shipping code changes with Codex.

- What it is: A CLI that runs a repeatable flow: `spec -> research -> implement -> review -> fix -> pr`.
- Who it is for: Developers who want a structured way to ship small changes fast.
- What problem it solves: Keeps work organized in files, runs quality checks, and reduces "what do I do next?" during AI-assisted coding.

## 60-Second Quickstart

Install either way:

```bash
npm i -g biotonomy
# then use: bt ...
```

```bash
npx biotonomy ...
```

Minimal demo in a fresh repo:

```bash
mkdir biotonomy-demo && cd biotonomy-demo
git init
npm init -y

npx biotonomy bootstrap
npx biotonomy spec hello-world
npx biotonomy review hello-world
npx biotonomy status
```

Expected files after the demo:

- `.bt.env`
- `.bt/`
- `specs/hello-world/SPEC.md`
- `specs/hello-world/REVIEW.md`
- `specs/hello-world/progress.txt`
- `specs/hello-world/history/001-spec.md`
- `specs/hello-world/history/002-review.md`
- `specs/hello-world/.artifacts/codex-review.log`

Notes:

- `review` still creates `REVIEW.md` even if Codex is not installed.
- `research` requires Codex.

## Ship A Small Change

Use this for a real change from idea to PR.

1. `spec` (define the change)

```bash
bt spec my-change
# or from GitHub issue:
# bt spec 123
```

- Automated today: creates `specs/<feature>/SPEC.md`, history, and progress logs.
- Manual today: fill in/clean up stories and acceptance criteria in `SPEC.md`.

2. `research` (gather context)

```bash
bt research my-change
```

- Automated today: runs Codex in read-only mode and writes `RESEARCH.md`.
- Manual today: confirm research quality and adjust plan if needed.

3. `implement` (make the change)

```bash
bt implement my-change
```

- Automated today: runs Codex in full-auto and then runs quality gates.
- Manual today: if Codex is unavailable, this stage is a stub and you implement changes yourself.

4. `review` (check what changed)

```bash
bt review my-change
```

- Automated today: writes `REVIEW.md` (with a fallback stub if Codex fails).
- Manual today: decide whether findings are acceptable for your team.

5. `fix` (address findings)

```bash
bt fix my-change
```

- Automated today: runs Codex fix pass and re-runs quality gates.
- Manual today: rerun until you are satisfied; no built-in auto-loop to "done" yet.

6. `pr` (open pull request)

```bash
bt pr my-change --dry-run
bt pr my-change --run
```

- Automated today: runs tests/lint, creates branch, optionally commits, pushes, opens PR via `gh`.
- Manual today: choose reviewers/labels, final PR polish, and merge strategy.

## Current Limitations

- No one-command autonomous loop yet (you run each stage yourself).
- `research` needs Codex installed and available.
- `implement`/`fix` can run as stubs without Codex (gates still run, code may not change).
- PR flow depends on `gh` and repository permissions.

## Troubleshooting

`gh` auth fails (`bt spec 123` or `bt pr ...`):

```bash
gh auth status
gh auth login
```

Codex missing (`codex required` or `codex not found`):

- Install Codex and make sure `codex` is on your `PATH`.
- Or set a custom binary in `.bt.env`: `BT_CODEX_BIN=/path/to/codex`.

Quality gate failures on `implement`/`fix`:

```bash
bt gates my-change
```

- Fix failing lint/typecheck/test commands.
- Override gate commands in `.bt.env` if auto-detection is wrong:
  - `BT_GATE_LINT=...`
  - `BT_GATE_TYPECHECK=...`
  - `BT_GATE_TEST=...`

Contributing and npm publish auth (token/2FA):

```bash
npm whoami
npm login
npm publish --dry-run
```

- If your npm account uses 2FA for publish, npm will require a one-time code during publish.

## Commands

```bash
bt bootstrap
bt spec <feature|issue#>
bt research <feature>
bt implement <feature>
bt review <feature>
bt fix <feature>
bt gates [feature]
bt status
bt pr <feature> [--dry-run|--run]
bt reset
```

## Development

```bash
npm test
npm run lint
```
