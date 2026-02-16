import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const bt = path.join(repoRoot, "bt.sh");

function runBt(args, { cwd, env } = {}) {
  const res = spawnSync("bash", [bt, ...args], {
    cwd,
    env: { ...process.env, ...(env || {}) },
    encoding: "utf8",
  });
  return {
    code: res.status ?? 1,
    stdout: res.stdout ?? "",
    stderr: res.stderr ?? "",
  };
}

function mkTmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-test-"));
}

function writeFile(p, s) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, s, "utf8");
}

function writeExe(p, s) {
  writeFile(p, s);
  fs.chmodSync(p, 0o755);
}

function test(name, fn) {
  try {
    fn();
    process.stderr.write(`ok - ${name}\n`);
  } catch (e) {
    process.stderr.write(`not ok - ${name}\n`);
    process.stderr.write(String(e?.stack || e) + "\n");
    process.exitCode = 1;
  }
}

test("help works", () => {
  const res = runBt(["--help"]);
  assert.equal(res.code, 0);
  assert.match(res.stdout + res.stderr, /biotonomy \(bt\)/);
});

test("unknown command exits 2", () => {
  const res = runBt(["nope"]);
  assert.equal(res.code, 2);
  assert.match(res.stderr, /unknown command/i);
});

test("bootstrap creates .bt.env and folders", () => {
  const cwd = mkTmp();
  const res = runBt(["bootstrap"], { cwd });
  assert.equal(res.code, 0);
  assert.ok(fs.existsSync(path.join(cwd, ".bt.env")));
  assert.ok(fs.existsSync(path.join(cwd, "specs")));
  assert.ok(fs.existsSync(path.join(cwd, ".bt")));
  assert.ok(fs.existsSync(path.join(cwd, "hooks")));
});

test("BT_TARGET_DIR: bootstrap writes .bt.env/specs/.bt/hooks inside target (not caller cwd)", () => {
  const caller = mkTmp();
  const target = mkTmp();

  const res = runBt(["bootstrap"], { cwd: caller, env: { BT_TARGET_DIR: target } });
  assert.equal(res.code, 0, res.stderr);

  assert.ok(fs.existsSync(path.join(target, ".bt.env")), "target .bt.env missing");
  assert.ok(fs.existsSync(path.join(target, "specs")), "target specs/ missing");
  assert.ok(fs.existsSync(path.join(target, ".bt")), "target .bt/ missing");
  assert.ok(fs.existsSync(path.join(target, "hooks")), "target hooks/ missing");

  assert.ok(!fs.existsSync(path.join(caller, ".bt.env")), "caller .bt.env should not be created");
  assert.ok(!fs.existsSync(path.join(caller, "specs")), "caller specs/ should not be created");
  assert.ok(!fs.existsSync(path.join(caller, ".bt")), "caller .bt/ should not be created");
});

test("--target: bootstrap writes .bt.env/specs/.bt/hooks inside target (not caller cwd)", () => {
  const caller = mkTmp();
  const target = mkTmp();

  const res = runBt(["--target", target, "bootstrap"], { cwd: caller });
  assert.equal(res.code, 0, res.stderr);

  assert.ok(fs.existsSync(path.join(target, ".bt.env")), "target .bt.env missing");
  assert.ok(fs.existsSync(path.join(target, "specs")), "target specs/ missing");
  assert.ok(fs.existsSync(path.join(target, ".bt")), "target .bt/ missing");
  assert.ok(fs.existsSync(path.join(target, "hooks")), "target hooks/ missing");

  assert.ok(!fs.existsSync(path.join(caller, ".bt.env")), "caller .bt.env should not be created");
  assert.ok(!fs.existsSync(path.join(caller, "specs")), "caller specs/ should not be created");
  assert.ok(!fs.existsSync(path.join(caller, ".bt")), "caller .bt/ should not be created");
});

