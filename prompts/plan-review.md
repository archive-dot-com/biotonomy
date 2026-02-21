# Plan Review Loop

Review the generated SPEC.md and RESEARCH.md (if exists) for the feature.
Ensure the plan is sound and safe.

Apply this fixed rubric:
1. Security baseline
2. Concurrency/idempotency
3. Data retention/privacy
4. Error contract determinism
5. Required failure/race test coverage

Rules:
- Keep criteria fixed to SPEC + rubric above; do not move goalposts.
- Any newly introduced finding must be tagged `[REGRESSION]` or `[SPEC_GAP]` (or explicitly tied to fixed rubric/SPEC evidence).

Output Verdict: APPROVED_PLAN or Verdict: NEEDS_CHANGES.
