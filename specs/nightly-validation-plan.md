# Nightly Validation Plan (2026-02-15 → 2026-02-16)

## Objective
By morning, make Biotonomy reliably run a Ralph-like loop with clear failure modes, tested across varied scenarios, and polished onboarding.

## Required Validation Targets

### A) Biotonomy functional loop tests (5 scenarios)
1. **Happy path local feature**
   - bootstrap → spec → research → implement → review → fix → status
   - verify artifacts + gates
2. **GitHub issue-backed spec path**
   - `bt spec <issue#>` with `gh` available
   - verify SPEC includes issue metadata and story skeletons
3. **Target repo mode (`BT_TARGET_DIR`)**
   - run commands from Biotonomy repo against Archie repo
   - verify outputs land under target `specs/`
4. **Gate failure path**
   - intentionally failing gate command
   - verify fail-loud behavior + artifacts + exit codes
5. **PR shipping path**
   - `bt pr` / `bt ship` flow
   - verify commit/push/pr behavior + no missing intended files

### B) Onboarding tests (2 scenarios)
1. **Stranger onboarding from npm package**
   - install/use from published `biotonomy@0.1.0`
   - record confusion points and time-to-first-success
2. **Stranger onboarding from npx/local path**
   - no global install path
   - validate docs and first-run ergonomics

### C) Full codex audit
- Run a comprehensive codex audit pass on Biotonomy for correctness, safety, DX, and loop reliability.
- Convert findings into GitHub issues (or close as fixed) with repro steps.

## Tracking / Reporting cadence
- 15-minute cron check-ins to Paul’s thread:
  - current commit and what changed
  - issue-by-issue status tags (DONE / IN-PROGRESS / NEXT / BLOCKED)
  - completed test scenario count (X/5) and onboarding count (Y/2)
  - blockers and next action

## Exit Criteria for “dialed in” morning state
- 5/5 loop scenarios completed with evidence
- 2/2 onboarding scenarios completed with friction documented
- High-severity issues fixed or filed with clear ownership
- README and launch docs reflect real behavior, not aspirational behavior
- PR flow reliably includes intended product changes (no silent omissions)
