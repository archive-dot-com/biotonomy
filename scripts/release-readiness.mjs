import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

function run(label, cmd, args, opts = {}) {
  process.stderr.write(`\n==> ${label}\n`);
  const res = spawnSync(cmd, args, {
    encoding: "utf8",
    stdio: opts.stdio || "inherit",
  });
  return {
    ok: (res.status ?? 1) === 0,
    status: res.status ?? 1,
    stdout: res.stdout || "",
    stderr: res.stderr || "",
  };
}

function parsePackJson(stdout) {
  try {
    const data = JSON.parse(stdout);
    return data?.[0] || null;
  } catch {
    return null;
  }
}

function formatBytes(n) {
  if (!Number.isFinite(n) || n < 0) return "n/a";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KiB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MiB`;
}

const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));

const test = run("npm test", "npm", ["test"]);
const lint = run("npm run lint", "npm", ["run", "lint"]);
const verifyPack = run("npm run verify:pack", "npm", ["run", "verify:pack"]);

const packDryRun = run("npm pack --dry-run --json", "npm", ["pack", "--dry-run", "--json"], {
  stdio: "pipe",
});
if (packDryRun.stdout) process.stdout.write(packDryRun.stdout);
if (packDryRun.stderr) process.stderr.write(packDryRun.stderr);

const packInfo = packDryRun.ok ? parsePackJson(packDryRun.stdout) : null;
const npmWhoami = run("npm whoami (optional)", "npm", ["whoami"], { stdio: "pipe" });
const npmUser = npmWhoami.ok ? npmWhoami.stdout.trim() : "not authenticated";

const checks = [
  ["tests", test.ok],
  ["lint", lint.ok],
  ["pack contents", verifyPack.ok],
  ["npm pack --dry-run", packDryRun.ok],
];
const allOk = checks.every(([, ok]) => ok);

process.stderr.write("\nPublish preflight summary\n");
process.stderr.write(`- package: ${pkg.name}@${pkg.version}\n`);
process.stderr.write(`- npm auth: ${npmUser}\n`);
for (const [name, ok] of checks) {
  process.stderr.write(`- ${name}: ${ok ? "PASS" : "FAIL"}\n`);
}

if (packInfo) {
  process.stderr.write("- pack artifact:\n");
  process.stderr.write(`  - file: ${packInfo.filename || "n/a"}\n`);
  process.stderr.write(`  - files: ${packInfo.files?.length ?? "n/a"}\n`);
  process.stderr.write(`  - package size: ${formatBytes(packInfo.size)}\n`);
  process.stderr.write(`  - unpacked size: ${formatBytes(packInfo.unpackedSize)}\n`);
}

if (!allOk) {
  process.stderr.write("\nRelease readiness failed. Fix failures before publishing.\n");
  process.exit(1);
}

process.stderr.write("\nRelease readiness passed. Safe to proceed with manual publish steps.\n");
