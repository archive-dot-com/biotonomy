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
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-test-p0-"));
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

test("P0: pr/ship should fail loud even with --no-commit if unstaged files found in tracked dirs", () => {
    const cwd = mkTmp();
    
    // Setup git repo
    spawnSync("git", ["init", "-q"], { cwd });
    
    // Required files etc
    runBt(["bootstrap"], { cwd });
    runBt(["spec", "feat-p0"], { cwd });
    
    // Create an unstaged file in a tracked directory
    const unstagedFile = path.join(cwd, "lib", "p0-fix.mjs");
    fs.mkdirSync(path.dirname(unstagedFile), { recursive: true });
    fs.writeFileSync(unstagedFile, "export const p0 = true;");

    // We use --no-commit but expect it to STILL fail because 'lib/' is in check_paths
    const res = runBt(["pr", "feat-p0", "--no-commit", "--dry-run"], { cwd });
    
    assert.equal(res.code, 1, `Expected exit code 1, got ${res.code}. Out: ${res.stdout} Err: ${res.stderr}`);
    assert.match(res.stderr, /Abort: ship requires all feature files to be staged/, "Should show abort message");
    assert.match(res.stderr, /lib\/p0-fix\.mjs/, "Should list the offending file");
});

if (process.exitCode) process.exit(process.exitCode);
