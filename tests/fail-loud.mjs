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
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-test-fail-loud-"));
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

test("ship (alias of pr) fails loud when required files are unstaged", () => {
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

if (process.exitCode) process.exit(process.exitCode);
