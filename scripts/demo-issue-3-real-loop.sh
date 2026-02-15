#!/usr/bin/env bash
set -euo pipefail

# End-to-end "real loop" demo for Issue #3.
# Runs the actual entrypoint (bt.sh) against a deterministic workspace and
# writes scrubbed (timestamp/path-normalized) outputs under specs/issue-3-real-loop/.

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROOT="$PWD"
BT="$ROOT/bt.sh"

BASE="$ROOT/specs/issue-3-real-loop"
WORK="$BASE/workspace"
BIN="$WORK/bin"

iters="${BT_DEMO_ITERS:-3}"
if [[ $# -gt 0 ]]; then
  case "${1:-}" in
    -h|--help)
      cat <<EOF
Usage:
  npm run demo -- [iterations]

Writes deterministic demo outputs under:
  specs/issue-3-real-loop/

You can also set:
  BT_DEMO_ITERS=5
EOF
      exit 0
      ;;
    *[!0-9]*)
      echo "demo: iterations must be a number (got: $1)" >&2
      exit 2
      ;;
    *)
      iters="$1"
      ;;
  esac
fi

demo_sed_inplace() {
  local expr="$1"
  local file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i -E "$expr" "$file"
  else
    sed -i '' -E "$expr" "$file"
  fi
}

run_bt() {
  local -a args=("$@")
  # bt logs to stderr; capture both, and normalize ANSI coloring.
  (
    export BT_NO_COLOR=1
    export LC_ALL=C
    export LANG=C
    export PATH="$BIN:$PATH"
    cd "$WORK"
    bash "$BT" "${args[@]}"
  ) 2>&1
}

write_stub_gh() {
  cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "issue" && "${2:-}" == "view" && "${3:-}" == "3" ]]; then
  cat <<'JSON'
{"title":"Core loop (Codex + gh integration)","url":"https://github.com/archive-dot-com/biotonomy/issues/3","body":"Issue #3 demo body.\n\nThis is deterministic stub data."}
JSON
  exit 0
fi
echo "stub gh: unexpected args: $*" >&2
exit 2
EOF
  chmod 755 "$BIN/gh"
}

write_stub_codex() {
  cat >"$BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "exec" ]]; then
  echo "stub codex: expected 'exec' (got: ${1:-})" >&2
  exit 2
fi
shift

out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift; out="${1:-}"; shift ;;
    *) shift ;;
  esac
done

# Read-only path writes an output file; full-auto path just exits 0.
if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  # Keep output stable across runs (no timestamps).
  cat >"$out" <<'MD'
# Codex Stub Output

Verdict: OK

This is deterministic stub output for the Issue #3 real-loop demo.
MD
fi
exit 0
EOF
  chmod 755 "$BIN/codex"
}

scrub_workspace_nondeterminism() {
  # Normalize timestamps in files that intentionally include them.
  local f
  if [[ -f "$WORK/.bt/state/gates.json" ]]; then
    demo_sed_inplace 's/"ts":[[:space:]]*"[^"]+"/"ts": "1970-01-01T00:00:00Z"/' "$WORK/.bt/state/gates.json"
  fi
  if [[ -d "$WORK/specs/issue-3" ]]; then
    if [[ -f "$WORK/specs/issue-3/gates.json" ]]; then
      demo_sed_inplace 's/"ts":[[:space:]]*"[^"]+"/"ts": "1970-01-01T00:00:00Z"/' "$WORK/specs/issue-3/gates.json"
    fi
    if [[ -f "$WORK/specs/issue-3/progress.txt" ]]; then
      demo_sed_inplace 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/1970-01-01 00:00:00/' "$WORK/specs/issue-3/progress.txt"
    fi
    if [[ -d "$WORK/specs/issue-3/history" ]]; then
      for f in "$WORK/specs/issue-3/history/"*.md; do
        [[ -f "$f" ]] || continue
        demo_sed_inplace 's/^- when: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/- when: 1970-01-01 00:00:00/' "$f"
      done
    fi
  fi
}

mkdir -p "$BASE"
rm -rf "$WORK"
mkdir -p "$WORK" "$BIN"

# Minimal project scaffolding for deterministic repo resolution and gate behavior.
cat >"$WORK/.bt.env" <<'EOF'
BT_SPECS_DIR=specs
BT_STATE_DIR=.bt

# Make gates deterministic and fast.
BT_GATE_LINT=true
BT_GATE_TYPECHECK=true
BT_GATE_TEST=true

# Use the stubbed codex in workspace bin/.
BT_CODEX_BIN=codex
EOF

write_stub_gh
write_stub_codex

(
  cd "$WORK"
  git init -q
  git remote add origin https://github.com/archive-dot-com/biotonomy.git
) >/dev/null 2>&1 || true

raw="$BASE/transcript.raw.txt"
out="$BASE/transcript.txt"
snap="$BASE/snapshot.txt"

: >"$raw"

{
  echo "biotonomy issue-3 real-loop demo"
  echo "iterations=$iters"
  echo

  run_bt bootstrap
  run_bt spec 3

  i=1
  while [[ "$i" -le "$iters" ]]; do
    echo "== iteration $i =="
    run_bt research issue-3
    run_bt implement issue-3 || true
    run_bt review issue-3
    run_bt gates issue-3 || true
    run_bt status
    echo
    i=$((i + 1))
  done
} >>"$raw"

scrub_workspace_nondeterminism

# Create a scrubbed transcript: normalize bt timestamps and any absolute paths.
cp "$raw" "$out"
demo_sed_inplace 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/1970-01-01 00:00:00/' "$out"
demo_sed_inplace "s#${WORK}#<WORK>#g" "$out"
demo_sed_inplace "s#${ROOT}#<REPO>#g" "$out"

# Snapshot key outputs (tree + a couple of file excerpts).
{
  echo "workspace: <WORK>"
  echo
  echo "files:"
  (cd "$WORK" && find . -type f -not -path "./.git/*" | LC_ALL=C sort)
  echo
  echo "SPEC.md (head):"
  sed -n '1,40p' "$WORK/specs/issue-3/SPEC.md"
  echo
  echo "RESEARCH.md (head):"
  sed -n '1,40p' "$WORK/specs/issue-3/RESEARCH.md"
  echo
  echo "REVIEW.md (head):"
  sed -n '1,40p' "$WORK/specs/issue-3/REVIEW.md"
} >"$snap"

demo_sed_inplace "s#${WORK}#<WORK>#g" "$snap"

echo "demo: wrote $out" >&2
echo "demo: wrote $snap" >&2