test("--target: can appear after subcommand and is stripped before subcommand parsing", () => {
  const caller = mkTmp();
  const target = mkTmp();

  const res = runBt(["bootstrap", "--target", target], { cwd: caller });
  assert.equal(res.code, 0, res.stderr);

  assert.ok(fs.existsSync(path.join(target, ".bt.env")), "target .bt.env missing");
  assert.ok(!fs.existsSync(path.join(caller, ".bt.env")), "caller .bt.env should not be created");
});

test("env loading (BT_SPECS_DIR) affects status output", () => {
  const cwd = mkTmp();
  writeFile(
    path.join(cwd, ".bt.env"),
    "export BT_SPECS_DIR=specz # inline comment\nBT_STATE_DIR=.bt\n"
  );
  fs.mkdirSync(path.join(cwd, "specz"), { recursive: true });

  const res = runBt(["status"], { cwd });
  assert.equal(res.code, 0);
  assert.match(res.stdout, /specs_dir: specz/);
});

test("status counting: treats '**status:** completed' as done", () => {
  const cwd = mkTmp();
  writeFile(
    path.join(cwd, "specs", "feat-completed", "SPEC.md"),
    [
      "# SPEC",
      "",
      "- **story:** verify completed mapping",
      "  - **status:** completed",
      "",
    ].join("\n")
  );

  const res = runBt(["status"], { cwd });
  assert.equal(res.code, 0, res.stderr);
  assert.match(
    res.stdout,
    /feature: feat-completed stories=1 pending=0 in_progress=0 done=1 failed=0 blocked=0/
  );
});

test("BT_TARGET_DIR: spec writes SPEC.md under target", () => {
  const caller = mkTmp();
  const target = mkTmp();

  const res = runBt(["spec", "feat-t"], { cwd: caller, env: { BT_TARGET_DIR: target } });
  assert.equal(res.code, 0, res.stderr);

  const specPath = path.join(target, "specs", "feat-t", "SPEC.md");
  assert.ok(fs.existsSync(specPath), "target SPEC.md missing");
  assert.ok(!fs.existsSync(path.join(caller, "specs", "feat-t", "SPEC.md")), "caller SPEC.md should not be created");
});

test("implement fails when a configured gate fails", () => {
    const cwd = mkTmp();
    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    writeExe(codex, `#!/usr/bin/env bash\nexit 0\n`);

    writeFile(
        path.join(cwd, ".bt.env"),
        [
            "BT_SPECS_DIR=specs",
            "BT_STATE_DIR=.bt",
            "BT_GATE_TEST=false",
            "",
        ].join("\n")
    );

    const spec = runBt(["spec", "feat-x"], { cwd });
    assert.equal(spec.code, 0, spec.stderr);

    const impl = runBt(["implement", "feat-x"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` }
    });
    assert.equal(impl.code, 1);
    assert.match(impl.stderr, /gate failed: test/i);
});

test("research writes RESEARCH.md (stubs codex via PATH)", () => {
  const cwd = mkTmp();

  const spec = runBt(["spec", "feat-r"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "exec" ]]; then
  echo "unexpected codex invocation" >&2
  exit 2
fi
# Full-auto research: intentionally do NOT write RESEARCH.md so bt creates a stub.
exit 0
`
  );

  const res = runBt(["research", "feat-r"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stderr);

  const out = path.join(cwd, "specs", "feat-r", "RESEARCH.md");
  assert.ok(fs.existsSync(out), "RESEARCH.md missing");
  const content = fs.readFileSync(out, "utf8");
  assert.match(content, /^# Research: feat-r/m);

  const log = path.join(cwd, "specs", "feat-r", ".artifacts", "codex-research.log");
  assert.ok(fs.existsSync(log), "codex-research.log missing");
});

test("review writes REVIEW.md with Verdict: (stubs codex via PATH)", () => {
  const cwd = mkTmp();

  const spec = runBt(["spec", "feat-v"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "exec" ]]; then
  echo "unexpected codex invocation" >&2
  exit 2
fi
shift
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift; out="$1"; shift ;;
    *) shift ;;
  esac
done
if [[ -z "$out" ]]; then
  # full-auto path; do nothing
  exit 0
fi
printf '%s\\n' "# Review from stub" "Findings: none" "Verdict: APPROVED" > "$out"
exit 0
`
  );

  const res = runBt(["review", "feat-v"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stderr);

  const out = path.join(cwd, "specs", "feat-v", "REVIEW.md");
  assert.ok(fs.existsSync(out), "REVIEW.md missing");
  const content = fs.readFileSync(out, "utf8");
  assert.match(content, /^Verdict: APPROVED/im);
});

test("loop (stubbed): runs implement -> review and finishes on APPROVED", () => {
    const cwd = mkTmp();
    const spec = runBt(["spec", "feat-loop"], { cwd });
    assert.equal(spec.code, 0);

    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    writeExe(
      codex,
      `#!/usr/bin/env bash
set -euo pipefail
# Stub for both implement and review.
# If called with -o (review), write Verdict: APPROVED
out=""
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    out="\${args[i+1]}"
  fi
done

if [[ -n "$out" ]]; then
  printf "Verdict: APPROVED\\n" > "$out"
fi
exit 0
`
    );

    const res = runBt(["loop", "feat-loop"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` },
    });
    const combined = res.stdout + res.stderr;
    assert.equal(res.code, 0, combined);
    assert.match(combined, /verdict: APPROVED/);
    assert.match(combined, /Loop successful/);
});

