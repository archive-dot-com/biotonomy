# Biotonomy Audit Report (Issue #26)
Date: 2026-02-16
Scope: correctness, safety, DX, and loop reliability

## 1) Critical Findings
- None identified in this audit run.

## 2) High Findings

### H1: `bt pr` can miss unstaged product changes outside hardcoded paths [VERIFIED: FIXED]
- Severity: High
- Area: Correctness / DX / shipping reliability
- Evidence: `commands/pr.sh:194` previously limited unstaged checks to a fixed allowlist.
- Status: **FIXED** in previous tick (but audited here for regression).
- Verification: `tests/audit-findings.mjs` (test "H1 Repro").

### H2: Loop and gates treat "no gates configured/detected" as PASS [VERIFIED: FIXED]
- Severity: High
- Area: Loop reliability / safety
- Evidence: `lib/gates.sh:115-119` returns success when no gates run.
- Impact: `bt loop` could report success without running ANY validation.
- Status: **FIXED**. `bt loop` now calls `bt_run_gates --require-any`.
- Verification: `tests/audit-findings.mjs` (test "H2 Repro").

## 3) Medium Findings

### M1: `plan-review` writes Codex logs to shared `/tmp/codex.log` [VERIFIED: FIXED]
- Severity: Medium
- Area: Safety / observability / multi-run isolation
- Evidence: `commands/plan-review.sh` used a hardcoded `/tmp/codex.log`.
- Status: **FIXED**. Now uses `$dir/.artifacts/codex-plan-review.log`.
- Verification: `tests/audit-findings.mjs` (test "M1 Repro").

### M2: Loop preflight runs before verifying plan approval artifact [VERIFIED: PASS]
- Severity: Medium
- Area: DX / deterministic failure modes
- Evidence: `commands/loop.sh:65-80`
- Findings: Code already checks for `PLAN_REVIEW.md` before running preflight gates. Audit confirmed order is correct in current branch.

## 4) Audit Receipts

- [x] Run `npm test` after all fixes.
- [x] Create failing tests for H2 and M1.
- [x] Verify tests pass after fixes.
- [x] Confirm no regressions in `tests/run.mjs`.

## 5) Recommended GitHub Issues (with repro steps)

- (H2 and M1 issues closed via this audit fix)
