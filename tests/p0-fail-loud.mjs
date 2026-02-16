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
  return fs.mkdtempSync(path.join(os.tmpdir(), "biotonomy-test-p0-fail-loud-"));
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

test("spec/implement/review/fix: reject traversal feature names (fail-loud)", () => {
    const cwd = mkTmp();

    // Spec with traversal should fail loud
    const res1 = runBt(["spec", "../../attacker"], { cwd });
    assert.equal(res1.code, 1, "spec should exit 1 on traversal");
    assert.ok(res1.stderr.includes("invalid feature"), "missing invalid feature error");

    // Loop with traversal should fail loud
    const res2 = runBt(["loop", "../../attacker"], { cwd });
    assert.equal(res2.code, 1, "loop should exit 1 on traversal");
    assert.ok(res2.stderr.includes("invalid feature"), "missing invalid feature error");

    // implement with traversal should fail loud
    const res3 = runBt(["implement", "../../attacker"], { cwd });
    assert.equal(res3.code, 1, "implement should exit 1 on traversal");
    assert.ok(res3.stderr.includes("invalid feature"), "missing invalid feature error");
});

test("spec: support sanitized URL for feature", () => {
    const cwd = mkTmp();

    // Mock gh to allow fetching issue data
    const ghPath = path.join(cwd, "gh-mock");
    fs.writeFileSync(ghPath, "#!/bin/bash\necho '{\"title\": \"Sanitize Slug\", \"url\": \"http://gh\", \"body\": \"desc\"}'", { mode: 0o755 });

    const env = { PATH: `${cwd}:${process.env.PATH}` };

    // Use a full issue URL
    const res = runBt(["spec", "https://github.com/archive-dot-com/biotonomy/issues/34"], { cwd, env });
    assert.equal(res.code, 0, `spec should handle URL: ${res.stderr}`);
    assert.ok(fs.existsSync(path.join(cwd, "specs/issue-34/SPEC.md")), "SPEC.md not found in issue-34 folder");
});

if (process.exitCode) process.exit(process.exitCode);
