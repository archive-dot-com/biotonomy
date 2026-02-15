import { spawnSync } from "node:child_process";
import assert from "node:assert/strict";

function sh(cmd, args) {
  const res = spawnSync(cmd, args, { encoding: "utf8" });
  if ((res.status ?? 1) !== 0) {
    throw new Error(
      `command failed: ${cmd} ${args.join(" ")}\n${res.stdout || ""}\n${res.stderr || ""}`
    );
  }
  return { stdout: res.stdout || "", stderr: res.stderr || "" };
}

// Prefer JSON output when available (npm >=9 supports --json for pack).
let files = null;
try {
  const { stdout } = sh("npm", ["pack", "--dry-run", "--json"]);
  const j = JSON.parse(stdout);
  // npm returns an array; each entry has "files": [{path,size,mode}, ...]
  files = (j?.[0]?.files || []).map((f) => f.path).filter(Boolean);
} catch {
  // Fallback: parse the human output (less stable, but better than nothing).
  const { stdout } = sh("npm", ["pack", "--dry-run"]);
  files = stdout
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("npm notice "))
    .map((l) => l.replace(/^npm notice\s+/, ""))
    .filter((l) => l.startsWith("package.json") || l.startsWith("bt.sh") || l.includes("/"));
}

assert.ok(Array.isArray(files) && files.length > 0, "npm pack produced no file list");

const mustHave = [
  "package.json",
  "README.md",
  "LICENSE",
  "bt.sh",
  "commands/bootstrap.sh",
  "lib/env.sh",
  "prompts/implement.md",
];
for (const p of mustHave) {
  assert.ok(files.includes(p), `pack missing required file: ${p}`);
}

const mustNotHave = [".github/workflows/ci.yml", ".gitignore", "specs/"];
for (const p of mustNotHave) {
  const has = files.some((f) => f === p || f.startsWith(p));
  assert.ok(!has, `pack unexpectedly includes: ${p}`);
}

process.stderr.write(`ok - pack includes ${files.length} files\n`);

