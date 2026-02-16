# Biotonomy Audit Report (Issue #26)
Date: 2026-02-16
Scope: correctness, safety, DX, and loop reliability (no code changes in this run)

## 1) Critical Findings
- None identified in this audit run.

## 2) High Findings

### H1: `bt pr` can miss unstaged product changes outside hardcoded paths
- Severity: High
- Area: Correctness / DX / shipping reliability
- Evidence: `commands/pr.sh:194` limits unstaged checks to `tests lib commands scripts specs prompts`.
- Impact: `bt pr`/`bt ship` can succeed while real implementation files (for example `src/**`) remain unstaged, causing silent omission of intended code in PRs.
- Repro:
```bash
TMP="$(mktemp -d /tmp/bt-audit-pr-XXXXXX)"
cp bt.sh "$TMP/" && cp -R commands lib prompts "$TMP/"
(cd "$TMP" && git init -q && git config user.email a@b.c && git config user.name t)
(cd "$TMP" && git add bt.sh commands lib prompts && git commit -qm init)
(cd "$TMP" && bash bt.sh bootstrap && bash bt.sh spec feat1)
(cd "$TMP" && git add .bt.env specs && git commit -qm "add spec artifacts")
mkdir -p "$TMP/src" && echo 'unstaged code' > "$TMP/src/app.ts"
(cd "$TMP" && bash bt.sh pr feat1 --dry-run --no-commit; echo "exit=$?")
# Observed: exit=0 (passes) even though src/app.ts is unstaged.
```

### H2: Loop and gates treat "no gates configured/detected" as PASS
- Severity: High
- Area: Loop reliability / safety
- Evidence: `lib/gates.sh:115-119` returns success when no gates run; `commands/loop.sh:64-69` treats that as preflight PASS and later convergence PASS.
- Impact: `bt loop` can report success with `Verdict: APPROVED` without running lint/typecheck/tests, creating false confidence and regression risk.
- Repro:
```bash
TMP="$(mktemp -d /tmp/bt-audit-loop-XXXXXX)"
cp bt.sh "$TMP/" && cp -R commands lib prompts "$TMP/"
mkdir -p "$TMP/specs/f1" "$TMP/bin"
printf 'Verdict: APPROVED_PLAN\n' > "$TMP/specs/f1/PLAN_REVIEW.md"
cat > "$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
out=''; for ((i=1;i<=$#;i++)); do [[ "${!i}" == "-o" ]] && j=$((i+1)) && out="${!j}"; done
[[ -n "$out" ]] && echo 'Verdict: APPROVED' > "$out"
exit 0
SH
chmod +x "$TMP/bin/codex"
(cd "$TMP" && PATH="$TMP/bin:$PATH" bash bt.sh loop f1 --max-iterations 1)
# Observed: warnings "no gates ran" but final result is successful loop convergence.
```

## 3) Medium Findings

### M1: `plan-review` writes Codex logs to shared `/tmp/codex.log`
- Severity: Medium
- Area: Safety / observability / multi-run isolation
- Evidence: `commands/plan-review.sh:34` sets `BT_CODEX_LOG_FILE="/tmp/codex.log"`.
- Impact: concurrent runs can clobber each other; logs are not feature-scoped under `specs/<feature>/.artifacts/`; weaker auditability and possible leakage across runs on shared machines.
- Repro:
```bash
# Run plan-review for two features (or repos) concurrently; both write to /tmp/codex.log.
# Observed: single shared log file, last writer wins.
```

### M2: Loop preflight runs before verifying plan approval artifact
- Severity: Medium
- Area: DX / deterministic failure modes
- Evidence: `commands/loop.sh:64-69` runs preflight gates before checking `PLAN_REVIEW.md` at `commands/loop.sh:73-78`.
- Impact: users can pay full gate runtime and side effects before receiving the primary actionable error (missing/unapproved plan review).
- Repro:
```bash
# In a repo with expensive gates and missing specs/<feature>/PLAN_REVIEW.md:
# bt loop <feature>
# Observed: gates execute first, then command fails for missing/unapproved plan review.
```

## 4) Test Gaps
- Missing test that `bt pr` fails when unstaged files exist outside the current hardcoded `check_paths` list (for example `src/**`, `app/**`).
- Missing test enforcing policy for "no gates ran" behavior in `bt loop` and `bt gates` (should be explicit fail/warn mode decision).
- Missing test that `plan-review` writes logs under `specs/<feature>/.artifacts/` (and does not use global `/tmp/codex.log`).
- Missing test for command-order UX in loop: ensure `PLAN_REVIEW.md` validation occurs before preflight gates (if intended behavior is fast-fail).

## 5) Recommended GitHub Issues (with repro steps)

1. Title: `pr/ship: fail-loud check misses unstaged implementation files outside whitelisted directories`
- Labels: `bug`, `reliability`, `dx`, `high`
- Repro: use H1 repro block above.
- Expected: `bt pr` exits non-zero and lists unstaged files regardless of top-level path.
- Actual: exits 0 when unstaged files are outside `tests|lib|commands|scripts|specs|prompts`.

2. Title: `loop/gates: no-gate condition is treated as PASS, allowing false convergence`
- Labels: `bug`, `safety`, `loop`, `high`
- Repro: use H2 repro block above.
- Expected: configurable strict mode, or default fail when no gates are available in loop mode.
- Actual: loop succeeds with only "no gates ran" warnings.

3. Title: `plan-review: replace shared /tmp/codex.log with feature-scoped artifact log`
- Labels: `bug`, `observability`, `medium`
- Repro: use M1 repro note above.
- Expected: logs written to `specs/<feature>/.artifacts/codex-plan-review.log`.
- Actual: logs are global and shared at `/tmp/codex.log`.

4. Title: `loop UX: validate PLAN_REVIEW approval before running preflight gates`
- Labels: `enhancement`, `dx`, `medium`
- Repro: use M2 repro note above.
- Expected: immediate fail with plan-review guidance before gate execution.
- Actual: gates run first, then missing/unapproved plan review error appears.
