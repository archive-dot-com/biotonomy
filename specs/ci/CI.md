# CI (Deterministic)

This repo's CI is intended to be deterministic and reproducible from a clean checkout.

## Contract

- **Triggers:** push and pull_request
- **Runner:** `ubuntu-24.04`
- **Runtime:** Node `20.x` via `actions/setup-node`
- **Commands:** `npm test` then `npm run lint`
- **Shell linting:** `shellcheck` is installed in CI so shell lint runs (it is optional locally)

## Determinism

CI uses `npm ci` when `package-lock.json` exists, which pins dependency resolution and makes installs reproducible. If the lockfile is missing, CI falls back to `npm install` (non-deterministic) but that should be treated as a temporary state.

If you change dependencies:
- Update `package-lock.json` in the same PR.
- Prefer `npm ci` in CI and `npm install` for local edits that intentionally update the lockfile.

## Artifacts

This workflow does not upload build artifacts.

If artifacts are added later (coverage reports, packaged tarballs, etc.), keep them deterministic:
- Generate artifacts from a clean checkout.
- Include exact versions and inputs in metadata (Node version, git SHA, lockfile).
- Use stable paths/names, and avoid embedding timestamps unless required.

