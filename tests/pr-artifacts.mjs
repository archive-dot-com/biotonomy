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
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-test-pr-artifacts-"));
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

test("P2: Artifacts section is included in PR body", () => {
  const cwd = mkTmp();
  runBt(["bootstrap"], { cwd });
  runBt(["spec", "feat-artifacts"], { cwd });

  // Initialize git so pr doesn't fail on status checks
  spawnSync("bash", ["-lc", "git init -q"], { cwd, encoding: "utf8" });
  spawnSync("bash", ["-lc", "git add ."], { cwd, encoding: "utf8" });
  
  // Dry run output should contain the "Artifacts comment would contain:" marker
  const res = runBt(["pr", "feat-artifacts", "--dry-run"], { cwd });
  const combined = res.stdout + res.stderr;
  assert.equal(res.code, 0, "pr should exit 0 on dry-run");
  assert.ok(combined.includes("Artifacts comment would contain:"), "Missing artifacts preview header");
  assert.ok(combined.includes("### `specs/feat-artifacts/SPEC.md`"), "Missing SPEC in artifacts preview");
});

test("P2: Artifacts section includes files from .artifacts directory", () => {
    const cwd = mkTmp();
    runBt(["bootstrap"], { cwd });
    runBt(["spec", "feat-dir-artifacts"], { cwd });
    
    const artifactsDir = path.join(cwd, "specs", "feat-dir-artifacts", ".artifacts");
    fs.mkdirSync(artifactsDir, { recursive: true });
    fs.writeFileSync(path.join(artifactsDir, "log.txt"), "some log content");

    // Initialize git and stage files
    spawnSync("bash", ["-lc", "git init -q"], { cwd, encoding: "utf8" });
    spawnSync("bash", ["-lc", "git add ."], { cwd, encoding: "utf8" });
    
    // Dry run output should contain the log.txt artifact
    const res = runBt(["pr", "feat-dir-artifacts", "--dry-run"], { cwd });
    const combined = res.stdout + res.stderr;
    assert.equal(res.code, 0, "pr should exit 0 on dry-run");
    assert.ok(combined.includes("### `specs/feat-dir-artifacts/.artifacts/log.txt`"), "Missing artifact file in preview");
    assert.ok(combined.includes("some log content"), "Missing artifact content in preview");
});

if (process.exitCode) process.exit(process.exitCode);
