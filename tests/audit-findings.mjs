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
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-audit-test-"));
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

test("H1 Repro: pr fails when unstaged code exists in non-whitelisted directory", () => {
  const cwd = mkTmp();
  
  // Setup a git repo
  spawnSync("git", ["init", "-q"], { cwd });
  spawnSync("git", ["config", "user.email", "test@example.com"], { cwd });
  spawnSync("git", ["config", "user.name", "test"], { cwd });

  // Bootstrap and commit initial structure
  runBt(["bootstrap"], { cwd });
  spawnSync("git", ["add", "."], { cwd });
  spawnSync("git", ["commit", "-qm", "init"], { cwd });

  runBt(["spec", "audit-feat"], { cwd });
  spawnSync("git", ["add", "."], { cwd });
  spawnSync("git", ["commit", "-qm", "feat specs"], { cwd });

  // Create an unstaged file in a NEW directory 'src' (not in the old whitelist)
  const srcDir = path.join(cwd, "src");
  fs.mkdirSync(srcDir, { recursive: true });
  fs.writeFileSync(path.join(srcDir, "app.ts"), "unstaged code");

  const res = runBt(["pr", "audit-feat", "--dry-run", "--no-commit"], { cwd });

  assert.equal(res.code, 1, "Should fail due to unstaged src/app.ts");
  assert.match(res.stderr, /Abort: ship requires all feature files to be staged/);
  assert.match(res.stderr, /src\/app\.ts/);
});

test("H2 Repro: loop fails when no gates are configured", () => {
    const cwd = mkTmp();
    runBt(["bootstrap"], { cwd });
    runBt(["spec", "feat-no-gates"], { cwd });
    const featDir = path.join(cwd, "specs", "feat-no-gates");
    fs.writeFileSync(path.join(featDir, "PLAN_REVIEW.md"), "Verdict: APPROVED_PLAN\n");

    // Empty .bt.env to ensure NO gates are configured
    fs.writeFileSync(path.join(cwd, ".bt.env"), "BT_SPECS_DIR=specs\nBT_STATE_DIR=.bt\n");

    const bin = path.join(cwd, "bin");
    fs.mkdirSync(bin, { recursive: true });
    const codex = path.join(bin, "codex");
    fs.writeFileSync(codex, `#!/usr/bin/env bash
out=''
for ((i=1;i<=$#;i++)); do [[ "\${!i}" == "-o" ]] && j=$((i+1)) && out="\${!j}"; done
[[ -n "$out" ]] && echo 'Verdict: APPROVED' > "$out"
exit 0
`);
    fs.chmodSync(codex, 0o755);

    const res = runBt(["loop", "feat-no-gates", "--max-iterations", "1"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}` }
    });

    // In current buggy state, this will exit 0. We want it to exit 1.
    assert.equal(res.code, 1, "Loop should fail if no gates ran");
    assert.match(res.stderr, /preflight gates failed \(or none configured\)/);
});

test("M1 Repro: plan-review uses feature-scoped log instead of /tmp/codex.log", () => {
    const cwd = mkTmp();
    runBt(["bootstrap"], { cwd });
    runBt(["spec", "feat-scoped-log"], { cwd });

    const bin = path.join(cwd, "bin");
    fs.mkdirSync(bin, { recursive: true });
    const codex = path.join(bin, "codex");
    fs.writeFileSync(codex, `#!/usr/bin/env bash
echo "writing to \$BT_CODEX_LOG_FILE"
echo "codex run for \$BT_FEATURE" >> "\$BT_CODEX_LOG_FILE"
# Check if /tmp/codex.log is being written (it shouldn't be)
if [[ "\$BT_CODEX_LOG_FILE" == "/tmp/codex.log" ]]; then
  exit 1
fi
cat <<'EOF' > "specs/\$BT_FEATURE/PLAN_REVIEW.md"
# Approved
Verdict: APPROVED_PLAN
EOF
exit 0
`);
    fs.chmodSync(codex, 0o755);

    const res = runBt(["plan-review", "feat-scoped-log"], {
        cwd,
        env: { PATH: `${bin}:${process.env.PATH}`, BT_CODEX_BIN: "codex" }
    });

    assert.equal(res.code, 0, res.stdout + res.stderr);

    const expectedLog = path.join(cwd, "specs", "feat-scoped-log", ".artifacts", "codex-plan-review.log");
    assert.ok(fs.existsSync(expectedLog), `Log should exist at ${expectedLog}`);
});
