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

test("env loading (BT_SPECS_DIR) affects status output", () => {
  const cwd = mkTmp();
  writeFile(path.join(cwd, ".bt.env"), "BT_SPECS_DIR=specz\nBT_STATE_DIR=.bt\n");
  fs.mkdirSync(path.join(cwd, "specz"), { recursive: true });

  const res = runBt(["status"], { cwd });
  assert.equal(res.code, 0);
  assert.match(res.stdout, /specs_dir: specz/);
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
    "reset",
  ];
  for (const c of cmds) {
    const res = runBt([c, "--help"]);
    assert.equal(res.code, 0, `${c} help failed: ${res.stderr}`);
  }
});

test("notify hook is invoked when BT_NOTIFY_HOOK is set", () => {
  const cwd = mkTmp();
  const hook = path.join(cwd, "hook.sh");
  const out = path.join(cwd, "hook.out");
  writeFile(
    hook,
    `#!/usr/bin/env bash\nset -euo pipefail\necho \"$*\" >> ${JSON.stringify(out)}\n`
  );
  fs.chmodSync(hook, 0o755);

  writeFile(path.join(cwd, ".bt.env"), `BT_NOTIFY_HOOK=${hook}\n`);

  const res = runBt(["bootstrap"], { cwd });
  assert.equal(res.code, 0);
  assert.ok(fs.existsSync(out), "hook output missing");
  const content = fs.readFileSync(out, "utf8");
  assert.match(content, /bt bootstrap complete/i);
});

if (process.exitCode) process.exit(process.exitCode);

