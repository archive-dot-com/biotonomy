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
    env: { ...process.env, BT_GATE_TEST: "true", ...(env || {}) },
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

test("launcher works when invoked via symlinked node_modules/.bin/bt path", () => {
  const cwd = mkTmp();
  const binDir = path.join(cwd, "node_modules", ".bin");
  const shim = path.join(binDir, "bt");

  fs.mkdirSync(binDir, { recursive: true });
  fs.symlinkSync(path.join(repoRoot, "bt"), shim);

  const res = spawnSync("bash", [shim, "--help"], {
    cwd,
    env: { ...process.env },
    encoding: "utf8",
  });

  assert.equal(res.status ?? 1, 0, (res.stdout ?? "") + (res.stderr ?? ""));
  assert.match((res.stdout ?? "") + (res.stderr ?? ""), /biotonomy \(bt\)/);
});

test("unknown command exits 2", () => {
  const res = runBt(["nope"]);
  assert.equal(res.code, 2);
  assert.match(res.stderr, /unknown command/i);
});

test("package bin mapping includes npx biotonomy command", () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(repoRoot, "package.json"), "utf8"));
  assert.equal(pkg.bin?.bt, "bt");
  assert.equal(pkg.bin?.biotonomy, "bt");
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

test("bootstrap fails loud before mkdir when critical scaffold path is a file", () => {
  const cwd = mkTmp();
  writeFile(path.join(cwd, ".bt"), "not a dir");

  const res = runBt(["bootstrap"], { cwd });
  assert.equal(res.code, 1, res.stdout + res.stderr);
  assert.match(res.stderr, /critical scaffold path exists as a file: .*\/\.bt/i);

  assert.ok(!fs.existsSync(path.join(cwd, "specs")), "specs/ should not be created");
  assert.ok(!fs.existsSync(path.join(cwd, "hooks")), "hooks/ should not be created");
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

test("bt_realpath fallback normalizes relative paths when realpath/python3 are unavailable", () => {
  const cwd = mkTmp();
  const nested = path.join(cwd, "a", "b");
  fs.mkdirSync(path.join(cwd, "a", "target"), { recursive: true });
  fs.mkdirSync(nested, { recursive: true });

  const fakeBin = path.join(cwd, "fake-bin");
  fs.mkdirSync(fakeBin, { recursive: true });
  fs.symlinkSync("/bin/bash", path.join(fakeBin, "bash"));

  const res = spawnSync(
    "/bin/bash",
    [
      "-c",
      `source "${path.join(repoRoot, "lib", "path.sh")}"; cd "${nested}"; bt_realpath "../target/./artifact.txt"`,
    ],
    {
      env: { ...process.env, PATH: fakeBin },
      encoding: "utf8",
    }
  );

  assert.equal(res.status, 0, res.stderr || "bt_realpath invocation failed");
  assert.equal(res.stdout.trim(), path.join(cwd, "a", "target", "artifact.txt"));
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

test("status gate parsing handles compact JSON without whitespace", () => {
  const cwd = mkTmp();
  writeFile(
    path.join(cwd, ".bt", "state", "gates.json"),
    '{"ts":"2026-02-16T02:00:00Z","results":{"lint":{"cmd":"npm run lint","status":0},"test":{"cmd":"npm test","status":1}}}'
  );

  const res = runBt(["status"], { cwd });
  assert.equal(res.code, 0, res.stderr);
  assert.match(res.stdout, /global:\s*\[gates:fail 2026-02-16T02:00:00Z \(test\)\]/);
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

    runBt(["spec", "feat-x"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-x");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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

test("plan-review writes PLAN_REVIEW.md with plan verdict (stubs codex via PATH)", () => {
  const cwd = mkTmp();

  const spec = runBt(["spec", "feat-plan-v"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
# In runBt, BT_PROJECT_ROOT is set to cwd
out="specs/\${BT_FEATURE}/PLAN_REVIEW.md"
mkdir -p "\$(dirname "\$out")"
printf '%s\\n' "# Plan Review from stub" "Verdict: APPROVED_PLAN" > "\$out"
exit 0
`
  );

  const res = runBt(["plan-review", "feat-plan-v"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const out = path.join(cwd, "specs", "feat-plan-v", "PLAN_REVIEW.md");
  assert.ok(fs.existsSync(out), `PLAN_REVIEW.md missing: ${res.stdout} ${res.stderr}`);
});

test("implement hard-fails without approved PLAN_REVIEW verdict", () => {
    const cwd = mkTmp();

    runBt(["spec", "feat-plan-gate-impl"], { cwd });
    // NO PLAN_REVIEW.md yet

    const res = runBt(["implement", "feat-plan-gate-impl"], { cwd });
    assert.equal(res.code, 1, res.stdout + res.stderr);
    assert.match(res.stderr, /PLAN_REVIEW\.md/i);

    const featDir = path.join(cwd, "specs", "feat-plan-gate-impl");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    const out = path.join(featDir, "REVIEW.md");
    writeExe(codex, `#!/usr/bin/env bash\nexit 0\n`);

    const res2 = runBt(["implement", "feat-plan-gate-impl"], {
      cwd,
      env: { PATH: `${bin}:${process.env.PATH}` }
    });
    assert.equal(res2.code, 0, res2.stdout + res2.stderr);
});

test("loop (stubbed): runs implement -> review and finishes on APPROVED", () => {
    const cwd = mkTmp();

    runBt(["spec", "feat-loop"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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

test("loop accepts Verdict: APPROVE as successful convergence", () => {
    const cwd = mkTmp();

    runBt(["spec", "feat-loop-approve"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop-approve");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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
  printf 'Verdict: APPROVE\\n' > "$out"
fi
exit 0
`
  );

  const res = runBt(["loop", "feat-loop-approve", "--max-iterations", "1"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);
  assert.match(res.stdout + res.stderr, /Loop successful/i);

  const progressPath = path.join(cwd, "specs", "feat-loop-approve", "loop-progress.json");
  const progress = JSON.parse(fs.readFileSync(progressPath, "utf8"));
  assert.equal(progress.result, "success");
  assert.equal(progress.iterations[0].verdict, "APPROVE");
});

test("loop validates --max-iterations as a positive integer", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-invalid-max"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const res = runBt(["loop", "feat-loop-invalid-max", "--max-iterations", "nope"], { cwd });
  assert.equal(res.code, 2, res.stdout + res.stderr);
  assert.match(res.stderr, /--max-iterations.*positive integer/i);
});

test("loop persists per-iteration history and deterministic progress artifact", () => {
    const cwd = mkTmp();

    runBt(["spec", "feat-loop-history"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop-history");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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

    runBt(["spec", "feat-loop-order"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop-order");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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

test("loop fails loud when implement fails and does not run review", () => {
    const cwd = mkTmp();

    runBt(["spec", "feat-loop-impl-fail"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop-impl-fail");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

    const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  const events = path.join(cwd, "loop-impl-fail.events");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
logf="\${BT_CODEX_LOG_FILE:-}"
kind="$(basename "$logf" .log | sed 's/^codex-//')"
printf '%s\\n' "$kind" >> ${JSON.stringify(events)}

if [[ "$kind" == "implement" ]]; then
  exit 9
fi

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
exit 0
`
  );

  const res = runBt(["loop", "feat-loop-impl-fail", "--max-iterations", "2"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });

  assert.equal(res.code, 1, res.stdout + res.stderr);
  assert.match(res.stderr, /implement failed on iter 1/i);

  const calls = fs.readFileSync(events, "utf8").trim().split("\n").filter(Boolean);
  assert.deepEqual(calls, ["implement"], `unexpected calls after implement failure: ${calls.join(" -> ")}`);
});

test("loop hard-fails without approved PLAN_REVIEW verdict before implement/review", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-plan-gate-loop"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const events = path.join(cwd, "plan-gate-loop.events");
  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  const npm = path.join(bin, "npm");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "codex:$*" >> ${JSON.stringify(events)}
exit 0
`
  );
  writeExe(
    npm,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "npm:$*" >> ${JSON.stringify(events)}
exit 0
`
  );

  const res = runBt(["loop", "feat-plan-gate-loop"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 1, res.stdout + res.stderr);
  assert.match(res.stderr, /PLAN_REVIEW\.md/i);
  assert.match(res.stderr, /bt plan-review feat-plan-gate-loop/i);
  assert.ok(!fs.existsSync(events), "loop should fail before npm/codex are invoked");
});

test("loop exits non-zero on max iterations and persists failure progress", () => {
    const cwd = mkTmp();

    runBt(["spec", "feat-loop-max-fail"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop-max-fail");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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

    runBt(["spec", "feat-loop-preflight"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-loop-preflight");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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

  const targetFeatureDir = path.join(target, "specs", "feat-loop-target");
  writeFile(path.join(targetFeatureDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n\nProceed.\n");

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
    "plan-review",
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

test("spec issue#: README acceptance bullets generate README-specific stories (no canned internal stories)", () => {
  const cwd = mkTmp();
  writeFile(path.join(cwd, ".bt.env"), "BT_REPO=outside-org/docs-cli\n");

  const bin = path.join(cwd, "bin");
  const gh = path.join(bin, "gh");
  writeExe(
    gh,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  cat <<'JSON'
{"title":"README refresh for new contributors","url":"https://github.com/outside-org/docs-cli/issues/27","body":"Update docs for external users.\\n\\n## Acceptance Criteria\\n- [ ] README includes prerequisites for macOS and Linux\\n- [ ] README quickstart includes bt spec 27 workflow\\n- [ ] README troubleshooting explains gh auth failures"}
JSON
  exit 0
fi
exit 2
`
  );

  const res = runBt(["spec", "27"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stderr);

  const specPath = path.join(cwd, "specs", "issue-27", "SPEC.md");
  const spec = fs.readFileSync(specPath, "utf8");
  assert.match(spec, /## \[ID:S1\].*README refresh for new contributors/);
  assert.match(spec, /README includes prerequisites for macOS and Linux/);
  assert.match(spec, /README troubleshooting explains gh auth failures/);
  assert.doesNotMatch(spec, /Confirm repo resolution and env fallback/);
  assert.doesNotMatch(spec, /Fetch issue details via gh/);
});

test("spec: existing feature SPEC is not overwritten without --force", () => {
  const cwd = mkTmp();
  const first = runBt(["spec", "feat-force-default"], { cwd });
  assert.equal(first.code, 0, first.stderr);

  const specPath = path.join(cwd, "specs", "feat-force-default", "SPEC.md");
  writeFile(specPath, "# custom spec\n");

  const second = runBt(["spec", "feat-force-default"], { cwd });
  assert.equal(second.code, 0, second.stderr);
  assert.match(second.stdout + second.stderr, /SPEC already exists/i);
  assert.equal(fs.readFileSync(specPath, "utf8"), "# custom spec\n");
});

test("spec: existing feature SPEC is overwritten with --force", () => {
  const cwd = mkTmp();
  const first = runBt(["spec", "feat-force-overwrite"], { cwd });
  assert.equal(first.code, 0, first.stderr);

  const specPath = path.join(cwd, "specs", "feat-force-overwrite", "SPEC.md");
  writeFile(specPath, "# custom spec\n");

  const second = runBt(["spec", "--force", "feat-force-overwrite"], { cwd });
  assert.equal(second.code, 0, second.stderr);
  assert.doesNotMatch(fs.readFileSync(specPath, "utf8"), /^# custom spec$/m);
  assert.match(fs.readFileSync(specPath, "utf8"), /^# Stories$/m);
});

test("spec: issue-backed SPEC can be regenerated with --force", () => {
  const cwd = mkTmp();
  writeFile(path.join(cwd, ".bt.env"), "BT_REPO=acme-co/biotonomy\n");

  const bin = path.join(cwd, "bin");
  const counter = path.join(cwd, "gh.counter");
  const gh = path.join(bin, "gh");
  writeExe(
    gh,
    `#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f ${JSON.stringify(counter)} ]]; then
  count="$(cat ${JSON.stringify(counter)})"
fi
count=$((count + 1))
printf '%s' "$count" > ${JSON.stringify(counter)}
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  if [[ "$count" -eq 1 ]]; then
    cat <<'JSON'
{"title":"First title","url":"https://github.com/acme-co/biotonomy/issues/7","body":"First body"}
JSON
  else
    cat <<'JSON'
{"title":"Second title","url":"https://github.com/acme-co/biotonomy/issues/7","body":"Second body"}
JSON
  fi
  exit 0
fi
exit 2
`
  );

  const first = runBt(["spec", "7"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(first.code, 0, first.stderr);
  const specPath = path.join(cwd, "specs", "issue-7", "SPEC.md");
  assert.match(fs.readFileSync(specPath, "utf8"), /## First title/);

  const second = runBt(["spec", "--force", "7"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(second.code, 0, second.stderr);
  const content = fs.readFileSync(specPath, "utf8");
  assert.match(content, /## Second title/);
  assert.doesNotMatch(content, /## First title/);
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

test("gates JSON stays valid when gate command has quotes and backslashes", () => {
  const cwd = mkTmp();
  const cmdWithEscapes = `printf "path \\\\tmp\\\\x and quote \\"ok\\"" >/dev/null`;
  writeFile(
    path.join(cwd, ".bt.env"),
    [
      "BT_SPECS_DIR=specs",
      "BT_STATE_DIR=.bt",
      "BT_GATE_LINT=true",
      "BT_GATE_TYPECHECK=true",
      `BT_GATE_TEST=${cmdWithEscapes}`,
      "",
    ].join("\n")
  );

  const res = runBt(["gates"], { cwd });
  assert.equal(res.code, 0, res.stderr);

  const gatesJson = path.join(cwd, ".bt", "state", "gates.json");
  const raw = fs.readFileSync(gatesJson, "utf8");
  const data = JSON.parse(raw);
  assert.equal(data.results.test.status, 0);
  assert.equal(data.results.test.cmd, cmdWithEscapes);
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
    writeFile(path.join(cwd, "specs", "feat-f1", "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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
    runBt(["spec", "feat-f1"], { cwd });

    const res = runBt(["fix", "feat-f1"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` }
    });

    assert.equal(res.code, 1, "fix should exit non-zero when codex fails");
    const log = fs.readFileSync(callLog, "utf8");
    assert.match(log, /codex called/);
    assert.doesNotMatch(log, /npm called/, "gates should not run after codex failure");
});

test("review fails loud when codex fails", () => {
  const cwd = mkTmp();
  runBt(["bootstrap"], { cwd });
  runBt(["spec", "feat-review-fail"], { cwd });

  const bin = path.join(cwd, "bin");
  fs.mkdirSync(bin, { recursive: true });
  const codex = path.join(bin, "codex");
  fs.writeFileSync(codex, `#!/usr/bin/env bash
exit 1
`);
  fs.chmodSync(codex, 0o755);

  const res = runBt(["review", "feat-review-fail"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });

  assert.equal(res.code, 1, "review should exit 1 on codex failure");
  assert.ok(res.stderr.includes("codex failed (review), stopping"), "should fail loud");
});

test("ship (alias of pr) also fails loud when required files are unstaged", () => {
  const cwd = mkTmp();
  runBt(["bootstrap"], { cwd });
  runBt(["spec", "feat-unstaged-ship"], { cwd });

  const git = spawnSync("bash", ["-lc", "git init -q"], { cwd, encoding: "utf8" });
  assert.equal(git.status, 0, git.stderr);

  // Create an implementation file but don't add it.
  const libDir = path.join(cwd, "lib");
  fs.mkdirSync(libDir, { recursive: true });
  fs.writeFileSync(path.join(libDir, "index.mjs"), "export const x = 1;");

  const res = runBt(["ship", "feat-unstaged-ship", "--dry-run"], { cwd });

  assert.equal(res.code, 1, "ship should exit 1 on unstaged files");
  assert.ok(res.stderr.includes("Abort: ship requires all feature files to be staged"), "missing abort message");
  assert.ok(res.stderr.includes("lib/index.mjs"), "should list the unstaged file");
});

test("ship/pr fail-loud: should NOT attempt git add automatically", () => {
  const cwd = mkTmp();
  runBt(["bootstrap"], { cwd });
  const git = spawnSync("bash", ["-lc", "git init -q"], { cwd, encoding: "utf8" });
  assert.equal(git.status, 0);
  
  const testFile = path.join(cwd, "tests", "fail-loud-test.mjs");
  fs.mkdirSync(path.dirname(testFile), { recursive: true });
  fs.writeFileSync(testFile, "test");
  
  // We expect it to FAIL because files are unstaged, and it should NOT add them.
  // Note: runBt uses -lc bash which might have different env, ensure git works.
  const res = runBt(["ship", "fail-loud-feat", "--run"], { cwd });
  assert.equal(res.code, 1, "Should exit with error code 1");
  assert.match(res.stderr, /Found unstaged files/, "Should report unstaged files");
  
  // Verify it didn't add them (should still be UNTRACKED/UNSTAGED)
  const statusRes = spawnSync("git", ["status", "--porcelain", "tests/fail-loud-test.mjs"], { cwd, encoding: "utf8" });
  assert.match(statusRes.stdout, /^\?\? /, "File should remain untracked (??)");
});

test("issue #10: loop gate sequencing (implement->review; NEEDS_CHANGES->fix->implement->review) relying on internal gates", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-seq"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);
  writeFile(path.join(cwd, "specs", "feat-seq", "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

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
  const reviewCountFile = path.join(cwd, "review.count");
  writeExe(
    codex,
    `#!/usr/bin/env bash
set -euo pipefail
logf="\${BT_CODEX_LOG_FILE:-}"
kind="$(basename "$logf" .log | sed 's/^codex-//')"
printf '%s\\n' "codex:$kind" >> ${JSON.stringify(events)}

if [[ "$kind" == "review" ]]; then
  out=""
  args=("$@")
  for ((i=0; i<\${#args[@]}; i++)); do
    if [[ "\${args[i]}" == "-o" ]]; then
      out="\${args[i+1]}"
    fi
  done
  if [[ -n "$out" ]]; then
    c=0
    [[ -f ${JSON.stringify(reviewCountFile)} ]] && c=$(cat ${JSON.stringify(reviewCountFile)})
    c=$((c+1))
    echo "$c" > ${JSON.stringify(reviewCountFile)}
    if [[ "$c" -eq 1 ]]; then
      printf 'Verdict: NEEDS_CHANGES\\n' > "$out"
    else
      printf 'Verdict: APPROVED\\n' > "$out"
    fi
  fi
fi
`
  );

  const envFile = path.join(cwd, ".bt.env");
  writeFile(
    envFile,
    [
      `BT_GATE_TEST=${npm} test`,
      "",
    ].join("\n")
  );

  const res = runBt(["loop", "feat-seq", "--max-iterations", "3"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const lines = fs.readFileSync(events, "utf8").trim().split("\n").filter(Boolean);
  
  const expected = [
    "npm:test",       // preflight
    "codex:implement",
    "npm:test",       // internal to bt implement
    "codex:review",
    "npm:test",       // convergence check in loop after review
    "codex:fix",
    "npm:test",       // internal to bt fix
    "codex:implement",
    "npm:test",       // internal to bt implement
    "codex:review",
    "npm:test"        // final convergence check
  ];
  
  assert.deepEqual(lines, expected, `Incomplete or wrong sequence: ${lines.join(" -> ")}`);
});

test("issue #10: loop-progress.json persists per-iteration stage results", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-stage-results"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);
  writeFile(path.join(cwd, "specs", "feat-loop-stage-results", "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
  const reviewCount = path.join(cwd, "review-stage.count");
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
  printf '%s\n' "$c" > ${JSON.stringify(reviewCount)}
  if [[ "$c" -eq 1 ]]; then
    printf 'Verdict: NEEDS_CHANGES\n' > "$out"
  else
    printf 'Verdict: APPROVED\n' > "$out"
  fi
fi
exit 0
`
  );

  const res = runBt(["loop", "feat-loop-stage-results", "--max-iterations", "3"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const progressPath = path.join(cwd, "specs", "feat-loop-stage-results", "loop-progress.json");
  const progress = JSON.parse(fs.readFileSync(progressPath, "utf8"));

  assert.equal(progress.iterations.length, 2);
  assert.equal(progress.iterations[0].implementStatus, "PASS");
  assert.equal(progress.iterations[0].reviewStatus, "PASS");
  assert.equal(progress.iterations[0].fixStatus, "PASS");
  assert.equal(progress.iterations[1].implementStatus, "PASS");
  assert.equal(progress.iterations[1].reviewStatus, "PASS");
  assert.equal(progress.iterations[1].fixStatus, "SKIP");
});

test("issue #32: loop resumes from next iteration when prior progress is implement-failed", () => {
  const cwd = mkTmp();
  const spec = runBt(["spec", "feat-loop-resume-32"], { cwd });
  assert.equal(spec.code, 0, spec.stderr);

  const featDir = path.join(cwd, "specs", "feat-loop-resume-32");
  writeFile(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

  const historyDir = path.join(featDir, "history");
  fs.mkdirSync(historyDir, { recursive: true });
  writeFile(path.join(historyDir, "2026-02-16T000000+0000-loop-iter-001.md"), "Verdict: NEEDS_CHANGES\n");

  const progressPath = path.join(featDir, "loop-progress.json");
  writeFile(
    progressPath,
    JSON.stringify(
      {
        feature: "feat-loop-resume-32",
        maxIterations: 3,
        completedIterations: 1,
        result: "implement-failed",
        iterations: [
          {
            iteration: 1,
            implementStatus: "FAIL",
            reviewStatus: "SKIP",
            fixStatus: "SKIP",
            verdict: "",
            gates: "FAIL",
            historyFile: "",
          },
        ],
      },
      null,
      2
    )
  );

  const events = path.join(cwd, "resume-32.events");
  const bin = path.join(cwd, "bin");
  const codex = path.join(bin, "codex");
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
  printf 'Verdict: APPROVED\\n' > "$out"
fi
`
  );

  const res = runBt(["loop", "feat-loop-resume-32", "--max-iterations", "3"], {
    cwd,
    env: { PATH: `${bin}:${process.env.PATH}` },
  });
  assert.equal(res.code, 0, res.stdout + res.stderr);

  const progress = JSON.parse(fs.readFileSync(progressPath, "utf8"));
  assert.equal(progress.completedIterations, 2);
  assert.equal(progress.result, "success");
  assert.equal(progress.iterations.length, 2);
  assert.equal(progress.iterations[0].iteration, 1);
  assert.equal(progress.iterations[0].implementStatus, "FAIL");
  assert.equal(progress.iterations[1].iteration, 2);
  assert.equal(progress.iterations[1].verdict, "APPROVED");

  const historyFiles = fs.readdirSync(historyDir);
  assert.ok(historyFiles.some((f) => f.endsWith("-loop-iter-001.md")), "missing existing loop iter 1 history");
  assert.ok(historyFiles.some((f) => f.endsWith("-loop-iter-002.md")), "missing resumed loop iter 2 history");

  const callOrder = fs.readFileSync(events, "utf8").trim().split("\n").filter(Boolean);
  assert.deepEqual(callOrder, ["implement", "review"], `unexpected calls after resume: ${callOrder.join(" -> ")}`);
});

test("loop (non-auto): implement/fix return non-zero when gates fail", () => {
    const cwd = mkTmp();
    runBt(["spec", "feat-loop-gate-fail"], { cwd });
    writeFile(path.join(cwd, "specs", "feat-loop-gate-fail", "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    writeExe(codex, `#!/usr/bin/env bash\nexit 0\n`);

    const npm = path.join(bin, "npm");
    writeExe(npm, `#!/usr/bin/env bash\nexit 1\n`);

    writeFile(path.join(cwd, ".bt.env"), `BT_GATE_TEST=${npm} test\n`);

    const res = runBt(["loop", "feat-loop-gate-fail", "--max-iterations", "1"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}`, BT_GATE_TEST: "true", BT_GATE_LINT: "true", BT_GATE_TYPECHECK: "true" }
    });

    assert.equal(res.code, 1, "loop should exit 1 when preflight gates fail");
    assert.match(res.stderr, /preflight gates failed/i);
});

test("issue #31: audit umbrella issue template exists", () => {
  const templatePath = path.join(repoRoot, ".github", "ISSUE_TEMPLATE", "audit-umbrella.md");
  assert.ok(fs.existsSync(templatePath), `missing template: ${templatePath}`);
});

test("issue #31: audit umbrella template enforces receipts and unresolved sections", () => {
  const templatePath = path.join(repoRoot, ".github", "ISSUE_TEMPLATE", "audit-umbrella.md");
  const content = fs.readFileSync(templatePath, "utf8");

  assert.match(content, /^name:\s*Audit Umbrella/m);
  assert.match(content, /^about:\s*Umbrella issue for claim-by-claim audit closure/m);
  assert.match(content, /^##\s+Required Closure Checklist/m);
  assert.match(content, /^-\s+\[ \]\s+Claim-by-claim receipts table completed/m);
  assert.match(content, /^-\s+\[ \]\s+Unresolved claims list completed \(or explicitly none\)/m);
  assert.match(content, /^##\s+Claim-by-Claim Receipts/m);
  assert.match(content, /^\|\s*Claim ID\s*\|\s*Receipt Link\(s\)\s*\|\s*Evidence Summary\s*\|/m);
  assert.match(content, /^##\s+Unresolved Claims/m);
  assert.match(content, /^-\s+\[ \]\s+None$/m);
});

if (process.exitCode) process.exit(process.exitCode);
