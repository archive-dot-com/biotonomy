import { execSync } from 'node:child_process';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

const BT_ROOT = process.cwd();
const BT_BIN = path.join(BT_ROOT, 'bt');

function bt(args) {
  try {
    return execSync(`${BT_BIN} ${args}`, {
      encoding: 'utf8',
      env: { ...process.env, BT_ROOT, BT_PROJECT_ROOT: BT_ROOT },
      stdio: ['ignore', 'pipe', 'pipe']
    });
  } catch (err) {
    return err;
  }
}

console.log('Running Issue #34 TDD tests (URL sanitization into slugs)...');

// Helper to cleanup spec dir
function cleanup(slug) {
  const p = path.join(BT_ROOT, 'specs', slug);
  if (fs.existsSync(p)) {
    fs.rmSync(p, { recursive: true, force: true });
  }
}

// Test 1: Feature name with spaces/special chars should be sanitized
const test1Slug = 'feat-34-test-spaces';
const test1Input = 'hello world special!@# chars';
const expectedSlug1 = 'hello_world_special____chars'; // Based on common slugification (replacing invalid with _)
/* Actually, let's see what we WANT. 
   If bt_require_feature is where we check, maybe we should have a bt_sanitize_slug.
*/

console.log('Test 1: Sanitizing feature names with spaces...');
cleanup('hello_world_special____chars');
const out1 = bt('spec "hello world special!@# chars"');
if (out1 instanceof Error) {
  console.log('❌ Test 1 failed (as expected before fix):', out1.stderr.trim());
} else {
  console.log('✅ Test 1 passed (unexpectedly!):', out1.trim());
}

// Test 2: URL as feature should be sanitized
console.log('\nTest 2: Sanitizing URLs used as feature name...');
const urlInput = 'https://github.com/biotonomy/bt/issues/34';
// This SHOULD trigger the "issue" path because of the regex in spec.sh:
// [[ "$arg" =~ ^https?://github.com/([^/]+/[^/]+)/issues/([0-9]+) ]]
// So it actually shouldn't fail the slug check if it hits that branch.

const customUrlInput = 'https://example.com/some/weird/path';
cleanup('https___example.com_some_weird_path');
const out2 = bt(`spec "${customUrlInput}"`);
if (out2 instanceof Error) {
  console.log('❌ Test 2 failed (as expected before fix):', out2.stderr.trim());
} else {
  console.log('✅ Test 2 passed (unexpectedly!):', out2.trim());
}
