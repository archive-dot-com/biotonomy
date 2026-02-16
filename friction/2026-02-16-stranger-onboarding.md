# Stranger Onboarding Friction Log (#33)

**Scenario:** Fresh project, `npm install biotonomy`, use `bt` CLI.
**Date:** 2026-02-16
**Version:** biotonomy@0.2.2 (as found in repo)

## Commands & Timing
1. `mkdir stranger-test && cd stranger-test && npm init -y`: 1s
2. `npm install biotonomy`: 1s (cached locally likely, but realistic)
3. `npx bt --help`: <1s
4. `npx bt bootstrap`: <1s
5. `npx bt spec onboarding-33`: <1s
6. `npx bt plan-review onboarding-33`: ~20s (Codex turn)

**Elapsed Time to First Command:** ~3 seconds.
**Elapsed Time to Feature Setup:** ~25 seconds.

## Friction Findings
1. **[MAJOR] `bt spec <url>` produces invalid feature names:**
   - Command: `bt spec https://github.com/archive-dot-com/biotonomy/issues/33`
   - Result: Creates directory `specs/https://...`
   - Problem: Subsequent commands (`plan-review`, `loop`) fail because they validate the feature name against `^[A-Za-z0-9][A-Za-z0-9._-]*$`.
   - Fix: `bt spec` should sanitize URLs into slugs automatically.

2. **[MAJOR] `bt plan-review` fails to write `PLAN_REVIEW.md` when Codex returns a verdict:**
   - Command: `bt plan-review onboarding-33`
   - Result: Codex returns "Verdict: NEEDS_CHANGES" (or APPROVED_PLAN) in the chat, but `PLAN_REVIEW.md` is NOT written to the feature directory.
   - Root Cause: `commands/plan-review.sh` calls `bt_codex_exec_full_auto` which just runs `codex exec --full-auto`. It doesn't capture the stdout to the `out` file. It expects Codex to write the file, but the prompt/Codex behavior might not reliably do so without an explicit `-o` or better instructions.
   - Verification: `bt_cmd_plan_review` dies with `PLAN_REVIEW.md was not created`.

3. **[MINOR] Missing `.git` check/warning:**
   - `npx bt plan-review` fails with "Not inside a trusted directory" if `.git` is missing because it calls `codex exec`. `bt bootstrap` should perhaps `git init` or warn.

4. **[MINOR] No local fallback for Plan Review:**
   - If Codex isn't available or fails, the user is stuck. The "v0.1.0 stub" in `plan-review.sh` only triggers if `bt_codex_available` is false.

## Verdict: FAIL
The tool is not "stranger-ready" because the very first flow (spec from URL -> plan-review) results in hard failures (invalid feature name and missing output file).

## Follow-up Issues Created
- [ ] #34: `bt spec` should sanitize URL inputs into valid feature slugs.
- [ ] #35: `bt plan-review` must capture Codex output to `PLAN_REVIEW.md`.