test("loop persists per-iteration history and deterministic progress artifact", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-history"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  const reviewCount = path.join(cwd, "review.count");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
out=""
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    out="\${args[i+1]}"
  fi
done
if [[ -n "$out" ]]; then
  c=0
  if [[ -f ${JSON.stringify(reviewCount)} ]]; then
    c=$(cat ${JSON.stringify(reviewCount)})
  fi
  c=$((c+1))
  printf '%s\\n' "$c" > ${JSON.stringify(reviewCount)}
  if [[ "$c" -eq 1 ]]; then
    printf 'Verdict: NEEDS_CHANGES\\n' > "$out"
  else
    printf 'Verdict: APPROVED\\n' > "$out"
  fi
fi
exit 0
`
  );

  const res = runBt(["loop", "feat-loop-history", "--max-iterations", "3"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const historyDir = path.join(cwd, "specs", "feat-loop-history", "history");
  const historyFiles = fs.readdirSync(historyDir);
  assert.ok(historyFiles.some((f) => f.endsWith("-loop-iter-001.md")), "missing loop iter 1 history");
  assert.ok(historyFiles.some((f) => f.endsWith("-loop-iter-002.md")), "missing loop iter 2 history");

  const progressPath = path.join(cwd, "specs", "feat-loop-history", "loop-progress.json");
  assert.ok(fs.existsSync(progressPath), "missing loop-progress.json");
  const progress = JSON.parse(fs.readFileSync(progressPath, "utf8"));
  assert.equal(progress.feature, "feat-loop-history");
  assert.equal(progress.maxIterations, 3);
  assert.equal(progress.completedIterations, 2);
  assert.equal(progress.result, "success");
  assert.equal(progress.iterations[0].verdict, "NEEDS_CHANGES");
  assert.equal(progress.iterations[1].verdict, "APPROVED");
});

test("loop runs implement before each review iteration; fix only after NEEDS_CHANGES verdict", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-order"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  const reviewCount = path.join(cwd, "review-order.count");
  const events = path.join(cwd, "loop-order.events");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
logf="\${BT_CODEX_LOG_FILE:-}"
kind="$(basename "$logf" .log | sed 's/^codex-//')"
printf '%s\\n' "$kind" >> ${JSON.stringify(events)}

out=""
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    out="\${args[i+1]}"
  fi
done

if [[ -n "$out" ]]; then
  c=0
  if [[ -f ${JSON.stringify(reviewCount)} ]]; then
    c=$(cat ${JSON.stringify(reviewCount)})
  fi
  c=$((c+1))
  printf '%s\\n' "$c" > ${JSON.stringify(reviewCount)}
  if [[ "$c" -eq 1 ]]; then
    printf 'Verdict: NEEDS_CHANGES\\n' > "$out"
  else
    printf 'Verdict: APPROVED\\n' > "$out"
  fi
fi
exit 0
`
  );

  const res = runBt(["loop", "feat-loop-order", "--max-iterations", "3"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const callOrder = fs.readFileSync(events, "utf8").trim().split("\n").filter(Boolean);
  assert.deepEqual(
    callOrder,
    ["implement", "review", "fix", "implement", "review"],
    `unexpected loop order: ${callOrder.join(" -> ")}`
  );
});

