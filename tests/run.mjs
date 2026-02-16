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

  const impl = runBt(["implement", "feat-x"], { cwd });
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
printf '%s\\n' "# Review from stub" "Findings: none" > "$out"
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
  assert.match(content, /^Verdict:/im);
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

if (process.exitCode) process.exit(process.exitCode);
