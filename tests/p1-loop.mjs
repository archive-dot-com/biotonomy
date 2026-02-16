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
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-test-p1-"));
}

function writeExe(p, s) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, s);
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

test("P1: loop driver sequencing logic check", () => {
    const cwd = mkTmp();
    runBt(["bootstrap"], { cwd });
    runBt(["spec", "feat-p1"], { cwd });
    fs.writeFileSync(path.join(cwd, "specs", "feat-p1", "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

    const bin = path.join(cwd, "bin");
    const codex = path.join(bin, "codex");
    const callsLog = path.join(cwd, "calls.log");

    // Stub codex to behave differently based on iteration
    writeExe(codex, `#!/usr/bin/env bash
# Kind is extracted from log file name if set
logf="\${BT_CODEX_LOG_FILE:-}"
kind="unknown"
if [[ -n "$logf" ]]; then
  kind="$(basename "$logf" .log | sed 's/^codex-//')"
fi
echo "$kind" >> ${callsLog}

if [[ "$kind" == "review" ]]; then
  # Grab the output path from args
  out=""
  args=("$@")
  for ((i=0; i<\${#args[@]}; i++)); do
    if [[ "\${args[i]}" == "-o" ]]; then
      out="\${args[i+1]}"
    fi
  done

  # Find out which iteration we are on using a local counter
  c=0
  [[ -f ${cwd}/review_counter ]] && c=$(cat ${cwd}/review_counter)
  c=$((c + 1))
  echo $c > ${cwd}/review_counter

  if [[ -n "$out" ]]; then
    if [[ "$c" -eq 1 ]]; then
      echo "Verdict: NEEDS_CHANGES" > "$out"
    else
      echo "Verdict: APPROVED" > "$out"
    fi
  fi
fi
exit 0
`);

    const res = runBt(["loop", "feat-p1", "--max-iterations", "3"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` }
    });

    assert.equal(res.code, 0, "Loop failed: " + res.stdout + " " + res.stderr);
    
    const calls = fs.readFileSync(callsLog, "utf8").trim().split("\n");
    // Expected sequence:
    // 1. implement (iter 1)
    // 2. review (iter 1) -> NEEDS_CHANGES
    // 3. fix
    // 4. implement (iter 2)
    // 5. review (iter 2) -> APPROVED
    const expected = ["implement", "review", "fix", "implement", "review"];
    assert.deepEqual(calls, expected, "Sequence mismatch: " + calls.join("->"));
});

if (process.exitCode) process.exit(process.exitCode);
