# biotonomy

Autonomous feature shipping for Codex: a lean, file-based development loop you run from a repo via `bt`.

## What is real today (v0.1.0)

- This is a minimal bash CLI that writes state into your repo (`.bt/`, `specs/<feature>/...`).
- `bt bootstrap`, `bt spec <feature>`, and `bt status` are fully usable without Codex.
- `bt review` works without Codex (it writes a stub output if Codex is unavailable).
- `bt implement` and `bt fix` will run quality gates; if Codex is unavailable they act as stubs (they record history/progress and still run gates).
- `bt research` requires Codex.

## 60s demo

In any repo (or a scratch folder):

```bash
npm install -g biotonomy

mkdir -p /tmp/bt-demo && cd /tmp/bt-demo
git init

bt bootstrap
bt spec demo-feature
bt implement demo-feature   # runs gates (if any) + records history
bt review demo-feature      # writes specs/demo-feature/REVIEW.md (stub if Codex is missing)
bt status

ls -R specs/demo-feature
sed -n '1,80p' specs/demo-feature/REVIEW.md
```

## Issue #3 Real Loop (End-to-End, Deterministic)

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

## Quickstart

In the repo you want Biotonomy to operate on:

```bash
bt bootstrap
bt spec 123
bt research issue-123
bt implement issue-123
bt review issue-123
bt fix issue-123
bt status
```

Notes:
- Configuration is project-local in `.bt.env` (loaded automatically by searching upward from your cwd).
- State is file-based under `specs/<feature>/`.
- Notifications are hook-based via `BT_NOTIFY_HOOK`.
- If `codex` is installed, some commands will invoke it; otherwise they degrade to stubs (except `bt research`, which requires Codex).

## Architecture

Biotonomy is intentionally minimal bash:

- `bt.sh`: CLI entrypoint and router
- `commands/*.sh`: command implementations (v0.1.0 stubs are runnable)
- `lib/*.sh`: shared helpers (env loading, state paths, notifications)
- `prompts/*.md`: prompt templates for Codex stages (implement/review/fix/research)
- `hooks/*`: example notification hooks (e.g. Telegram)

### Configuration: `.bt.env`

Biotonomy loads `.bt.env` without `source` (it parses `KEY=VALUE` lines) to avoid executing arbitrary code.

Common variables:
- `BT_SPECS_DIR` (default `specs`)
- `BT_STATE_DIR` (default `.bt`)
- `BT_NOTIFY_HOOK` (optional executable script path)
- `BT_GATE_LINT`, `BT_GATE_TYPECHECK`, `BT_GATE_TEST` (optional command overrides; auto-detect is future work)
- `BT_CODEX_BIN` (optional; defaults to `codex`)

### Notifications

If `BT_NOTIFY_HOOK` is set to an executable path, Biotonomy calls it with a single message string.

Example: `hooks/telegram.sh` expects:
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`

## Development

```bash
npm test
npm run lint
```

Lint uses `shellcheck` if it is installed; otherwise it skips with a warning.

## PR Automation (Opt-In)

If you use GitHub CLI (`gh`), there is a safe helper that defaults to `--dry-run`:

```bash
npm run pr:open -- issue-3 --dry-run
npm run pr:open -- issue-3 --run
```

It determines the branch from `specs/<feature>/SPEC.md` frontmatter (`branch:`) when present, otherwise uses `feat/<feature>`.