test("loop exits non-zero on max iterations and persists failure progress", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-max-fail"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
out=""
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    out="\${args[i+1]}"
  fi
done
if [[ -n "$out" ]]; then
  printf 'Verdict: NEEDS_CHANGES\\n' > "$out"
fi
exit 0
`
  );

  const res = runBt(["loop", "feat-loop-max-fail", "--max-iterations", "2"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 1, res.stdout + res.stderr);
  assert.match(res.stderr, /max iterations/i);

  const progressPath = path.join(cwd, "specs", "feat-loop-max-fail", "loop-progress.json");
  assert.ok(fs.existsSync(progressPath), "missing loop-progress.json on failure");
  const progress = JSON.parse(fs.readFileSync(progressPath, "utf8"));
  assert.equal(progress.maxIterations, 2);
  assert.equal(progress.completedIterations, 2);
  assert.equal(progress.result, "max-iterations-exceeded");
  assert.equal(progress.iterations.length, 2);

  const historyDir = path.join(cwd, "specs", "feat-loop-max-fail", "history");
  const historyFiles = fs.readdirSync(historyDir);
  assert.ok(historyFiles.some((f) => f.endsWith("-loop-iter-001.md")), "missing loop iter 1 history");
  assert.ok(historyFiles.some((f) => f.endsWith("-loop-iter-002.md")), "missing loop iter 2 history");
});

test("loop runs preflight gates before first implement iteration (stub npm + codex call-order log)", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-preflight"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const events = path.join(cwd, "call-order.log");
  const bin = path.join(cwd, "bin");
  const npm = path.join(bin, "npm");
  writeExe(
    npm,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "npm:$*" >> ${JSON.stringify(events)}
exit 0
`
  );
  const codex = path.join(bin, "codex");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "codex:$*" >> ${JSON.stringify(events)}
out=""
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    out="\${args[i+1]}"
  fi
done
if [[ -n "$out" ]]; then
  printf 'Verdict: APPROVED\\n' > "$out"
fi
`
  );

  const envFile = path.join(cwd, ".bt.env");
  writeFile(
    envFile,
    [
      `BT_GATE_LINT=${npm} run lint`,
      `BT_GATE_TYPECHECK=${npm} run typecheck`,
      `BT_GATE_TEST=${npm} test`,
      "",
    ].join("\n")
  );

  const res = runBt(["loop", "feat-loop-preflight", "--max-iterations", "1"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  assert.ok(fs.existsSync(events), "missing call-order.log");
  const lines = fs.readFileSync(events, "utf8").trim().split("\n").filter(Boolean);
  assert.ok(lines.length >= 2, "expected at least one gate and one codex event");
  assert.match(lines[0], /^npm:/, `first call should be preflight gate via npm, got: ${lines[0] || "<none>"}`);
  assert.ok(lines.some((line) => line.startsWith("codex:")), "expected codex invocation");
});

test("BT_TARGET_DIR: loop writes review/progress/history artifacts under target", () => {
  const caller = mkTmp();
  const target = mkTmp();

  const spec = runBt(["spec", "feat-loop-target"], {
    cwd: caller,
    env: { BT_TARGET_DIR: target },
  });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(caller, "bin");
  const codex = path.join(bin, "codex");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
out=""
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "-o" ]]; then
    out="\${args[i+1]}"
  fi
done
if [[ -n "$out" ]]; then
  printf 'Verdict: APPROVED\\n' > "$out"
fi
`
  );

  const res = runBt(["loop", "feat-loop-target"], {
    cwd: caller,
    env: { BT_TARGET_DIR: target, PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const targetFeatureDir = path.join(target, "specs", "feat-loop-target");
  assert.ok(fs.existsSync(path.join(targetFeatureDir, "REVIEW.md")), "target REVIEW.md missing");
  assert.ok(fs.existsSync(path.join(targetFeatureDir, "loop-progress.json")), "target loop-progress.json missing");
  assert.ok(fs.existsSync(path.join(targetFeatureDir, "history")), "target history/ missing");
  assert.ok(
    fs.readdirSync(path.join(targetFeatureDir, "history")).some((f) => f.endsWith("-loop-iter-001.md")),
    "target history should contain loop iteration artifact"
  );

  const callerFeatureDir = path.join(caller, "specs", "feat-loop-target");
  assert.ok(!fs.existsSync(path.join(callerFeatureDir, "REVIEW.md")), "caller REVIEW.md should not be created");
  assert.ok(!fs.existsSync(path.join(callerFeatureDir, "loop-progress.json")), "caller loop-progress.json should not be created");
});

test("command routing: each command --help exits 0", () => {
  const cmds = [
    "bootstrap",
    "spec",
    "research",
    "implement",
    "review",
    "fix",
    "compound",
    "design",
    "status",
    "gates",
    "reset",
    "pr",
    "ship",
  ];
  for (const c of cmds) {
    const res = runBt([c, "--help"]);
    assert.equal(res.code, 0, `${c} help failed: ${res.stderr}`);
  }
});

test("spec issue#: stubs gh via PATH and writes specs/issue-<n>/SPEC.md", () => {
  const cwd = mkTmp();
  writeFile(path.join(cwd, ".bt.env"), "BT_REPO=acme-co/biotonomy\n");

  const bin = path.join(cwd, "bin");
  const ghLog = path.join(cwd, "gh.args");
  const gh = path.join(bin, "gh");
  writeExe(
    gh,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$@" >> ${JSON.stringify(ghLog)}
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  # Emit JSON like gh would.
  cat <<'JSON'
{"title":"Core loop (Codex + gh integration)","url":"https://github.com/acme-co/biotonomy/issues/3","body":"Line 1\\n\\nLine 2 with   extra   spaces"}
JSON
  exit 0
fi
echo "unexpected gh invocation" >&2
exit 2
`
  );

  const res = runBt(["spec", "3"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stderr);

  const specPath = path.join(cwd, "specs", "issue-3", "SPEC.md");
  assert.ok(fs.existsSync(specPath), "SPEC.md missing");
  const spec = fs.readFileSync(specPath, "utf8");
  assert.match(spec, /issue:\s*3/);
  assert.match(spec, /repo:\s*acme-co\/biotonomy/);
  assert.match(spec, /# Problem/);
  assert.match(spec, /## Core loop \(Codex \+ gh integration\)/);
  assert.match(spec, /\*\*link:\*\* https:\/\/github\.com\/acme-co\/biotonomy\/issues\/3/);
  assert.match(spec, /Line 1 Line 2 with extra spaces/); // whitespace collapsed
  assert.match(spec, /## Footer/);
  assert.match(spec, /`gh issue view 3 -R acme-co\/biotonomy --json title,body,url`/);

  const args = fs.readFileSync(ghLog, "utf8");
  assert.match(args, /^issue\nview\n3\n-R\nacme-co\/biotonomy\n--json\ntitle,body,url\n/m);
});

test("repo resolution: uses git remote origin when available (no BT_REPO)", () => {
  const cwd = mkTmp();
  const r = (cmd) =>
    spawnSync("bash", ["-lc", cmd], { cwd, encoding: "utf8" });

  let res = r("git init -q");
  assert.equal(res.status, 0, res.stderr);
  res = r("git remote add origin https://github.com/o-rg/r-epo.git");
  assert.equal(res.status, 0, res.stderr);

  const bin = path.join(cwd, "bin");
  const gh = path.join(bin, "gh");
  writeExe(
    gh,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  cat <<'JSON'
{"title":"T","url":"https://github.com/o-rg/r-epo/issues/5","body":"B"}
JSON
  exit 0
fi
exit 2
`
  );

  const btRes = runBt(["spec", "5"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(btRes.code, 0, btRes.stderr);
  const specPath = path.join(cwd, "specs", "issue-5", "SPEC.md");
  const spec = fs.readFileSync(specPath, "utf8");
  assert.match(spec, /repo:\s*o-rg\/r-epo/);
});

test("notify hook is invoked when BT_NOTIFY_HOOK is set", () => {
  const cwd = mkTmp();
  const hook = path.join(cwd, "hook.sh");
  const out = path.join(cwd, "hook.out");
  writeFile(
    hook,
    `#!/usr/bin/env bash\nset -euo pipefail\necho "$*" >> ${JSON.stringify(out)}\n`
  );
  fs.chmodSync(hook, 0o755);

  writeFile(path.join(cwd, ".bt.env"), `BT_NOTIFY_HOOK=${hook}\n`);

  const res = runBt(["bootstrap"], { cwd });
  assert.equal(res.code, 0);
  assert.ok(fs.existsSync(out), "hook output missing");
  const content = fs.readFileSync(out, "utf8");
  assert.match(content, /bt bootstrap complete/i);
});

test("pr (dry-run): prints expanded gh argv and resolved base branch (stubs git/npm)", () => {
  const cwd = mkTmp();

  const bin = path.join(cwd, "bin");
  const npmLog = path.join(cwd, "npm.args");
  const gitLog = path.join(cwd, "git.args");
  const npm = path.join(bin, "npm");
  const git = path.join(bin, "git");

  writeExe(
    npm,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$@" >> ${JSON.stringify(npmLog)}
exit 0
`
  );

  writeExe(
    git,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$@" >> ${JSON.stringify(gitLog)}
case "$1" in
  show-ref)
    # Pretend branch does not exist so bt creates it.
    exit 1
    ;;
  symbolic-ref)
    # bt expects refs/remotes/<remote>/<branch>.
    printf '%s\\n' "refs/remotes/origin/main"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
`
  );

  const res = runBt(["pr", "feat-pr"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stderr);

  // Key: argv expansion should be real (no literal ${...}), and base should resolve to "main".
  assert.match(res.stdout + res.stderr, /\[dry-run\] gh pr create --head feat\/feat-pr --base main/);
  assert.doesNotMatch(res.stdout + res.stderr, /\$\{pr_args/);
  assert.doesNotMatch(res.stdout + res.stderr, /\$\{ref##/);
});

test("pr (--run): calls gh with correct argv (no empty args) and resolved base (stubs git/npm/gh)", () => {
  const cwd = mkTmp();

  const bin = path.join(cwd, "bin");
  const ghLog = path.join(cwd, "gh.args");
  const npm = path.join(bin, "npm");
  const git = path.join(bin, "git");
  const gh = path.join(bin, "gh");

  writeExe(
    npm,
    `#!/usr/bin/env bash
set -euo pipefail
exit 0
`
  );

  writeExe(
    git,
    `#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  show-ref)
    exit 1
    ;;
  symbolic-ref)
    printf '%s\\n' "refs/remotes/origin/main"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
`
  );

  writeExe(
    gh,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$@" >> ${JSON.stringify(ghLog)}
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  printf '%s\\n' "https://github.com/acme-co/biotonomy/pull/123"
fi
exit 0
`
  );

  const res = runBt(["pr", "feat-pr2", "--run"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stderr);

  const args = fs.readFileSync(ghLog, "utf8");
  // Ensure gh gets command+subcommand and no empty-string argument (which would write a blank line).
  assert.match(args, /^pr\ncreate\n--head\nfeat\/feat-pr2\n--base\nmain\n--title\nfeat: feat-pr2\n--body\nFeature: feat-pr2\n/m);
  // After create, bt posts a deterministic artifacts comment using --body-file (argv-safe for multiline bodies).
  assert.match(args, /\npr\ncomment\nhttps:\/\/github\.com\/acme-co\/biotonomy\/pull\/123\n--body-file\n[^\n]+\n/);
  assert.doesNotMatch(args, /(^|\n)\n/);
});

test("pr: --base/--remote missing value exits 2 with validation error", () => {
  const cases = [
    { args: ["pr", "feat-missing-base", "--base"], flag: "--base" },
    { args: ["pr", "feat-missing-remote", "--remote"], flag: "--remote" },
  ];

  for (const c of cases) {
    const res = runBt(c.args);
    assert.equal(res.code, 2, `${c.flag} missing value should exit 2`);
    assert.match(res.stderr, new RegExp(`${c.flag} requires a value`));
    assert.doesNotMatch(res.stderr, /shift count out of range/i);
  }
});

test("gates behavior: writes global or feature gates.json with detailed JSON", () => {
  const cwd = mkTmp();
  writeFile(
    path.join(cwd, ".bt.env"),
    [
      "BT_SPECS_DIR=specs",
      "BT_STATE_DIR=.bt",
      "BT_GATE_TEST=true",
      "BT_GATE_LINT=true",
      "BT_GATE_TYPECHECK=true",
      "",
    ].join("\n")
  );

  // 1. Global gates (no feature)
  const res = runBt(["gates"], { cwd });
  assert.equal(res.code, 0, `global gates failed: ${res.stderr}`);

  const gatesJson = path.join(cwd, ".bt", "state", "gates.json");
  assert.ok(fs.existsSync(gatesJson), "global gates.json missing");
  const data = JSON.parse(fs.readFileSync(gatesJson, "utf8"));
  assert.ok(data.ts);
  assert.equal(data.results.test.status, 0);
  assert.equal(data.results.lint.status, 0);

  // 2. Feature-specific gates
  const spec = runBt(["spec", "feat-g"], { cwd });
  assert.equal(spec.code, 0);

  const res2 = runBt(["gates", "feat-g"], { cwd });
  assert.equal(res2.code, 0, `feature gates failed: ${res2.stderr}`);

  const featGatesJson = path.join(cwd, "specs", "feat-g", "gates.json");
  assert.ok(fs.existsSync(featGatesJson), "feature gates.json missing");
  const data2 = JSON.parse(fs.readFileSync(featGatesJson, "utf8"));
  assert.equal(data2.results.test.status, 0);
  assert.equal(data2.results.lint.status, 0);
});

if (process.exitCode) process.exit(process.exitCode);

test("pr: fails when required files are unstaged", () => {
  const cwd = mkTmp();
  runBt(["bootstrap"], { cwd });
  runBt(["spec", "feat-unstaged"], { cwd });

  const git = spawnSync("bash", ["-lc", "git init -q"], { cwd, encoding: "utf8" });
  assert.equal(git.status, 0, git.stderr);

  const npmLog = path.join(cwd, "npm.args");
  const bin = path.join(cwd, "bin");
  fs.mkdirSync(bin, { recursive: true });
  writeExe(
    path.join(bin, "npm"),
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$@" >> ${JSON.stringify(npmLog)}
exit 99
`
  );

  // Create an implementation file but don't add it.
  const libDir = path.join(cwd, "lib");
  fs.mkdirSync(libDir, { recursive: true });
  fs.writeFileSync(path.join(libDir, "index.mjs"), "export const x = 1;");

  const res = runBt(["pr", "feat-unstaged", "--dry-run"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });

  assert.equal(res.code, 1, "pr should exit 1 on unstaged files");
  assert.ok(res.stderr.includes("Abort: ship requires all feature files to be staged"), "missing abort message");
  assert.ok(res.stderr.includes("lib/index.mjs"), "should list the unstaged file");
  assert.ok(!fs.existsSync(npmLog), "npm should not run before unstaged-file validation");
});

test("P2: Artifacts section is included in PR body", () => {
  const cwd = mkTmp();
  runBt(["bootstrap"], { cwd });
  runBt(["spec", "feat-artifacts"], { cwd });

  const bin = path.join(cwd, "bin");
  fs.mkdirSync(bin, { recursive: true });
  writeExe(
    path.join(bin, "git"),
    `#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  show-ref) exit 1 ;;
  symbolic-ref) printf '%s\\n' "refs/remotes/origin/main"; exit 0 ;;
  *) exit 0 ;;
esac
`
  );
  writeExe(
    path.join(bin, "npm"),
    `#!/usr/bin/env bash
set -euo pipefail
exit 77
`
  );

  // Fake a review and an artifact
  writeFile(path.join(cwd, "specs", "feat-artifacts", "REVIEW.md"), "Verdict: APPROVED");
  writeFile(path.join(cwd, "specs", "feat-artifacts", ".artifacts", "summary.txt"), "Done.");

  const res = runBt(["pr", "feat-artifacts", "--dry-run", "--no-commit"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });

  assert.equal(res.code, 0, res.stderr);
  assert.ok(res.stdout.includes("### `specs/feat-artifacts/SPEC.md`"), "SPEC missing from artifacts");
  assert.ok(res.stdout.includes("### `specs/feat-artifacts/REVIEW.md`"), "REVIEW missing from artifacts");
  assert.ok(res.stdout.includes("### `specs/feat-artifacts/.artifacts/summary.txt`"), "Artifact missing");
});

test("implement fails loud when codex fails and skips gates", () => {
    const cwd = mkTmp();
    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    const npm = path.join(bin, "npm");
    const callLog = path.join(cwd, "calls.log");

    writeExe(codex, `#!/usr/bin/env bash
echo "codex called" >> ${JSON.stringify(callLog)}
exit 1
`);
    writeExe(npm, `#!/usr/bin/env bash
echo "npm called" >> ${JSON.stringify(callLog)}
exit 0
`);

    writeFile(path.join(cwd, ".bt.env"), `BT_GATE_TEST=${npm} test\n`);
    runBt(["spec", "feat-f1"], { cwd });

    const res = runBt(["implement", "feat-f1"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` }
    });

    assert.equal(res.code, 1, "implement should exit non-zero when codex fails");
    const log = fs.readFileSync(callLog, "utf8");
    assert.match(log, /codex called/);
    assert.doesNotMatch(log, /npm called/, "gates should not run after codex failure");
});

test("fix fails loud when codex fails and skips gates", () => {
    const cwd = mkTmp();
    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    const npm = path.join(bin, "npm");
    const callLog = path.join(cwd, "calls.log");

    writeExe(codex, `#!/usr/bin/env bash
echo "codex called" >> ${JSON.stringify(callLog)}
exit 1
`);
    writeExe(npm, `#!/usr/bin/env bash
echo "npm called" >> ${JSON.stringify(callLog)}
exit 0
`);

    writeFile(path.join(cwd, ".bt.env"), `BT_GATE_TEST=${npm} test\n`);
    runBt(["spec", "feat-f2"], { cwd });

    const res = runBt(["fix", "feat-f2"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` }
    });

    assert.equal(res.code, 1, "fix should exit non-zero when codex fails");
    const log = fs.readFileSync(callLog, "utf8");
    assert.match(log, /codex called/);
    assert.doesNotMatch(log, /npm called/, "gates should not run after codex failure");
});

if (process.exitCode) process.exit(process.exitCode);
